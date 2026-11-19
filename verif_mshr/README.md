# WBB UVM 验证框架（模型已接入，待环境审阅）

直接例化 `WriteBackBuffer`，复用 `RefModel/Cache/WriteBackBuffer.hpp` 作为 WBB 参考模型。
后端存储使用 `RefModel/MEM/SparseMemory.hpp` 的纯 C++ 稀疏内存。
基础 `wbb_base_test` 已接入两笔完整写回激励，逐笔经过 reserve、push、内存发送和响应释放。

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
- `src/wbb/model/wbb_predictor.sv`：已有 C++ WBB 模型的 UVM 适配，不重写 WBB 状态机。
- `src/wbb/model/wbb_memory_store.sv`：两个独立 C++ 内存实例及受测地址集合，无 SV 存储算法。
- `src/wbb/component/scoreboard/`：比较模型输出、检查协议、计数守恒和最终存储内容。
- `wbb_compare_item`：同拍比较数据，`actual_sample` 引用 monitor 的实际采样，`expected_*` 保存模型期望值；经 `compare_port` / `compare_export` 传给 scoreboard。
- `dpi/`：C ABI 适配，处理参数、整行转换、对象生命周期和错误返回。
- `test/wbb/`：基础两笔写回与 `wbb_data_pattern_test` 数据图样case；`test/adapter/`：独立 DPI ABI 自检，不实例化 WBB DUT。

上游 `wbb_transaction` 表示一笔完整写回事务，包含随机化字段 `addr`、`line_data`、`q0Addr`、`q1Addr`，三个地址均约束为块对齐。
`writeback_line(addr, line_data, q0Addr, q1Addr)` 或 `step(tr)` 提交完整事务，driver 自动预留并保存槽号，
预留成功后的下一拍 push 整行，随后完成 item；完成 item 不代表内存写回完成。
WBB 满时 driver 保持预留请求并等待，最多 `reserve_timeout_cycles` 拍；超时明确报 fatal。
不再需要 sequence 传递 `accepted/selected_slot` 或分别发送 reserve/push item。
逐拍的 `wbb_sample` 和比较对象不改变粒度，继续记录两个阶段各自的接口行为。
原有 `reserve_line`、`push_line`、`query`、`idle_cycles` 辅助接口已移除；
q0/q1 分别由本笔 transaction 指定，预留等待及 push 阶段保持，空闲时恢复为0。
两个查询地址可以相同或不同，也可以与写回地址不同；逐拍独立改变查询地址的控制后续另行扩展。
`send_ready`、`memWriteResp_valid/id` 只由 memory driver 驱动。
DUT 的 `send_valid/addr/data/id`、`memWriteResp_ready` 由 monitor 观察。
所有 SV 类使用4空格缩进、分行构造函数、extern类外实现和原环境日志宏。

## 每拍流程

1. 上升沿通过 monitor clocking block 的 `input #1step` 获取完整沿前快照。
2. memory driver 消费相同快照：实际写握手触发实际内存更新并登记 `{id, due_time}`；已握手ack才移出队列、释放在途ID。
3. predictor 将快照的上游输入、实际内存ready及实际ack交给C++适配；适配读取 `reserve/full/hasSameAddr/sendReq`，然后只调用一次 `tick()`。
4. 参考模型预测的发送握手独立更新期望内存；实际与预测快照成对发送至scoreboard。
5. 下一下降沿，memory driver 按队列容量驱动ready，将到期的队首响应送给DUT。响应被反压时队首保持，valid/ID保持。

两份内存使用不同对象：实际值只来自DUT，期望值只来自WBB参考模型。
scoreboard逐拍比较容量/空槽/地址查询/发送valid及有效payload，同时独立检查发送反压稳定性。
结束时检查WBB模型、响应队列、在途ID排空，reserve/push/send/ack计数相等，
并对实际/期望写地址的并集逐行回读比较，避免遗漏错误地址写入。

## 时序与配置

`wbb_config` 包含：上游active/passive、总超时、`reserve_timeout_cycles=1000`、`mem_page_size=4096`、
`mem_write_latency_ns=10.0`、`mem_max_pending=WBB_ENTRIES`。
内存代理目前固定启用，支持独立于上游的顺序响应；未加入随机反压/乱序策略。
ready通常为1，仅响应队列达到容量时拉低。

内存在写请求握手时更新。到期时间=接收时刻+配置延迟（ns），
到期后的下降沿驱动响应、下一上升沿握手，因此实际ack延迟按时钟边沿向后取整，
从不早于配置值，且最早在接收后的下一上升沿完成。C++不等待、不重复累计延迟。
当总线返回被反压时，等待时间由实际ready进一步延长。

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
make run_verdi
make check_dpi          # 独立SV/C++数据往返自检，不运行DUT case
```

Makefile沿用原结构，仅补充DPI源码、C++17编译和check_dpi入口。
当前filelist使用 `Design/DCacheMSHR/rtl/WriteBackBuffer.v` 和
`verif_mshr/src/wbb/pkg/wbb_params_pkg.sv`。
`make generate` 已适配这两个位置，由同一个Scala配置生成，随后必须重新编译。
更改WBB槽数前，也必须同步C++配置；适配层会拒绝不一致配置。

运行日志：`work/log/vcs_sim.log`；波形：`work/wave/wave.fsdb`；DPI自检：`work/log/dpi_check.log`。
基础用例成功标记为 `WBB_TEST_PASS`，检查两笔事务四类事件计数、C++预测结果、最终内存内容及IO协议。
旧 work/ 中历史smoke/capacity日志不代表当前框架的验证结论。

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
