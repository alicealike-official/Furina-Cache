import spinal.core._
import spinal.lib._

// ---------- 配置 ----------
case class CacheConfig(
    numSets:       Int   = 32,
    blockSize:     Int   = 64,      // 字节
    numWays:       Int   = 4,
    dataWidth:     Int   = 32,
    addrWidth:     Int   = 32,
    mshrEntries:   Int   = 4,       // MSHR 最大并发缺失数
    mshrMaxPending:Int   = 4        // 每个 MSHR 可合并的最大请求数
) {
    val indexWidth    = log2Up(numSets)
    val offsetWidth   = log2Up(blockSize)
    val tagWidth      = addrWidth - offsetWidth - indexWidth
    val wordsPerBlock = blockSize / (dataWidth / 8)
    val wordOffWidth  = log2Up(wordsPerBlock)
    val mshrIdWidth   = log2Up(mshrEntries)
    val reqTagWidth   = log2Up(mshrEntries * mshrMaxPending + 1) // CPU 请求 ID 宽度
}

// ---------- 接口 ----------
case class CpuReq(cfg: CacheConfig) extends Bundle {
    val addr  = UInt(cfg.addrWidth bits)
    val wrEn  = Bool()
    val wData = Bits(cfg.dataWidth bits)
    val id    = UInt(cfg.reqTagWidth bits)
}

case class CpuResp(cfg: CacheConfig) extends Bundle {
    val data = Bits(cfg.dataWidth bits)
    val id   = UInt(cfg.reqTagWidth bits)
}

case class MemReq(cfg: CacheConfig) extends Bundle {
    val addr  = UInt(cfg.addrWidth bits)
    val wrEn  = Bool()
    val wData = Bits(cfg.blockSize * 8 bits)
    val id    = UInt(cfg.mshrIdWidth bits) // MSHR 条目号
}

case class MemResp(cfg: CacheConfig) extends Bundle {
    val rData = Bits(cfg.blockSize * 8 bits)
    val id    = UInt(cfg.mshrIdWidth bits)
}

// ---------- MSHR 等待槽 ----------
case class MshrPendingSlot(cfg: CacheConfig) extends Bundle {
    val valid   = Bool()
    val isWrite = Bool()
    val wData   = Bits(cfg.dataWidth bits)
    val wordOff = UInt(cfg.wordOffWidth bits)
    val respId  = UInt(cfg.reqTagWidth bits)
}

// ---------- MSHR 条目 ----------
case class MshrEntry(cfg: CacheConfig) extends Bundle {
    val valid     = Bool()
    val blockAddr = UInt(cfg.addrWidth - cfg.offsetWidth bits)
    val index     = UInt(cfg.indexWidth bits)
    val allocWay  = UInt(log2Up(cfg.numWays) bits)
    val isWrite   = Bool()                  // 原始缺失是否为写
    val state     = UInt(2 bits)            // 0:IDLE, 1:EVICT, 2:WAIT_FILL, 3:FILL

    val pendingSlots = Vec(MshrPendingSlot(cfg), cfg.mshrMaxPending)
    val fillData     = Bits(cfg.blockSize * 8 bits)
}

// ---------- 顶层流水线 Cache ----------
class PipelinedCache(cfg: CacheConfig) extends Component {
    val io = new Bundle {
        val cpu     = slave(Stream(CpuReq(cfg)))
        val cpuResp = master(Stream(CpuResp(cfg)))
        val memReq  = master(Stream(MemReq(cfg)))
        val memResp = slave(Stream(MemResp(cfg)))
    }

    // ---------- 存储阵列（寄存器，组合读） ----------
    val valid = Array.fill(cfg.numWays)(Vec(Reg(Bool()) init False, cfg.numSets))
    val dirty = Array.fill(cfg.numWays)(Vec(Reg(Bool()) init False, cfg.numSets))
    val tag   = Array.fill(cfg.numWays)(Vec(Reg(UInt(cfg.tagWidth bits)), cfg.numSets))
    val dataMem = Array.fill(cfg.numWays)(
        Vec(Reg(Bits(cfg.dataWidth bits)), cfg.numSets, cfg.wordsPerBlock)
    )

    // ---------- 替换策略 (FIFO) ----------
    val fifoCounters = Vec(Reg(UInt(log2Up(cfg.numWays) bits)) init 0, cfg.numSets)
    val allocWay = fifoCounters(io.cpu.payload.addr(cfg.indexWidth + cfg.offsetWidth - 1 downto cfg.offsetWidth))

