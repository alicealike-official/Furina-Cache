# DCACHE-PPA-002 并行写回判断优化尝试

日期：2026-11-26。状态：实验版 RTL 生成、映射及两角 STA 已完成。SS 最差超时从112.3 ps降至20.0 ps，有改善但仍未满足700 MHz；保留当前改动，功能待验证。按用户要求，不运行功能验证。

## 为什么继续尝试

上轮只改变最后的路号选择方式，没有改善最差路径，已恢复原实现。本轮单独测试另一个结构：让“是否需要写回”与“最终替换路号”并行计算，尝试缩短 evictDirty → reserveFail → s2Stuck → R1 控制这条链。

比较基线仍为 [run_20261126_084413](../../synthesis/dcache28/work/run_20261126_084413/)。原 SS WNS −0.1123 ns、TNS −566.1709 ns，TT WNS +0.2783 ns，面积 636430.536 µm²，最差路径 s1Index[3] → UnitCache.rdValidPipe_0，29级组合单元。

## 本次改动

[ReplacePolicy.scala](../../Design/DCacheMSHR/src/main/scala/furina/dcache/ReplacePolicy.scala)增加 allocWayMatches(setIndex, lockMask, matches) 查询。默认实现先算路号再取属性，保持其他策略可用；OrderedPolicy 为 FIFO/LRU 提供直接实现：按原偏好序检查未锁位置，首个可用位置的 matches 值直接参与合并。全锁时保持原队首默认行为。

原 allocWay 及替换顺序更新不变，不沿用 PPA-001 的路号选择改动。PLRU 使用默认属性查询，没有新增并行选择算法；本轮默认顶层仍是 FIFO。

[DCache.scala](../../Design/DCacheMSHR/src/main/scala/furina/dcache/DCache.scala)预先构造每路的 valid&&dirty 属性，用策略属性查询产生 policyDirty，并将写回条件改为：

```text
evictDirty = hasVictim && !hasEmpty && policyDirty
```

原结构需要等 victimWay 编码出来，再用路号动态读取 valid 和 dirty。新结构直接从各优先级位置的选中条件得到属性，最终路号仍按原方法独立生成，供淘汰目标使用。

按源码逻辑分析：有空路时 victimWay 必选 valid=0 的未锁路，因此原写回条件必为假，新条件的 !hasEmpty 同样使其为假；无空路时 victimWay 就是 policyWay，两种写回条件对应同一有效脏属性；没有可用路时 hasVictim 为假，两者均不写回。没有增加寄存器、流水拍数或接口，没有修改参考模型、存储体或验证环境。这不是形式等价或仿真验证结论。

## 运行范围

使用原 run.py、相同 SS 库映射 700 MHz，再运行 TT/SS STA。独立目录 [run_20261126_132416](../../synthesis/dcache28/work/run_20261126_132416/)，不复用上轮映射，不调整时钟或 IO 约束。所有存储仍映射标准单元，无 SRAM 宏、无布局布线寄生、理想时钟，不能作为物理实现签核或功耗结论。

## 结果与处置

两轮 manifest 除 RTL 输入外，其余字段完全一致。综合及 STA 流程正常完成；退出码2表示 SS 时序仍失败，不是工具执行失败。

| 指标 | 基线 | 本轮并行判断 | 变化 |
| --- | ---: | ---: | --- |
| SS WNS | −0.1123 ns | −0.0200 ns | 改善92.3 ps，最差超时减少约82% |
| SS TNS | −566.1709 ns | −0.4001 ns | 大幅减少，但仍非零 |
| TT WNS | +0.2783 ns | +0.3445 ns | 改善66.2 ps，仍满足700 MHz |
| TT TNS | 0 ns | 0 ns | 均无负裕量 |
| 标准单元面积 | 636430.536 µm² | 637892.892 µm² | 增加1462.356 µm²，约0.230% |
| 单元数 | 795562 | 798637 | 增加3075 |
| 触发器数 | 150166 | 150166 | 不变 |
| SS 最差路径组合级数 | 29 | 30 | 级数未减少，映射后的总延迟减少 |
| 最差路径缓冲级数及延迟 | 8级 / 0.2901 ns | 10级 / 0.3851 ns | 不能仅用门级数或缓冲数判断整体速度 |

