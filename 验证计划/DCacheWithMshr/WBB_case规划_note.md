# WBB IP 验证 case 规划

本 note 将 WBB IP 验证组织为 12 组 case，列出各组的主要场景、对应验证点和实施状态，供后续编写 sequence、配置内存响应和登记覆盖结果时使用。

验证点编号对应 [WBB IP验证](WBB_IP验证.md)，接口时序依据 [WBB IP架构设计文档](../../Architecture/WBB_IP架构设计文档.md)。各 case 可以覆盖多个验证点，同一验证点也可能需要多个 case 才能完整闭合。

## Case 清单

| Case | 主要验证内容 | 对应验证点 | 实施状态与条件 |
| --- | --- | --- | --- |
| `wbb_base_test` | 基础 reserve → push → send → response 全流程，检查地址、数据、ID及释放 | WBR-002、003、005、007、008；WBS-001、003、005、006 | 已有两笔基础写回运行结果，作为这些验证点的基础场景证据 |
| `wbb_data_pattern_test` | 全0、全1、逐字/逐字节递增、交替位、walking-1/0、随机整行数据，检查字序和数据完整性 | WBR-007；WBS-001；CFG-005 | 已实现，默认配置固定 seed 运行通过；具体场景、数量与证据见下文 |
| `wbb_capacity_test` | 填满 N 个槽后提交第 N+1 笔，检查满时预留失败、各笔数据正确、响应释放后恢复 | WBR-001、002、004、005、006；WBS-005、009 | 已实现，默认4槽配置运行通过；场景命中次数与覆盖范围见下文 |
| `wbb_query_test` | 两查询口同址、异址、单边命中、双边命中、均不命中，覆盖不同槽阶段 | WBR-003、010、011、012；WBS-006 | 已实现并通过，2轮共8笔写回，覆盖reserved/pending/issued与释放后查询 |
| `wbb_reuse_test` | 释放后用新地址、新数据复用槽，检查旧地址匹配解除、旧状态和数据清理 | WBR-015；WBS-006、012 | 已实现并通过，3轮共12笔写回，每槽使用3次 |
| `wbb_send_backpressure_test` | send 被反压期间新增候选，检查 valid、地址、数据、ID 保持及恢复后的发送 | WBS-002、003、005；IF-002、004 | 用户修复WBB-DUT-001后冷编译回归通过，仍命中10拍背压和1次候选插入 |
| `wbb_arbitration_test` | 多槽同时待发，检查轮询顺序、回绕、公平性和连续发送 | WBS-007、008、011 | 已实现并通过，4候选连续4拍发送，全槽及回绕命中 |
| `wbb_response_order_test` | 从实际已发送的 ID 中选择响应，按逆序或指定排列返回，检查对应槽释放 | WBS-004、005、006、009 | 已实现并通过，实际ID逆序响应，逐次查询已释放与仍占用地址 |
| `wbb_event_collision_test` | 不同槽的响应释放分别与 reserve、push、send 同拍发生 | WBR-013、014；WBS-010 | 已实现并通过，三类交叉各命中1次，无reserve/push同拍 |
| `wbb_delayed_push_test` | 预留后延迟 push，检查 reserved 持续占用、查询命中及禁止提前发送 | WBR-004、006、008 的延迟模式子项 | 用户修复后回归通过，5笔延迟push、全reserved保持7拍等目标仍命中 |
| `wbb_pipeline_test` | 构造 `push(A)` 与 `reserve(B)` 同拍，检查不同事务的槽号和数据归属 | WBR-009 | 按当前决定暂缓，保留为待覆盖项 |
| `wbb_random_test` | 合法地址、数据、查询、反压和响应顺序组合随机，多轮复用后排空 | WBS-012；RND-001、008、010 | 用户修复后seed1/2/3在两种时钟下全部通过，各32批128笔 |

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