    // ---------- 地址分解 ----------
    val req      = io.cpu.payload
    val offset   = req.addr(cfg.offsetWidth - 1 downto 0)
    val index    = req.addr(cfg.indexWidth + cfg.offsetWidth - 1 downto cfg.offsetWidth)
    val tagIn    = req.addr(cfg.addrWidth - 1 downto cfg.indexWidth + cfg.offsetWidth)
    val wordOff  = offset(cfg.offsetWidth - 1 downto log2Up(cfg.dataWidth / 8))
    val blockAddr= req.addr(cfg.addrWidth - 1 downto cfg.offsetWidth)

    // ---------- 命中判断（组合） ----------
    val wayHits = (0 until cfg.numWays).map(w => valid(w)(index) && tag(w)(index) === tagIn)
    val hit     = wayHits.orR
    val hitWay  = OHToUInt(wayHits)

    // ---------- MSHR 实例 ----------
    val mshr = Vec(Reg(MshrEntry(cfg)), cfg.mshrEntries)
    // 初始化 MSHR
    for (i <- 0 until cfg.mshrEntries) {
        mshr(i).valid init False
        mshr(i).state init 0
        for (j <- 0 until cfg.mshrMaxPending) {
            mshr(i).pendingSlots(j).valid init False
        }
    }

    // ---------- MSHR 查找 ----------
    val mshrHits    = mshr.map(e => e.valid && e.blockAddr === blockAddr)
    val mshrHit     = mshrHits.orR
    val mshrHitIdx  = OHToUInt(mshrHits)
    val mshrEmpty   = mshr.map(!_.valid).orR
    val mshrAllocIdx= PriorityEncoder(mshr.map(!_.valid))
    val mshrFull    = !mshrEmpty

    // 当前命中的 MSHR 条目（用于合并）
    val hitMshrEntry = mshr(mshrHitIdx)
    val canMerge     = !hitMshrEntry.pendingSlots.map(_.valid).andR // 还有空闲槽

    // ---------- CPU 请求接受条件 ----------
    val isMiss     = !hit && !mshrHit
    val needMshr   = isMiss || mshrHit  // 缺失或命中 MSHR（合并）都需要 MSHR 资源
    val canAccept  = hit || (mshrHit && canMerge) || (isMiss && mshrEmpty)
    io.cpu.ready := canAccept

    // ---------- 命中响应 FIFO ----------
    val hitRespFifo = StreamFifo(CpuResp(cfg), 4)
    hitRespFifo.io.push.valid   := False
    hitRespFifo.io.push.payload := CpuResp(cfg).getZero

    when(io.cpu.valid && io.cpu.ready && hit) {
        val rdata = dataMem(hitWay)(index)(wordOff)
        hitRespFifo.io.push.valid := True
        hitRespFifo.io.push.payload.data := rdata
        hitRespFifo.io.push.payload.id   := req.id
    }

    // ---------- 缺失处理：分配/合并 ----------
    val allocNew = io.cpu.valid && io.cpu.ready && isMiss
    val mergeReq = io.cpu.valid && io.cpu.ready && mshrHit && canMerge

    when(allocNew) {
        val entry = mshr(mshrAllocIdx)
        entry.valid      := True
        entry.blockAddr  := blockAddr
        entry.index      := index
        entry.allocWay   := allocWay
        entry.isWrite    := req.wrEn
        entry.state      := 0   // IDLE，下一拍自动启动状态机
        for (i <- 0 until cfg.mshrMaxPending) {
            entry.pendingSlots(i).valid := False
        }
        // 将当前请求放入第一个等待槽
        entry.pendingSlots(0).valid   := True
        entry.pendingSlots(0).isWrite := req.wrEn
        entry.pendingSlots(0).wData   := req.wData
        entry.pendingSlots(0).wordOff := wordOff
        entry.pendingSlots(0).respId  := req.id
    }

    when(mergeReq) {
        val entry = hitMshrEntry
        val freeIdx = PriorityEncoder(entry.pendingSlots.map(!_.valid))
        entry.pendingSlots(freeIdx).valid   := True
        entry.pendingSlots(freeIdx).isWrite := req.wrEn
        entry.pendingSlots(freeIdx).wData   := req.wData
        entry.pendingSlots(freeIdx).wordOff := wordOff
        entry.pendingSlots(freeIdx).respId  := req.id
    }

    // ---------- MSHR 状态机（每个条目独立） ----------
    for (i <- 0 until cfg.mshrEntries) {
        val entry = mshr(i)
        when(entry.valid) {
            switch(entry.state) {
                is(0) { // IDLE -> 检查是否需要写回
                    val isDirty = dirty(entry.allocWay)(entry.index)
                    when(isDirty) {
                        entry.state := 1 // EVICT
                    } otherwise {
                        entry.state := 2 // WAIT_FILL
                    }
                }
                // EVICT 和 WAIT_FILL 的跳转由内存响应/握手驱动（见下文）
                is(3) { // FILL -> 完成后回 IDLE
                    // FILL 处理将在下面单独完成
                }
            }
        }
    }

