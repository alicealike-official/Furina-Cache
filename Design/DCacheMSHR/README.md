# 带 MSHR 的非阻塞 D-Cache（SpinalHDL 重构版）

基于《Cache 架构设计文档 v2》与《设计问题与取舍记录》重新实现的 D-Cache，**不参考 `RefModel/` 下的 C++ 模型**，也不修改仓库原有文件。所有代码位于本目录，作为一个独立 sbt 子工程存在。

---

## 1. 目录结构

```text
Design/DCacheMSHR/
├── build.sbt                        # 独立工程（SpinalHDL 1.10.2 / Scala 2.11.12）
├── project/build.properties         # sbt 2.0.8
├── README.md
├── src/main/scala/furina/dcache/
│   ├── CacheConfig.scala            # 参数、地址分解、位宽约束
│   ├── Bundles.scala                # CPU/内存/MSHR 接口 Bundle
│   ├── Ram2R2W.scala                # 严格 2R2W bank（四副本等价实现）
│   ├── CacheMem.scala               # R1/R2 读、W1/W2 写、清 valid、状态查询
│   ├── ReplacePolicy.scala          # FIFO / LRU / RR，可插拔
│   ├── Mshr.scala                   # MSHR：合并、发送、填充、重放、Way Lock
│   ├── WriteBackBuffer.scala        # WBB：预留 / push / 轮询写回 / 释放
│   ├── DCache.scala                 # 顶层：两级流水、冻结、响应队列、互联
│   ├── DCacheVerilog.scala          # Verilog 生成入口
│   └── sim/
│       ├── SimHarness.scala         # 驱动 + 独立 scoreboard + 内存模型
│       └── AllTests.scala           # 定向 + 随机测试
└── rtl/                             # sbt run 生成的 Verilog（不入库）
```

模块层次（生成的 `rtl/DCache.v`）：

```text
DCache
├── CacheMem      （内部例化 4×16 个 Ram2R2W bank）
├── Mshr
├── WriteBackBuffer
├── ReplacePolicy（Area，内联）
└── StreamFifo ×2（读响应队列 / 写响应队列）
```

---

## 2. 参数

默认值取自文档 §3.1，全部可通过 `CacheConfig` 覆盖：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `NUM_SETS` | 32 | 组数 |
| `NUM_WAYS` | 4 | 相联度 |
| `BLOCK_SIZE` | 64 | 行大小（字节） |
| `DATA_WIDTH` | 32 | 字宽 |
| `ADDR_WIDTH` | 32 | 物理地址宽度 |
| `MSHR_ENTRIES` | 4 | MSHR 条目数 |
| `MSHR_MAX_PENDING` | 4 | 每条目最大 Slot 数 |
| `WBB_ENTRIES` | 4 | 写回缓冲条目数 |
| `RESP_QUEUE_DEPTH` | 4 | 读/写响应队列深度 |
| `NUM_BUS_OUTSTANDING` | 16 | 总线最大未完成事务数 |
| `ID_WIDTH` | 5 | CPU 请求 ID 宽度（文档 §3.4 推导：在途请求上界 25 → 5 位） |

派生参数：`indexWidth=5`、`offsetWidth=6`、`tagWidth=21`、`wordsPerBlock=16`、`wordOffWidth=4`、`mshrIdWidth=2`、`wbbIdWidth=2`、`busIdWidth=4`。

约束在 `CacheConfig` 的 `require` 中固化（组数/块大小/路数/MSHR/WBB 均为 2 的幂，`WBB_ENTRIES <= NUM_BUS_OUTSTANDING` 等）。

---

## 3. 外部接口

与原有 Spinal 代码保持同名同义（包名改为 `furina.dcache`，避免与 `furina.cache` 冲突）：

