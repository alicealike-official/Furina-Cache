# WBB UVM 验证环境

直接例化 `WriteBackBuffer`，复用 `RefModel/Cache/WriteBackBuffer.hpp` 作为 WBB 参考模型。
后端存储使用 `RefModel/MEM/SparseMemory.hpp` 的纯 C++ 稀疏内存。
基础 `wbb_base_test` 已接入两笔完整写回激励，逐笔经过 reserve、push、内存发送和响应释放。
规划中的11个非流水case均已实现。用户修复DUT和C++参考模型后，最新冷编译回归26组全部通过，UVM_WARNING/ERROR/FATAL均为0。
完整结果见[最新回归汇总](sim/work/regression/reports/run_20261119_092126_919356/summary.md)和[验证记录](../验证计划/DCacheWithMshr/WBB_case规划_note.md)。修复前20通过/6失败的报告仍保留用于对照。

## 结构与信号归属

```text
上游 sequence → wbb_agent.driver → reserve / push / q0Addr / q1Addr → DUT
                                                                  ↓ send
                             memory_agent.driver ← 逐拍 monitor ← DUT
                                ↓          ↓
                         实际 SparseMemory  send_ready / memWriteResp → DUT

逐拍 monitor → predictor → DPI → 已有 C++ WBB model
                    ↓                  ↓
               配对实际/预测        期望 SparseMemory
                    ↓                  ↓
                 scoreboard ← 结束时两份内存回读比较
```

- `src/common/`：时钟、复位、原环境日志宏。
- `src/wbb/component/agent/wbb_agent.sv`：上游 driver/sequencer 和统一逐拍 monitor。
- `src/wbb/component/agent/wbb_memory_agent.sv`：反应式内存代理，无需上游 sequence 伪造 ack。
- `src/wbb/component/monitor/wbb_activity_monitor.sv`：记录已发生的IO事件、查询阶段和场景命中；通过采样事件通知sequence，不预测DUT输出。
- `src/wbb/component/agent/wbb_sequencer.sv`：向场景sequence提供配置及只读IO事件记录。
- `src/wbb/model/wbb_predictor.sv`：已有 C++ WBB 模型的 UVM 适配，不重写 WBB 状态机。
- `src/wbb/model/wbb_memory_store.sv`：两个独立 C++ 内存实例及受测地址集合，无 SV 存储算法。
- `src/wbb/component/scoreboard/`：比较模型输出、检查协议、计数守恒和最终存储内容。
- `wbb_compare_item`：同拍比较数据，`actual_sample` 引用 monitor 的实际采样，`expected_*` 保存模型期望值；经 `compare_port` / `compare_export` 传给 scoreboard。
- `dpi/`：C ABI 适配，处理参数、整行转换、对象生命周期和错误返回。
- `test/wbb/`：基础、数据模式、容量、查询、复用、背压、仲裁、响应顺序、事件交叉、延迟push和随机case；不包含pipeline case。
- `test/adapter/`：独立DPI和内存driver自检，不实例化WBB DUT。

上游 `wbb_transaction` 默认表示一笔完整写回事务，包含随机化字段 `addr`、`line_data`、`q0Addr`、`q1Addr`，三个地址均约束为块对齐。
`writeback_line(addr, line_data, q0Addr, q1Addr)` 或 `step(tr)` 提交完整事务，driver 自动预留并保存槽号，
预留成功后的下一拍 push 整行，随后完成 item；完成 item 不代表内存写回完成。
WBB 满时 driver 保持预留请求并等待，最多 `reserve_timeout_cycles` 拍；超时明确报 fatal。
不再需要 sequence 传递 `accepted/selected_slot` 或分别发送 reserve/push item。
逐拍的 `wbb_sample` 和比较对象不改变粒度，继续记录两个阶段各自的接口行为。
`reserve_line`、`push_line` 不作为独立item提交；`query(q0,q1,cycles)` 和 `idle_cycles(cycles)` 使用独立查询/空闲操作，期间没有reserve/push。
q0/q1 分别由本笔 transaction 指定，预留等待及 push 阶段保持，空闲时恢复为0。
两个查询地址可以相同或不同，也可以与写回地址不同。所有上游信号仍只由一个driver驱动。
普通写回的 `push_delay_cycles` 默认1，只有显式延迟编译模式才能大于1。
`wbb_batch_transaction` 包含多笔完整写回：先全部reserve，保持指定采样拍数，再逐笔push；整批完成才item_done，整个过程没有reserve/push同拍。
`send_ready`、`memWriteResp_valid/id` 只由 memory driver 驱动。
DUT 的 `send_valid/addr/data/id`、`memWriteResp_ready` 由 monitor 观察。
所有 SV 类使用4空格缩进、分行构造函数、extern类外实现和原环境日志宏。

