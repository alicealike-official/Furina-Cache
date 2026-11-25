# DCache顶层UVM框架

当前已接入重新生成的真实DCache RTL及低有效resetn端口。原C++模型的响应FIFO时序经修复后，默认空态与基础smoke在10 ns/4 ns下共4/4通过，UVM warning/error/fatal均为0。历史差异及修复记录见[DCACHE-CHECK-001](../Architecture/DebugNote/DCACHE-CHECK-001_CPU响应与模型时序差异.md)。这仅证明框架和基础通路，不代表完整顶层验证闭合。

## 组织与职责

| 路径/组件 | 职责 |
| --- | --- |
| src/dcache/interface | 固定规格整行V-R接口和沿前mon_cb采样 |
| config | CPU/内存接收开关、响应延迟和watchdog，单位均为拍 |
| sequence/transaction | CPU请求、四态IO快照、实际/模型输出配对 |
| component/agent | CPU主动/被动agent、独立内存agent |
| component/driver | CPU请求保持、内存读写FIFO响应、独立CPU响应接收控制 |
| component/monitor | 每沿发布独立sample对象，按CPU/内存信号分组 |
| model | 原C++ CacheTop预测器与原SparseMemory的SV封装 |
| component/scoreboard | 逐拍模型比较、CPU ID/类型配对、事件计数及收尾 |
| bind | 七个V-R通道保持/已知值检查、地址对齐及启动复位输出 |
| test/dcache | 默认空态base和两读一写smoke；不铺开复杂功能case |
| sim_dcache | 原Makefile风格、独立filelist、work及Verdi入口 |
| generated/dcache | 仅接收成功生成且公开端口符合契约的DCache.v |

时钟配置只由dcache_tb_top创建，经test→env→clk_agent→driver逐级传递。使用已有公共时钟/复位agent，目标为异步低有效resetn。复位期间各信号只有对应driver驱动。读写请求与响应独立，当前响应策略先提供FIFO、固定周期延迟和接收开关；乱序/随机调度可后续扩展。

## 原C++模型与DPI

`dpi/dcache_dpi.cpp`包含原`RefModel/Cache/CacheTop.hpp`和`RefModel/MEM/SparseMemory.hpp`，没有另写Cache或MEM模型。SV声明在`pkg/dcache_dpi.svh`，调用处注明来源。

每拍monitor→predictor把沿前输入传给原CacheTop，依次eval、读取输出、tick。模型只接收实际握手的内存响应；MSHR/WBB的ready仍由DUT决定。scoreboard精确比较当前FIFO参考模型的CPU输出、内存请求和整行数据；若实际合法选择或时序与模型不同，需要先核对spec再归因，不可直接改模型迎合DUT。

后端MEM与CacheTop实例分离。内存读握手时保存原C++ SparseMemory的行快照，写请求握手时才更新后端；CPU写不直接更新后端。响应被反压时队首及载荷保持，只有实际握手才删除记录。每个ID各自归属，读写同值ID不会相互覆盖。

数据检查目前以原CacheTop为主，CPU ID/类型及七通道协议另行独立检查。未来复杂case可增加原始激励期望和写回版本检查；本轮未声称这些专项功能已经验证。

## 运行入口

在仓库根目录执行：

```bash
make -C verif_mshr/sim_dcache generate
make -C verif_mshr/sim_dcache vcs_compile
make -C verif_mshr/sim_dcache run
make -C verif_mshr/sim_dcache run TEST_NAME=dcache_smoke_test
make -C verif_mshr/sim_dcache run_verdi
make -C verif_mshr/sim_dcache check_framework
```

不指定TEST_NAME时只运行base的空态检查；smoke由sequence发出0x1000读、写0x12345678、再读，test等待并核对两读一写完成。所有请求ID不同。CPU driver的item_done仅表示请求接受，响应由monitor/scoreboard追踪，不把请求到返回强制串行。