| 方向 | 接口 | 载荷 |
|---|---|---|
| 输入 | `cpu` (Stream) | `addr, wrEn, wData, id` |
| 输出 | `cpuReadResp` (Stream) | `rData, id` |
| 输出 | `cpuWriteResp` (Stream) | `id` |
| 输出 | `memReadReq` (Stream) | `addr, id` |
| 输入 | `memReadResp` (Stream) | `rData`(整行 512b), `id` |
| 输出 | `memWriteReq` (Stream) | `addr, wData`(整行), `id` |
| 输入 | `memWriteResp` (Stream) | `id` |

* CPU 地址按字对齐，内存地址按块对齐，均按文档约定由上层保证。
* 内存读写通道彼此独立，读 ID / 写 ID 属于两个独立空间。
* MSHR 位次零扩展到总线 ID；响应侧取总线 ID 低位回索引。

---

## 4. 实现要点（对应文档章节）

### 4.1 两级流水与 Stage2 冻结（§6、§11）

* Stage1：握手、地址分解、驱动 R1，并行计算 `cpuReady`。
* Stage2：用上一拍 R1 结果做 tag 比较，执行命中读/写、MSHR 合并或淘汰分配。
* `cpuReady = !s2Stuck && !respFullAny && (canMerge || missPath)`；
  `s2Stuck` 按 §11.2 的完整条件实现（含"脏 victim 但 WBB 预留失败"，§8.4）；
  `respFullAny` 取"读/写任一响应队列满"（§9.3）。
* 冻结期间保持流水寄存器、门控 Stage2 的所有写、`cpuReady=False`，
  并保持 `R1.en = fire || s2Stall`、地址为当前请求 index 以刷新读数据（§6.8）。
* 命中读：Stage2 产生响应；命中写：Stage2 驱动 W1 并返回写响应，
  存储体在下一个时钟沿更新（§6.5）。

### 4.2 CacheMem（§5）

* R1：同组各路 tag/valid/dirty + 目标字（同步读，一拍延迟）。
* R2：victim 整行读（同步读，一拍延迟）。
* W1：命中单字写，同时置 dirty。
* W2：填充整行写，写 tag、置 valid、dirty = 是否有写 Slot。
* CLR：淘汰时只清 valid，不动 data/dirty。
* valid/dirty 用独立寄存器平铺，因此"填充置位"与"淘汰清零"可同拍发生，
  且无需占用存储体端口。
* victim 选择使用的 valid/dirty 来自**当前寄存器**（组合查询），
  而 tag 取自流水线快照：未被锁定的路其 tag 不会被填充改变，
  这样既避免了"上一拍命中写刚置脏、本拍淘汰却看不到"的丢数据窗口，
  也保持了 Stage2 判定使用快照的语义。

### 4.3 严格 2R2W 存储体（§5.5）

FPGA 没有原生 2R2W BRAM，`Ram2R2W` 用**四副本 + 每 set 新旧标记**实现逻辑上的
2 读 2 写：

| 副本 | 写口 | 读口 |
|---|---|---|
| A1 | W1 | R1 |
| A2 | W1 | R2 |
| B1 | W2 | R1 |
| B2 | W2 | R2 |

* 每个 bank 的每个 set 维护 `newestIsA`：W1 写后 A 新，W2 写后 B 新；
  R1/R2 同时读 A/B 两份，按读发起那一拍记录的标记选择最新副本。
* 同一 `(set, way, word)` 上 W1 与 W2 不会同拍出现（fill 路处于 Way Lock，
  命中写被 `!wayLocked` 屏蔽），因此无需 W1 顺延。
* 代价：data 存储约 4 倍（8 KB → 32 KB 逻辑容量）。若后续要省面积，
  可换成文档 §5.5 的"单写口 + W2 优先、W1 由 Stage2 冻结顺延"方案，
  但那是功能等价而非严格 2R2W。

### 4.4 MSHR（§7）

* 状态机：`IDLE → SEND → MISS_WAIT → FILL → IDLE`。
* Entry 字段与文档 §7.2 对齐（含 `allocWay`、`fillData`、`replayCnt`、
  `validCnt`、`hasWriteSlot`、`wbSlotIdx`）。