## Test 公共检查方法

通用方法只在 [wbb_base_test.sv](test/wbb/wbb_base_test.sv) 实现，派生test直接继承调用。

| 方法 | 用途 |
| --- | --- |
| `require_active_agent()` | 启动激励前检查sequencer存在 |
| `wait_for_drain()` | 等待最后一笔发送和响应完成，保留4个下降沿的观察时间和总超时保护 |
| `get_writeback_counts()` | 保存当前reserve/push/send/response计数，供阶段结束时检查新增笔数 |
| `check_writeback_counts(expected, before)` | 统一检查四类事件；before默认全0，表示检查整个case的总数 |
| `check_count(name, actual, expected, at_least)` | 统一检查计数恰好相等或至少达到要求，缺失项逐个报出名称、实际值和要求 |
| `check_memory_line(addr, expected, label, fatal_on_mismatch)` | 统一经C++/DPI读取实际内存并比较整行，返回是否相同；准备阶段可要求失败即fatal |
| `run_scenario(seq, expected)` | 启动场景sequence、等待响应、检查完整事务数量和最终内存 |
| `check_scenario_data(seq)` | 对多次写入同一地址使用最后一版数据做最终内存比较；每次发送仍由模型及SVA独立检查 |

capacity子test负责观察满槽和释放事件、指定各项需要出现的次数；pattern子test负责各数据模式的数量要求，
只有内存比较成功才增加对应模式的计数。它们调用base的判断和报错方法，原有测试要求和等待顺序保持不变。
公共计数和内存错误分别使用 `WBB_TEST_COUNT`、`WBB_TEST_MEMORY`，诊断中包含具体场景名称。

## 每拍流程

1. 上升沿通过 monitor clocking block 的 `input #1step` 获取完整沿前快照。
2. memory driver 消费相同快照：实际写握手触发实际内存更新并登记 `{id, accepted_cycle, due_cycle}`；响应握手后才移出队列、释放在途ID。
3. predictor 将快照的上游输入、实际内存ready及实际ack交给C++适配；适配读取 `reserve/full/hasSameAddr/sendReq`，然后只调用一次 `tick()`。
4. 参考模型预测的发送握手独立更新期望内存；实际与预测快照成对发送至scoreboard。
5. activity记录沿前场景及已接受事件，唤醒等待这些事件的sequence；sequence只修改调度配置，不直接驱动接口。
6. 下一下降沿，memory driver按接收策略驱动ready，并从到期请求中按策略选择响应。已经呈现的响应锁定到实际握手，期间valid/ID保持。

两份内存使用不同对象：实际值只来自DUT，期望值只来自WBB参考模型。
scoreboard逐拍比较容量/空槽/地址查询/发送valid及有效payload，同时独立检查发送反压稳定性。
结束时检查WBB模型、响应队列、在途ID排空，reserve/push/send/ack计数相等，
并对实际/期望写地址的并集逐行回读比较，避免遗漏错误地址写入。

## 时序与配置

