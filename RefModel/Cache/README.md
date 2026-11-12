# Cache 参考模型（RefModel/Cache）

本目录是《Cache 架构设计文档 v2》的行为级 C++ 参考模型，按层拆分。三个 Layer 1 模块彼此独立、可单测，也共用同一套"每拍两步"的时序约定。

| 文件 | 类 | 职责 | 对应文档 |
|---|---|---|---|
| `params.hpp` | — | 参数、类型、地址解码、ID 映射 | §3 / §4.5 / §5.1 |
| `CacheMem.hpp` | `CacheMem` | tag/valid/dirty/data 存储体，2 读 + 2 写 + 清零 | §5 |
| `MSHR.hpp` | `MSHR` | 未命中登记、合并、发读、填充、重放 | §7 |
| `WriteBackBuffer.hpp` | `WriteBackBuffer` | 脏行写回缓冲：预留 / push / 异步写回 / 释放 | §8 |
| `ReplacePolicy.hpp` | `FifoPolicy` / `LruPolicy` / `PlruPolicy` | 可插拔替换策略（Policy Concept）：victim 选择 / onHit / onFill | §10 |
| `CacheTop.hpp` | `CacheTopT<Policy>`（`CacheTop` = FIFO） | 顶层组装：两级流水、命中判断、Way Lock、响应队列、三模块互联；策略由模板参数注入 | §2 / §6 / §10 / §11 / §12 |

Layer 1（`CacheMem` / `MSHR` / `WriteBackBuffer`）只做各自的存储与状态机；`CacheTop` 负责把它们组装成完整 DCache（含 Stage2 冻结、`cpuReady`、victim 选择、Way Lock、响应队列）。

---

## 统一时序约定

每个模块都是"松散时序"：

```cpp
// (1) 本拍开始：布置 *_req 输入，读取组合输出
// (2) 调用 tick()：表示本拍时钟沿，状态更新
```

`tick()` 内所有更新都基于"本拍开始时的状态"，等价于硬件"组合求值 → 沿上更新"。

### 关于命中写的生效拍与读写优先级

- 模型里命中的 W1 在 Stage2 那一拍的 `tick()` 生效，即 `T+1 → T+2` 的沿，对 `T+2` 可见；
  这与文档 §6.5 / §12.2 的"第二到第三拍的时钟沿生效"一致。
- `CacheMem` 默认按 `W2 → W1 → Clear → R1 → R2` 串行化，即同沿读写被确定性地解析为**写优先**。
  因此 `CacheTop` 的 `prevW1` 旁路（§6.6）在默认模式下不会改变结果，属于防御性实现。
- 为验证 §6.6 旁路与 §2.5 的 `!wayLocked` 旧快照窗口，`CacheMem` 提供**测试专用**的
  `readFirst = true`（R1/R2 先采样，模拟读优先存储体），默认关闭；
  可通过 `CacheTop::setCacheReadFirst(true)` 切换。
- 本模型是功能级参考模型，**不承诺与 RTL 逐拍等价**；逐拍比对时需要把上述优先级/流水差异考虑进去。

---

## 1. CacheMem —— 存储主体

**做什么**：按 set/way 保存 valid/dirty/tag/data，提供两个读通道、两个写通道和 victim 清零。

**接口**

| 方向 | 端口 | 说明 |
|---|---|---|
| 输入 | `r1_req {en,index,wordOff}` | 流水线字读（同组各路 tag/valid/dirty + 该字） |
| 输入 | `r2_req {en,index,way}` | victim 整行读 |
| 输入 | `w1_req {en,index,way,wordOff,data}` | 命中单字写（置 dirty） |
| 输入 | `w2_req {en,index,way,tag,dirty,line}` | 填充整行写 |
| 输入 | `clr_req {en,index,way}` | 清 victim valid（不动 data/dirty） |
| 输出 | `r1_resp {tag[],valid[],dirty[],data[]}` | tick 后有效 |
| 输出 | `r2_resp {line}` | tick 后有效 |

方法：`reset()`、`tick()`；调试用 `getValid/getDirty/getTag/getWord`、`poke*`、`dump()`。

> 同拍访问顺序：`W2 → W1 → Clear → R1 → R2`，读口看到的是本拍写入后的值。

---

## 2. MSHR —— 未命中处理

**做什么**：一条 Cache 行一个 Entry、一个 CPU 请求一个 Slot；负责合并同地址请求、向内存发整行读、填充、按顺序重放。

