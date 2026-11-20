# 非阻塞 Cache IP 验证环境

WBB与MSHR分别使用独立的仿真入口和生成目录，共用`src/common`中的时钟、复位及日志工具。

| 模块 | UVM源码 | 仿真入口 | 生成RTL与参数 | 使用说明 |
| --- | --- | --- | --- | --- |
| WBB | `src/wbb/` | [sim_wbb](sim_wbb/Makefile) | `generated/wbb/` | [WBB_README](WBB_README.md) |
| MSHR | `src/mshr/` | [sim_mshr](sim_mshr/Makefile) | `generated/mshr/` | [MSHR_README](MSHR_README.md) |

```text
verif_mshr/
├── generated/
│   ├── wbb/              # WriteBackBuffer.v、wbb_params_pkg.sv
│   └── mshr/             # Mshr.v、mshr_params_pkg.sv
├── sim_wbb/              # WBB Makefile、filelist、脚本及work
├── sim_mshr/             # MSHR Makefile、filelist、脚本及work
├── src/
│   ├── common/
│   ├── wbb/
│   └── mshr/
├── test/                 # wbb、mshr及各自的adapter/断言自检
├── dpi/                  # 各模块的C++适配
├── tb/                   # 各模块独立顶层
├── WBB_README.md
└── MSHR_README.md
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