`clk_rst_config` 只由 `tb/tb_top.sv` 创建，按
`tb_top → wbb_base_test → wbb_environment → clk_rst_agent → clk_rst_driver`
逐级通过config_db传递同一个对象。各级只获取配置并传给直接子组件；配置缺失或句柄为空时立即fatal，
不再自行创建默认配置。默认时钟周期10 ns、启动复位4拍；TB顶层支持 `+CLOCK_PERIOD_NS=4` 修改时钟周期。
`wbb_capacity_test` 直接设置响应延迟拍数，仅读取 `clk_cfg.initial_reset_cycles` 计算总超时预算，不创建或改写时钟配置。

本次基础、数据模式和容量case回归均通过，UVM_WARNING/ERROR/FATAL均为0。
容量case的 `+UVM_CONFIG_DB_TRACE` 日志见 `sim/work/log/wbb_capacity_clock_config.log`，
已核对各级set/get使用同一个时钟配置对象。

`wbb_config` 包含：上游active/passive、总超时、`reserve_timeout_cycles=1000`、`mem_page_size=4096`、
`mem_write_latency_cycles=2`、`mem_max_pending=WBB_ENTRIES`。内存延迟必须至少为1拍。
默认仍是顺序响应、固定延迟和容量允许时ready=1。场景可通过以下配置控制内存侧：

| 配置 | 用途 |
| --- | --- |
| `mem_send_enable` | 允许/暂停接收send，仍受待响应容量限制 |
| `mem_response_enable` | 允许/暂停选择新响应；已经呈现的响应不能撤回 |
| `mem_response_order` | FIFO、LIFO、随机或指定ID，选择范围只包含合法已到期请求 |
| `mem_selected_response_id` | 指定响应策略使用的实际在途ID |
| `mem_random_ready` / `mem_ready_percent` | 插入随机send背压 |
| `mem_random_latency` / `mem_min_latency_cycles` / `mem_max_latency_cycles` | 每笔接受时确定随机响应等待拍数 |

场景sequence通过 `wbb_scenario_sequence` 取得配置与IO事件统计，控制修改对齐采样沿之后，下一下降沿应用。
`wbb_activity_monitor` 保存的是接口历史，供调度和覆盖计数使用；C++参考模型及SVA继续负责行为正确性。

内存在写请求握手时更新。若请求在采样沿 E[k] 接受，延迟配置为 L 拍，就保存 `due_cycle=k+L`。
在 E[k+L-1] 之后的下降沿准备响应；队首未被其他响应阻塞且ready有效时，恰好在 E[k+L] 握手。
例如L=1表示紧接的下一上升沿响应。driver使用 `cycle+1 >= due_cycle` 准备下一拍输出，
不会等到到期拍之后才开始驱动，也不使用物理时间换算协议延迟。
响应被反压或前一个响应尚未完成时，可以晚于到期拍握手，期间valid和ID保持；C++存储模型不负责等待。

默认2拍保持此前10 ns时钟下基础case的实际响应拍数。容量case直接配置32拍；旧时间调度在该场景实际等了33拍，
现已修正。10 ns和4 ns时钟下三个case均通过，逐笔响应拍数分别保持2、2、32。
`+UVM_VERBOSITY=UVM_HIGH` 时，`MEM_RESPONSE_TIMING` 日志列出接受拍、响应拍和实际间隔。

时钟发生器按配置的半周期时间翻转；`input #1step` 和复位断言的1 ps结算等待用于避免仿真采样竞争，
它们不是事务延迟。独立断言自测的普通等待及总超时也改为按时钟沿计数，停钟场景使用持续运行的参考时钟。

仅支持启动复位：DUT使用高有效异步reset，TB低有效rst_n取反，下降沿释放。
两个内存对象初始化为空，WBB模型复位；运行中再次复位会明确报错。
上游driver当前串行完成一笔事务的reserve/push后再处理下一笔，item之间有空闲间隔；
后续若需要前一笔push与后一笔reserve同拍，再扩展流水驱动，完整transaction的语义不变。

## 参数与错误处理

Scala生成RTL，SV参数包定义接口位宽；C++ WBB模型继续使用已有 `RefModel/Cache/params.hpp`。
创建DPI模型时核对地址宽、数据宽、块大小、WBB条目数、槽ID宽、总线ID宽，
不一致报fatal，避免将2槽SV直接连接到4槽C++模型。
当前验证默认四槽配置。仅修改plusarg不能改变编译期容量。

