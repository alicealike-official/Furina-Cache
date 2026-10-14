// DCacheWithMSHR.scala
import spinal.core._
import spinal.lib._

// ---------- 配置参数 ----------
case class CacheConfig(
    numSets:        Int = 32,
    blockSize:      Int = 64,   // 字节
    numWays:        Int = 4,
    dataWidth:      Int = 32,
    addrWidth:      Int = 32,
    mshrEntries:    Int = 4,    // MSHR 条目数
    mshrMaxPending: Int = 4     // 每个 MSHR 最多挂起的请求数
) {
    val indexWidth  = log2Up(numSets)
    val offsetWidth = log2Up(blockSize)
    val tagWidth    = addrWidth - offsetWidth - indexWidth
    val wordsPerBlock = blockSize / (dataWidth / 8)
    val wordOffWidth  = log2Up(wordsPerBlock)

    // MSHR 条目 ID 宽度 (用于内存请求/响应匹配)
    val mshrIdWidth = log2Up(mshrEntries)
    // 请求标签宽度（区分 CPU 未完成的请求）
    val reqTagWidth = log2Up(mshrEntries * mshrMaxPending + 1)
}

// ---------- 接口 Bundle ----------
case class CpuReq(cfg: CacheConfig) extends Bundle {
    val addr  = UInt(cfg.addrWidth bits)
    val wrEn  = Bool()
    val wData = Bits(cfg.dataWidth bits)
    val id    = UInt(cfg.reqTagWidth bits)   // CPU 请求标签
}

case class CpuResp(cfg: CacheConfig) extends Bundle {
    val data = Bits(cfg.dataWidth bits)
    val id   = UInt(cfg.reqTagWidth bits)
}

case class MemReq(cfg: CacheConfig) extends Bundle {
    val addr  = UInt(cfg.addrWidth bits)
    val wrEn  = Bool()
    val wData = Bits(cfg.blockSize * 8 bits)
    val id    = UInt(cfg.mshrIdWidth bits)   // MSHR 条目号
}

case class MemResp(cfg: CacheConfig) extends Bundle {
    val rData = Bits(cfg.blockSize * 8 bits)
    val id    = UInt(cfg.mshrIdWidth bits)
}

// ---------- MSHR 条目 ----------
case class MshrPendingSlot(cfg: CacheConfig) extends Bundle {
    val valid    = Bool()
    val isWrite  = Bool()
    val wData    = Bits(cfg.dataWidth bits)
    val wordOff  = UInt(cfg.wordOffWidth bits)
    val respId   = UInt(cfg.reqTagWidth bits)  // 返回给 CPU 的 ID
}

case class MshrEntry(cfg: CacheConfig) extends Bundle {
    val valid     = Bool()
    val blockAddr = UInt(cfg.tagWidth + cfg.indexWidth bits)
    val isWrite   = Bool()          // 原始缺失类型
    val index     = UInt(cfg.indexWidth bits)
    val allocWay  = UInt(log2Up(cfg.numWays) bits)

    // 状态： IDLE, EVICT_WAIT, MISS_WAIT, FILL
    val state     = UInt(2 bits)

    val pendingSlots = Vec(MshrPendingSlot(cfg), cfg.mshrMaxPending)
    val fillData = Bits(cfg.blockSize * 8 bits)
}

// ---------- 顶层 Cache ----------
class DCacheWithMSHR(cfg: CacheConfig) extends Component {
    val io = new Bundle {
        val cpu = slave(Stream(CpuReq(cfg)))
        val mem = master(Stream(MemReq(cfg)))     // 请求通道
        val memResp = slave(Stream(MemResp(cfg))) // 响应通道
        // CPU 响应
        val cpuResp = master(Stream(CpuResp(cfg)))
    }

    // ---- 存储阵列 ----
    // val valid = Array.fill(cfg.numWays)(Reg(Bits(cfg.numSets bits)) init 0)
    val valid = Array.fill(cfg.numWays)(
        Vec(Reg(Bool() init False), cfg.numSets)
    )

    //val dirty = Array.fill(cfg.numWays)(Reg(Bits(cfg.numSets bits)) init 0)
    val dirty = Array.fill(cfg.numWays)(
        Vec(Reg(Bool() init False), cfg.numSets)
    )

    val tag   = Array.fill(cfg.numWays)(
        Vec(Reg(UInt(cfg.tagWidth bits) init 0), cfg.numSets)
    )

    val dataMem = Array.fill(cfg.numWays)(
        Vec(Reg(Bits(cfg.dataWidth bits) init 0), wordCount = cfg.numSets * cfg.wordsPerBlock)
    )

    // ---- 地址分解 ----
    val req         = io.cpu.payload
    val offset      = req.addr(cfg.offsetWidth - 1 downto 0)
    val index       = req.addr(cfg.indexWidth + cfg.offsetWidth - 1 downto cfg.offsetWidth)
    val tagIn       = req.addr(cfg.addrWidth - 1 downto cfg.indexWidth + cfg.offsetWidth)
    val wordOff     = offset(cfg.offsetWidth - 1 downto log2Up(cfg.dataWidth / 8))
    val blockAddr   = req.addr(cfg.addrWidth - 1 downto cfg.offsetWidth)