首次运行使用4槽、64 B行、32位字、32位地址、10 ns时钟及当时的10 ns内存延迟配置，实际响应间隔为2拍，默认严格下一拍push模式。固定 `+ntb_random_seed=20261119` 运行至32070 ns，reserve/push/send/response均为1063，九类模式计数全部满足预期，`c_reserve_push`命中1063次，UVM_WARNING/ERROR/FATAL均为0。当前配置已改为直接指定2拍；后续10 ns和4 ns时钟回归同样通过，详见下文周期检查记录。

- [sequence拆分后固定seed运行日志](../../verif_mshr/sim/work/log/wbb_data_pattern_sequence_seed20261119.log)
- [对应波形](../../verif_mshr/sim/work/wave/wbb_data_pattern_sequence_seed20261119.fsdb)
- [编译日志](../../verif_mshr/sim/work/log/wbb_data_pattern_sequence_compile.log)
- [基础case回归日志](../../verif_mshr/sim/work/log/wbb_base_after_sequence_split.log)：两笔写回通过。

本次编译使用 `verif_mshr/generated/WriteBackBuffer.v`，SHA-256为 `ac3e5cd84054c7cb32d1f1d628a88003533a96cbc760e60af234ae882642960e`。日志和波形位于可清理的 `sim/work` 下，执行 `make clean` 前应按需归档。

这些结果提供 WBR-007、WBS-001、CFG-005 的当前配置数据通路证据；本轮实际使用槽0/1，不作为全槽隔离、全部候选状态或其他配置已经完成的依据。C++存储的字节地址端序由 `RefModel/test/test_sparse_memory.cpp` 的原始字节读取检查补充，本次 `make -C RefModel run-memory` 通过。三个验证点在主表中仍保留未闭合，后续按必要场景补齐。

## 容量 case 实现与结果（2026-11-19）

[wbb_capacity_sequence.sv](../../verif_mshr/src/wbb/sequence/wbb_capacity_sequence.sv) 准备并发送 N+1 笔完整写回，每笔使用不同的块地址和整行数据。[wbb_capacity_test.sv](../../verif_mshr/test/wbb/wbb_capacity_test.sv) 负责配置内存响应延迟、启动 sequence、接收 monitor 采样、等待响应完成以及检查结果。sequence 不访问 environment、vif 或 C++ 模型。

内存 driver 的 `mem_max_pending` 设为 N，`mem_write_latency_cycles` 设为 `4*N+16` 拍。默认4槽时每个请求等待32拍响应，使第5笔请求确实遇到满槽；延迟不再乘以时钟周期或换算成ns。仍使用原有严格下一拍 push 的 driver，未增加上游流水或延迟 push。

时钟配置统一由 `tb_top` 创建并逐级传递，capacity test只读取 `clk_cfg.initial_reset_cycles` 计算总超时预算。test、env和clock agent均不在配置缺失时另建对象；缺失或空句柄会明确报错。[config_db跟踪回归日志](../../verif_mshr/sim/work/log/wbb_capacity_clock_config.log)记录了此前配置传递调整；当前按周期响应的结果如下。

test 通过 analysis 连接接收现有 monitor 的沿前采样。每拍先检查状态，再统计该拍的 reserve/send/response，保证响应握手当拍仍按槽尚未释放处理。检查原有 C++ WBB 模型、scoreboard 和 SVA 的同时，还必须命中以下场景：

| 场景 | 通过条件 | 本次结果 |
| --- | --- | --- |
| 使用所有槽 | 前 N 次 reserve 使用 N 个不同槽 | `slots=1111`，槽0/1/2/3均使用 |
| 预留最后一个空槽 | 在无响应的情况下成功预留第 N 个槽 | `last_free=1` |
| 预留即占用、满时仍可 push | 第 N 个槽尚在等待 push 时，已 full=1；其 push 正常发生 | `full_push=1` |
| 满槽请求等待 | 第 N+1 笔 reserve 在 full=1、reserveOk=0 时至少等待4拍 | `blocked_cycles=23` |
| 发送不等于释放 | N 笔均已发送、仍无响应时，至少保持4拍满状态 | `all_sent_full_cycles=23` |
| 响应当拍不能使用新空槽 | 首个响应握手当拍，等待中的 reserve 仍不成功 | `full_response=1` |
| 下一拍恢复 | 首个响应后的下一拍，第 N+1 笔预留成功，槽号等于刚释放的ID | `recovered=1` |
| 完整写回及数据 | reserve/push/send/response均为 N+1，逐地址内存回读与原始激励相同 | 四项计数均为5，五行数据比较通过 |