`check_framework`先生成再编译，再执行base/smoke各10 ns/4 ns，终端彩色显示PASS/FAIL/NOT RUN。生成或端口检查失败会报告NOT RUN；当前已运行真实DUT，按各组结果登记。

独立框架开发检查：

```bash
make -C verif_mshr/sim_dcache check_compile
make -C verif_mshr/sim_dcache check_dpi
```

`check_compile`使用只声明端口的空桩，验证UVM语法、接线和DPI链接，产物在work/compile_only；空桩启动会fatal，不能运行case。`check_dpi`不实例化DUT，只创建原CacheTop、推进空态、检查原SparseMemory整行往返。两项均不算DUT功能通过。

## 当前验证结果与限制

2026-11-25：

- UVM、SVA和C++ DPI编译链接通过：[编译日志](sim_dcache/work/framework_initial/compile_only.log)。
- 原C++对象创建、复位/空态推进及SparseMemory整行DPI往返通过：[DPI日志](sim_dcache/work/framework_initial/dpi.log)。
- 当前RTL生成失败：[生成日志](sim_dcache/work/framework_initial/generate.log)。真实DUT默认启动/smoke均未运行，无功能闭合更新。

已有旧RTL的公开端口用于整理数据字段，复位端口为reset；本框架按已确认spec直接要求resetn，不做取反兼容或自动修改设计。生成问题解决后还需确认实际输出为异步低有效、固定容量、FIFO策略；端口名本身不能证明复位实现语义。

环境收尾只检查已接受CPU请求及内存事务完成，并观察额外输出。Cache仍可能保留脏行，因此不要求后端等于CPU最新写值，也不擅自发flush。活动事务复位、长时间乱序、压力、策略差异和覆盖率闭合均留待后续case。


## 生成修复后接入进度

RTL已成功重新生成，当前公开复位端口名为reset；需确认它的有效极性后再调整TB绑定，不能只凭名称自动取反。框架报告已增加源码哈希、波形存在性、文件变化检查和失败原因，真实DUT运行仍未开始。


## 最新真实DUT运行

[四组报告](sim_dcache/work/framework/run_20261125_100532/summary.md)：base在10 ns/4 ns均PASS，smoke均FAIL。smoke完成3笔请求及两读一写响应，实际读值为0和0x12345678。已修复无效载荷比较的DV问题；每组仍有6次valid周期差异，未修改DUT或模型，未延迟期望来获得通过。前面的生成/复位阻塞内容保留为历史。


## 模型修复后基础复核

[最新四组报告](sim_dcache/work/framework/run_20261125_104508/summary.md)为4/4 PASS。重新生成RTL、冷编译当前C++模型；默认无testname空态和两读一写smoke各在10 ns/4 ns运行，原有比较及协议检查均通过。模型同步读延迟问题关闭，历史FAIL不覆盖当前结论。


后续验证场景见[DCache case规划](../验证计划/DCacheWithMshr/DCache_case规划_note.md)：31组CPU到内存的功能/压力case，以及复位暂缓、模块依赖和逐项范围说明。除基础smoke外均为规划，不表示已经实现或通过。


## 公开IO功能case

27个新增case入口及sequence已经接入，范围和暂缓子项见[DCache case记录](../验证计划/DCacheWithMshr/DCache_case规划_note.md)。新增连续CPU提交、独立架构数据记录（复用原C++ SparseMemory）、内存逆序/随机时序、实际事件计数和受测脏行驱逐回读。所有延迟按拍，仍使用原CacheTop与协议SVA。

`python3 -B verif_mshr/sim_dcache/script/run_dcache_regression.py`运行常规公开IO矩阵，长跑用`--tests dcache_long_run_test`选择。CPU联合响应反压的模型差异经修复后已完成通过复核；详见[DCACHE-CHECK-002](../Architecture/DebugNote/DCACHE-CHECK-002_CPU读写响应联合反压差异.md)，未放宽比较或修改DE。

