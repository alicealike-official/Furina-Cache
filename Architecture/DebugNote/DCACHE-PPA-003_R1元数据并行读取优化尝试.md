# DCACHE-PPA-003 R1元数据并行读取优化尝试

日期：2026-11-26。状态：两轮同条件综合及STA完成。实验版时序和面积均变差，已恢复实验前源码，重新生成RTL；未运行功能验证。

## 目标及对比边界

PPA-002将SS最差超时降至20 ps后，最差终点集中在R1读副本标记rd1RecA。现有路径先计算s2Stuck，随后选择R1组地址，再根据该地址读取小状态。本轮尝试把“先选地址再读状态”改为“两组状态提前读好，最后选择”。

用户随后要求保留原victimDirty作为仿真观察信号，并加keep。PPA-002的20 ps数据不包含该观察逻辑；为了公平归因，本轮以当前含keep的版本重新综合作为基线，与同样含keep的实验版比较。沿用PPA-002并行写回判断，不修改综合脚本、库或约束。两次运行使用原脚本的临时副本及各自不可变RTL快照，避免生成新RTL影响运行中的输入哈希检查。

## 实验修改

修改DCache.scala、CacheMem.scala、Ram2R2W.scala。CacheMem增加默认关闭的parallelR1Metadata生成选项；DCache顶层开启该选项，提供Stage2旧组号、CPU新组号及s2Stuck选择信号。默认独立CacheMem生成接口保留原样。

valid和dirty分别按两个组号组合读取，最后选择一份进入原有寄存器。Ram2R2W的newestIsA标记同样提前按两个地址读取，末端选择后进入原rd1RecA。原R1数据及tag读取仍使用原来的地址选择，未复制512位数据通路，未增加流水级。

源码层面，原式state[Mux(stuck,old,new)]替换为Mux(stuck,state[old],state[new])。仍在相同读使能下采样，原字偏移、复位、写入及同沿读写的旧状态语义均保留。这是设计意图分析，尚未通过仿真或形式等价证明。

期望缩短冻结控制到状态寄存器的路径，代价可能是更多组合读选择及活动功耗；不能预先认定有效，综合器也可能重组出其他结构。

## 结果及处置

本轮重新综合了两个版本，均包含 PPA-002 并行写回判断和 victimDirty keep。两轮 manifest 除 RTL 输入外，工艺库哈希、工具路径、映射角、频率、时钟与 IO 约束等字段均一致。

| 项目 | 当前版基线，含 keep | 并行状态读取实验版 |
| --- | ---: | ---: |
| SS WNS | −0.0093 ns | −0.0991 ns |
| SS TNS | −0.0657 ns | −260.9045 ns |
| TT WNS | +0.3510 ns | +0.2858 ns |
| TT TNS | 0 ns | 0 ns |
| 标准单元面积 | 636688.458 µm² | 665830.242 µm² |
| 标准单元数 | 796449 | 786058 |
| 触发器数 | 150166 | 150166 |
| SS 最差组合路径级数 | 30 | 33 |

SS 最差超时恶化89.8 ps，标准单元面积增加29141.784 µm²，约4.577%。单元数量不等于面积，实验版单元更少但总面积更大。两个版本TT通过、SS均未通过700 MHz，退出码2表示时序失败，不是综合工具执行失败。

基线最差路径是 s1Index[3] → UnitCache.banks_2_4_rd1RecA，数据到达1.3676 ns、允许到达1.3583 ns。实验版最差路径转为 s1Index[1] → UnitCache.banks_2_1_memB1_spinal_port0[27]，数据到达1.4599 ns、允许到达1.3608 ns，终点已经是数据副本B1的同步读输出寄存器。两版仍有组索引和读通路相关控制，但实验版没有改善整体最差时序，不能仅因为原状态终点退出第一名就称优化成功。

这次只提前读取小状态，没有提前或复制数据/tag通路。整体映射发生变化后，数据读通路成为瓶颈；没有针对各局部路径做额外归因或消融实验，不能把失败全部归结于某一个选择器。也不能宣称此类结构在所有配置和映射条件下必然更差。

## 归档与恢复

- [含 keep 的基线报告](../../synthesis/dcache28/work/run_20261126_135029/summary.json)、[SS 时序](../../synthesis/dcache28/work/run_20261126_135029/timing_ss.rpt)、[路径审计](../../synthesis/dcache28/work/run_20261126_135029/path_audit.json)。
- [实验版报告](../../synthesis/dcache28/work/run_20261126_135432/summary.json)、[SS 时序](../../synthesis/dcache28/work/run_20261126_135432/timing_ss.rpt)、[路径审计](../../synthesis/dcache28/work/run_20261126_135432/path_audit.json)。
- 实验版源码：[DCache.scala](../../synthesis/dcache28/work/run_20261126_135432/DCache.parallel.scala)、[CacheMem.scala](../../synthesis/dcache28/work/run_20261126_135432/CacheMem.parallel.scala)、[Ram2R2W.scala](../../synthesis/dcache28/work/run_20261126_135432/Ram2R2W.parallel.scala)。各运行目录同时保留工具生成的完整RTL和映射报告。

已恢复这三份工作源码为实验前版本，并重新生成对应RTL；PPA-002并行写回判断、victimDirty原定义和keep均保留。本次方案一不进入正式实现，不继续扩大修改范围。综合目录被Git忽略，长期保存需另行归档，本记录保存主要数字与结论。

本轮含keep基线的9.3 ps与PPA-002原不含keep版本的20 ps不相同，说明观察逻辑也可能影响整体映射，不能跨版本直接归因。本次后续应使用含keep的基线数字，但这仍是无布局布线寄生的标准单元映射结果，不代表物理签核，也不证明功能或功耗。

