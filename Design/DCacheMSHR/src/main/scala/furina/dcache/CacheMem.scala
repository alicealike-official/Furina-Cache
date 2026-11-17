// ============================================================
// 文件名   : CacheMem.scala
// 描述     : Cache 存储体
// 文档依据 : 《Cache 架构设计文档 v2》§5.2 - §5.6
//
// 端口模型：
//   R1 : 流水线字读（同组各路 tag/valid/dirty + 目标字）
//   R2 : victim 整行读（用于写回）
//   W1 : 命中单字写（同时置 dirty）
//   W2 : 填充整行写（写 tag/valid/dirty/整行数据）
//   CLR: 淘汰时清 victim valid（只清 valid，不动 data/dirty）
//   INS: 组合查询当前 valid/dirty，供 Stage2 选择 victim
//
// valid/dirty 使用独立寄存器（而不是 Mem），因此天然支持同拍
// "填充置位" 与 "淘汰清零" 同时发生，不占存储体端口。
// ============================================================

package furina.dcache

import spinal.core._

class CacheMem(cfg: CacheConfig) extends Component {
    import cfg._

    val io = new Bundle {
        // -------- R1：流水线字读 --------
        val r1 = new Bundle {
            val en = in Bool()
            val index = in UInt(indexWidth bits)
            val wordOff = in UInt(wordOffWidth bits)
            val tag = out Vec(UInt(tagWidth bits), NUM_WAYS)
            val valid = out Vec(Bool(), NUM_WAYS)
            val dirty = out Vec(Bool(), NUM_WAYS)
            val data = out Vec(Bits(DATA_WIDTH bits), NUM_WAYS)
            // val tag = out Bits(tagWidth * NUM_WAYS bits)
            // val valid = out Bits(NUM_WAYS bits)
            // val dirty = out Bits(NUM_WAYS bits)
            // val data = out Bits(DATA_WIDTH * NUM_WAYS bits)

        }

        // -------- R2：victim 整行读 --------
        val r2 = new Bundle {
            val en = in Bool()
            val index = in UInt(indexWidth bits)
            val way = in UInt(wayWidth bits)
            val line = out Bits(lineWidth bits)
        }

        // -------- W1：命中单字写 --------
        val w1 = new Bundle {
            val en = in Bool()
            val index = in UInt(indexWidth bits)
            val way = in UInt(wayWidth bits)
            val wordOff = in UInt(wordOffWidth bits)
            val data = in Bits(DATA_WIDTH bits)
        }

        // -------- W2：填充整行写 --------
        val w2 = new Bundle {
            val en = in Bool()
            val index = in UInt(indexWidth bits)
            val way = in UInt(wayWidth bits)
            val tag = in UInt(tagWidth bits)
            val dirty = in Bool()
            val line = in Bits(lineWidth bits)
        }

        // -------- CLR：清 victim valid --------
        val clr = new Bundle {
            val en = in Bool()
            val index = in UInt(indexWidth bits)
            val way = in UInt(wayWidth bits)
        }

        // -------- INS：当前状态组合查询（victim 选择用） --------
        val inspect = new Bundle {
            val index = in UInt(indexWidth bits)
            // val valid = out Vec(Bool(), NUM_WAYS)
            // val dirty = out Vec(Bool(), NUM_WAYS)
            val valid = out Bits(NUM_WAYS bits)
            val dirty = out Bits(NUM_WAYS bits)
        }
    }
    noIoPrefix()

    // ---------------- 存储体 ----------------
    // valid / dirty：按 set × way 平铺的寄存器
    private val validBits = Vec(Vec(Reg(Bool()) init False, NUM_WAYS), NUM_SETS)
    private val dirtyBits = Vec(Vec(Reg(Bool()) init False, NUM_WAYS), NUM_SETS)

    // tag：按路分体，W2 写、R1 读
    private val tagMems = Seq.fill(NUM_WAYS)(Mem(UInt(tagWidth bits), NUM_SETS))

    // data：按 路 × 字 分体，每个 bank 为严格 2R2W
    private val banks: Seq[Seq[Ram2R2W]] = Seq.tabulate(NUM_WAYS) { _ =>
        Seq.tabulate(wordsPerBlock)(_ => new Ram2R2W(cfg, DATA_WIDTH))
    }

