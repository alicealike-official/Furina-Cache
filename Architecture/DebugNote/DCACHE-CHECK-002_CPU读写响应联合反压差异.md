# DCACHE-CHECK-002：CPU读写响应联合反压下的模型差异

日期：2026-11-25。状态：**原C++模型队列满条件经设计方修复后，公开IO回归62/62通过，当前差异关闭。**

## 修改前的场景

`dcache_cpu_backpressure_test`先通过CPU预热一条行，再分别执行只阻塞读响应、只阻塞写响应、同时阻塞两种响应。每阶段提交24笔已预热行的请求，暂停接收128拍后放行；CPU请求受阻时driver保持全部字段到握手。

前两种阶段正常；联合阻塞阶段出现逐拍模型差异。测试只观察公开CPU和内存接口，没有内部FIFO、Stage2或提交事件探针。

## 修改前的首轮公开证据

10 ns、seed1时：

| 仿真时间 | 字段 | DUT | 原C++期望 |
| --- | --- | --- | --- |
| 3825 ns | cpu_ready | 0 | 1 |
| 3835 ns | cpu_ready | 0 | 1 |
| 4995 ns | cpuWriteResp_valid | 0 | 1 |
| 5015 ns | cpuWriteResp_valid | 0 | 1 |

4 ns同样出现这些逻辑周期的差异。测试最终完成73笔CPU请求、37次读响应和36次写响应，仅有一次内存读，没有写回。公开IO的CPU读值检查、ID/类型检查、协议保持及场景计数未报错；仍不能据此豁免逐拍模型差异。

首个差异是CPU接收资格，后续模型可能因此走上不同轨迹，不能把每条后续valid差异都当成独立DE缺陷。最初公开 IO 诊断尚未归因；后续源码核查与模型修复见下文。模型 ready 仍由自身状态计算，不替换成 DUT ready，也不修改比较规则。

## 复现

```bash
python3 -B verif_mshr/sim_dcache/script/run_dcache_regression.py \
    --tests dcache_cpu_backpressure_test --periods 10 4
```

[首轮报告](../../verif_mshr/sim_dcache/work/regression/run_20261125_110529/summary.md) / [首轮10 ns日志](../../verif_mshr/sim_dcache/work/regression/run_20261125_110529/dcache_cpu_backpressure_test_p10_s1.log)。完整复核结果以case规划末尾的新报告为准。

## 处理边界

此前验证环境处理记录：新增变量曾误用SV关键字`matches`导致编译失败；已改名。响应队列的逆序选择也限定为响应开关打开且尚未呈现时执行，避免在关闭期间不断重排候选。上述修改不改变CPU联合反压的接收开关或模型比较。

该case不能登记为通过，也不能据它关闭响应队列满、联合反压或相关冻结路径。其他独立case继续执行，失败日志和FSDB保留。


完整复核：[62组公开IO报告](../../verif_mshr/sim_dcache/work/regression/run_20261125_110929/summary.md)为60 PASS、2 FAIL，失败均为本case的10 ns/4 ns组合，每组4次DCACHE_MODEL_MISMATCH，无独立架构读值或协议错误。两种时钟的实际请求和响应均为73笔。原默认空态/smoke另在[四组基础复核](../../verif_mshr/sim_dcache/work/framework/run_20261125_111519/summary.md)中全部通过。

## 已确认的原因

[Cache 架构文档 §9.3](../Cache架构设计文档v2.md#93-规则)规定读写任一响应队列满都冻结 Stage2 并反压 cpuReady；§11.1 也明确这不是只检查当前请求类型对应的队列。

[Scala 顶层](../../Design/DCacheMSHR/src/main/scala/furina/dcache/DCache.scala)使用 `respFullAny = !rdFifo.io.push.ready || !wrFifo.io.push.ready`，同时用于 Stage1 准入和 Stage2 冻结，符合这条规格。

原 [C++ CacheTop 模型](../../RefModel/Cache/CacheTop.hpp)则使用 `respFullFor(isWrite)`：写请求只检查写响应队列，读请求只检查读响应队列。Stage1 传入新请求的 cpu_wrEn，Stage2 传入流水请求的 s2WrEn_。因此一条队列满、另一条尚未满时，模型可能继续接受或提交另一类型的请求，而 DUT 已经暂停。

例如读响应队列满、写响应队列未满且新来写请求：DUT 给出 ready=0，旧模型仍可能给出 ready=1。这个确定的策略差异能够解释记录中首个接收资格分歧。两边随后可能接受或提交不同数量的请求，后续写响应 valid 错位未必是独立的数据通路问题。没有检查验证侧采样/推进，也没有重跑场景，因此不能提前断言这处修复一定消除全部差异。

## 本次修改

仅修改 `RefModel/Cache/CacheTop.hpp`：

- 将类型相关的 respFullFor(bool) 改为无请求类型参数的 respAnyFull()，条件为读响应总占用达到深度或写响应总占用达到深度。
- Stage1 准入调用 respAnyFull()，任一响应队列满时不再接受新 CPU 请求。
- Stage2 冻结调用同一条件，任一响应队列满时暂停提交，冻结原因统计沿用原有 RESP_FULL。

容量仍通过 readQueueSize()/writeQueueSize() 计算，包含此前 CHECK-001 增加的有效同步读输出寄存器。保留该同步读修复，不改变 FIFO 深度、预取或背压保持逻辑。读写各队列的实际入队检查仍分别检查各自容量，命中和 replay 的入队优先级不变。

本次没有修改 Scala、DPI 适配、验证用例、驱动、scoreboard 或比较规则，没有访问验证文件夹。

## 编译与待验证状态

已使用 `g++ -std=c++17 -Wall -Wextra -c` 编译包含 CacheTop.hpp 的编译单元，并显式实例化默认 FIFO 替换策略的 CacheTopT；编译通过。修改文件的空白差异检查通过。

未运行测试或仿真。当前状态为“模型策略已修正、编译通过、功能及时序待确认”。上文 60 PASS、2 FAIL 是修改前的历史结果，仍保留。后续由用户重新编译使用新模型的仿真程序，确保没有链接旧 DPI 对象，再检查联合反压、单侧反压、队列满与释放以及原先四处逐拍差异。没有新回归证据前不登记为已解决或 PASS。


## 修复后完整复核

[本轮62组报告](../../verif_mshr/sim_dcache/work/regression/run_20261125_120234/summary.md)全部通过，UVM warning/error/fatal均为0。重新生成RTL并冷编译当前模型；CPU联合反压10 ns/4 ns、三种子随机和六组长跑全部通过。验证激励、逐拍比较和独立架构数据检查未修改，旧FAIL记录保留作历史。长跑每组66080笔实际请求全部完成。
