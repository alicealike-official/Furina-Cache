# DCache：TSMC 28 HPC+开源综合

使用Yosys、ABC及OpenSTA综合当前生成的`DCache`顶层。所有存储数组映射为标准单元，不接入SRAM宏，不用黑盒跳过存储逻辑。仅处理生成RTL，不包含UVM或bind探针；不修改DUT、模型或工艺库。

## 重现

若工具目录已丢失，先下载并解包开源工具到临时目录，不做系统安装：

```bash
python3 synthesis/dcache28/bootstrap_tools.py
```

然后重新生成RTL并运行：

```bash
python3 -B verif_mshr/sim_dcache/script/prepare_dcache.py
python3 synthesis/dcache28/run.py --frequency-mhz 700 --mapping-corner ss
```

默认工具为`/tmp/furina-synth-tools/root/usr/bin/{yosys,sta}`或PATH中同名工具，可用`--yosys`、`--sta`指定。映射器ABC与Yosys在同一目录。库从本地`~/local/tsmc28/TSMC28/logic`选择`bwp40p140`的TT 0.9V/25°C和SS 0.81V/125°C，保持外部引用，不复制工艺库进项目。

`--mapping-corner ss`使用慢角库做700MHz目标映射，再对同一网表进行TT与SS分析。若更改映射角或频率，必须重新映射，不用旧500MHz网表冒充新目标综合。需要仅重跑时序时，可以在相同频率、映射角和输入哈希下传入`--resume RUN_DIRECTORY`。

综合脚本、源RTL快照、哈希、memory统计、映射Verilog/JSON、面积报告和时序报告分别保存在忽略的`work/run_TIMESTAMP`。映射完成并生成`summary.json`后，核对常量端点并还原关键寄存器名称：

```bash
python3 synthesis/dcache28/analyze.py synthesis/dcache28/work/run_TIMESTAMP
```

该命令生成`path_audit.json`和网表/脚本哈希，关键路径名称只从工具生成的网表与时序报告读取，不人工阅读DUT行为实现。工具执行失败会报错；若工具成功但目标时序不满足，主脚本仍保存结果，并返回2，在终端红色显示`SETUP VIOLATED`。

## 约束与范围

- 频率700MHz对应1.428571429ns；时钟不确定度50ps、转换时间50ps。
- 输入延迟200ps、输入转换时间50ps；输出延迟200ps、负载0.01pF。它们是本轮分析假设，并非已确定的系统接口验收规格。
- ABC目标取整数1428ps，使用BUFFD1BWP40P140驱动和10fF输出负载；实际是否满足周期由OpenSTA独立检查。
- 时钟网络ideal，无布局布线、时钟树或提取寄生，面积是标准单元面积，不是物理核心面积。
- resetn路径排除，不声称复位recovery/removal、hold或全PVT签核。
- 未进行活动驱动功耗分析或门级形式等价验证。
- 原先500MHz的全部标准单元结果不能替代SRAM实现结果，本轮同样如此。

脚本适配本机OpenSTA 2.0.17的命令语法，使用Yosys `write_verilog -simple-lhs`避免旧版本对拼接赋值左值的解析限制。不通过改RTL、时序库或隐藏时序违例来获取通过。

## 已完成结果

[700MHz首轮结果及关键路径](RESULT_700MHz.md)：在SS库上重新映射，TT满足；SS最差setup为−112.3ps，违例保持不关闭。包含实际单元面积、寄存器端点、路径延迟及完整日志链接。