    // ---------------- R1 输出对齐 ----------------
    // 同步读在时钟沿采样地址、下一拍出数据；valid/dirty/wordOff 也打一拍对齐。
    private val rdValidPipe = Vec(Reg(Bool()) init False, NUM_WAYS)
    private val rdDirtyPipe = Vec(Reg(Bool()) init False, NUM_WAYS)
    private val rdWordOffPipe = Reg(UInt(wordOffWidth bits)) init 0
    when(io.r1.en) {
        rdWordOffPipe := io.r1.wordOff
        for (w <- 0 until NUM_WAYS) {
            rdValidPipe(w) := validBits(io.r1.index)(w)
            rdDirtyPipe(w) := dirtyBits(io.r1.index)(w)
        }
    }

    for (w <- 0 until NUM_WAYS) {
        io.r1.tag(w) := tagMems(w).readSync(io.r1.index, enable = io.r1.en)
        io.r1.valid(w) := rdValidPipe(w)
        io.r1.dirty(w) := rdDirtyPipe(w)

        val wordOut = Vec((0 until wordsPerBlock).map(word => banks(w)(word).rd1Data))
        io.r1.data(w) := wordOut(rdWordOffPipe)
    }

    // ---------------- R2 整行读 ----------------
    // 读地址在时钟沿被采样，下一拍数据才有效；输出 mux 必须使用
    // "读发起那一拍"的 way，而不是当前输入（当前请求可能已经变化）。
    private val rd2WayPipe = Reg(UInt(wayWidth bits)) init 0
    when(io.r2.en) { rd2WayPipe := io.r2.way }

    private val lineWords = Vec(Bits(DATA_WIDTH bits), wordsPerBlock)
    for (word <- 0 until wordsPerBlock) {
        lineWords(word) := Vec((0 until NUM_WAYS).map(w => banks(w)(word).rd2Data))(rd2WayPipe)
    }
    io.r2.line := Cat(lineWords)

    // ---------------- bank 端口连接 ----------------
    for (w <- 0 until NUM_WAYS) {
        for (word <- 0 until wordsPerBlock) {
            val bank = banks(w)(word)

            bank.rd1Addr := io.r1.index
            bank.rd1En := io.r1.en && (io.r1.wordOff === U(word, wordOffWidth bits))

            bank.rd2Addr := io.r2.index
            bank.rd2En := io.r2.en && (io.r2.way === U(w, wayWidth bits))

            bank.w1Addr := io.w1.index
            bank.w1Data := io.w1.data
            bank.w1En := io.w1.en &&
                (io.w1.way === U(w, wayWidth bits)) &&
                (io.w1.wordOff === U(word, wordOffWidth bits))

            bank.w2Addr := io.w2.index
            bank.w2Data := io.w2.line(word * DATA_WIDTH, DATA_WIDTH bits)
            bank.w2En := io.w2.en && (io.w2.way === U(w, wayWidth bits))
        }
    }

    // ---------------- valid / dirty / tag 写 ----------------
    when(io.clr.en) {
        validBits(io.clr.index)(io.clr.way) := False
    }

    when(io.w1.en) {
        dirtyBits(io.w1.index)(io.w1.way) := True
    }

    when(io.w2.en) {
        for (w <- 0 until NUM_WAYS) {
            tagMems(w).write(io.w2.index, io.w2.tag, enable = io.w2.way === U(w, wayWidth bits))
        }
        validBits(io.w2.index)(io.w2.way) := True
        dirtyBits(io.w2.index)(io.w2.way) := io.w2.dirty
    }

    // ---------------- 当前状态查询 ----------------
    for (w <- 0 until NUM_WAYS) {
        io.inspect.valid(w) := validBits(io.inspect.index)(w)
        io.inspect.dirty(w) := dirtyBits(io.inspect.index)(w)
    }
}


object CacheMemVerilog extends App {
    val cfg = CacheConfig()
    val config = SpinalConfig(
        targetDirectory = "rtl",
        withTimescale = false
    )
    config.generateVerilog(new CacheMem(cfg))
}