    // ---------- 内存请求生成与仲裁 ----------
    val memReqStreams = for (i <- 0 until cfg.mshrEntries) yield {
        val entry = mshr(i)
        val stream = Stream(MemReq(cfg))
        stream.valid := False
        stream.payload.addr  := 0
        stream.payload.wrEn  := False
        stream.payload.wData := 0
        stream.payload.id    := i

        when(entry.valid) {
            when(entry.state === 1) { // EVICT
                stream.valid := True
                stream.payload.wrEn := True
                stream.payload.addr := Cat(tag(entry.allocWay)(entry.index), entry.index, U(0, cfg.offsetWidth bits)).asUInt
                // 组装写回数据
                val wdata = Bits(cfg.blockSize * 8 bits)
                for (w <- 0 until cfg.wordsPerBlock) {
                    wdata(w * cfg.dataWidth, cfg.dataWidth bits) := dataMem(entry.allocWay)(entry.index)(w)
                }
                stream.payload.wData := wdata
            }
            when(entry.state === 2) { // WAIT_FILL
                stream.valid := True
                stream.payload.wrEn := False
                stream.payload.addr := entry.blockAddr @@ U(0, cfg.offsetWidth bits)
            }
        }
        stream
    }
    // 仲裁（低索引高优先）
    val memReqArbiter = StreamArbiter.lowerFirst(memReqStreams)
    io.memReq << memReqArbiter.io.output

    // ---------- 内存响应路由 ----------
    io.memResp.ready := False
    for (i <- 0 until cfg.mshrEntries) {
        val entry = mshr(i)
        when(io.memResp.valid && io.memResp.id === i) {
            when(entry.state === 1) {
                // EVICT 写回完成
                entry.state := 2   // 转到 WAIT_FILL
                io.memResp.ready := True
            }
            when(entry.state === 2) {
                // 读缺失数据返回
                entry.fillData := io.memResp.rData
                entry.state    := 3   // 进入 FILL
                io.memResp.ready := True
            }
        }
    }

    // ---------- MSHR FILL 处理与响应生成 ----------
    val mshrRespStreams = for (i <- 0 until cfg.mshrEntries) yield {
        val entry = mshr(i)
        val stream = Stream(CpuResp(cfg))
        stream.valid := False
        stream.payload.data := 0
        stream.payload.id   := 0

        when(entry.valid && entry.state === 3) {
            // 更新 Cache
            valid(entry.allocWay)(entry.index) := True
            tag(entry.allocWay)(entry.index)   := entry.blockAddr(entry.blockAddr.high downto cfg.indexWidth)
            dirty(entry.allocWay)(entry.index) := entry.isWrite
            for (w <- 0 until cfg.wordsPerBlock) {
                dataMem(entry.allocWay)(entry.index)(w) := entry.fillData(w * cfg.dataWidth, cfg.dataWidth bits)
            }
            // 处理等待槽
            for (j <- 0 until cfg.mshrMaxPending) {
                when(entry.pendingSlots(j).valid) {
                    val slot = entry.pendingSlots(j)
                    // 如果是写，合并写数据
                    when(slot.isWrite) {
                        dataMem(entry.allocWay)(entry.index)(slot.wordOff) := slot.wData
                        dirty(entry.allocWay)(entry.index) := True
                    }
                    // 产生响应
                    stream.valid := True
                    stream.payload.id   := slot.respId
                    stream.payload.data := slot.isWrite ? B(0, cfg.dataWidth bits) | entry.fillData(slot.wordOff * cfg.dataWidth, cfg.dataWidth bits)
                }
            }
            // 清除所有等待槽并释放 MSHR
            for (j <- 0 until cfg.mshrMaxPending) {
                entry.pendingSlots(j).valid := False
            }
            entry.valid := False
            // 更新替换策略指针
            fifoCounters(entry.index) := entry.allocWay + 1
        }
        stream
    }

    // ---------- 响应合并：命中 + MSHR 所有条目 ----------
    val allRespStreams = hitRespFifo.io.pop +: mshrRespStreams
    val respArbiter = StreamArbiter.roundRobin(allRespStreams, waitForReady = true)
    io.cpuResp << respArbiter.io.output
}

// 辅助：优先编码器
object PriorityEncoder {
    def apply(sels: Seq[Bool]): UInt = {
        val width = log2Up(sels.length)
        val result = UInt(width bits)
        result := 0
        for (i <- sels.length - 1 to 0 by -1) {
            when(sels(i)) { result := i }
        }
        result
    }
}