**Entry 状态**：`IDLE → SEND → MISS_WAIT → FILL → IDLE`。

**接口**

| 方向 | 端口/方法 | 说明 |
|---|---|---|
| 输入 | `alloc_req {en,tag,index,allocWay,isWrite,wData,wordOff,respID,wbSlotIdx}` | 分配新条目（Stage2 权威提交） |
| 输入 | `merge_req {en,entry,isWrite,wData,wordOff,respID}` | 合并进已有条目 |
| 输入 | `mem_rd_resp {en,id,line}` | 内存读响应（MISS_WAIT→FILL） |
| 输入 | `mem_rd_ready` / `replay_ready` / `fill_ready` | 发送 / 重放 / 填充握手 |
| 查询 | `match(tag,index)` | `{hit,entry,state,mergeable,slotFree,freeSlot}` |
| 查询 | `hasFree()` / `full()` / `validEntries()` | 条目占用情况 |
| 输出 | `sendReq()` | 内存读请求（低位优先，**调用即锁存**到握手） |
| 输出 | `fillReq()` | W2 填充请求（**调用即提交**） |
| 输出 | `replayReq()` | 重放候选（条目级轮询，条目内低 Slot 优先） |

方法：`reset()`、`tick()`；调试用 `entry(i)`、`dump()`。

**关键规则**：`SEND`/`MISS_WAIT` 可合并，`FILL` 不可；填充 `dirty = hasWriteSlot`；重放读数据来自 `fillData + 前序同字写`（不读 Cache）；写 Slot 只回写响应。

---

## 3. WriteBackBuffer —— 脏行写回

**做什么**：暂存被替换的脏行，异步写回内存。生命周期：`预留(写 addr) → push(写 data) → 发送 → memWriteResp 释放`。

**接口**

| 方向 | 端口/方法 | 说明 |
|---|---|---|
| 输入 | `rsv_req {en,addr}` | 预留槽位 + 写块地址 |
| 输入 | `push_req {en,slot,line}` | 把 victim 整行装入预留槽 |
| 输入 | `mem_wr_ready` / `mem_wr_resp {en,id}` | 内存写握手 / 完成 |
| 查询 | `reserve()` / `reserve(bool en)` | 组合探测：`{ok,slot}` |
| 查询 | `full()` / `hasSameAddr(blockAddr)` | 满（含 reserved）/ 同地址 |
| 输出 | `sendReq()` | 内存写请求（轮询仲裁） |

方法：`reset()`、`tick()`；调试用 `get*`、`poke*`、`dump()`。

**关键规则**：占用 = `valid || reserved`；预留当拍写 addr；同地址检查覆盖 `reserved + valid`；只有 victim 满足 `valid && dirty` 才预留（清 valid 不清 dirty，无效路上的残留 dirty 不算脏，§10.4/§11.2）。

---

## 4. CacheTop —— 顶层组装

**做什么**：把三个 Layer 1 模块接成完整 DCache：Stage1/Stage2、命中判断、MSHR 合并/分配、淘汰原子组、Stage2 冻结、Way Lock、响应队列、可插拔替换策略（默认 FIFO）。

**接口**

| 方向 | 端口 | 说明 |
|---|---|---|
| 输入 | `cpu_valid/addr/wrEn/wData/id` | CPU 请求 |
| 输入 | `cpuReadResp_ready` / `cpuWriteResp_ready` | 响应反压 |
| 输入 | `memReadReq_ready` / `memWriteReq_ready` | 内存请求 ready |
| 输入 | `memReadResp_valid/line/id` | 内存读响应 |
| 输入 | `memWriteResp_valid/id` | 内存写响应 |
| 输出 | `cpu_ready` | Stage1 准入 |
| 输出 | `cpuReadResp_valid/rData/id` | 读响应 |
| 输出 | `cpuReadResp_hit/merged` | 观测：Cache 命中 / MSHR 合并 |
| 输出 | `cpuWriteResp_valid/id` | 写响应 |
| 输出 | `cpuWriteResp_hit/merged` | 观测：Cache 命中 / MSHR 合并 |
| 输出 | `memReadReq_valid/addr/id` | 内存读请求（来自 MSHR） |
| 输出 | `memWriteReq_valid/addr/line/id` | 内存写请求（来自 WBB） |

每拍用法：

```cpp
top.eval();                 // 观察本拍组合输出
if (top.cpu_valid && top.cpu_ready) { /* 握手 */ }
top.tick();                 // 时钟沿
```

