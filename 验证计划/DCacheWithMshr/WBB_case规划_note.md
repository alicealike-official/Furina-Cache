# WBB IP 验证 case 规划

本 note 将 WBB IP 验证组织为 12 组 case，列出各组的主要场景、对应验证点和实施状态，供后续编写 sequence、配置内存响应和登记覆盖结果时使用。

验证点编号对应 [WBB IP验证](WBB_IP验证.md)，接口时序依据 [WBB IP架构设计文档](../../Architecture/WBB_IP架构设计文档.md)。各 case 可以覆盖多个验证点，同一验证点也可能需要多个 case 才能完整闭合。

## Case 清单

| Case | 主要验证内容 | 对应验证点 | 实施状态与条件 |
| --- | --- | --- | --- |
| `wbb_base_test` | 基础 reserve → push → send → response 全流程，检查地址、数据、ID及释放 | WBR-002、003、005、007、008；WBS-001、003、005、006 | 已有两笔基础写回运行结果，作为这些验证点的基础场景证据 |
| `wbb_data_pattern_test` | 全0、全1、逐字/逐字节递增、交替位、walking-1/0、随机整行数据，检查字序和数据完整性 | WBR-007；WBS-001；CFG-005 | 已实现，默认配置固定 seed 运行通过；具体场景、数量与证据见下文 |
| `wbb_capacity_test` | 填满 N 个槽后提交第 N+1 笔，检查预留失败、已有内容保持、释放后恢复 | WBR-001、002、004、005、006；WBS-005、009 | 规划中，可通过长写响应延迟及 sequence 构造，要求实际进入 full |
| `wbb_query_test` | 两查询口同址、异址、单边命中、双边命中、均不命中，覆盖不同槽阶段 | WBR-003、010、011、012；WBS-006 | 规划中，基础组合可随写回事务驱动；独立逐拍查询需要扩展查询控制 |
| `wbb_reuse_test` | 释放后用新地址、新数据复用槽，检查旧地址匹配解除、旧状态和数据清理 | WBR-015；WBS-006、012 | 规划中，可通过多轮填满和排空遍历各槽 |
| `wbb_send_backpressure_test` | send 被反压期间新增候选，检查 valid、地址、数据、ID 保持及恢复后的发送 | WBS-002、003、005；IF-002、004 | 规划中，容量型反压可通过内存配置构造；精确候选插入顺序需更细的调度控制 |
| `wbb_arbitration_test` | 多槽同时待发，检查轮询顺序、回绕、公平性和连续发送 | WBS-007、008、011 | 规划中，建议增加可控 ready 策略，支持积累候选后统一放行 |
| `wbb_response_order_test` | 从实际已发送的 ID 中选择响应，按逆序或指定排列返回，检查对应槽释放 | WBS-004、005、006、009 | 规划中，需要扩展 memory driver 的响应选择、握手校验及记录移除逻辑 |
| `wbb_event_collision_test` | 不同槽的响应释放分别与 reserve、push、send 同拍发生 | WBR-013、014；WBS-010 | 规划中，需要精确控制请求和响应拍次，并记录目标交叉事件确实发生 |
| `wbb_delayed_push_test` | 预留后延迟 push，检查 reserved 持续占用、查询命中及禁止提前发送 | WBR-004、006、008 的延迟模式子项 | 规划中，需要显式启用延迟 push 模式并扩展 driver 的阶段调度 |
| `wbb_pipeline_test` | 构造 `push(A)` 与 `reserve(B)` 同拍，检查不同事务的槽号和数据归属 | WBR-009 | 按当前决定暂缓，保留为待覆盖项 |
| `wbb_random_test` | 合法地址、数据、查询、反压和响应顺序组合随机，多轮复用后排空 | WBS-012；RND-001、008、010 | 规划中，先开展地址/数据随机，随机时序及乱序响应随内存驱动能力扩展 |

## 数据图样 case 实现与结果（2026-11-19）

实现入口：[wbb_data_pattern_test.sv](../../verif_mshr/test/wbb/wbb_data_pattern_test.sv)，继承 `wbb_base_test`。激励由新增的 [wbb_data_pattern_sequence.sv](../../verif_mshr/src/wbb/sequence/wbb_data_pattern_sequence.sv) 负责，该sequence继承 `wbb_base_sequence`，在 `body()` 中组织预置、固定图样、walking图样和整行随机化，并调用已有完整事务接口提交。

test负责配置watchdog、调用 `seq.start(env.agent.sequencer)`、等待排空及结果检查。预置与正式图样使用两个sequence实例：先以 `preload_only=1` 运行预置，test确认响应排空并回读全一后，再启动正式图样。sequence不持有environment、vif或C++模型句柄；原始激励保存为protected值记录，test通过只读getter取得副本，用于最终内存比较。

