// ============================================================
// 文件名   : WriteBackBuffer.scala
// 描述     : 写回缓冲 WBB
// 文档依据 : 《Cache 架构设计文档 v2》§8
//
// 生命周期：预留（写 addr） -> push（写 data、置 valid）
//          -> 轮询发出内存写 -> memWriteResp 释放
//
// "占用" 必须同时计入 valid 与 reserved：
//   空闲 = !valid && !reserved
//   满   = 所有条目均 valid || reserved
// 同地址检查同样覆盖 valid 与 reserved。
// ============================================================

package furina.dcache

import spinal.core._
import spinal.lib._

class WriteBackBuffer(cfg: CacheConfig) extends Component {
    import cfg._

    private val N = WBB_ENTRIES

    val io = new Bundle {
        // 预留（仅脏 victim）
        val reserve = in(new Bundle {
            val en = Bool()
            val addr = UInt(ADDR_WIDTH bits)
        })
        val reserveOk = out Bool()
        val reserveSlot = out UInt(wbbIdWidth bits)

        // 下一拍 push 整行
        val push = in(new Bundle {
            val en = Bool()
            val slot = UInt(wbbIdWidth bits)
            val line = Bits(lineWidth bits)
        })

        // 内存写通道
        val send = master Stream (MemWriteReq(cfg))
        val memWriteResp = slave Stream (MemWriteResp(cfg))

        // 状态查询
        val full = out Bool()

        // 同地址查询（Stage1 / Stage2 各一个）
        val q0Addr = in UInt(ADDR_WIDTH bits)
        val q0Same = out Bool()
        val q1Addr = in UInt(ADDR_WIDTH bits)
        val q1Same = out Bool()
    }
    noIoPrefix()

    private val valid = Vec(Reg(Bool()) init False, N)
    private val reserved = Vec(Reg(Bool()) init False, N)
    private val issued = Vec(Reg(Bool()) init False, N)
    private val addr = Vec(Reg(UInt(ADDR_WIDTH bits)) init 0, N)
    private val data = Vec(Reg(Bits(lineWidth bits)) init 0, N)

    // ---------------- 空闲 / 满 ----------------
    private val freeVec = Vec((0 until N).map(i => !valid(i) && !reserved(i)))
    private val occupiedVec = Vec((0 until N).map(i => valid(i) || reserved(i)))

    io.reserveOk := freeVec.orR
    io.reserveSlot := priorityLowest(freeVec, wbbIdWidth)
    io.full := occupiedVec.andR

    private def priorityLowest(vec: Seq[Bool], width: Int): UInt = {
        val res = UInt(width bits)
        res := U(0, width bits)
        for (i <- (vec.length - 1) to 0 by -1) {
            when(vec(i)) { res := U(i, width bits) }
        }
        res
    }

    // ---------------- 同地址检查（覆盖 valid + reserved） ----------------
    private def sameAddr(query: UInt): Bool = {
        val hit = Vec((0 until N).map(i => occupiedVec(i) && addr(i) === query))
        hit.orR
    }
    io.q0Same := sameAddr(io.q0Addr)
    io.q1Same := sameAddr(io.q1Addr)

    // ---------------- 预留 ----------------
    when(io.reserve.en && io.reserveOk) {
        val s = io.reserveSlot
        reserved(s) := True
        addr(s) := io.reserve.addr
    }

    // ---------------- push ----------------
    when(io.push.en) {
        val s = io.push.slot
        data(s) := io.push.line
        valid(s) := True
        reserved(s) := False
    }

    // ---------------- 发送仲裁（轮询） ----------------
    private val rrPtr = Reg(UInt(wbbIdWidth bits)) init 0
    private val sendCand = Vec((0 until N).map(i => valid(i) && !issued(i)))

    private val rotCand = Vec(Bool(), N)
    for (k <- 0 until N) {
        val idx = (rrPtr + U(k, wbbIdWidth bits)).resize(wbbIdWidth)
        rotCand(k) := sendCand(idx)
    }
    private val sendValid = rotCand.orR
    private val rotK = priorityLowest(rotCand, wbbIdWidth)
    private val sendIdx = (rrPtr + rotK).resize(wbbIdWidth)

    io.send.valid := sendValid
    io.send.payload.addr := addr(sendIdx)
    io.send.payload.wData := data(sendIdx)
    io.send.payload.id := sendIdx.resize(busIdWidth)

    when(io.send.valid && io.send.ready) {
        issued(sendIdx) := True
        rrPtr := (sendIdx + 1).resize(wbbIdWidth)
    }

    // ---------------- 写响应释放 ----------------
    io.memWriteResp.ready := True
    when(io.memWriteResp.valid) {
        val rid = io.memWriteResp.payload.id(wbbIdWidth - 1 downto 0)
        valid(rid) := False
        issued(rid) := False
    }
}

object WriteBackBufferVerilog extends App {
    val cfg = CacheConfig()
    val config = SpinalConfig(
        targetDirectory = "rtl",
        withTimescale = false
    )
    config.generateVerilog(new WriteBackBuffer(cfg))
}
