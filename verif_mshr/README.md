# 非阻塞 Cache IP 验证环境

WBB、MSHR和DCache顶层分别使用独立的仿真入口和生成目录，共用`src/common`中的时钟、复位及日志工具。

## 一键全量回归

在项目根目录执行：

```bash
./run_regression.sh
```

Shell入口调用`script/run_all_regression.py`统一调度，从各模块原入口读取全部case，显式包含长跑。执行顺序为：生成当前RTL→按profile编译→全部framework检查结束→通过framework的profile并行执行功能/长跑/复位/性能case。需要当前shell已加载VCS、sbt及许可证环境。

完整默认计划为295个独立仿真：12个framework组合、242个功能组合（含长跑）、12个本地复位组合、29个性能组合。功能回归使用10ns/4ns，随机与长跑使用seed 1/2/3；WBB适用case同时运行serial/pipeline。性能矩阵按其独立配置执行。具体数量随原入口清单更新，`--dry-run`展示当前计划。

```bash
./run_regression.sh --dry-run  # 只查看完整命令，不启动工具
./run_regression.sh --jobs 8   # 最多同时运行8个simv，默认4
./run_regression.sh --jobs 4 --no-waves  # 关闭波形，其他检查不变
./run_regression.sh --tests wbb_long_run_test mshr_long_run_test dcache_long_run_test
```

仅编译4个profile：WBB strict、WBB delayed、MSHR、DCache。同一profile的framework、普通case、复位和性能共用一个只读simv；时钟、seed及WBB普通输入模式通过plusarg切换，不重复编译。`--compile-jobs`控制单次VCS编译线程数，与`--jobs`控制的simv并发数独立。

framework阶段覆盖WBB两种编译配置的默认base启动，以及MSHR/DCache的base与smoke，均跑两种时钟。所有framework结果收齐后才进入第二阶段；某profile生成/编译或framework失败，该profile的后续case标为NOT RUN，其他通过的profile继续执行。普通case失败不取消其他case；Ctrl-C终止本轮工具进程组，未完成结果不算通过。

每轮独立目录为`verif_mshr/sim_dcache/work/all_regression/run_时间戳/`：`build/`保存本轮4个编译产物；`cases/每个组合/`各自拥有cwd、command.json、simulation.log、stdout.log、wave.fsdb和coverage.vdb，避免并行写UCLI/FSDB/VDB或DPI文件冲突。只复制编译数据库模板，不共享可写的运行数据库。本入口不调用各模块原脚本的main；原脚本仍可单独使用。

终端逐case打印带颜色的完成状态并在结束时按阶段汇总。`summary.json`、`summary.md`和`summary.tsv`由主调度线程统一保存，含逐case状态和日志链接；JSON同时保留命令、原入口专用判定与性能指标。性能10ns/4ns对照在所有结果收齐后比较，不依赖完成顺序。退出码：全部通过为0，失败/未运行为1，中断为130。不要在运行期间修改RTL/验证源码或执行clean，源文件哈希变化会使本轮结果失效。

这是一键仿真回归，不启动综合，不合并代码覆盖率，也不额外运行DPI、断言或memory agent的环境自检程序。

统一调度器已完成一次真实全量验证：[295/295通过](sim_dcache/work/all_regression/run_20261126_123254_803643/summary.md)。[调度审查](sim_dcache/work/all_regression/run_20261126_123254_803643/scheduler_audit.json)确认仅4个编译产物、全部framework先完成、实际并发峰值4、295个独立运行目录/VDB；WBB/MSHR/DCache长跑分别12/6/6组均通过。

| 模块 | UVM源码 | 仿真入口 | 生成RTL与参数 | 使用说明 |
| --- | --- | --- | --- | --- |
| WBB | `src/wbb/` | [sim_wbb](sim_wbb/Makefile) | `generated/wbb/` | [WBB_README](WBB_README.md) |
| MSHR | `src/mshr/` | [sim_mshr](sim_mshr/Makefile) | `generated/mshr/` | [MSHR_README](MSHR_README.md) |
| DCache顶层 | `src/dcache/` | [sim_dcache](sim_dcache/Makefile) | `generated/dcache/`（生成受阻） | [DCACHE_README](DCACHE_README.md) |

