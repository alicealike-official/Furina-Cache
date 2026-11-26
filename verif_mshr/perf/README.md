# DCache性能测试

在项目根目录运行：

```bash
make -C verif_mshr/sim_dcache perf
```

入口先生成当前RTL，再单独编译并运行`dcache_perf_test`。每组配置开启全新的仿真，预热与正式测量分开。不会调用综合，也不会解析DUT行为实现。正常结束后在终端打印带颜色的PASS/FAIL和每拍完成笔数。

每轮结果放在`sim_dcache/work/perf/run_时间戳/`：

| 文件 | 内容 |
|---|---|
| summary.md / summary.csv | 逐组性能概览 |
| summary.json | 所有配置、精确运行命令、检查结果、完整指标与源文件SHA256 |
| inputs.json | 本轮输入文件哈希 |
| 各组.json | 真实IO测得的周期、延迟分布、事务计数、资源占用 |
| 各组.log / stdout.log | UVM、原模型、SVA及模拟器输出 |
| generate.stdout.log / compile.log | 当前RTL生成与编译证据 |

默认不导出波形，不收集新的功能覆盖率。失败也保留日志和已产生的指标，失败组不会被登记成有效性能结果。

## 组件分工

| 文件 | 职责与可扩展内容 |
|---|---|
| test/dcache/dcache_perf_test.sv | 配置确定性的CPU/内存接收方式、读取参数、启动sequence |
| src/dcache/sequence/dcache_perf_sequence.sv | 数据、地址、预热、串行/连续提交与场景必命中检查 |
| src/dcache/perf/dcache_perf_monitor.sv | 按真实CPU/内存握手和现有只读探针计数；不驱动信号 |
| src/dcache/perf/dcache_perf_result.sv | 周期指标、分位数及JSON导出 |
| sim_dcache/script/run_dcache_perf.py | 定义测试矩阵、独立运行、完整性审查、终端/CSV汇总 |

复用已有CPU driver、memory agent、CacheTop/MSHR/WBB的原C++参考模型、SparseMemory以及scoreboard/SVA，不在性能组件中重写预测模型。MSHR占用取现有锁矩阵，WBB占用由实际reserve到响应握手的槽生命周期统计。没有增加bind信号。

后续主要修改sequence中的场景和runner的`profiles()`；增加指标时再扩展monitor/result。不要为提高数字关闭数据比较、放宽断言或跳过排空。

## 单组参数

同一个`dcache_perf_test`通过以下plusarg选择配置；完整命令可直接从某轮`summary.json`复制。

| 参数 | 默认值 | 含义 |
|---|---|---|
| PERF_SCENARIO | hit_read | hit_read/hit_write/hit_mixed/independent/merge/dirty |
| PERF_SUBMISSION | stream | stream连续提交；serial等待上一笔CPU响应后提交下一笔 |
| PERF_REQUESTS | 1024 | 测量阶段CPU请求数，不含预热 |
| PERF_GROUP_SIZE | 1 | merge场景中每冷行的请求数，支持1/2/4 |
| PERF_READ_LATENCY | 8 | 内存读响应延迟，单位拍，至少1 |
| PERF_WRITE_LATENCY | 8 | 内存写确认延迟，单位拍，至少1 |
| PERF_RESULT_FILE | work/dcache_perf.json | JSON输出路径；父目录需已存在 |
| CLOCK_PERIOD_NS | 由顶层时钟配置决定 | 顶层生成时钟；所有场景等待仍按拍 |

`merge`只支持连续提交。自定义请求量需为同行笔数的整数倍。`dirty`先通过CPU把全部way置脏，再执行新行写分配；不在测量结尾flush仍驻留的脏行。

## 统计口径

- 响应延迟：最终响应握手沿减请求接受沿，不包括请求在ready前的等待。
- CPU完成窗口：首个请求valid被采样的沿，到最后CPU响应握手沿，两端均计入。完成吞吐率为请求数除以该窗口周期数。
- 全部完成窗口：同一起点，到CPU响应及已发内存事务全部完成的最后事件沿。末尾写回确认计入，空闲检查额外等待拍不计入。
- 接受吞吐率：请求数除以首笔接受到末笔接受的采样拍数。连续命中应为1笔/拍。
- CPU反压与TB空拍：在首次呈现到末笔接受的窗口内分别统计valid且!ready、!valid。连续模式要求TB空拍为0。
- MSHR/WBB占用：按沿前值计数，均值取全部完成窗口。MSHR满/WBB满/同行限制是在CPU反压时同时观察到的条件，彼此可能重叠，不能相加作为总停顿，也不能当成独立因果归因。
- 平均/P50/P95/最大延迟：只取真实握手样本，分位数使用nearest-rank；没有样本为null。

串行基线和连续提交运行同一个DUT，使用相同地址、数据和内存配置。串行基线只限制CPU最多一笔在途；它不等于v1.0阻塞式Cache，也不关闭后台写回。测试没有CPU响应反压、随机内存延迟或受限外部带宽；整行V-R内存可每拍接受事务，因此不能当作AXI burst或实际DRAM结果。

本测试不新增功能验证点，不改变现有闭合结论。仿真周期用于确认环境可换频，不能据此判断800MHz时序是否收敛。