[机器摘要](../../synthesis/dcache28/work/run_20261126_132416/summary.json)、[SS 时序](../../synthesis/dcache28/work/run_20261126_132416/timing_ss.rpt)、[TT 时序](../../synthesis/dcache28/work/run_20261126_132416/timing_tt.rpt)、[路径审计](../../synthesis/dcache28/work/run_20261126_132416/path_audit.json)已保存。

基线最差路径为 s1Index[3] → UnitCache.rdValidPipe_0。本轮最差路径为 s1Index[3] → UnitCache.banks_2_11_rd1RecA；前十条路径终点都为 bank 的 rd1RecA。这些寄存器保存读发起时哪份数据副本最新的标志。本轮最差路径 clock-to-Q 为0.0931 ns，组合传播约1.2853 ns，数据到达1.3784 ns，允许到达1.3584 ns，仍差20 ps。瓶颈仍在组索引经控制/地址选择进入 R1 读状态的同类路径，不能说整个冻结反馈链已经被消除。

本轮结果支持“提前直接计算写回属性”的改动在当前映射条件下有效，但不证明所有参数、策略和物理实现下均有相同收益，也不证明功能等价。由于有明确综合收益，保留这版工作源码与重新生成的 RTL，不恢复；没有运行验证。

归档源文件：[DCache.parallelDirty.scala](../../synthesis/dcache28/work/run_20261126_132416/DCache.parallelDirty.scala)、[ReplacePolicy.parallelDirty.scala](../../synthesis/dcache28/work/run_20261126_132416/ReplacePolicy.parallelDirty.scala)。运行目录同时保留对应 RTL 快照、哈希及报告；工作目录被 Git 忽略，长期保存需另行归档。本记录保留主要数字和结论。

后续首先由用户确认修改后的行为，再围绕剩余 R1 读控制、地址选择和扇出评估下一项独立优化。当前尚未达到 SS 700 MHz，且没有 SRAM 宏或布局布线时序，不能把20 ps的小余量缺口当成最终物理实现接近签核。未评估功耗，不因面积变化自行推断功耗。

## 历史修改 保留仿真观察信号 victimDirty（现已撤销）

2026-11-26，按用户要求恢复原定义 `val victimDirty = curValid(victimWay) && curDirty(victimWay)`，并在 Scala 源码中注释“仅供仿真观察，不参与实际写回控制”。对该信号添加 `keep` 属性，使其在生成的 RTL 中保留原名。

实际写回逻辑仍使用 `hasVictim && !hasEmpty && policyDirty`，没有重新接回 victimDirty。已执行 DCacheVerilog 生成，确认 `rtl/DCache.v` 包含 `(* keep *) wire victimDirty` 及原表达式对应的赋值。生成通过，未运行仿真或重新综合。

上文20 ps超时及面积数据属于添加观察信号之前的快照。keep 可能使后续综合保留额外观察逻辑，因此不能把既有综合数字直接当作包含该 keep 信号的新版本结果；后续若综合，应区分调试保留信号的配置。

## 规格同步

2026-11-26，按用户要求将已保留的 Dirty 并行计算组织写入 Cache 架构文档 v2：§8.5说明路号与写回判断并行准备；§10.1补充 allocWayMatches 属性查询及同一候选约束；§10.4给出 dirtyValid、policyDirty、evictDirty 定义、空路及全锁边界、FIFO/LRU与PLRU实现范围；§11.2把实际冻结条件从 victimDirty 改写为 evictDirty，并将 victimDirty 明确为保留的仿真观察信号。

本次只同步规格文字，不修改设计、模型或验证环境，不运行编译、综合或验证。既有综合结果及未完成的功能验证状态按原记录保留。

## 最新修改 删除 victimDirty 观察信号

2026-11-26，用户确认不再需要该仿真观察信号。已删除 DCache.scala 中 victimDirty 的原定义、仿真用途注释及 keep 属性；实际写回控制仍为 hasVictim && !hasEmpty && policyDirty。同步删除架构 spec §10.4、§11.2 中保留 victimDirty 的说明，既有并行 Dirty 计算定义不变。

已重新生成 DCache RTL，生成成功，并确认 Scala 和 rtl/DCache.v 中均不再有 victimDirty。未运行功能验证或重新综合。前面保留观察信号的段落是历史记录，当前版本以本节为准；含 keep 基线的9.3 ps结果不直接作为此次删除后的新综合结论。
