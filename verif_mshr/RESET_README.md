# WBB / MSHR / DCache本地复位验证

日期：2026-11-26。最终[18/18报告](sim_dcache/work/reset_regression/run_20261126_095417/summary.md)、[逐阶段命中](sim_dcache/work/reset_regression/run_20261126_095417/reset_evidence.json)。两种周期10ns/4ns，所有组UVM warning/error/fatal为0。12组复位case共执行52次复位、598次专项条件检查；另6组正常功能复核通过。

## 本轮范围

用户确认异步低有效；不要求tag/data清零；只验证本地清空，旧响应处理暂缓。复位检查对象包括有效/脏位、请求与响应valid、锁、旁路/流水/待push状态及FIFO策略初值。没有要求无效载荷、空槽编号或ready统一为0。

已发送/等响应场景使外部旧响应源保持静默。TB在复位时清理自己的旧响应调度并显式记录取消数量，仅为维持合法激励；没有把旧响应送回新事务，也不因此认为DUT具备系统旧ID隔离能力。实际后端已经接受的写内容保留。CPU期望在复位后以实际后端为起点，随后继续按新请求接受顺序更新，不要求保留复位前未写回的脏Cache内容。

最终验收只引用UVM/SVA。本轮不以额外门级分析关闭物理recovery/removal；RST-011物理部分继续保留缺口。没有新增综合或修改DUT模块逻辑来获取PASS。

## Case与实际阶段

| Case | 每组复位次数 | 必须先到达的实际状态及检查 |
| --- | ---: | --- |
| wbb_reset_test | 4 | 空闲复位；时钟运行/停止×释放首拍/次拍reserve四组合；复位后普通reserve/push/send/ack完成 |
| wbb_reset_active_test | 3 | RESERVED且未push、满槽PENDING且send受阻、全部ISSUED且外部响应静默；每次清空后重新占满全部槽并完成写回 |
| mshr_reset_test | 4 | 空闲复位四组合；首拍/次拍分别读/写alloc，随后内存/fill/replay完成，查询和全锁矩阵为空 |
| mshr_reset_active_test | 4 | SEND受阻、fill受阻、replay受阻、全部Entry等待静默外部响应；分别停钟清空并重新请求 |
| dcache_reset_test | 4 | 32set×4way有效且脏，全部FIFO顺序先改变；检查128个valid/dirty清零、32组FIFO恢复初序，旧地址重新取行；运行/停钟×首拍/次拍四组合 |
| dcache_reset_active_test | 7 | 写队满与旁路/流水冻结、读队满、脏淘汰待push、WBB满待发、已fill且replay受阻、读等待响应、WBB已发待确认；停钟清空后恢复正常请求 |

正常功能复核为wbb_data_pattern_test、mshr_smoke_test、dcache_read_during_write_test各两周期。既有原C++模型、稀疏内存、scoreboard和IO SVA全部继续运行。没有新写Cache行为模型或使用force/后门写入。

所有阶段在前置状态实际命中后执行，检查失败立即产生UVM错误，最终必须同时满足阶段数量、复位数量和检查计数。每阶段完成后输出RESET_STAGE_COVERAGE，整组输出RESET_COVERAGE；不能只凭test执行到末尾算通过。停钟时检查实际上升沿计数没有增加，输出清空检查发生在下一有效沿之前。短暂等待均为时钟周期的分数，只用于仿真调度稳定，不定义物理复位传播时间。

## 环境修改

- clk_rst_driver仍是唯一时钟/复位驱动，增加assert_reset、release_reset及实际上升沿计数；时钟配置继续只由TB创建并逐级传递。
- 普通driver外层处理复位取消并撤销自己拥有的输入；MSHR的复位边界alloc有显式TB标记，复位后真实空态下在首个下降沿准备，不增加普通事务的提交捷径。
- 原predictor通过已有DPI重置原C++对象，并把复位采样交给实际事件scoreboard清理旧区间。MSHR/WBB/CPU/内存的取消数量单独记账，不增加真实响应或release计数，不清已经报出的错误。
- 观察器排空条件包含实际取消量，保留累计覆盖；DCache被动IP环境继承同一局部复位配置。
- 各内存代理在异步复位时撤销valid，清理自己的旧调度，保留实际SparseMemory内容。allow_reset_cancellation默认关闭，普通case仍拒绝无声明的意外取消；本地非空复位台架显式启用。
- WBB的验证生成入口WbbVerificationVerilog补齐ASYNC/LOW，TB从.reset(~rst_n)改为.resetn(rst_n)。这是DV生成/接线修正；WriteBackBuffer、Mshr、DCache模块逻辑未修改。

## 失败及归因

MSHR初次非空case超时：SEND阶段4个Entry已被复位取消，新的1笔请求已完成，但旧排空条件仍要求累计alloc=release，忽略取消量。修复为实际release加cancelled_entries，保留真实计数。原[超时日志](sim_dcache/work/reset_regression/run_20261126_095417/history/reset_mshr_active_first.log)、[波形](sim_dcache/work/reset_regression/run_20261126_095417/history/reset_mshr_active_first.fsdb)与[修复后首轮日志](sim_dcache/work/reset_regression/run_20261126_095417/history/reset_mshr_active_retry.log)留档。

WBB加入ISSUED复位阶段后，[中间回归](sim_dcache/work/reset_regression/run_20261126_094210/summary.md)16/18通过，两组WBB超时：旧等待条件仍要求累计send=response，忽略复位取消的4笔确认义务。新写回已完成但等待无法结束。修复为真实response加cancelled_responses，不伪造ACK。

[版本对比](sim_dcache/work/reset_regression/run_20261126_095417/dut_model_comparison.json)确认WBB超时轮与最终轮的生成RTL和原C++模型哈希未变化。上述两类超时均由DV等待条件导致；没有通过改DUT或放宽功能比较获得PASS。历史失败保持FAIL。

另发现新回归脚本错误地假设WBB Makefile会转发SIM_ARGS，导致早期标4ns的3组实际仍是10ns。原始报告保留，增加[时钟审计版](sim_dcache/work/reset_regression/run_20261126_094732/summary.clock_audited.md)，不使用它作为4ns通过证据。现改为直接向simv传参，共用时钟driver测量实际周期；回归同时核对配置值、测量值和请求值。最终095417轮18组实际周期全部正确，只有该轮作为最终双周期闭合证据。

## 当前闭合情况

| 模块 | 已闭合/总数 | 仍未闭合 |
| --- | --- | --- |
| WBB | 50/50 | 无；RST-010、RST-011已移出，不计为通过 |
| MSHR | 79/79 | 同上 |
| DCache顶层 | 151/151 | 同上 |

用户后续决定将RST-010、RST-011移出当前验收清单，不再列为部分覆盖或待补任务，不计为通过。已完成的本地清空与恢复测试保留；当前闭合不包含系统旧响应和物理释放时序。

## 重跑

```bash
python3 -B verif_mshr/script/run_reset_regression.py
```

默认重新生成/编译三模块，执行全部18组，并在终端用颜色打印PASS/FAIL。只跑某一模块可用`--modules wbb`、`mshr`或`dcache`；周期由`--periods 10 4`指定。源文件哈希、日志、FSDB、构建结果和每阶段证据分别留档，不覆盖历史运行。
