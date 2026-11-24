# MSHR-DUT-002：fill反压期间被新候选替换

更新日期：2026-11-24。状态：**设计方修复后已重新生成RTL，含fill保持断言的52/52回归通过，按当前配置关闭。**

最初报告依据公开 IO 确认违约。随后检查源码，确认设计及模型都缺少 fill 选择保持。本次只修改设计、参考模型和本记录，未访问验证文件夹，未执行测试或仿真。

## 修复前的契约与复现

fill_en即valid，fillReady即ready。fill_en&&!fillReady时，en及tag/index/way/dirty/整行数据必须保持到握手。该要求不规定仲裁算法，也不要求低下标优先或轮询。

`mshr_fill_backpressure_sequence`先检查单候选阻塞八拍，再暂停fill、分别给两个Entry提交两笔Slot请求。先返回较高Entry并观察四拍fill受阻，再返回较低Entry；继续反压后才放行。所有等待以采样周期计。

| 10 ns时钟的相邻采样沿 | fill_en | fillReady | tag | index | way | dirty |
| --- | --- | --- | --- | --- | --- | --- |
| 455 ns，周期42 | 1 | 0 | 1 | 1 | 1 | 1 |
| 465 ns，周期43 | 1 | 0 | 1 | 0 | 0 | 1 |

455 ns同时接受ID0的内存响应；465 ns旧fill尚未接受，目标和整行数据已经变化。`MSHR_FILL_STALL_TRACE`保存前后整行数据，独立IO SVA报`MSHR_DUT_FILL_STABLE`。4 ns时钟在同一逻辑周期复现。

定向case实际命中：fill_new_candidate=1、fill_stall=32、fill_stall_release=2。最终3次alloc/send/response/fill/release、2次merge和5次replay均完成，原始数据检查通过；这不能豁免此前保持违约。模型精确比较未报错也不能证明该接口行为正确。

## 修复前的验证与报告

[10组报告](../../verif_mshr/sim_mshr/work/regression/run_20261124_165306_312976/summary.md)：fill_backpressure两时钟、多候选fill两时钟、random三种子×两时钟，10组均FAIL。错误均为`MSHR_DUT_FILL_STABLE`，没有环境输入违规或其他功能报错。

[定向日志](../../verif_mshr/sim_mshr/work/regression/run_20261124_165306_312976/mshr_fill_backpressure_test_p10_s1.log) / [FSDB](../../verif_mshr/sim_mshr/work/regression/run_20261124_165306_312976/mshr_fill_backpressure_test_p10_s1.fsdb) / [输入哈希](../../verif_mshr/sim_mshr/work/regression/run_20261124_165306_312976/inputs.json)。

```bash
python3 -B verif_mshr/sim_mshr/script/run_mshr_regression.py \
    --tests mshr_fill_backpressure_test mshr_fill_arbitration_test mshr_random_test \
    --max-errors 0 --color always
```

上述历史验证新增了保持SVA、动态候选场景、实际命中统计及IO诊断。原case名fill_arbitration保留，但不要求DUT采用特定仲裁顺序。MSC-005及当前随机回归不能闭合；设计修复后应复跑定向、随机和带新断言的长跑。

## 已确认的根因

[设计源码](../../Design/DCacheMSHR/src/main/scala/furina/dcache/Mshr.scala)原来用 `priorityLowest(fillCand)` 直接选择 fill 的 Entry。高下标 Entry 的 fill 被阻塞时，较低 Entry 收到内存响应、进入 FILL，就会改变选择，导致目标和整行数据一起切换。

这与 WBB send、MSHR replay 同属“已呈现请求缺少保持”，但选择方式不同：fill 原来按低下标优先，没有轮询指针，也没有 rotK。错误不在于缺少轮询，而在于新的候选能替换尚未被接受的 fill。既有 `fillDone` 只在接受时置位的条件本身是正确的。

[参考模型](../../RefModel/Cache/MSHR.hpp)的 `pickFill()` 原来也每次重新扫描最低下标候选。因此模型与 DUT 一致仍可能同时违反接口契约，需要一并修正，不能通过放宽保持检查解决。

## 已采用的修复

Scala 增加 `fillHold` 和 `fillHoldIdx`，将候选选择与实际输出索引分开：

- 没有挂起请求时，沿用原有低下标选择。
- `fill.en && !fillReady` 时记录当前已呈现的 Entry。
- 保持期间持续输出该 Entry 的 tag、index、way、dirty 和整行数据，新响应不能抢占。
- 恢复 ready 的接受沿仍交付原请求；只有 `fill.en && fillReady` 才清保持并置对应 Entry 的 `entryFillDone`。
- 复位清除新增保持状态。

