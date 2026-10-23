// ============================================================
// 文件名   : Bundles.scala
// 描述     : 对外接口与模块间接口定义
// 文档依据 : 《Cache 架构设计文档 v2》§4、§7.2、§8.2
// ============================================================

package furina.dcache

import spinal.core._
import spinal.lib._

// ---------------- CPU 侧（与原有 spinal 代码保持同名同义） ----------------
case class CpuReq(cfg: CacheConfig) extends Bundle {
    val addr = UInt(cfg.ADDR_WIDTH bits)
    val wrEn = Bool()
    val wData = Bits(cfg.DATA_WIDTH bits)
    val id = UInt(cfg.ID_WIDTH bits)
}

case class CpuReadResp(cfg: CacheConfig) extends Bundle {
    val rData = Bits(cfg.DATA_WIDTH bits)
    val id = UInt(cfg.ID_WIDTH bits)
}

case class CpuWriteResp(cfg: CacheConfig) extends Bundle {
    val id = UInt(cfg.ID_WIDTH bits)
}

// ---------------- 内存侧（文档 §4.2） ----------------
case class MemReadReq(cfg: CacheConfig) extends Bundle {
    val addr = UInt(cfg.ADDR_WIDTH bits)
    val id = UInt(cfg.busIdWidth bits)
}

case class MemReadResp(cfg: CacheConfig) extends Bundle {
    val rData = Bits(cfg.lineWidth bits)
    val id = UInt(cfg.busIdWidth bits)
}

case class MemWriteReq(cfg: CacheConfig) extends Bundle {
    val addr = UInt(cfg.ADDR_WIDTH bits)
    val wData = Bits(cfg.lineWidth bits)
    val id = UInt(cfg.busIdWidth bits)
}

case class MemWriteResp(cfg: CacheConfig) extends Bundle {
    val id = UInt(cfg.busIdWidth bits)
}

// ---------------- MSHR 查询接口（Stage1 / Stage2 各一个查询口） ----------------
case class MshrQuery(cfg: CacheConfig) extends Bundle {
    val tag = UInt(cfg.tagWidth bits)
    val index = UInt(cfg.indexWidth bits)
}

case class MshrMatch(cfg: CacheConfig) extends Bundle {
    val hit = Bool()
    val entry = UInt(cfg.mshrIdWidth bits)
    val mergeable = Bool()
    val slotFree = Bool()
    val freeSlot = UInt(log2Up(cfg.MSHR_MAX_PENDING) max 1 bits)
}

// ---------------- MSHR 重放响应 ----------------
case class MshrReplay(cfg: CacheConfig) extends Bundle {
    val rData = Bits(cfg.DATA_WIDTH bits)
    val id = UInt(cfg.ID_WIDTH bits)
    val isWrite = Bool()
}