适配按32位packed字传输整行，字0对应最低位；内存模型按字节显式转换，
不使用主机端序的reinterpret_cast来解释行数据。
有效载荷中的X/Z在进入两态C++模型之前报错。
非法句柄、参数、模型输入及C++异常转换为失败状态与错误字符串；异常不跨DPI边界。
final_phase销毁各模型实例，存储容器自动释放页面。

## 构建与检查

```sh
# 纯C++检查，不需要SystemC/VCS
make -C RefModel run-memory run-dpi run-wbb

cd verif_mshr/sim
make vcs_compile
make vcs_simulate       # TEST_NAME为空，运行基础两笔写回
make vcs_simulate TEST_NAME=wbb_data_pattern_test
make vcs_simulate TEST_NAME=wbb_capacity_test
make run_verdi
make check_dpi          # 独立SV/C++数据往返自检，不运行DUT case
python3 script/check_wbb_memory_timing.py  # 独立检查内存driver的响应拍数和背压保持
```

Makefile沿用原结构。当前filelist实际使用 `verif_mshr/generated/WriteBackBuffer.v` 和
`verif_mshr/generated/wbb_params_pkg.sv`。现有 `make generate` 的输出路径仍是旧位置，重新生成时需要核对并同步到filelist使用的位置，随后重新编译。
更改WBB槽数前，也必须同步C++配置；适配层会拒绝不一致配置。

运行日志：`work/log/vcs_sim.log`；波形：`work/wave/wave.fsdb`；DPI自检：`work/log/dpi_check.log`。
基础用例成功标记为 `WBB_TEST_PASS`，检查两笔事务四类事件计数、C++预测结果、最终内存内容及IO协议。
旧 work/ 中历史smoke/capacity日志不代表当前框架的验证结论。

在仓库根目录按验证计划顺序运行全部非流水case：

```sh
python3 verif_mshr/sim/script/run_wbb_regression.py
```

脚本默认运行10 ns/4 ns时钟，随机case使用seed=1/2/3，其余case用seed=1，总计26组。
严格/延迟编译产物分开放在 `sim/work/regression/strict` 和 `delayed`，每轮日志、波形、TCL、覆盖名称单独保存。
支持 `--tests`、`--periods`、`--random-seeds` 和 `--skip-compile`。有任何真实错误时最终退出码为1，失败后继续其余case，不豁免已知DUT错误。
回归结束后，终端自动打印对齐的汇总表、通过/失败/未运行数量、总结果和失败日志路径。
PASS使用绿色，FAIL使用红色，WARNING/NOT RUN使用黄色；窄终端省略profile和事件数列，详细内容仍在报告中。
`--color auto` 为默认值：检测到交互终端才启用颜色，并遵循 `NO_COLOR`；可用 `--color always` 强制或 `--color never` 关闭。
JSON、Markdown和仿真日志保持纯文本，颜色只用于终端输出。未运行与未完成项单独统计，仍使整体结果失败。

只重新展示已有报告，无需编译或仿真，也不会改写结果文件：

```sh
python3 verif_mshr/sim/script/run_wbb_regression.py \
    --report verif_mshr/sim/work/regression/summary.json
```

`summary.json` 和 `summary.md` 记录配置、DUT哈希、各case结果及证据链接；最新归档位于 `reports/run_20261119_092126_919356/`，另有 `inputs.json` 记录本轮RTL、Scala、模型和DPI源码的哈希。

单独运行延迟push case时必须显式选择对应编译配置：

```sh
make -C verif_mshr/sim vcs_compile WORK_DIR=work/delayed/ SVA_DEFINES=+define+WBB_ALLOW_DELAYED_PUSH
make -C verif_mshr/sim vcs_simulate WORK_DIR=work/delayed/ TEST_NAME=wbb_delayed_push_test
```

