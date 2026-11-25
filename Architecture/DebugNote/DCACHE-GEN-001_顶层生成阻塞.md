# DCACHE-GEN-001：DCache顶层RTL生成阻塞

日期：2026-11-25。状态：**原位宽错误与复位接入均已解决，已生成resetn接口并运行真实DUT，本生成阻塞关闭。**

使用现有`runMain furina.dcache.DCacheVerilog`入口，仅生成RTL，没有执行未维护的Spinal仿真测试。生成在PhaseNormalizeNodeInputs阶段失败，日志报告：

```text
WIDTH MISMATCH (7 bits <- 8 bits) on Bits(UInt)
vector: toplevel/UnitMshr/lockMask : out Bits[128 bits]
index: (UInt + UInt)[8 bits]
```

日志定位到DCache.scala:99和:115，多个路的同类索引分别报错。此处只记录工具诊断，没有阅读DUT实现来定位或修改内部代码。原生成目录中11月16日的DCache.v为旧产物，不能用它代替当前设计；公开端口还显示reset，需按目标异步低有效契约确认新的resetn接口。

[原生成日志](../../verif_mshr/sim_dcache/work/framework_initial/generate.log)。

UVM框架已经完成编译和C++ DPI连接检查，但编译用端口桩不包含DUT行为，默认启动及smoke均未运行。设计方解决生成问题后，执行`make -C verif_mshr/sim_dcache check_framework`重新生成、编译并运行两种时钟的UVM检查。任何DE或归因不明的失败均应保留，不由DV自动修改DUT。


## 生成修复后的接入检查

2026-11-25再次调用现有DCacheVerilog，RTL生成成功。公开端口仍使用`reset`名称，而TB按已确认的异步低有效规格连接`resetn`。仅凭名称不能判断极性，因此没有取反、改DUT或把旧RTL作为替代。需要确认：若reset本身已经异步低有效，仅修改TB端口名称映射；若仍高有效，由设计方调整生成配置。

[本轮入口报告](../../verif_mshr/sim_dcache/work/framework/run_20261125_100035/summary.md)四组均NOT RUN；生成日志已通过，失败位置为DV接入的端口契约检查，不是原锁索引错误复发。


最新：低有效resetn接入后默认空态两时钟通过；smoke的CPU响应/模型时序差异另见[DCACHE-CHECK-001](DCACHE-CHECK-001_CPU响应与模型时序差异.md)。