现有 scoreboard 记录 `full_cycles=27`；`c_reserve_push` 命中5次，`c_full_release` 命中2次。test 的 `full_response` 只记录首次满槽释放，SVA 的 `c_full_release` 记录整轮仿真中的满到非满变化，所以两者次数不同。10 ns时钟下仿真在810 ns结束，4 ns时钟下324 ns结束，两次UVM_WARNING/ERROR/FATAL均为0。

旧的ns调度在32拍对应的时间到达后才等下降沿驱动响应，实际间隔是33拍。改为提前在下降沿准备第 k+32 拍的响应后，实际间隔准确为32拍，所以满槽等待从旧记录的24拍变为23拍。这是DV调度修正，DUT没有修改。

这是确定性定向case，地址和数据没有随机化，运行时未指定随机seed。使用的 generated RTL SHA-256为 `ac3e5cd84054c7cb32d1f1d628a88003533a96cbc760e60af234ae882642960e`，与数据模式case一致。

- [10 ns容量case日志](../../verif_mshr/sim/work/log/wbb_capacity_cycles_10ns.log) / [4 ns日志](../../verif_mshr/sim/work/log/wbb_capacity_cycles_4ns.log)：每笔均等待32拍。
- [10 ns容量case波形](../../verif_mshr/sim/work/wave/wbb_capacity_cycles_10ns.fsdb) / [4 ns波形](../../verif_mshr/sim/work/wave/wbb_capacity_cycles_4ns.fsdb)
- [编译日志](../../verif_mshr/sim/work/log/wbb_cycle_latency_compile.log)
- [10 ns基础case回归](../../verif_mshr/sim/work/log/wbb_base_cycles_10ns.log) / [4 ns回归](../../verif_mshr/sim/work/log/wbb_base_cycles_4ns.log)：各2笔写回，每笔响应间隔2拍。
- [10 ns数据模式case回归](../../verif_mshr/sim/work/log/wbb_data_pattern_cycles_10ns.log) / [4 ns回归](../../verif_mshr/sim/work/log/wbb_data_pattern_cycles_4ns.log)：各1063笔写回，每笔响应间隔2拍。

本case提供 WBR-001、002、004、005、006 和 WBS-005、009 的容量边界证据，覆盖最后一槽预留、满槽拒绝以及已发送未响应的占用保持。N>1时全reserved、长时间待发数据保持、send背压和不同响应顺序仍由后续case完成；本轮 `stalled_cycles=0`，不能作为send背压已经验证的依据。验证点主表保持未闭合，已通过的具体场景登记在证据表。

## 周期延迟的环境自检（2026-11-19）

内存响应以请求握手的采样沿为起点：第 k 拍接受、配置 L 拍延迟，队首没有阻塞且响应ready有效时，在第 k+L 拍握手。L必须至少为1；响应背压或队首阻塞可以延长实际等待。

[内存driver独立自检](../../verif_mshr/test/adapter/wbb_memory_timing_check.sv) 使用真实monitor和memory driver，并从接口事件独立计拍。它不实例化DUT，用于检查验证环境自身的调度。