`tick()` 内部会再 `eval()` 一次（幂等）；`dump()` 可打印 CacheMem / MSHR / WBB / WayLock。

### 4.1 替换策略的模板注入（§10.1）

`CacheTop` 实际上是 `CacheTopT<Policy>` 的模板，策略在**编译期**注入，无虚函数开销：

```cpp
CacheTop      top;        // = CacheTopT<FifoPolicy>，默认
CacheTopLru   lruTop;     // = CacheTopT<LruPolicy>
CacheTopPlru  plruTop;    // = CacheTopT<PlruPolicy>
CacheTopT<MyPolicy> my;   // 自定义策略
```

自定义策略只需满足 `ReplacePolicy.hpp` 顶部描述的 Policy Concept：

```cpp
void reset();
int  getVictim(int set, const std::array<bool, NUM_WAYS>& valid,
               const std::array<bool, NUM_WAYS>& locked) const;
void onHit (int set, int way);   // Stage2 命中提交拍（§10.3）
void onFill(int set, int way);   // 填充写 Cache 拍（§10.3）
```

`getVictim` 必须是**纯函数**，并遵守 §10.4：优先"valid=0 且未锁"的路；否则按策略顺序给候选且跳过锁定路；全锁返回 -1。策略本身不感知 valid/locked，这两个数组每拍由 `CacheTop` 传入，因此淘汰被中止时不会污染策略状态。

已提供 `FifoPolicy`（默认）、`LruPolicy`、`PlruPolicy`（4 路 tree-PLRU，复位后偏好序 0..N−1）；随机策略待补（§14 第二项）。`test/test_policy.cpp`（`make run-policy`）对三者跑同一套契约测试、锁定队首的顺延语义、以及端到端 victim 选择（FIFO→way0 / LRU→way1 / PLRU→way2）。

> `Cache/alloc_policies/*.hpp` 是早期接口（`get_victim(set, cache_set)`，不支持 Way Lock）留下的草稿，`CacheTop` 不使用，保留仅供参考。

### 4.2 CPU 请求 ID 的激励约束（§3.4）

`CpuId` 在参考模型里仍是 32 位整数，**不刻意收窄成 `ID_WIDTH` 位**；但激励必须满足 `id < CPU_ID_LIMIT`（`= 2^ID_WIDTH`，当前 32），否则在 RTL 上会被截断/别名。`test_cachetop*.cpp` 的 `submit()` 都带这个断言；`test_cachetop_perf.cpp` 用一个小 ID 池，在请求被接收时分配、响应返回时归还，并断言池不空（等价于验证"在途请求 ≤ 25 < 32"）。

---

## 5. 集成方式

顶层每拍按下面顺序组织（示意）：

```cpp
// ===== 本拍组合阶段 =====

// --- 1) Stage2：MSHR 匹配 / 合并 / 分配 ---
auto mi = mshr.match(tag, set);

if (mi.hit && mi.mergeable && mi.slotFree) {
    // 命中且可合并（SEND / MISS_WAIT）
    mshr.merge_req = { true, mi.entry, req.isWrite, req.wData,
                       req.wordOff, req.respID };
} else if (!mi.hit) {
    // 未命中：淘汰 + 分配（victim 脏时先预留 WBB）
    //   干净 victim 不需要预留，视为 wbReserveSuccess
    auto rsv       = wbb.reserve(true);                    // 组合探测
    bool reserveOk = !victimDirty || rsv.ok;
    bool commit    = doAllocate && reserveOk;
    if (commit) {
        cache.clr_req  = { true, set, victimWay };         // 清 valid
        cache.r2_req   = { true, set, victimWay };         // 读 victim 整行
        wbb.rsv_req    = { victimDirty, toBlockAddr(victimAddr) }; // 预留 + 写 addr
        // 槽位记录进 MSHR 条目的 wbSlotIdx，下一拍 push 时使用
        mshr.alloc_req = { true, tag, set, victimWay,
                           req.isWrite, req.wData, req.wordOff,
                           req.respID, victimDirty ? rsv.slot : -1 };
    }
    // commit=false -> Stage2 冻结，等资源
} else {
    // 命中但条目在 FILL（不可合并）-> Stage2 冻结
}

// --- 2) 填充写 Cache：MSHR -> W2 ---
auto f = mshr.fillReq();
if (f.en) cache.w2_req = { true, f.index, f.way, f.tag, f.dirty, f.line };

// --- 3) victim 整行 -> WBB push（下一拍） ---
//   pendWbSlot = 上一拍 commit 时保存的槽位（等价于 MSHR 条目的 wbSlotIdx）
if (pushNow && pendWbSlot >= 0)
    wbb.push_req = { true, pendWbSlot, cache.r2_resp.line };

// --- 4) 内存侧 ---
auto rd = mshr.sendReq();      // -> memReadReq
auto wr = wbb.sendReq();       // -> memWriteReq
mshr.mem_rd_resp = memReadResp;
wbb.mem_wr_resp  = memWriteResp;

// --- 5) 重放 -> 响应队列 ---
auto rp = mshr.replayReq();
if (rp.en && respQueueReady) { /* 读返回 rp.rData，写只回 respID */ }

// ===== 本拍时钟沿 =====
cache.tick();
mshr.tick();
wbb.tick();
```

