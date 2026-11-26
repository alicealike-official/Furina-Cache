# DUT代码覆盖率

本流程只统计Line、Condition、Branch、FSM、Toggle五项代码覆盖率。不新增covergroup/cross，不报告assert或group分数。既有UVM、原C++模型和SVA继续检查正确性，原有场景计数仍作为case通过条件，不能把它们当成功能覆盖率百分比。

## 收集范围

| 结果 | 仪表/报告范围 |
| --- | --- |
| WBB独立IP | tb_top.dut；strict与显式delayed配置使用同一固定规格RTL，在模型可兼容时合并 |
| MSHR独立IP | mshr_tb_top.dut |
| DCache/self_rtl | dcache_tb_top.dut下的DCache、CacheMem、MSHR、WBB自研代码；官方StreamFifo实现单独列出 |
| DCache/whole_dut | 同一DUT树，包括两个官方StreamFifo模块 |

收集以DUT树为起点，最终报告显式排除bind到DUT内的探针/断言封装子树；UVM/testbench/DPI/SVA模块不计分。首轮原始库保留部分bind辅助测量数据，最终URG范围审计已过滤；脚本后续编译也排除这些子树。DCache中IP的覆盖率只来自CPU驱动的集成case，不拿独立IP数据补集成缺口。仅统计当前固定FIFO配置，不包含已移出的参数扩展、其它策略或旧响应处理。

## 设置

- `-cm line+cond+branch+fsm+tgl`：代码五项，无assert/group指标。
- `-cm_line contassign`：包括Spinal生成RTL中的连续赋值，不能直接与旧默认行覆盖率比较。
- `-cm_cond allops+anywidth+tf`：包括非逻辑运算、宽表达式及RTL任务/函数条件。
- `-cm_tgl mda`：包括存储数组toggle。
- `-cm_fsmopt allowTmp+report2StateFsms`：按工具支持识别临时变量赋值与两状态FSM，不手写模型凑FSM分数。
- 没有使用手工line/bin排除、`-cm_noconst`或`-elfile`来提高分数。官方FIFO的分列属于范围说明，不是对自研代码的waiver。

若VCS没有识别可统计FSM，报告为N/A、0个对象，不能记成100%。每项保留covered/coverable分母，不只看综合平均分。

## 运行

```bash
python3 -B verif_mshr/coverage/run_code_coverage.py
```

默认固定10ns，随机/长跑三个种子，包含现有全部正向case与本地复位case；WBB支持的case同时跑serial/pipeline，延迟push单独编译。代码覆盖率不需要将同一组按周期缩放的激励重复收集两次；需要双周期时用`--periods 10 4`。所有实际周期仍由clock driver测量，并和请求值比较。

可用选项：`--modules wbb mshr dcache`、`--seeds 1 2 3`、`--skip-long`、`--tests TEST_NAME ...`、`--waves`。默认不重复保存FSDB以减少覆盖率长跑开销；仿真日志、VDB和命令始终保留，失败时可按记录命令加波形复现。

每轮使用`work/run_TIMESTAMP`独立目录，重新生成RTL、冷编译四套profile，不运行clean或混入历史数据库。每个case/输入模式/周期/种子使用独立VDB和唯一cm_name，避免覆盖同名数据。只有进程、UVM、SVA、完成标记、实际时钟和VDB记录均通过的case进入合并；失败数据保留，整体状态不改为通过。

URG输出HTML与文本报告，原始单case数据库、合并数据库、完整日志、实际命令与输入哈希均保留。没有自动排除未命中的代码，也没有因覆盖率未达100%自动改变DUT。覆盖率结果用于发现漏测路径，与验证点清单的逻辑闭合分别记录。

## Makefile接口

三套Makefile只增加可选的COVERAGE_METRICS、COVERAGE_OPTIONS、COVERAGE_DATABASE变量，原普通回归默认设置保持兼容。本流程显式选择代码五项、DUT范围及独立数据库，不影响现有常规仿真入口。


## 已完成基线

[2026-11-26实际结果](RESULTS.md)：129/129仿真通过，五项代码覆盖率、DCache内部模块明细和未命中数量均留档。当前不是全代码100%闭合，没有自动waiver或新功能覆盖组。