最新公开IO回归：[60/62通过](sim_dcache/work/regression/run_20261125_110929/summary.md)，仅CPU联合反压两组待归因；原入口[4/4基础复核](sim_dcache/work/framework/run_20261125_111519/summary.md)通过。长跑每组65536笔主随机请求及544笔驱逐辅助请求，共66080笔，六组全部完成。


## 公开IO模型修复后回归

[最新62/62报告](sim_dcache/work/regression/run_20261125_120234/summary.md)全部通过，UVM warning/error/fatal均为0。原C++模型响应队列满条件已修正，CPU联合反压两时钟通过。长跑六组各完成66080笔请求；DV激励、SVA和模型比较未放宽。旧60/62记录反映修复前状态，当前以本段为准。

原默认空态/smoke入口另在[最新4/4报告](sim_dcache/work/framework/run_20261125_120752/summary.md)中通过。


## 内部只读接口探针

C11、C19、C30已接入只读探针。bind位置为[src/dcache/integration/bind/dcache_probe_bind.sv](src/dcache/integration/bind/dcache_probe_bind.sv)，当前实例路径`dcache_tb_top.dut.u_dcache_probe.probe`。模块端口及顶层提交信号集中映射，UVM只读采样；当前默认启用集成monitor，所有case还接入MSHR/WBB被动检查。详细字段和扩展约定见[探针说明](src/dcache/integration/README.md)。

[最新68组回归](sim_dcache/work/regression/run_20261125_131237/summary.md)全部通过，新增锁/响应竞争/资源边界case各两时钟通过；内部事件检查与外部原模型检查同时启用。


## 分层环境与IP复用

原MSHR/WBB被动agent、标准sample、predictor、scoreboard及SVA已直接接入所有顶层case。局部C++实例独立于CacheTop内部对象；只有顶层CPU/内存driver驱动DUT。新增`src/dcache/integration/{bind,ip,monitor,transaction}`明确顶层组装职责，原IP源码仍保留在各自目录。详细目录、层次和两个bind位置见[分层说明](src/dcache/integration/README.md)。

[分层68/68回归](sim_dcache/work/regression/run_20261125_133737/summary.md)及[基础4/4](sim_dcache/work/framework/run_20261125_134959/summary.md)通过。另完成编译桩和DPI入口复核，独立DPI目标使用DCACHE_PORT_STUB避免绑定不存在的DUT。验证点已清理并逐项更新，剩余内容见[闭合审查](../验证计划/DCacheWithMshr/DCache顶层闭合审查.md)。


## 当前FIFO配置补测

新增旁路比较键、长冻结、相反类型响应队满、连续脏淘汰、FIFO跳锁、非连续ID、三种吞吐流、重分配数据版本、fill后锁定、WBB满时合并、流水资格变化及资源释放交叉case；另把均匀、热点、同set冲突、随机CPU接收反压拆为独立随机profile。具体必命中要求见[case规划](../验证计划/DCacheWithMshr/DCache_case规划_note.md#extended-cases)。

[112组完整回归](sim_dcache/work/regression/run_20261125_150533/summary.md)全部通过；[逐case内部计数](sim_dcache/work/regression/run_20261125_150533/internal_coverage_evidence.json)保存实际命中证据。原CacheMem/FifoPolicy被动检查的用途、碰撞排除范围和bind位置见[集成说明](src/dcache/integration/README.md)。本轮不新增复位专项或复杂替换策略。

新增组合补测入口：`dcache_memory_combinations_test`。每次运行先执行两轮随机顺序的填充/逐字写读/驱逐，再执行32,768笔随机连续请求；双读、双写和W2→W1后读取共276个组合条件必须每次全部命中。回归默认对该case执行seed 1/2/3、10 ns/4 ns。[6/6报告](sim_dcache/work/regression/run_20261125_154026/summary.md)与[逐组组合证据](sim_dcache/work/regression/run_20261125_154026/combination_evidence.json)已保存，MEM-009/010/012闭合，主表现为144/168项闭合。