    // ---- 命中判断 ----
    val wayHits = (0 until cfg.numWays).map { w =>
        valid(w)(index) && tag(w)(index) === tagIn
    }
    
    val hit   = wayHits.orR
    val hitWay = OHToUInt(wayHits)

    // ---- 替换策略 (FIFO) ----
    val fifoCounters = Vec(Reg(UInt(log2Up(cfg.numWays) bits)) init 0, cfg.numSets)
    val allocWay = fifoCounters(index)

    // ---- MSHR 模块 ----
    val mshr = Vec(Reg(MshrEntry(cfg)), cfg.mshrEntries)
    // 初始化 MSHR
    for (i <- 0 until cfg.mshrEntries) {
        mshr(i).valid init False
        mshr(i).state init 0
        for (j <- 0 until cfg.mshrMaxPending) {
            mshr(i).pendingSlots(j).valid init False
        }
    }

    // 查找 MSHR 是否命中
    val mshrHitVec = mshr.map(e => e.valid && e.blockAddr === blockAddr)
    val mshrHit    = mshrHitVec.orR
    val mshrHitIdx = OHToUInt(mshrHitVec)

    // 是否有空闲 MSHR 条目
    val mshrEmptyVec = mshr.map(!_.valid)
    val mshrEmpty = mshrEmptyVec.orR
    val mshrAllocIdx = PriorityEncoder(mshrEmptyVec)

    // 检查 MSHR 中等待槽是否有空位 (用于合并)
    val mshrCanMerge = if (cfg.mshrMaxPending > 0) {
        val hitEntry = mshr(mshrHitIdx)
        !hitEntry.pendingSlots.map(_.valid).andR
    } else False

    // CPU 请求能否被接受
    val canAccept = hit || (mshrHit && mshrCanMerge) || (!mshrHit && mshrEmpty)
    io.cpu.ready := canAccept

    // ---- CPU 响应 FIFO (避免组合环) ----
    val respFifo = StreamFifo(CpuResp(cfg), cfg.mshrEntries * cfg.mshrMaxPending + 4)
    respFifo.io.push.valid := False
    respFifo.io.push.payload.data := 0
    respFifo.io.push.payload.id   := 0
    io.cpuResp << respFifo.io.pop.toFlow  // 输出响应流

    // ---- 记录已接受但尚未响应的请求 ID (用于命中时立即进入 FIFO) ----
    val reqAccepted = io.cpu.valid && io.cpu.ready

    // ---- 命中处理 ----
    when(reqAccepted && hit) {
        // 命中：直接读取数据，推入响应 FIFO
        val rdata = dataMem(hitWay)(index)(wordOff)
        respFifo.io.push.valid := True
        respFifo.io.push.payload.data := rdata
        respFifo.io.push.payload.id   := req.id
    }

    // ---- 缺失处理 ----
    // 分配新 MSHR 或合并到已有条目
    val allocNew = reqAccepted && !hit && !mshrHit
    val mergeReq = reqAccepted && !hit &&  mshrHit

    // 新分配时，初始化 MSHR 条目
    when(allocNew) {
        val entry = mshr(mshrAllocIdx)
        entry.valid     := True
        entry.blockAddr := blockAddr
        entry.isWrite   := req.wrEn
        entry.index     := index
        entry.allocWay  := allocWay
        entry.state     := 0   // IDLE，下一周期状态机启动
        // 清空等待槽
        for (i <- 0 until cfg.mshrMaxPending) {
            entry.pendingSlots(i).valid := False
        }
        // 将当前请求写入第一个等待槽
        entry.pendingSlots(0).valid   := True
        entry.pendingSlots(0).isWrite := req.wrEn
        entry.pendingSlots(0).wData   := req.wData
        entry.pendingSlots(0).wordOff := wordOff
        entry.pendingSlots(0).respId  := req.id
    }

    // 合并到已有条目
    when(mergeReq) {
        val entry = mshr(mshrHitIdx)
        // 找到第一个空闲槽位
        val freeIdx = PriorityEncoder(entry.pendingSlots.map(!_.valid))
        entry.pendingSlots(freeIdx).valid   := True
        entry.pendingSlots(freeIdx).isWrite := req.wrEn
        entry.pendingSlots(freeIdx).wData   := req.wData
        entry.pendingSlots(freeIdx).wordOff := wordOff
        entry.pendingSlots(freeIdx).respId  := req.id
    }