历史DUT问题 **WBB-DUT-001** 已由用户在DUT和C++模型中补充发送保持后修复。
本次冷编译复核中，背压case、延迟push case及随机seed=2在10 ns/4 ns下全部通过，目标场景仍命中，独立保持断言没有放宽。
修复前的问题时序和日志保留在验证记录中；本结论对应当前4槽配置及已执行种子，不替代其他参数或暂缓流水场景的验证。

修改时钟周期可以在编译后直接给TB顶层传参，例如：

```sh
cd verif_mshr/sim
work/run/simv +UVM_TESTNAME=wbb_capacity_test +CLOCK_PERIOD_NS=4 \
    +UVM_VERBOSITY=UVM_HIGH -cm line+cond+fsm+branch+tgl+assert \
    -cm_dir work/simv.vdb -cm_name wbb_capacity_4ns -l work/log/wbb_capacity_4ns.log
```

`test/adapter/wbb_memory_timing_check.sv` 不实例化DUT，复用真实monitor、memory driver和C++稀疏内存。
通过独立的接口采样计数，检查10 ns/4 ns时钟下的1/2/32拍响应，以及两笔响应被背压时的保持和恢复。
六种正常组合通过，0拍配置的负例正确报 `MEM_CONFIG` fatal。日志保存在 `sim/work/memory_timing/log/`。
`make check_sva` 的严格、延迟及bind自检在默认10 ns和额外4 ns运行下均通过；自测中的预期断言错误不属于DUT失败。

## 数据图样 case（2026-11-19）

`wbb_data_pattern_test` 继承基础test，复用现有driver、C++模型、scoreboard及SVA。
专用 `wbb_data_pattern_sequence` 在 `body()` 中生成图样、随机化数据、分配地址并提交事务；
test只配置、调用 `start()`、等待排空及检查结果。预置和正式图样由两个sequence实例分别执行，
test在两者之间等待预置响应并回读确认。sequence按值保存原始激励，通过只读getter供test检查，
不直接访问environment、vif或C++模型。
覆盖全0、全1、逐字递增、逐字节递增、AA/55交替位、整行逐位walking-1/0，以及32笔随机整行。
默认512位行共1062个图样，另有1笔全一预置写回用于检查全零覆盖已有数据。
排空后，经C++稀疏内存的只读封装 `memory.read_actual()` 与原始激励逐地址比较，
并检查各图样数量和reserve/push/send/response精确计数。

固定seed=20261119运行32070 ns，四类事件均1063，UVM_WARNING/ERROR/FATAL均为0。
sequence拆分后的日志为 `sim/work/log/wbb_data_pattern_sequence_seed20261119.log`，对应波形为
`sim/work/wave/wbb_data_pattern_sequence_seed20261119.fsdb`。原两笔基础case回归也通过；
纯C++稀疏内存检查在本case首次实现时已通过。
验证点映射和覆盖范围见[case规划note](../验证计划/DCacheWithMshr/WBB_case规划_note.md)。

固定种子复现可在编译后直接运行，不需要修改Makefile：

```sh
cd verif_mshr/sim
work/run/simv +UVM_TESTNAME=wbb_data_pattern_test +ntb_random_seed=20261119 \
    -cm line+cond+fsm+branch+tgl+assert -cm_dir work/simv.vdb \
    -cm_name wbb_data_pattern_sequence_seed20261119 -l work/log/wbb_data_pattern_sequence_seed20261119.log
```

## 容量 case（2026-11-19）

`wbb_capacity_sequence` 连续提交 `WBB_ENTRIES+1` 笔不同地址和数据的写回。
`wbb_capacity_test` 把内存待响应容量设为槽数，响应延迟设为 `4*WBB_ENTRIES+16` 拍，
使前N笔已发送但尚未响应时，第N+1笔必须等待空槽。test通过现有monitor的analysis连接观察接口，
检查满状态下的push、等待请求、响应当拍不提前预留，以及下一拍成功使用刚释放的槽。
最后检查N+1笔完整事务和C++稀疏内存回读，继续复用原有参考模型、scoreboard及SVA。