- 时钟10 ns/4 ns × 延迟1/2/32拍，共6组正常自检通过；每组3笔响应精确满足配置拍数，另有2笔检查响应背压与顺序恢复，5笔内存数据回读均正确。
- 0拍延迟负例正确触发 `MEM_CONFIG` fatal；这属于预期环境错误。
- 严格/延迟push/bind断言自测在10 ns和4 ns下通过。自测普通等待和超时使用时钟沿，停钟复位场景使用持续运行的参考时钟。
- 运行脚本：[check_wbb_memory_timing.py](../../verif_mshr/sim/script/check_wbb_memory_timing.py)。[1拍日志](../../verif_mshr/sim/work/memory_timing/log/period_4_latency_1.log)、[32拍日志](../../verif_mshr/sim/work/memory_timing/log/period_4_latency_32.log)、[0拍负例日志](../../verif_mshr/sim/work/memory_timing/log/period_10_latency_0.log)。

时钟翻转仍使用TB顶层配置的实际时间周期；monitor的 `#1step`、异步复位断言的1 ps及自测等待断言结果的2 ps用于仿真采样和结算，不表示事务延迟，不改成等待整拍。

## 公共检查方法复用（2026-11-19）

等待响应完成、四类事务计数检查、单行C++内存回读比较，以及“恰好/至少出现多少次”的检查，统一在 `wbb_base_test` 实现。
子test保留各自的激励组织、场景观察和数量要求，并继承这些方法。容量case逐项调用 `check_count()` 指定目标，
不再用一大段条件只报一个笼统错误；数据模式case继续只对内存比较成功的数据计数，预置全一失败仍立即fatal。

提取公共方法后，10 ns和4 ns下基础/数据模式/容量三个case均通过，UVM_WARNING/ERROR/FATAL均为0。
事务数仍分别为2、1063、5；容量满槽等待23拍、满状态27拍，所有覆盖计数及结束采样周期均保持不变。

| Case | 10 ns日志 | 4 ns日志 |
| --- | --- | --- |
| 基础写回 | [日志](../../verif_mshr/sim/work/log/wbb_base_helpers_base_10ns.log) | [日志](../../verif_mshr/sim/work/log/wbb_base_helpers_base_4ns.log) |
| 数据模式 | [日志](../../verif_mshr/sim/work/log/wbb_base_helpers_data_pattern_10ns.log) | [日志](../../verif_mshr/sim/work/log/wbb_base_helpers_data_pattern_4ns.log) |
| 容量边界 | [日志](../../verif_mshr/sim/work/log/wbb_base_helpers_capacity_10ns.log) | [日志](../../verif_mshr/sim/work/log/wbb_base_helpers_capacity_4ns.log) |

## 全部非流水 case 的首次回归（修复前，2026-11-19）

清单中的11个非流水case均已实现并按顺序执行，`wbb_pipeline_test` 未实现、未运行。新增8组sequence/test，基础case的数据生成也已移入 `wbb_smoke_sequence`。共享启动、计数和内存比较仍在base test中，具体case只组织激励和检查自己的命中目标。

本轮使用当前4槽generated RTL，SHA-256仍为 `ac3e5cd84054c7cb32d1f1d628a88003533a96cbc760e60af234ae882642960e`。时钟为10 ns和4 ns，随机case使用seed=1/2/3，其余case使用seed=1。共26组：**20组通过、6组失败**。失败没有列入白名单，回归脚本以退出码1结束。

[本轮完整汇总及每组log/FSDB链接](../../verif_mshr/sim/work/regression/reports/run_20261119_080300_487790/summary.md)；[机器可读结果](../../verif_mshr/sim/work/regression/reports/run_20261119_080300_487790/summary.json)。工作目录可被clean清除，提交或归档验证证据时应另外保存这些产物。

