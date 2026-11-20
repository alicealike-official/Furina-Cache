# DCache 顶层集成时序图

四张图对应 [DCache顶层集成与连接说明](../../DCache顶层集成与连接说明.md) §10，依据实际连接构造示例，不是仿真输出。

从仓库根目录重新生成单张图：

```sh
wavedrom --input Architecture/figures/dcache_integration/dirty-eviction.json > Architecture/figures/dcache_integration/dirty-eviction.svg
```

每拍4个绘图刻度，E0/E1位于刻度1/5的上升沿，输入提前建立，状态沿后更新。`x`表示无效字段，conceptual为说明用计数。FIFO入队和CPU实际pop是不同事件，图不规定外部固定返回延迟。

响应仲裁图使用深度4、初始写队占2/读队占0、没有CPU pop的轨迹；两个队列的空间变化均由图中实际入队推导。