```text
verif_mshr/
├── generated/
│   ├── wbb/              # WriteBackBuffer.v、wbb_params_pkg.sv
│   ├── mshr/             # Mshr.v、mshr_params_pkg.sv
│   └── dcache/           # 生成成功后导入DCache.v
├── sim_wbb/              # WBB Makefile、filelist、脚本及work
├── sim_mshr/             # MSHR Makefile、filelist、脚本及work
├── sim_dcache/           # 顶层独立入口；当前生成错误待处理
├── src/
│   ├── common/
│   ├── wbb/
│   ├── mshr/
│   └── dcache/
├── test/                 # wbb、mshr、dcache及各自的连接检查
├── dpi/                  # 各模块的C++适配
├── tb/                   # 各模块独立顶层
├── WBB_README.md
├── MSHR_README.md
└── DCACHE_README.md
```

在仓库根目录分别运行：

```sh
make -C verif_mshr/sim_wbb generate
make -C verif_mshr/sim_wbb vcs_compile
make -C verif_mshr/sim_wbb vcs_simulate TEST_NAME=wbb_base_test
make -C verif_mshr/sim_wbb run_verdi

make -C verif_mshr/sim_mshr generate
make -C verif_mshr/sim_mshr vcs_compile
make -C verif_mshr/sim_mshr run TEST_NAME=mshr_smoke_test
make -C verif_mshr/sim_mshr run_verdi
```

WBB原`sim/`已迁至`sim_wbb/`，原`generated/`根下的WBB文件已移入`generated/wbb/`。
两套filelist只引用各自生成目录，运行、清理和覆盖率目录也各自独立。

WBB已有日志和波形仍在迁移后的`sim_wbb/work`。旧编译产物含绝对路径，已保存在
`sim_wbb/work/before_layout_builds`；迁移后需重新编译，首次不要使用`--skip-compile`。
历史`summary.json`、`summary.md`、`inputs.json`及原日志保持原样，仍反映当时的运行路径与版本；
`summary.relocated.md`仅提供迁移后的可点击链接，不是一次新回归。

验证点与case规划见[验证计划目录](../验证计划/DCacheWithMshr)。

MSHR、WBB、CacheMem、响应队列与替换策略在DCache中的连接和时序，见 [DCache顶层集成与连接说明](../Architecture/DCache顶层集成与连接说明.md)。该文档也列出当前顶层生成入口与低有效复位目标尚未对齐的情况。

## UVM代码风格

- 名称优先简洁且有意义，其次是较长但明确的名称；地址、数据、索引和句柄不使用无意义的单字母。`cfg`、`vif`等已有明确约定的短名可保留，继承UVM接口的形参遵守基类签名。
- 提交事务用`item`，接口快照用`sample`；遍历变量按对象命名，例如`slot_index`、`word_index`。固定地址和数据也用能说明用途的常量名。
- 统一4空格缩进，task/function展开书写。较长方法按实际小动作分段，每段用空行和简明注释说明目的及必要时序。
- 自定义方法的用途说明放在实现处，不放在extern声明处；new、build_phase等UVM标准方法不添加重复的头部说明。
- 调用C++模型或DPI时注明来源；风格整理保留激励、等待拍数、检查条件和错误报告语义。

### 检查用途标识

环境配置、对象有效性、初始化顺序、方法参数及场景适用条件的报错检查，在相应语句或连续检查块前用`【防御性检查】`标明，并说明具体前提。这些检查用于发现验证环境自身的使用错误，不作为DUT功能覆盖证据。

在提交前约束地址对齐、索引范围或地址唯一性等协议输入前提时，使用`【激励合法性检查】`。DUT输出、实际握手时序、数据比较、场景命中和超时检查保留各自的功能说明，不能只因使用fatal就归入防御性检查。标识只帮助阅读，不改变检查执行或失败判定。


DCache顶层采用分层检查：`src/dcache/integration`组装原`src/mshr`和`src/wbb`的被动检查链，原IP主动环境继续独立使用；模型、时钟和内存职责见[顶层分层目录](src/dcache/integration/README.md)。