合法协议下，待填充 Entry 已进入 FILL，不再合并新 Slot，也不能提前重放、释放或复用；其目标、原始行和参与合成的写 Slot 均保持稳定。所以只保存 Entry 索引即可，无需额外复制 512 位整行数据。默认四 Entry 配置新增三位控制寄存器及索引选择逻辑。

C++ 模型增加 `fillHoldValid_` 和 `fillHoldEntry_`，`pickFill()` 优先返回锁定 Entry。`tick()` 在状态更新前取得 `fillSel`；本拍确实调用过 `fillReq()` 且有效请求被背压时，锁住这个沿前选择，避免被本沿的新内存响应替换。实际接受时才清保持并置 `fillDone`，reset 清除新增状态。保留原有 `fillPresented_` 调用约定以及此前 replay 保持修复。

## 当前端口条件与后续改进方向

当前顶层 [DCache.scala](../../Design/DCacheMSHR/src/main/scala/furina/dcache/DCache.scala)把 `mshr.io.fillReady` 恒置为 True。fill 使用专用 W2 整行写通路，可以与 W1 等操作并行；Way Lock 保护填充目标。这里的“独立”指同一时钟下资源和操作可以并行，不表示跨时钟域异步传输。在当前集成条件下，fill 不会遭遇此次下游背压。

原设计“每拍最多一个内存响应，所以不需要 fill 仲裁”的推理，依赖 W2 能及时接收。每拍最多一笔是数量上限，不能单独保证这一笔当拍完成。一次 fill 的接受发生在一个握手沿，但等这个沿可以持续多拍：

| 周期 | 内存返回 | fillReady | 待填充情况 |
| --- | --- | --- | --- |
| T | A 返回 | 0 | A 等待 |
| T+1 | B 返回 | 0 | A、B 都等待 |
| T+2 | 无新返回 | 1 | 接受此前保持的 A，B 留待之后 |

当前 MSHR 的 `memReadResp.ready` 恒为 True，因此 fill 受阻时仍能接收后续响应，必须保存积压义务并保持已呈现请求。[MSHR IP 规格 §9.3 与 §9.4](../MSHR_IP架构设计文档.md#93-fillready反压)已明确这些要求，同时不要求特定 fill 仲裁算法或轮询顺序。

**本阶段决定：保留 fillReady 并补齐最小保持能力，继续使用当前专用 W2；暂不为 fill 增加轮询，也不改变存储体端口组织。** 这样当前功能验证有明确的背压契约，以后下游因端口共享而拉低 ready 时，MSHR 可以按同一契约等待。

后续若为了 PPA 从 2R2W 改为更少的端口，再结合实际资源冲突设计下游仲裁：哪些读写共享端口、fill 与命中访问谁先执行、未获准操作如何冻结，以及怎样避免重复提交、丢响应和长期饥饿。轮询只是可选策略，不能把减少存储体端口的改动简化成“加一个轮询器”。

届时需要一起评估面积、关键路径、功耗、首次发送延迟和连续吞吐，并验证顶层暂停与恢复。当前保持方案的成本主要是少量控制状态，但没有综合或布局布线数据，不能声称具体 PPA 收益。若改为阻塞上游内存响应来限制积压，也需重新分析流控及已接收响应的保存方式，本次未采用该改法。

## 本次编译与待验证状态

`sbt compile` 和包含 `MSHR.hpp` 的 C++ 编译单元通过 `g++ -std=c++17 -Wall -Wextra -c` 编译。只完成源码编译，没有执行仿真或测试，没有重新生成 Verilog，也没有访问验证文件夹。

本问题处于“实现已修复、编译通过、功能待确认”状态。用户后续需要生成新版 RTL、重新编译包含新模型的仿真程序，并执行回归；尤其要确保模型头文件更新后没有复用旧 DPI 对象文件。上文 10 组 FAIL 属于修复前证据，不是修复后结果；相关验证点仍待用户确认。


## 修复后复核

[最新52组报告](../../verif_mshr/sim_mshr/work/regression/run_20261124_172220_492146/summary.md)全部PASS，UVM warning/error/fatal均为0。重新生成用户修复后的RTL并冷编译当前参考模型，未修改验证激励、SVA或判定条件。

两种时钟的fill背压定向均命中新候选1次、反压32拍、解除反压2次；多候选、三种子随机及六组长跑均通过。长跑每组完成16384笔Slot请求。MSC-005、RND-002、RND-010按本配置闭合；前文失败轨迹及旧报告保留作历史。
