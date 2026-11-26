# DCache顶层分层集成检查

## 目录

```text
src/dcache/
├── component/                 # CPU/内存agent、外部monitor、端到端scoreboard和环境
├── model/                     # 原CacheTop和SparseMemory的顶层DPI封装
├── interface/                 # 外部接口及仅含集成信号的probe interface
├── integration/
│   ├── bind/
│   │   ├── dcache_ip_bind.sv       # UnitMshr/UnitWbb全部端口→原IP interface，复用原SVA
│   │   └── dcache_probe_bind.sv    # CacheMem/FIFO/顶层提交控制→集成probe
│   ├── ip/
│   │   ├── dcache_ip_checks.sv     # 两个被动检查环境的容器
│   │   ├── dcache_mshr_checks.sv   # 原mshr_agent(PASSIVE)+predictor+scoreboard
│   │   ├── dcache_cachemem_checks.sv # 原CacheMem独立实例与实际端口比较
│   │   └── dcache_wbb_checks.sv    # 原wbb_agent(PASSIVE)+predictor+scoreboard+写观察器
│   ├── monitor/dcache_probe_monitor.sv
│   └── transaction/dcache_probe_sample.sv
└── sequence/                  # CPU/内存正常接口激励，内部接口只用于等待与覆盖
```

原IP代码仍在`src/mshr`和`src/wbb`，不复制到顶层目录。`component`负责顶层外部通路，`integration`专门负责模块之间的连接与被动IP接入。

## UVM层次

```text
uvm_test_top.env
├── agent                      CPU driver/sequencer/monitor
├── memory_agent               唯一实际后端内存driver
├── sink_driver                唯一CPU响应ready驱动
├── predictor                  独立C++ CacheTop实例
├── scoreboard                 顶层逐拍比较、CPU ID和事务完整性
├── activity                   原始CPU顺序数据与外部事件计数
├── ip_checks
│   ├── mshr
│   │   ├── agent.monitor      原mshr_monitor，发布原mshr_sample
│   │   ├── predictor          原mshr_predictor，独立new C++ MSHR
│   │   └── scoreboard         原mshr_scoreboard
│   └── wbb
│       ├── agent.monitor      原wbb_monitor，发布原wbb_sample
│       ├── predictor          原wbb_predictor，独立new C++ WriteBackBuffer
│       ├── scoreboard         原wbb_scoreboard
│       └── writes             被动记录实际send数据，供原WBB内存比较
├── cachemem_checks            原CacheMem被动端口检查
└── probe_monitor              原FifoPolicy及CPU→提交、跨模块交接、来源仲裁及集成覆盖
```

两个IP agent均设置为UVM_PASSIVE，不创建其driver或sequencer，也不创建其memory agent。CPU通过DCache产生内部输入，原monitor每个上升沿生成完整沿前快照，原predictor输入这些实际IO；不在顶层重写IP sample或行为模型。

CacheTop内部的MSHR/WBB对象由CacheTop自行推进；独立IP predictor经各自DPI create另建对象，每拍只推进自己的对象一次，没有共享句柄。顶层check_phase核对三个检查链的采样拍数相同；完整回归另保存逐组采样核对记录。

## bind与采样

- IP映射：[dcache_ip_bind.sv](bind/dcache_ip_bind.sv)。当前层级为`dcache_tb_top.dut.u_dcache_ip_checks.mshr_vif`和`wbb_vif`。
- 集成映射：[dcache_probe_bind.sv](bind/dcache_probe_bind.sv)。当前层级为`dcache_tb_top.dut.u_dcache_probe.probe`。

两个文件末尾使用`bind DCache`，所有DE路径集中在这两个文件。原IP interface由只读assign连接真实实例端口，原IP SVA同时接入。顶层probe已移除重复的MSHR/WBB接口字段及映射；集成monitor需要关联IP事件时，直接读取共享IP interface的`mon_cb`，sample只保留本次检查的值快照。

所有clocking block使用同一时钟和`input #1step`。集成monitor从CPU、IP、CacheMem/FIFO接口取得同一沿前值，在检查旧状态后才登记本沿新事件；不依赖analysis回调谁先运行。没有force/release、后门写入或从参考模型内部推断DUT发生了什么。