| Case | 每组写回数 | 两种时钟下的结果与实际证据 |
| --- | --- | --- |
| base | 2 | 通过，四类事件均为2 |
| data_pattern | 1063 | 通过，九类数据模式均达到规定数量 |
| capacity | 5 | 通过，全部4槽使用，第5笔等待23拍，首次响应后下一拍预留成功 |
| query | 8 | 通过，reserved双命中/单边命中、pending/issued双口组合均命中；同址双命中6拍、异址双命中10拍 |
| reuse | 12 | 通过，每槽使用3次；旧地址不命中而新地址issued命中12拍；A/B/A三轮换数据 |
| send_backpressure | 6 | 失败，槽3挂起后插入槽0，10拍背压中发送载荷改变，见WBB-DUT-001 |
| arbitration | 5 | 通过，4个pending候选，连续4拍发送，4槽各一次，末槽到首槽回绕1次 |
| response_order | 4 | 通过，按实际发送ID的逆序响应，3次乱序事件，释放与仍占用地址查询6拍 |
| event_collision | 6 | 通过，response与reserve/push/send的不同槽交叉各命中1次 |
| delayed_push | 5 | 失败，5笔均延迟push，全reserved保持7拍、最大reserve→push间隔13拍；后续插入候选复现WBB-DUT-001 |
| random | 128 | seed1/3通过，seed2失败；每组32批全部完成，seed2出现3次发送保持违约 |

所有组合的reserve/push/send/response计数都相等，最终内存比较通过；这不抵消中间发生的协议违约。失败组合只有 `WBB_STABILITY` 和 `WBB_DUT_SEND_STABLE`，没有环境输入违约或fatal。所有组合的 `c_overlap` 均为0，确认没有引入上游reserve/push流水。

### 新增共享能力

- `wbb_transaction` 默认仍为完整写回，新增QUERY/IDLE操作，查询由同一个上游driver驱动。
- `push_delay_cycles` 默认1；大于1以及批量预留后push都要求显式 `WBB_ALLOW_DELAYED_PUSH`。批次包含完整事务，整批push完成后才item_done。
- 内存driver增加发送/响应开关、指定ID/随机响应、随机ready和随机周期延迟。已经呈现的响应对象锁定到实际握手，不因策略变化而撤销。
- `wbb_activity_monitor` 只记录IO事件，供场景调度及命中计数；不读取DUT层次、不预测输出、不替代C++模型。
- `wbb_scenario_sequence` 通过sequencer获取配置和IO事件，按采样沿安排控制；数据与地址仍在sequence生成。
- `run_scenario()`、`check_scenario_data()` 统一完成数量、排空和最终内存检查。重复地址最终比较最后一版，每个较早版本仍在send时由已有模型和SVA检查。
- 回归脚本沿用原Makefile，严格/延迟编译产物隔离，逐case/时钟/seed保存日志与波形。

运行全部case：

```sh
python3 verif_mshr/sim/script/run_wbb_regression.py
```

### WBB-DUT-001：send背压期间新候选替换已呈现请求

当前状态：**用户已修复DUT和C++模型，本次26组冷编译回归全部通过**。关联WBS-002、IF-002/004及原Q-01风险。以下保留修复前的复现和定位记录；最新证据见后面的复核回归。

规格依据：[WBB IP规格§8.2](../../Architecture/WBB_IP架构设计文档.md)要求 `send_valid=1 && send_ready=0` 后继续保持valid、地址、数据及ID，即使新槽成为候选也不能替换旧请求。

背压定向case在10 ns时钟下的关键沿前采样如下：

| 采样沿 | 本拍上游/内存事件 | send valid/ready | ID | 地址 | word0 |
| --- | --- | --- | --- | --- | --- |
| 235～265 ns | 槽3的新请求持续等待 | 1/0 | 3 | 0x140 | 0x00050000 |
| 275 ns | 响应旧槽0，释放该槽 | 1/0 | 3 | 0x140 | 0x00050000 |
| 285 ns | 合法reserve槽0，地址0x180 | 1/0 | 3 | 0x140 | 0x00050000 |
| 295 ns | 下一拍合法push槽0 | 1/0 | 3 | 0x140 | 0x00050000 |
| **305 ns** | 没有send握手，但发送载荷已改变 | **1/0** | **0** | **0x180** | **0x00060000** |

输入均合法：槽0在275 ns释放后才重新预留，push严格晚一拍，地址不同且块对齐。235～325 ns连续10个采样沿ready均为0。实际变化发生在295 ns沿后，305 ns的沿前采样捕获它，因此两个检查器在305 ns同时报错。