集成时必须由上层（Layer 2/3）补齐：

1. Stage1/Stage2 流水与 `cpuReady`（含 MSHR 满 / WBB 满 / 同地址 / 可用 way / 响应队列满）。
2. Stage2 冻结：保持请求、门控写、`cpuReady=False`。
3. victim 选择与 Way Lock（与 MSHR 条目同生同死）。
4. WBB 预留作为淘汰原子组使能；预留失败整组回退。
5. 同地址检查（Stage1 + Stage2 重查，覆盖 `reserved`）。
6. 读/写响应队列与命中优先。

---

## 6. 构建与自测

```bash
cd RefModel
make run          # CacheMem 测试（build/cache_test）
make run-mshr
make run-wbb
make run-cachetop
make run-cachetop-full   # 内部数据 + 状态 + 随机影子模型 + 乱序响应
make run-perf            # 局部性性能测试
make run-policy          # 替换策略契约测试 + CacheTop 模板实例化
```

`MSHR` 与 `WriteBackBuffer` 带不变量自检（`checkInvariants()`），在调试构建下由 `tick()` 自动断言；`CacheMem` 提供 `get*` / `poke*` 供测试直接检查存储内容。

---

## 7. 局部性性能测试（`test_cachetop_perf.cpp`）

`make run-perf` 运行一个受控的局部性工作负载（模式 A），而不是顺序流/纯随机/容量扫描：

- **地址空间**：1024 个 Cache 行 = **64KB**（Cache 容量 8KB，工作集是 8 倍）。
- **总指令数**：`1024 × 50 = 51,200` 条 L/S；L/S 比例 50/50，store 数据随机。
- **模式**：每 100 条为一个 block：
  - 偶数 block：下一条有 **60%** 概率与上一条**同地址**；
  - 奇数 block：下一条 **0%** 同地址，总是随机选一个不同地址；
  - 每 100 条切换一次，循环；共 512 个 block（256 个 60% + 256 个 0%）。
- **地址**：`line × 64 + wordOff × 4`，随机 `line ∈ [1,1024]`、随机 `wordOff ∈ [0,15]`。

输出：

- **整体**：Cache 命中率 / 有效命中率（把 MSHR 合并算作未再读内存）、吞吐、延迟、MSHR/WBB/WayLock 占用、Stall 分解、内存流量。
- **阶段拆分**：60% 同地址阶段 vs 0% 随机阶段。
- **局部性拆分**：
  - **同地址**（时间局部性）；
  - **同行不同字**（空间局部性）；
  - **不同行**（无局部性）。
- **阶段 × 局部性矩阵**：直接看时间/空间局部性在不同阶段的表现。
- 每次读响应都与按程序顺序维护的影子内存比对，确保统计来自正确执行。

观测接口（只读，不改变行为）：

```cpp
const CacheTop::PerfCounters& p = top.perf();
top.stallReason();          // 本拍 Stage2 冻结原因
CacheTop::stallReasonName(top.stallReason());

// 响应级观测
top.cpuReadResp_hit;        // 该读响应来自 Cache 命中
top.cpuReadResp_merged;     // 该读响应来自 MSHR 合并 Slot
top.cpuWriteResp_hit;
top.cpuWriteResp_merged;
```

> 说明：这是**功能级参考模型**上的局部性评估，不是 RTL 逐拍性能保证。绝对数值依赖 `rdLatency=8`、`wrLatency=8` 等外部假设；适合比较不同局部性模式/参数下的相对趋势。`same line, diff word` 在“1024 行均匀随机”下天然很少；如果要强化空间局部性，可以在生成器里让 40% 非重复地址偏向相邻行/同一行其他字。