    // ---- MSHR 状态机 (每个条目独立) ----
    for (i <- 0 until cfg.mshrEntries) {
        val entry = mshr(i)
        when(entry.valid) {
            switch(entry.state) {
                is(0) {  // IDLE -> 检查是否需要写回脏块
                    val isDirty = dirty(entry.allocWay)(entry.index)
                    when(isDirty) {
                        entry.state := 1  // EVICT_WAIT
                    } otherwise {
                        entry.state := 2  // MISS_WAIT (直接进入读缺失)
                    }
                }
                is(1) {  // EVICT_WAIT: 等待写回完成 (内存响应确认)
                    // 由内存响应处理逻辑将状态改为 MISS_WAIT
                }
                is(2) {  // MISS_WAIT: 等待读缺失数据返回
                    // 由内存响应处理逻辑将状态改为 FILL
                }
                is(3) {  // FILL: 处理等待队列，完成后释放
                    // 此处仅标记完成，实际释放由 FILL 处理逻辑完成
                }
            }
        }
    }

    // ---- 内存请求生成 ----
    // 从所有 MSHR 条目中仲裁出内存请求
    val memReqArbiter = StreamArbiter.lowerFirst(cfg.mshrEntries)(MemReq(cfg))
    for (i <- 0 until cfg.mshrEntries) {
        val entry = mshr(i)
        memReqArbiter.io.inputs(i).valid := False
        memReqArbiter.io.inputs(i).payload.addr := 0
        memReqArbiter.io.inputs(i).payload.wrEn := False
        memReqArbiter.io.inputs(i).payload.wData := 0
        memReqArbiter.io.inputs(i).payload.id := i

        when(entry.valid) {
            // EVICT 状态: 写回脏块
            when(entry.state === 1 && !entry.isWrite) { // 仅读缺失需要写回? 写缺失也写分配，需要写回
                memReqArbiter.io.inputs(i).valid := True
                memReqArbiter.io.inputs(i).payload.wrEn := True
                // 写回地址 = {tag, index, 0}
                memReqArbiter.io.inputs(i).payload.addr := Cat(
                    tag(entry.allocWay)(entry.index),
                    entry.index,
                    U(0, cfg.offsetWidth bits)
                )
                // 组装写数据
                val wdata = Bits(cfg.blockSize * 8 bits)
                for (w <- 0 until cfg.wordsPerBlock) {
                    wdata(w * cfg.dataWidth, cfg.dataWidth bits) := dataMem(entry.allocWay)(entry.index)(w)
                }
                memReqArbiter.io.inputs(i).payload.wData := wdata
            }
            // MISS 状态: 读缺失
            when(entry.state === 2) {
                memReqArbiter.io.inputs(i).valid := True
                memReqArbiter.io.inputs(i).payload.wrEn := False
                memReqArbiter.io.inputs(i).payload.addr := Cat(
                    tagIn, entry.index, U(0, cfg.offsetWidth bits)
                )
                // 注意：此时 tagIn 是当前缺失的 tag，应保存在 MSHR 中？
                // 实际 blockAddr 已保存，可直接用 blockAddr 拼接 offset=0
                memReqArbiter.io.inputs(i).payload.addr := entry.blockAddr @@ U(0, cfg.offsetWidth bits)
            }
        }
    }

    // 内存请求输出（这里简化，直接驱动端口，未考虑背压）
    io.mem.valid := memReqArbiter.io.output.valid
    io.mem.payload := memReqArbiter.io.output.payload
    // 假设内存始终 ready
    memReqArbiter.io.output.ready := True

    // ---- 内存响应处理 ----
    io.memResp.ready := True
    when(io.memResp.valid) {
        val respId = io.memResp.id
        val entry = mshr(respId)
        // 根据当前状态处理
        when(entry.state === 1) {  // 写回完成
            entry.state := 2      // 进入 MISS_WAIT
        }
        when(entry.state === 2) {  // 读数据返回
            entry.fillData := io.memResp.rData
            entry.state := 3      // 进入 FILL
        }
    }

    // ---- FILL 处理（更新缓存 + 响应等待者） ----
    for (i <- 0 until cfg.mshrEntries) {
        val entry = mshr(i)
        when(entry.valid && entry.state === 3) {
            // 更新 Cache 行
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
                    // 如果是写，需要合并写数据到缓存行
                    when(slot.isWrite) {
                        dataMem(entry.allocWay)(entry.index)(slot.wordOff) := slot.wData
                        dirty(entry.allocWay)(entry.index) := True
                    }
                    // 生成响应
                    val respData = slot.isWrite ? U(0) | entry.fillData(slot.wordOff * cfg.dataWidth, cfg.dataWidth bits)
                    respFifo.io.push.valid := True
                    respFifo.io.push.payload.data := respData.asBits
                    respFifo.io.push.payload.id   := slot.respId
                }
            }
            // 清除等待槽
            for (j <- 0 until cfg.mshrMaxPending) {
                entry.pendingSlots(j).valid := False
            }
            // 释放 MSHR 条目并更新 FIFO 指针
            entry.valid := False
            // 更新替换策略计数器 (仅在该 set 上分配新块时)
            fifoCounters(entry.index) := entry.allocWay + 1
        }
    }
}

// 辅助函数
object PriorityEncoder {
    def apply(sel: Seq[Bool]): UInt = {
        val width = log2Up(sel.size)
        val result = UInt(width bits)
        result := 0
        for (i <- sel.size - 1 downto 0) {
            when(sel(i)) { result := i }
        }
        result
    }
}