只读定位显示：generated RTL根据当前 `valid&&!issued` 组合产生候选，`rotK`和`sendIdx`随候选变化。虽然 `rrPtr` 只在发送握手时更新，但没有锁住已经被背压的选择。槽0装载后，rrPtr仍为0，选择却从槽3变为槽0。这是DUT输出违反接口契约，不是DV采样竞争。

该场景下C++预测输出与DUT一致，独立scoreboard保持检查及IO SVA发现了规格违约；模型比较通过不能替代这些规格检查。本次没有修改DUT、C++参考模型或断言要求。

除定向case外，延迟push case在295 ns复现同类问题；随机seed=2在1285、1875、7995 ns复现三次。4 ns时钟下对应相同采样拍，结果一致。

- [定向失败日志](../../verif_mshr/sim/work/regression/strict/log/run_20261119_080300_487790/wbb_send_backpressure_test_p10_s1.log)
- [定向失败波形](../../verif_mshr/sim/work/regression/strict/wave/run_20261119_080300_487790/wbb_send_backpressure_test_p10_s1.fsdb)
- [首次复现的逐拍采样表](../../verif_mshr/sim/work/log/wbb_send_backpressure_edges.tsv)
- [延迟push失败日志](../../verif_mshr/sim/work/regression/delayed/log/run_20261119_080300_487790/wbb_delayed_push_test_p10_s1.log)
- [随机seed2失败日志](../../verif_mshr/sim/work/regression/strict/log/run_20261119_080300_487790/wbb_random_test_p10_s2.log)

单独复现：

```sh
python3 verif_mshr/sim/script/run_wbb_regression.py --tests wbb_send_backpressure_test --periods 10
```

首次回归时WBS-002记为DUT失败，保留上述历史证据。最新修复已通过下面的复核；参数组合、热复位及暂缓的流水场景仍按各自验证点单独安排。

## 用户修复后的复核回归（2026-11-19）

本轮重新核对实际filelist输入，确认 generated RTL已包含 `sendHold/sendHoldIdx`，C++参考模型也已同步保持沿前呈现的请求。没有修改DUT、参考模型、case、driver、scoreboard、SVA或回归脚本。

为避免增量构建沿用旧DPI对象，归档了strict/delayed两种配置的旧编译目录、可执行文件和覆盖库，保留旧日志与波形，再执行完整冷编译。两份编译日志均确认重新编译 `wbb_dpi.cpp`。源文件哈希在运行前后保持一致。

- 运行编号：`run_20261119_092126_919356`。
- DUT SHA-256：`7e55ed10a7f44bdcd8083c43010a7402ee6e4af62e454aaef1d50454c159b3f7`。
- C++ WBB模型 SHA-256：`4e388c0ee239f54ad2a2f86e31df649500bedc68e413d1f01f506d0b7ee29d89`。
- 范围：11个非流水case，10 ns/4 ns两种时钟；random使用seed=1/2/3，其余seed=1。
- **结果：26/26 PASS；每组UVM_WARNING/ERROR/FATAL均为0，所有请求/响应计数平衡。**

此前失败的场景没有被删除或绕过：背压case仍为挂起ID3、插入ID0、10拍停顿和1次候选插入；延迟push仍有5笔延迟、最大间隔13拍、全reserved保持7拍；random seed2仍完成32批128笔、112拍发送背压、11次乱序响应。独立的 `WBB_STABILITY` 和 `WBB_DUT_SEND_STABLE` 均未再报错。

[本轮汇总与每组日志/波形](../../verif_mshr/sim/work/regression/reports/run_20261119_092126_919356/summary.md) · [JSON结果](../../verif_mshr/sim/work/regression/reports/run_20261119_092126_919356/summary.json) · [输入文件哈希](../../verif_mshr/sim/work/regression/reports/run_20261119_092126_919356/inputs.json)。修复过程说明见[用户的DebugNote](../../Architecture/DebugNote/WBB-DUT-001_发送背压保持问题.md)。

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
