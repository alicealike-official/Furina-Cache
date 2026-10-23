// ============================================================
// 文件名   : Ram2R2W.scala
// 描述     : 严格 2 读 + 2 写 bank 的等价实现
// 文档依据 : 《Cache 架构设计文档 v2》§5.5（每个存储体为真双端口）
//
// FPGA 没有原生 2R2W 的 BRAM，这里用"四副本 + 每 set 新旧标记"
// 等价实现逻辑上的 2R2W：
//   A1 : W1 写 + R1 读
//   A2 : W1 写 + R2 读
//   B1 : W2 写 + R1 读
//   B2 : W2 写 + R2 读
// 每个 set 维护 recency：W1 写入后 A 新，W2 写入后 B 新。
// 读口同时读 A/B 两份，用读时刻的 recency 选择最新副本。
// 面积开销是单端口实现的 4 倍，这是严格 2R2W 的代价。
// ============================================================

package furina.dcache

import spinal.core._

class Ram2R2W(cfg: CacheConfig, width: Int) extends Area {
    require(width > 0)

    // ---------------- 读口 1（流水线字读 R1） ----------------
    val rd1Addr = UInt(cfg.indexWidth bits)
    val rd1En = Bool()
    val rd1Data = Bits(width bits)

    // ---------------- 读口 2（victim 整行读 R2） ----------------
    val rd2Addr = UInt(cfg.indexWidth bits)
    val rd2En = Bool()
    val rd2Data = Bits(width bits)

    // ---------------- 写口 1（命中单字写 W1） ----------------
    val w1Addr = UInt(cfg.indexWidth bits)
    val w1Data = Bits(width bits)
    val w1En = Bool()

    // ---------------- 写口 2（填充整行写 W2） ----------------
    val w2Addr = UInt(cfg.indexWidth bits)
    val w2Data = Bits(width bits)
    val w2En = Bool()

    // 每个 set 上哪一份副本是最新的：True -> A 新，False -> B 新
    val newestIsA = Vec(Reg(Bool()) init True, cfg.NUM_SETS)

    private val memA1 = Mem(Bits(width bits), cfg.NUM_SETS)
    private val memA2 = Mem(Bits(width bits), cfg.NUM_SETS)
    private val memB1 = Mem(Bits(width bits), cfg.NUM_SETS)
    private val memB2 = Mem(Bits(width bits), cfg.NUM_SETS)

    // 读：两份都读，按"读发起那一拍"的 recency 选择
    private val rd1A = memA1.readSync(rd1Addr, enable = rd1En)
    private val rd1B = memB1.readSync(rd1Addr, enable = rd1En)
    private val rd2A = memA2.readSync(rd2Addr, enable = rd2En)
    private val rd2B = memB2.readSync(rd2Addr, enable = rd2En)

    private val rd1RecA = Reg(Bool()) init True
    private val rd2RecA = Reg(Bool()) init True
    when(rd1En) { rd1RecA := newestIsA(rd1Addr) }
    when(rd2En) { rd2RecA := newestIsA(rd2Addr) }

    rd1Data := Mux(rd1RecA, rd1A, rd1B)
    rd2Data := Mux(rd2RecA, rd2A, rd2B)

    // 写：W1 只更新 A 副本，W2 只更新 B 副本
    memA1.write(w1Addr, w1Data, enable = w1En)
    memA2.write(w1Addr, w1Data, enable = w1En)
    memB1.write(w2Addr, w2Data, enable = w2En)
    memB2.write(w2Addr, w2Data, enable = w2En)

    // 同一 (set, way, word) 上 W1/W2 不会同拍出现（Way Lock 保证），
    // 因此下面两条对同一个 set 的 recency 更新不会互相覆盖；
    // 若因设计错误出现重合，W2 优先。
    when(w1En) { newestIsA(w1Addr) := True }
    when(w2En) { newestIsA(w2Addr) := False }
}
