# 三模块代码覆盖率基线

日期：2026-11-26。正式收集[129/129仿真通过](work/run_20261126_101423/summary.md)，实际周期全部测量为10ns；随机和长跑seed1/2/3，包含现有正常case、本地复位和WBB支持的serial/pipeline/delayed模式。VCS与URG版本均为O-2018.09-SP2。未新增功能覆盖组，未修改DUT或原模型算法。

## 主结果

| 范围 | Line | Condition | Branch | FSM（工具自动提取） | Toggle |
| --- | ---: | ---: | ---: | ---: | ---: |
| WBB独立IP | 100.00% | 99.23% | 100.00% | N/A | 95.61% |
| MSHR独立IP | 91.57% | 79.18% | 86.31% | 90.00% | 90.61% |
| DCache集成自研RTL | 99.05% | 99.57% | 98.72% | 90.00% | 85.17% |
| DCache完整DUT（含官方FIFO） | 99.02% | 99.55% | 98.68% | 90.00% | 85.20% |

DCache自研范围包含DCache、CacheMem、MSHR、WBB四个实际模块，不含两个官方StreamFifo实现。完整DUT报告另列。两者均明确排除bind到DUT内的探针/断言封装及其接口等验证辅助子树；UVM和DPI代码不计分。没有对真实自研DUT的未命中行或bin添加waiver。

WBB没有工具提取的FSM对象，N/A不是100%。MSHR的自动FSM对象4个编码态均命中，转移9/10，分数按URG转移目标计；未命中编码转移为'h2→'h1。此处不把工具编码直接映射为架构状态，也未判断该转移是否可达或加入排除。

## DCache内部模块明细

以下各行仅使用CPU驱动的顶层case，不把独立IP数据补进来。

| 模块 | Line | Condition | Branch | FSM | Toggle |
| --- | ---: | ---: | ---: | ---: | ---: |
| DCache顶层自身 | 100.00% | 97.67% | 100.00% | N/A | 94.25% |
| CacheMem | 100.00% | 100.00% | 100.00% | N/A | 84.52% |
| MSHR（集成） | 91.57% | 99.56% | 86.25% | 90.00% | 90.48% |
| WBB（集成） | 100.00% | 98.46% | 100.00% | N/A | 95.80% |

独立IP与集成分数分别保留，不平均或跨层级合并。DCache集成自研范围的218个行缺口及220个分支缺口均在MSHR模块；Toggle缺口主要来自CacheMem，缺93,033个方向目标。一个信号位通常有两个toggle方向目标，此数不能直接等同于寄存器位数。

## 原始缺口数量

| 范围 | 未命中行目标 | 未命中条件目标 | 未命中分支目标 | 未命中FSM转移 | 未命中Toggle方向目标 |
| --- | ---: | ---: | ---: | ---: | ---: |
| WBB独立IP | 0 | 1 | 0 | N/A | 350 |
| MSHR独立IP | 218 | 1,646 | 219 | 1 | 3,980 |
| DCache集成自研RTL | 218 | 43 | 220 | 1 | 97,910 |

没有自动将缺口认定为不可达，也没有生成手工排除。具体红色条目在HTML源代码、条件、分支、状态转移和toggle页面中可查看。本轮完成的是测量基线，并未达到全代码100%或做逐点缺口归因；没有用户指定的数值验收门槛。功能验证点闭合与代码目标命中分开记录，不用功能case通过数代替代码百分比。

## 打开报告

- WBB：[HTML](work/run_20261126_101423/reports/wbb/self_rtl/dashboard.html)、[文本](work/run_20261126_101423/reports/wbb/self_rtl/dashboard.txt)。
- MSHR：[HTML](work/run_20261126_101423/reports/mshr/self_rtl/dashboard.html)、[文本](work/run_20261126_101423/reports/mshr/self_rtl/dashboard.txt)。
- DCache自研：[HTML](work/run_20261126_101423/reports/dcache/self_rtl/dashboard.html)、[文本](work/run_20261126_101423/reports/dcache/self_rtl/dashboard.txt)。
- DCache含官方FIFO：[HTML](work/run_20261126_101423/reports/dcache/whole_dut/dashboard.html)、[文本](work/run_20261126_101423/reports/dcache/whole_dut/dashboard.txt)。
- [covered/coverable汇总](work/run_20261126_101423/summary.md)、[模块明细JSON](work/run_20261126_101423/module_metrics.json)、[缺口JSON](work/run_20261126_101423/coverage_gaps.json)、[范围及数据审计](work/run_20261126_101423/coverage_audit.json)。

## 收集口径与留档

4套独立编译profile：WBB strict/delayed、MSHR、DCache。129份独立case VDB均有唯一测试记录；合并31份WBB、28份MSHR、70份DCache，URG测试数量与实际通过数量一致。旧数据库、历史失败和同名覆盖数据均未混入。源码/生成RTL/原模型哈希从收集开始到结束未变。

启用连续赋值行、宽表达式/任务函数条件、数组toggle与FSM自动识别；详见[流程README](README.md)。本轮与旧默认coverage设置的分母不同，不直接比较旧百分比。SVA继续检查DUT正确性，但assert/group不是本轮覆盖率指标。

首轮编译以DUT树为起点，包含了bind在DUT内部的辅助子树；范围审计发现后，使用保存的URG hierarchy文件过滤它们，并核对只有4个自研或6个完整DUT模块计分。原始VDB保持不变，[过滤前报告记录](work/run_20261126_101423/summary.before_scope_audit.json)保留，不作为最终DUT分数。脚本后续编译也显式排除这两个验证子树。

收集没有发生真实DUT/SVA/UVM失败。报告开发阶段修正了模块列表解析器误把汇总行当模块、以及“FSM形状文件存在但内无FSM对象”的判断；它们没有改变仿真或DUT数据。最终URG报告无warning/error，代码指标和模块范围均已审计。

重跑入口：[run_code_coverage.py](run_code_coverage.py)。数据库与HTML均在忽略的work目录，不将大体积产物纳入版本控制。


工具环境记录：四次profile编译各有一条LINX_KRNL，提示旧版VCS未列入当前WSL2内核支持范围；原始日志保留。所有实际仿真UVM warning/error/fatal为0，最终URG报告无warning/error，未通过隐藏诊断改变结果。


最终脚本另用[1组DCache smoke](work/run_20261126_103746/summary.md)验证编译阶段也排除bind子树。其DUT covered/coverable及分数与“先采集再做报告过滤”的同一smoke完全一致，[范围校核记录](work/run_20261126_101423/compile_scope_validation.json)留档；这组仅校验流程，不混入正式129组分数。
