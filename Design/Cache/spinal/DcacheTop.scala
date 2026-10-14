package furina.cache
import spinal.core._
import spinal.lib._
import furina.cache.policy.ReplacePolicy
import furina.cache.policy.FifoPolicyFactory
class DCacheWithMSHR(
    cfg: CacheConfig,
    makePolicy: CacheConfig => ReplacePolicy
) extends Component {
    val io = new Bundle {
        // ----- Cpu请求 -----
        val cpu = slave(Stream(CpuReq(cfg)))
        // val cpuReadReq      = slave(Stream(CpuReadReq(cfg)))
        // val cpuWriteReq     = slave(Stream(CpuWriteReq(cfg)))

        // ----- Cpu响应 -----
        val cpuReadResp     = master(Stream(CpuReadResp(cfg)))
        val cpuWriteResp    = master(Stream(CpuWriteResp(cfg)))
        // val cpuResp = master(Stream(CpuResp(cfg)))

        // ----- MEM请求 -----
        val memReadReq      = master(Stream(MemReadReq(cfg)))
        val memWriteReq     = master(Stream(MemWriteReq(cfg)))

        // ----- MEM响应 -----
        val memReadResp     = slave(Stream(MemReadResp(cfg)))
        val memWriteResp    = slave(Stream(MemWriteResp(cfg)))
        // val mem = master(Stream(MemReq(cfg)))     // 请求通道
        // val memResp = slave(Stream(MemResp(cfg))) // 响应通道

    }
    noIoPrefix()
    val mem = new CacheMem(cfg)
    // 暂时不实现功能，先把所有输出置为闲置，避免 NO DRIVER
    io.cpu.ready            := False
    io.cpuReadResp.setIdle()
    io.cpuWriteResp.setIdle()
    io.memReadReq.setIdle()
    io.memWriteReq.setIdle()
    io.memReadResp.ready    := False
    io.memWriteResp.ready   := False
}



object DCacheWithMSHRVerilog extends App {
    val cfg     = CacheConfig() 
    val config = SpinalConfig(
        targetDirectory = "rtl",
        withTimescale   = false
    )
    config.generateVerilog(new DCacheWithMSHR(cfg, FifoPolicyFactory))
}