// ============================================================
// 文件名   : CacheMem.scala
// 作者     : alicealie
// 日期     : 2026-10-08
// 描述     : Cache的存储体
// 版本     : 1.0
// 修改记录 :
//   2026-10-08  alicealie  - 创建
// ============================================================


package furina.cache
import spinal.core._
import spinal.lib._

class CacheMem(cfg:CacheConfig) extends Area {

    val validMem    = Seq.fill(cfg.NUM_WAYS)(Mem(Bool(), cfg.NUM_SETS))
    val dirtyMem    = Seq.fill(cfg.NUM_WAYS)(Mem(Bool(), cfg.NUM_SETS))
    val tagMem      = Seq.fill(cfg.NUM_WAYS)(Mem(UInt(cfg.tagWidth bits), cfg.NUM_SETS))
    val dataMem     = Seq.fill(cfg.NUM_WAYS)(
        Seq.fill(cfg.wordsPerBlock)(Mem(Bits(cfg.DATA_WIDTH bits), cfg.NUM_SETS))
    )

    // 读控制信号
    val rdSetAddr   = UInt(cfg.indexWidth bits)
    val rdWordOff   = UInt(cfg.wordOffWidth bits) //dataMem的大小是NUM_SETS*BLOCK_SIZE
    val rdEn        = Bool()

    val rdTag       = Vec(UInt(cfg.tagWidth bits), cfg.NUM_WAYS)
    val rdValid     = Vec(Bool(), cfg.NUM_WAYS)
    val rdDirty     = Vec(Bool(), cfg.NUM_WAYS)
    val rdData      = Vec(Bits(cfg.DATA_WIDTH bits), cfg.NUM_WAYS)


    
    for (w <- 0 until cfg.NUM_WAYS) {
        val words       = Vec(Bits(cfg.DATA_WIDTH bits), cfg.wordsPerBlock)
        rdTag(w)   := tagMem(w).readSync(rdSetAddr, enable = rdEn)
        rdValid(w) := validMem(w).readSync(rdSetAddr, enable = rdEn)
        for (i <- 0 until cfg.wordsPerBlock) {
            words(i) := dataMem(w)(i).readSync(rdSetAddr, enable = rdEn)
        }
        // rdData(w)  := dataMem(w)(rdWordOff).readSync(rdSetAddr, enable = rdEn)
        rdData(w)      := words(rdWordOff)
        rdDirty(w)  := dirtyMem(w).readSync(rdSetAddr, enable = rdEn)
    }

    // 写控制信号
    val wrSetAddr   = UInt(cfg.indexWidth bits)
    val wrWay       = UInt((log2Up(cfg.NUM_WAYS) max 1) bits)
    val wrTag       = UInt(cfg.tagWidth bits)
    val wrData      = Bits(cfg.wordsPerBlock*cfg.DATA_WIDTH bits)
    val wrEn        = Bool()
    val wrIsFill    = Bool()

    for (w <- 0 until cfg.NUM_WAYS) {
        val sel = wrEn && (wrWay === w)
        tagMem(w).write(wrSetAddr, wrTag, enable = sel)
        validMem(w).write(wrSetAddr, True, enable = sel)
        dirtyMem(w).write(wrSetAddr, wrIsFill, enable = sel)
        for (word <- 0 until cfg.wordsPerBlock) {
            dataMem(w)(word).write(
                wrSetAddr, wrData(word * cfg.DATA_WIDTH, cfg.DATA_WIDTH bits),
                enable = sel
            )
        }
    }
}