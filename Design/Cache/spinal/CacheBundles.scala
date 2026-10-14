
package furina.cache
import spinal.core._
import spinal.lib._


// class CpuReadReq(cfg:CacheConfig) extends Bundle {
//     val addr = UInt(cfg.ADDR_WIDTH bits)
//     val id    = UInt(cfg.ID_WIDTH bits)
// }

case class CpuReq(cfg:CacheConfig) extends Bundle {
    val addr    = UInt(cfg.ADDR_WIDTH bits)
    val wrEn    = Bool()
    val wData   = Bits(cfg.DATA_WIDTH bits)
    val id      = UInt(cfg.ID_WIDTH bits)
}

case class CpuReadResp(cfg: CacheConfig) extends Bundle {
    val rData   = Bits(cfg.DATA_WIDTH bits)
    val id      = UInt(cfg.ID_WIDTH bits)
}

// class CpuWriteReq(cfg:CacheConfig) extends Bundle {
//     val addr    = UInt(cfg.ADDR_WIDTH bits)
//     val wData   = Bits(cfg.DATA_WIDTH bits)
//     val id      = UInt(cfg.ID_WIDTH bits)
// }

case class CpuWriteResp(cfg: CacheConfig) extends Bundle {
    val id      = UInt(cfg.ID_WIDTH bits)
}


case class MemReadReq(cfg:CacheConfig) extends Bundle {
    val addr  = UInt(cfg.ADDR_WIDTH bits) 
    val id    = UInt(log2Up(cfg.NUM_BUS_OUTSTANDING) bits)
}

case class MemReadResp(cfg:CacheConfig) extends Bundle {
    val rData = Bits(cfg.wordsPerBlock*cfg.DATA_WIDTH bits)
    val id    = UInt(log2Up(cfg.NUM_BUS_OUTSTANDING) bits)
}

case class MemWriteReq(cfg:CacheConfig) extends Bundle {
    val addr  = UInt(cfg.ADDR_WIDTH bits)
    val wData = Bits(cfg.wordsPerBlock*cfg.DATA_WIDTH bits)
    val id    = UInt(log2Up(cfg.NUM_BUS_OUTSTANDING) bits)
}

case class MemWriteResp(cfg:CacheConfig) extends Bundle {
    val id    = UInt(log2Up(cfg.NUM_BUS_OUTSTANDING) bits) 
}