缺接口会明确fatal，缺层级/端口会编译失败，不用常量0占位。端口桩和独立DPI检查通过DCACHE_PORT_STUB关闭DUT bind，仅用于编译或DPI连接，不计DUT功能通过。

## 为什么保留顶层检查

局部MSHR/WBB模型能检查实际输入之后的处理，却不能单独判断顶层是否传错了CPU地址。集成monitor因此维护CPU已接受请求队列，检查Stage2提交的ID、类型、块地址、字偏移和写数据，并要求一次commit恰好走一条命中/alloc/merge路径。merge根据真实Entry分配历史核对目标块。

冻结的CPU请求不能执行前台提交动作；fill/replay及内存后台推进保留。其他检查包括fill与CacheMem W2一致、脏淘汰原子动作、R2与push交接、命中响应和replay来源选择，以及模块资源边界计数。

原IP已承担的局部锁矩阵、空位预测及Stream保持检查通过原scoreboard/SVA复用，顶层不重复写同一套输出模型。为集成覆盖保留的Entry/Slot历史是实际事件记录，不是另一个MSHR参考模型。

WBB本地write observer仅向自己的原SparseMemory实际记录写数据，predictor记录期望数据，scoreboard比较二者；它不驱动MEM，也不修改DCache后端存储。顶层MEM、CPU架构期望存储及WBB本地实际/期望存储是独立对象。

## 错误归因与验证范围

原IP检查器中的`ENV_*`在独立IP场景表示输入来源违约。在顶层，它的来源可能是DCache产生的alloc/merge/reserve/push，不能仅凭错误ID含ENV就认定DV错误；应结合实例路径、原CPU请求和真实内部输入定位。确定DV错误才修改环境，DE或未知问题保留报告。

原模型可能对合法选择顺序提出比spec更窄的精确比较；出现仅顺序不同的差异时需要按spec判断，不能自动修改DUT或放宽检查。本次复用保留原模型算法，当前全部运行通过。

## 本轮证据

- [分层完整68/68](../../../sim_dcache/work/regression/run_20261125_133737/summary.md)。
- [三层采样拍数核对](../../../sim_dcache/work/regression/run_20261125_133737/ip_sampling_audit.json)。
- [基础4/4](../../../sim_dcache/work/framework/run_20261125_134959/summary.md)。

其余尚未闭合验证点见[顶层闭合审查](../../../../验证计划/DCacheWithMshr/DCache顶层闭合审查.md)。通过本轮case不等于所有存储体副本、其他策略、复位和性能子项都闭合。

## 当前FIFO配置的补充检查

`env.cachemem_checks`通过`dcache_memref_*` DPI创建原`RefModel/Cache/CacheMem.hpp`独立对象。实际R1/R2/W1/W2/CLR/inspect端口每拍送入，核对同步读返回和当前元数据。R1与同拍同址写/清valid碰撞的路、R2与同目标写碰撞的返回不强制判新旧；CPU最终读值仍由接受顺序数据检查和旁路检查负责。没有重新实现CacheMem算法。

`probe_monitor`中的FIFO策略检查经`dcache_fifo_*` DPI复用原`FifoPolicy`，以真实命中和实际fill更新，比较所有32组顺序与实际分配候选。它与CacheTop内部策略对象独立。当前只验证FIFO，不把其onHit无状态变化外推到LRU/PLRU。

`bind/dcache_probe_bind.sv`新增映射包括CacheMem完整公开端口、valid/dirty/tag元数据、FIFO顺序和架构流水/旁路字段。无RAM数据副本/recency探针，无内部驱动。新增的`monitor/dcache_extended_checks.svh`是同一monitor内的方法分组，负责旁路、长冻结、独立ready公式、真实FIFO push/pop顺序和事件交叉；仍从同一沿前快照检查，之后才记录生命周期。

CPU读值以请求接受顺序作为期望，跨行响应以ID匹配；接受→提交、提交→入队、入队→CPU接收分别统计拍数。随机CPU读/写ready独立选择并限制连续随机阻塞拍数，手工关闭ready仍由case控制何时恢复。写响应放行也支持最早周期号，不使用硬编码纳秒延迟。

