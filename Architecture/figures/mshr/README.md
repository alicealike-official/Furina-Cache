# MSHR IP 时序图

七张图对应 [MSHR IP架构文档](../../MSHR_IP架构设计文档.md) §13。JSON为WaveDrom源文件，SVG为可缩放的阅读版本。

从仓库根目录重新生成单张图：

```sh
wavedrom --input Architecture/figures/mshr/lifecycle.json > Architecture/figures/mshr/lifecycle.svg
```

每拍使用4个绘图刻度，clk的上升沿与E0、E1等标签对齐，输入先于采样沿建立，状态在沿后显示更新。刻度不代表实际传播延迟；async-reset图保持clk为低，不出现采样沿。

`x`只表示字段无效，不要求驱动X。`conceptual`表示从接口历史推导的抽象观察；WAIT、FILL-W、REPLAY分别对应MISS_WAIT、FILL待填充、FILL已填充待重放。bitA/bitB表示set/way对应的打包锁位。