| 图样 | 默认512位行的数量 | 检查目的 |
| --- | --- | --- |
| 全0、全1 | 各1 | 全位清零和置位；全0目标地址先通过DUT写全1、排空并回读确认 |
| 逐字递增 | 1 | `word0` 位于最低 `DATA_WIDTH` 位，检查首末字及所有字的位置 |
| 逐字节递增 | 1 | 检查packed整行中各字节位置，补充字内字节交换检查 |
| `0xAA` / `0x55` 交替位 | 各1 | 检查相邻位的不同取值 |
| walking-1 / walking-0 | 各512 | 单个1/0遍历整行每一位，包含所有字边界 |
| 随机整行 | 32 | 使用仿真器seed随机化完整行，补充数据组合 |

合计1062个图样，加上全零地址的全一预置，共1063笔完整写回。各图样使用独立块地址，只有全零图样复用已经完成响应的预置地址。默认数据行宽下，本test将watchdog最低预算提高到8604拍，不改变基础case的默认配置。

检查链沿用已有 C++ WBB 模型、scoreboard、C++稀疏内存和IO SVA。新增的 `wbb_memory_store::read_actual()` 只是已有 `sparse_mem_read_line` DPI 的只读封装；排空后逐地址与case原始生成的数据比较，仅对比较成功的图样计数。各模式的检查数量和四类事务计数必须精确满足预期，不能只依据case没有报错判断覆盖。

本次使用4槽、64 B行、32位字、32位地址、10 ns时钟、10 ns内存写延迟，默认严格下一拍push模式。固定 `+ntb_random_seed=20261119` 运行至32070 ns，reserve/push/send/response均为1063，九类模式计数全部满足预期，`c_reserve_push`命中1063次，UVM_WARNING/ERROR/FATAL均为0。

- [sequence拆分后固定seed运行日志](../../verif_mshr/sim/work/log/wbb_data_pattern_sequence_seed20261119.log)
- [对应波形](../../verif_mshr/sim/work/wave/wbb_data_pattern_sequence_seed20261119.fsdb)
- [编译日志](../../verif_mshr/sim/work/log/wbb_data_pattern_sequence_compile.log)
- [基础case回归日志](../../verif_mshr/sim/work/log/wbb_base_after_sequence_split.log)：两笔写回通过。

本次编译使用 `verif_mshr/generated/WriteBackBuffer.v`，SHA-256为 `ac3e5cd84054c7cb32d1f1d628a88003533a96cbc760e60af234ae882642960e`。日志和波形位于可清理的 `sim/work` 下，执行 `make clean` 前应按需归档。

这些结果提供 WBR-007、WBS-001、CFG-005 的当前配置数据通路证据；本轮实际使用槽0/1，不作为全槽隔离、全部候选状态或其他配置已经完成的依据。C++存储的字节地址端序由 `RefModel/test/test_sparse_memory.cpp` 的原始字节读取检查补充，本次 `make -C RefModel run-memory` 通过。三个验证点在主表中仍保留未闭合，后续按必要场景补齐。

## 执行口径

- 默认严格要求 reserve 成功后的下一拍 push。N>1 时的全 reserved 状态，以及长时间仅预留不 push 的轨迹，归入 `wbb_delayed_push_test` 的显式延迟模式。
- WBR-001 的空槽选择与 WBS-007 的仲裁顺序，分别记录 IP 契约检查和当前 C++ 模型的精确一致性检查，沿用 WBB IP 验证文件中的范围说明。
- 新写回事务的地址应排除当前已占用块，旧响应完成并释放后可以复用。两个查询地址允许命中已占用块。
- 乱序响应从已发送且尚未完成的 ID 集合中选择，每个请求对应一次响应。
- WBR-013、014 和 WBS-010 的释放交叉可单独安排，上游 reserve/push 流水场景继续按 WBR-009 暂缓。

## 配套通用检查

复位、参数配置及验证环境负例也需要独立安排，并在 [WBB IP验证](WBB_IP验证.md) 的相应条目中登记。

| 类别 | 主要内容 | 执行条件 |
| --- | --- | --- |
| 复位 | 启动空态、复位后首次请求、重复空闲复位、运行中事务取消 | 采用确认的异步低有效契约；运行中复位先确定旧响应隔离与取消语义 |
| 参数配置 | 槽数、行宽、地址宽、槽ID/总线ID宽及合法配置边界 | 同步 RTL、SV 和 C++ 模型配置，并重新生成、编译 |
| 环境负例 | 非法push、错误ID、重复/提前响应、数据错误、遗漏响应和超时 | 记录预期触发的checker/SVA错误，验证检查器能发现问题 |

## 覆盖登记要求

每个正常功能 case 同时检查功能结果与场景命中情况。基础 case 通过后，相关验证点仍需补齐其他边界和组合场景。

- 数据和状态通过已有 C++ WBB 模型、scoreboard、稀疏内存回读及 SVA 检查。
- 收尾时 WBB、内存响应队列和在途 ID 排空，reserve/push/send/response 计数一致。
- 满容量 case 记录 `full_cycles > 0`，反压 case 记录 `stalled_cycles > 0`。
- 仲裁 case 记录多个槽同时待发，乱序 case 记录实际响应顺序，同拍交叉 case 记录相应事件或 cover 命中。
- 每次闭合保存验证点编号、case、配置、seed、检查器/覆盖点和日志。

当前基础 case 入口见 [wbb_base_test.sv](../../verif_mshr/test/wbb/wbb_base_test.sv)。