* 匹配与合并：SEND/MISS_WAIT 可合并，FILL 不可；Slot 从低到高分配。
* 发送：低位优先 + `sendHold` 保持寄存器。只有"本条目被选中且总线握手"
  才进入 MISS_WAIT，避免未选中条目误判已发送（§7.7、问题记录 3.1）。
* 填充：收到内存响应后下一拍把 `fillData + 所有写 Slot` 合并成整行写 Cache，
  再逐 Slot 重放；`dirty = hasWriteSlot`。
* 重放：条目级轮询（RR），条目内 Slot 从低到高；读数据取
  `fillData + 该 Slot 之前的同字写`，不读 Cache（§7.11）。
* 条目释放时统一清 Entry/Slot，并释放 Way Lock。

### 4.5 Way Lock（§10.4）

没有单独的锁表，而是由 MSHR 条目组合导出：

```text
locked(set, way) = OR(entry.valid && entry.index == set && entry.allocWay == way)
```

与文档"生命周期与条目严格一致"等价，但从结构上消除了
"填充完成提前清锁"导致的二次释放 bug；置锁在分配后的下一拍可见，
正好挡住紧随请求对 victim 行的假命中。

### 4.6 WriteBackBuffer（§8）

* 生命周期：预留（写 addr）→ push（写 data、置 valid）→ 轮询发送 →
  `memWriteResp` 释放。
* `空闲 = !valid && !reserved`，`满 = 所有条目 valid || reserved`；
  同地址检查同样覆盖 `reserved` 与 `valid`。
* 只有"有效且脏"的 victim 才预留；预留失败时淘汰原子组整体不执行
  （不清 valid、不分配条目、不置锁、不读 R2），请求进入 Stage2 冻结。
* push 使用预留后下一拍的 R2 输出；预留地址使用 **victim 的 tag + 当前 set**，
  而不是新请求的地址。

### 4.7 响应队列（§9）

* 读、写各一个 `StreamFifo`，命中响应优先于重放响应推入。
* 按 §9.3，任一队列满都反压 `cpuReady` 并纳入 Stage2 冻结条件。
* 命中读与重放写、命中写与重放读可以同拍各自入队。

### 4.8 写后读旁路（§6.6）

写请求在 Stage2 驱动 W1，写入在下一沿生效；紧随其后被接收的读请求
在 Stage2 使用 R1 的旧数据。顶层保存上一拍 W1 的 `{tag,index,way,wordOff,data}`，
在读写目标完全一致时直接用写数据替代 R1 数据。`p1Valid` 在 Stage2 不冻结时
清除，避免陈旧旁路。

### 4.9 替换策略（§10）

接口保持文档 §10.1 的形式：

```scala
def allocWay(setIndex: UInt): UInt
def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit
def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit
```

* `FifoPolicy`：每 set 一个顺序队列，填充时把该路移到队尾。
* `LruPolicy`：命中和填充都移到队尾。
* `RoundRobinPolicy`：每 set 一个指针。
* "优先 valid=0 且未锁；否则从策略候选开始循环扫描、跳过锁定路；全锁不可用"
  由顶层按 §10.4 完成，策略本身不感知 valid/locked。
* `onHit` 在 Stage2 命中拍触发，`onFill` 在填充写 Cache 拍触发。

---

## 5. 验证

### 5.1 环境

* 仿真器：Synopsys VCS（`SimConfig.withVCS()`），本机验证版本 `O-2018.09-SP2`。
* 仿真不需要 `RefModel/`；scoreboard 是独立实现的。

### 5.2 验证结构

`SimHarness` 维护两套内存：

* `arch`：架构可见内存。请求被 CPU 接口接收时按程序顺序更新写值；
  读请求在接收时快照期望值。
* `back`：Cache 看到的后端内存。内存读在握手时取数，延迟后可乱序返回；
  内存写在握手时更新，并延迟返回写响应。

