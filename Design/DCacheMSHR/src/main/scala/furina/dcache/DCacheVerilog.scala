// ============================================================
// 文件名   : DCacheVerilog.scala
// 描述     : Verilog 生成入口
// ============================================================

package furina.dcache

import spinal.core._

object DCacheVerilog extends App {
    val cfg = CacheConfig()
    val config = SpinalConfig(
        targetDirectory = "rtl",
        withTimescale = false,
        defaultConfigForClockDomains = ClockDomainConfig(
            clockEdge = RISING,
            resetKind = ASYNC,
            resetActiveLevel = LOW
        )
    )
    config.generateVerilog(new DCache(cfg, FifoPolicyFactory))
}