默认4槽、32拍响应延迟运行通过：4槽均使用，第5笔等待23拍后成功，
reserve/push/send/response均为5，full_cycles=27，`c_full_release`命中2次。
10 ns时钟下810 ns结束，4 ns时钟下324 ns结束；两次采样周期数和所有响应的32拍间隔相同。
UVM_WARNING/ERROR/FATAL均为0；基础case和数据模式case在两种时钟下也通过。
本case使用确定的地址和数据，没有随机化。

最新运行日志为 `sim/work/log/wbb_capacity_cycles_10ns.log` 和 `wbb_capacity_cycles_4ns.log`，
对应波形在 `sim/work/wave/` 下，使用相同文件名前缀。
验证点对应关系和尚未覆盖的场景见[case规划note](../验证计划/DCacheWithMshr/WBB_case规划_note.md)。

## 本次验证（2026-11-17）

- 纯C++稀疏内存检查、DPI适配检查、已有WBB模型测试通过。
- VCS编译/链接通过，基础环境运行至200 ns，UVM_WARNING/ERROR/FATAL均为0，FSDB生成正常。
- 独立SV/C++ DPI检查通过，验证packed整行数据、参数不一致、模型tick顺序、实例隔离和销毁。
- 未运行新WBB功能case、随机压力或热复位；内存代理的复杂并发行为留待后续case覆盖。

### 上游完整事务接口调整

调用示例：`writeback_line(addr, line_data, q0Addr, q1Addr)`。也可以创建/随机化 `wbb_transaction` 后调用 `step(tr)`。
随机化时自动约束块对齐；手动赋值的非对齐写回或查询地址在driver中报错。
本次通过临时接口桩独立检查了两笔完整item的reserve→下一拍push、槽号锁存、整行数据、
等待空槽和无需等待内存ack的完成语义，并验证了无空槽时的预期超时。
未新增DUT功能case。当前 `wbb_sample.rst_n` 被注释而消费方仍引用它，
因此上述结果仅代表独立driver检查，完整环境编译需先统一该复位字段接口。


## WBB IO 架构契约与 SVA

独立规格见 [WBB IP 架构设计文档](../Architecture/WBB_IP架构设计文档.md)，依据Cache架构和顶层IO制定。
用户确认的目标是异步低有效复位；当前DUT/TB复位接线留待用户修改，本次没有改变接线。
默认reserve成功后严格下一拍push，可在编译时通过
`SVA_DEFINES=+define+WBB_ALLOW_DELAYED_PUSH` 显式允许更晚push。

`src/wbb/bind/wbb_io_assertions.sv` 只记录IO历史，检查生命周期、容量与查询、
有效载荷、反压保持、ID归属和轮询超越界。`bind_wbb.sv` 将其连接到tb_top接口线，
不访问DUT内部寄存器；两文件已列入tb.f。
输入违约报告WBB_ENV_*，DUT输出违约报告WBB_DUT_*。

```sh
make -C verif_mshr/sim check_sva
```

自测使用人工IO轨迹，不实例化WBB DUT。严格/延迟模式各27个场景及UVM bind检查通过；
负例故意触发指定断言，不能把这些预期error当成DUT回归结果。
本结果只验证checker；当前完整环境的rst_n字段接口不一致仍需另外处理。


## 基础激励运行结果（2026-11-18）

`wbb_base_test::run_sequence()` 使用已有 `wbb_base_sequence` 辅助接口，发送块地址
`BLOCK_SIZE` 和 `2*BLOCK_SIZE` 的两笔写回；两行分别使用 `0x10000000 + word_index`
和 `0x20000000 + word_index` 的数据。q0查询当前地址，q1查询另一块地址。
发送结束后等待环境排空，核对reserve/push/send/response增量均为2。

当前 `wbb_sample.rst_n` 已恢复声明，完整环境编译和仿真通过。
本次仿真200 ns结束，四类事务计数均为2，UVM_WARNING/ERROR/FATAL均为0，
`c_reserve_push` 命中2次，FSDB已更新。满槽、并发重叠和随机反压不属于该基础激励的覆盖范围。