每个 CPU 响应按 ID 与 `arch` 比对；同时检查未知 ID、类型错配、响应丢失。
内存模型可独立配置读延迟、抖动，以及 `memReadReq.ready` / `memWriteReq.ready` /
CPU 响应 `ready` 的随机反压概率。

### 5.3 用例

| 用例 | 内容 |
|---|---|
| `basic` | 冷读 → 填充；写命中 → 读回；再次读命中（校验只发过一次整行读）；写命中后紧接同字读（RAW 旁路） |
| `merge` | 同一冷行背靠背 W/R/W/R：4 个请求合并进 1 个 Entry，只发 1 次内存读；两次读分别看到 A、B（重放旁路正确） |
| `evict` | 同 set 填满 4 条脏行后第 5 条触发淘汰；检查 WBB 写回地址与整行数据；写回在途时立即重读被淘汰行，验证同地址顺序保证 |
| `hum` | 长延迟未命中未完成时，命中请求先返回（hit-under-miss） |
| `bp` | 内存请求 ready 与 CPU 响应 ready 随机反压，持续随机流量 |
| `random` | 128 行地址空间、2000 条随机读写，逐条 scoreboard 比对 |

`AllTests` 对 **FIFO 与 LRU** 两种策略各跑一遍全部用例。

### 5.4 当前结果

```text
================ policy = FIFO ================
[PASS] basic hit/miss/write  cycle=26
[PASS] miss merge & replay bypass  cycle=22
[PASS] dirty eviction / writeback  cycle=70
[PASS] hit-under-miss  (hit@26 < miss@43)
[PASS] backpressure  read=976 write=959 cycle=4003
[PASS] random  read=962 write=1040 cycle=4031
================ policy = LRU ================
[PASS] basic hit/miss/write  cycle=26
[PASS] miss merge & replay bypass  cycle=22
[PASS] dirty eviction / writeback  cycle=70
[PASS] hit-under-miss  (hit@26 < miss@43)
[PASS] backpressure  read=976 write=959 cycle=4003
[PASS] random  read=962 write=1040 cycle=4031
ALL TESTS PASSED
```

---

## 6. 运行方法

```bash
cd Design/DCacheMSHR

# 生成 Verilog 到 rtl/DCache.v
sbt run

# 全部仿真（FIFO + LRU，每个 6 个用例）
sbt "runMain furina.dcache.sim.AllTests"

# 只跑某个用例：basic / merge / evict / hum / bp / random
sbt "runMain furina.dcache.sim.AllTests evict"
```

VCS 需要可用的 `VCS_HOME` 与 license 环境（本机已配置）。
仿真工作目录 `simWorkspace/`、构建产物 `target/`、生成 RTL `rtl/` 均已加入 `.gitignore`。

---

## 7. 与文档的差异 / 已知取舍

1. **严格 2R2W 的面积**：用四副本实现，data 存储约 4 倍；功能上等价于文档的
   "每个 bank 为真双端口"。
2. **victim 的 dirty**：只有 `valid && dirty` 才写回。淘汰只清 valid、不清 dirty，
   因此无效路上的残留 dirty 不能触发写回（文档 §11.2 已明确）。
3. **victim 的 tag** 取流水线快照（R1），valid/dirty 取当前寄存器值；
   对于未被锁定的路，tag 不可能在 Stage1→Stage2 之间被填充改变，因此安全。
4. **一次性访存**：不支持字节使能/部分字写、非对齐访问、异常/总线错误/超时、
   ECC、多核一致性、原子操作，与文档 §1.4 一致。
5. **LRU 命中与填充同拍同 set**：两个更新会争用同一顺序队列，硬件上后写的
   `onFill` 优先；属于策略状态的近似，不影响数据正确性。FIFO 的 `onHit` 为空，
   不受影响。
6. **未实现**：重放饥饿计数（§14 第四项）、PLRU/随机策略、AXI 接口封装。
   这些都不影响当前功能与验证结论。