最终扩展结果：定向/随机[112/112](../../../sim_dcache/work/regression/run_20261125_150533/summary.md)、长跑[6/6](../../../sim_dcache/work/regression/run_20261125_151220/summary.md)、最后Entry跨拍补测[2/2](../../../sim_dcache/work/regression/run_20261125_152252/summary.md)、基础[4/4](../../../sim_dcache/work/framework/run_20261125_152341/summary.md)。最后补测只新增C49与实际事件计数，不更改原比较规则。

`count_memory_combinations`进一步按真实沿前端口记录双读、双写的way/word与同异set组合，以及W2→W1更新后从R1/R2读取的历史。`dcache_memory_combinations_test`使用随机顺序的受控写读和32,768笔随机连续流量，要求276个组合条件在每次运行中全部命中；参考数据仍来自原C++ CacheMem和原顶层/IP检查。没有新增内部驱动。

C50组合补测[6/6通过](../../../sim_dcache/work/regression/run_20261125_154026/summary.md)，每组276项要求全命中；共享计数扩展后的[基础4/4](../../../sim_dcache/work/framework/run_20261125_154417/summary.md)通过。详细组合矩阵见[case文档](../../../../验证计划/DCacheWithMshr/DCache_case规划_note.md#c50-存储端口组合补测)。


## 同址读写按spec旁路契约检查

`monitor/dcache_extended_checks.svh`新增`check_read_during_write`：当真实W1写与CPU接受读同沿、同tag/set/word时，按CPU ID保存写值，待该读实际提交时核对旁路选择及结果，冻结期间保留记录。现有CPU顺序数据、原C++模型和SVA继续运行。`count_raw_read_value`仅统计原始R1值与写值的关系，不要求RAM碰撞返回固定版本。

无新bind、编译内部临时信号引用或内部驱动。CacheMem原始碰撞比较的既有排除规则未放宽；原C++算法未改。C51新case及C05/C32/C33、混合随机与fill流水窗口共[20/20通过](../../../sim_dcache/work/regression/run_20261126_090229/summary.md)，[逐组碰撞证据](../../../sim_dcache/work/regression/run_20261126_090229/read_during_write_evidence.json)保存实际次数。该证据支持MEM-016按spec §6.6、§12.6的CPU可见功能闭合，不作为RAM原语单独验收。

## 并行dirty判断的DV接入

按Cache spec §10.4，实际写回资格为`evictDirty`。探针已移除旧`victimDirty`的bind端口、interface、sample及采样依赖；DE是否保留该观察信号不影响DV编译。`dirty_wait_after_fifo_release`改用真实`evictDirty`，原multi_stall case仍要求命中，不关闭场景检查。

新增`check_writeback_qualification`复用`dcache_fifo_step`返回的沿前最终候选（原C++ FifoPolicy，包含最低空路优先及锁过滤），结合当前inspect valid/dirty计算期望。inspect本身继续由原C++ CacheMem检查。Stage2有效时核对hasVictim和evictDirty，包括冻结期间；分配时核对MSHR hasWb，并在每拍核对WBB reserve和R2使能必须且只能由有效脏分配触发。原有原子淘汰、下一拍push、数据与参考模型检查保持启用。

不以DUT policyDirty或旧victimDirty作为期望，不增加新的DE内部信号绑定，不修改C++模型算法。新增统计为`writeback_qualification_checked`、`dirty_writeback_actions_checked`及`clean_allocation_no_writeback_checked`，表示实际执行检查的次数，不替代原case的必命中要求。

本轮迁移[24/24通过](../../../sim_dcache/work/all_regression/run_20261126_142932_933208/summary.md)：4组framework，dirty/clean淘汰、Way Lock、FIFO边界、淘汰边界、释放交叉、多原因冻结各两时钟，以及存储组合case两时钟三种子。multi_stall在每种时钟下命中21拍`dirty_wait_after_fifo_release`；本结果为相关补测，不替代一次完整295组回归。
