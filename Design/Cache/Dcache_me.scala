package cache
import spinal.core._ 
import spinal.lib._ 

//-----------------------辅助函数-----------------------//
def isPow2(x: Int): Boolean = x > 0 && (x & (x - 1)) == 0
//-----------------------辅助函数-----------------------//


//-----------------------配置参数-----------------------//
case class CacheConfig (
    numSets         :   Int = 32,
    blockSize       :   Int = 64,
    numWays         :   Int = 4,
    dataWidth       :   Int = 32,
    addrWidth       :   Int = 32,
    mshrEntries     :   Int = 4,
    mshrMaxPending  :   Int = 4
) {
    require(dataWidth % 32 == 0, "data width must be a multiple of 32!")
    require(isPow2(numSets), "numsets must be a power of 2")
    require(isPow2(blockSize), "blocksize must be a power of 2")
    require(isPow2(numWays), "numways must be a power of 2")
    require(isPow2(mshrMaxPending), "mshrMaxPending must be a power of 2")

    val indexWidth      = log2Up(numSets)
    val offsetWidth     = log2Up(blockSize)
    val tagWidth        = addrWidth - offsetWidth - indexWidth
    val wordsPerBlock   = blockSize / (dataWidth / 8)
    val mshrIdWidth     = log2Up(mshrEntries)
    val pendingWidth    = log2Up(mshrMaxPending)
    val wordOffWidth    = log2Up(wordsPerBlock)

    // CPU 请求ID，保证能够覆盖所有的MSHR寄存指令的同时能给新指令分配ID
    val reqIDWidth      = log2Up(mshrEntries * mshrMaxPending + 1)
    val replaceType     = "FIFO"
}
//-----------------------配置参数-----------------------//
object CacheState extends SpinalEnum {
    val NOVALID, VALID, RESERVED = newElement()
}

object MshrState extends SpinalEnum {
    val IDLE, EVICT, WAIT_FILL, FILL, SLOTFILL = newElement()
}

//-----------------------接口信号-----------------------//
case class CpuReq(cfg: CacheConfig) extends Bundle {
    val addr    = UInt(cfg.addrWidth bits)
    val wrEn    = Bool() //使能高表示写，低表示读
    val wData   = Bits(cfg.dataWidth bits)
    val id      = UInt(cfg.reqIDWidth bits)
}

case class CpuResp(cfg: CacheConfig) extends Bundle {
    val rData   = Bits(cfg.dataWidth bits)
    val id      = UInt(cfg.reqIDWidth bits)
}

case class MemReq(cfg: CacheConfig) extends Bundle {
    val addr    = UInt(cfg.addrWidth bits)
    val wrEn    = Bool()
    val wData   = Bits(cfg.blockSize * 8 bits)
    val id      = UInt(cfg.mshrIdWidth bits)
}

case class MemResp(cfg: CacheConfig) extends Bundle {
    val rData   = Bits(cfg.blockSize * 8 bits)
    val id      = UInt(cfg.mshrIdWidth bits) 
}
//-----------------------接口信号-----------------------//

//-----------------------数据组信号-----------------------//
case class CacheLine(cfg: CacheConfig) extends Bundle {
    val state   = CacheState()
    val dirty   = Bool()
    val tag     = UInt(cfg.tagWidth bits)
    val data    = Bits(cfg.blockSize * 8 bits)
}

case class MshrPendingSlot(cfg: CacheConfig) extends Bundle {
    val valid       = Bool()
    val isWrite     = Bool()
    val wData       = Bits(cfg.dataWidth bits)
    val wordOff     = UInt(cfg.wordOffWidth bits)
    val respId      = UInt(cfg.reqIDWidth bits)

}

case class MshrEntry(cfg: CacheConfig) extends Bundle {
    val valid       = Bool()
    val blockAddr   = UInt(cfg.addrWidth - cfg.offsetWidth bits)
    val index       = UInt(cfg.indexWidth bits)
    val allocWay    = UInt(log2Up(cfg.numWays) bits)
    // val isWrite     = Bool()
    val state       = MshrState()

    val pendingSlots    = Vec(MshrPendingSlot(cfg), cfg.mshrMaxPending)
    val fillData        = Bits(cfg.blockSize*8 bits)
    val rdPtr           = UInt(pendingWidth+1 bits) // 读指针，指向下一个需要被读取的请求
    val wrPtr           = UInt(pendingWidth+1 bits) // 写指针，指向下一个需要压入的请求
    // val slotCnt         = UInt(log2Up(cfg.mshrMaxPending+1) bits) // 当前有效槽位数
    // //当前处理的槽位
    // val processPtr  = UInt(log2Up(cfg.mshrMaxPending) bits)
}
//-----------------------数据组信号-----------------------//


// ============================================================//
//                                                             //
//                           Cache                             //
//                                                             //
// ============================================================//

class PipelinedCache(cfg: CacheConfig) extends Component {
    //-----------------------IO-----------------------//
    val io = new Bundle {
        val cpuReq      = slave(Stream(CpuReq(cfg)))
        val cpuResp     = master(Stream(CpuResp(cfg)))

        val memReq      = master(Stream(MemReq(cfg)))
        val memResp     = slave(Stream(MemResp(cfg)))
    }
    //-----------------------IO-----------------------//


    //-----------------------Inst -----------------------//
    val ways = Array.fill(cfg.numWays)(
        Vec(
            Reg(CacheLine(cfg)) init CacheLine(cfg).getZero, 
            cfg.numSets
        )
    )

    val mshr = Vec(
        Reg(MshrEntry(cfg)) init MshrEntry(cfg).getZero,
        cfg.mshrEntries
    )
    //-----------------------Inst -----------------------//

    //-----------------------地址分解-----------------------//
    val req         = io.cpuReq.payload
    val offset      = req.addr(cfg.offsetWidth-1 downto 0)
    val index       = req.addr(cfg.indexWidth + cfg.offsetWidth-1 downto cfg.offsetWidth)
    val tagIn       = req.addr(cfg.addrWidth-1 downto cfg.indexWidth + cfg.offsetWidth)
    val blockAddr   = req.addr(cfg.addrWidth-1 downto cfg.offsetWidth)
    val wordOff     = offset(cfg.offsetWidth - 1 downto log2Up(cfg.dataWidth / 8))
    //-----------------------地址分解-----------------------//


    //-----------------------Cache命中判断-----------------------//
    val wayhits     = (0 until cfg.numWays).map {
        w => (ways(w)(index).state === CacheState.VALID) && (ways(w)(index).tag === tagIn)
    }
    val hit         = wayhits.orR
    val hitWay     = OHToUInt(wayhits)
    //-----------------------Cache命中判断-----------------------//

    //-----------------------Cache替换算法-----------------------//
    val rep             = ReplacementFactory(cfg.replaceType, cfg.numWays, cfg.numSets)
    val allocWay        = rep.getVictimWay(index)
    // val curr_alloc_way  = rep1.getVictimWay()
    // val alloc_addr      = Cat(tag(curr_alloc_way)(index_in),
    //                         index_in,
    //                         B(0,offsetWidth bits)
    //                         )
    // val hit_rdata       = (!req.wrEn) ? DataMem(hit_way)(index_in)(word_offset) | B(0, dataWidth bits)
    // val alloc_data      = io.mem_resp.payload.rData(word_offset*dataWidth, cfg.dataWidth bits)
    //-----------------------Cache替换算法-----------------------//


    //-----------------------MSHR命中判断-----------------------//
    val mshrHits    = (0 until cfg.mshrEntries).map {
        e => mshr(e).valid && mshr(e).blockAddr === blockAddr
    }
    val mshrHit     = mshrHits.orR
    val mshrHitIdx  = OHToUInt(mshrHits)
    //-----------------------MSHR命中判断-----------------------//

    //-----------------------MSHR替换-----------------------//
    val mshrEmpty       =  mshr.map(!_.valid).orR   //MSHR有一个条目是空的
    val mshrFull        = !mshrEmpty
    val mshrAllocIdx    = PriorityEncoder(mshr.map(!_.valid))

    val hitMshrEntry    = mshr(mshrHitIdx)
    val mshrSlotEmpty   = (hitMshrEntry.rdPtr === hitMshrEntry.wrPtr)
    val mshrSlotFull    = (hitMshrEntry.wrPtr - hitMshrEntry.rdPtr) >= cfg.mshrMaxPending
    // val canMerge        = !hitMshrEntry.pendingSlots.map(_.valid).andR  //只要有一个slot valid为0，就表示可以merge
    val canMerge        = !mshrSlotFull
    //-----------------------MSHR替换-----------------------//

    assert(!(hit && mshrHit), "hit and mshrHit cannot be high simultaneously!")
    //-----------------------Cache Ready-----------------------//
    val isMiss      = !hit && !mshrHit
    val canAccept   = hit || (mshrHit && canMerge) || (isMiss && mshrEmpty)
    io.cpu.ready    := canAccept
    //-----------------------Cache Ready-----------------------//

    //-----------------------Cache Resp FIFO(命中处理)-----------------------//
    val hitRespFifo = StreamFifo(CpuResp(cfg), 4)
    hitRespFifo.io.push.valid   := False
    hitRespFifo.io.push.payload := CpuResp(cfg).getZero

    when (io.cpuReq.fire && hit) {
        when (!req.wrEn) { //读取请求
            // val rdata                           = dataMem(hitWay)(index)(wordOff)
            val rdata                           = ways(hitWay)(index).data((wordOff)*cfg.dataWidth, cfg.dataWidth)
            hitRespFifo.io.push.valid           := True
            hitRespFifo.io.push.payload.rData   := rdata
            hitRespFifo.io.push.payload.id      := req.id
        } otherwise { //写请求
            ways(hitWay)(index).data((wordOff)*cfg.dataWidth, cfg.dataWidth)     := req.wData
            ways(hitWay)(index).dirty           := True
            hitRespFifo.io.push.valid           := True
            hitRespFifo.io.push.payload.rData   := 0
            hitRespFifo.io.push.payload.id      := req.id
        }
    }
    //-----------------------Cache Resp FIFO(命中处理)-----------------------//

    //-----------------------缺失处理-----------------------//
    val allocNew    = io.cpuReq.fire && isMiss  // ready为高隐含了Entries有空
    val mergeReq    = io.cpuReq.fire && mshrHit && canMerge

    when(allocNew) {
        rep.updateOnFill(index, allocWay)
        val entry           = mshr(mshrAllocIdx)
        entry.valid         := True
        entry.blockAddr     := blockAddr
        entry.index         := index
        entry.allocWay      := allocWay
        // entry.isWrite       := req.wrEn
        entry.state         := MshrState.IDLE


        for (i <- 0 until cfg.mshrMaxPending) {
            entry.pendingSlots(i).valid := False
        } //先清空这个槽位

        // 再把这个请求放在第一位
        entry.pendingSlots(0).valid     := True
        entry.pendingSlots(0).isWrite   := req.wrEn
        entry.pendingSlots(0).wData     := req.wData
        entry.pendingSlots(0).wordOff   := wordOff
        entry.pendingSlots(0).respId    := req.id
        entry.wrPtr         := 1
    }

    when(mergeReq) {
        val entry   = hitMshrEntry
        // val freeIdx = FifoAlloc(entry.pendingSlots.map(!_.valid))
        entry.pendingSlots(entry.wrPtr(pendingWidth-1 downto 0)).valid     := True
        entry.pendingSlots(entry.wrPtr(pendingWidth-1 downto 0)).isWrite   := req.wrEn
        entry.pendingSlots(entry.wrPtr(pendingWidth-1 downto 0)).wData     := req.wData
        entry.pendingSlots(entry.wrPtr(pendingWidth-1 downto 0)).wordOff   := wordOff
        entry.pendingSlots(entry.wrPtr(pendingWidth-1 downto 0)).respId    := req.id

        entry.wrPtr := entry.wrPtr+1
    }
    //-----------------------缺失处理-----------------------//

    //-----------------------MSHR状态机-----------------------//
    for (i <- 0 until cfg.mshrEntries) {
        val entry = mshr(i)
        when (entry.valid) {
            switch(entry.state) {
                is(MshrState.IDLE) {
                    // val isDirty = dirty(entry.allocWay)(entry.index)
                    val isDirty = ways(entry.allocWay)(entry.index).dirty

                    when(isDirty) {
                        entry.state := MshrState.EVICT
                    } otherwise {
                        entry.state := MshrState.WAIT_FILL
                    }
                }
            }
        }
    }
    //-----------------------MSHR状态机-----------------------//


    //-----------------------内存请求生成-----------------------//
    val memReqStreams = for(i <- 0 until cfg.mshrEntries) yield {
        val entry   = mshr(i)
        val stream  = Stream(MemReq(cfg))

        stream.valid            := False
        stream.payload.wrEn     := False 
        stream.payload.addr     := 0
        stream.payload.wData    := 0
        stream.payload.id       := i

        when (entry.valid) {
            when (entry.state === MshrState.EVICT) {   // 写回内存里面的数据
                stream.valid            := True
                stream.payload.addr     := Cat(
                                                //tag(entry.allocWay)(entry.index), 
                                                ways(entry.allocWay)(entry.index).tag,
                                                entry.index, 
                                                B(0, cfg.offsetWidth bits)).asUInt
                stream.payload.wrEn     := True
                // val writeBackData       := Bits(cfg.blockSize * 8 bits)
                // for (w <- 0 until cfg.wordsPerBlock) {
                //     writeBackData(w * cfg.dataWidth, cfg.dataWidth bits) := dataMem(entry.allocWay)(entry.index)(w)
                // }
                // stream.payload.wData    := writeBackData
                stream.payload.wData    := ways(entry.allocWay)(entry.index).data
            }

            when (entry.state === MshrState.WAIT_FILL) {   //发送读取请求
                stream.valid            := True
                stream.payload.addr     := entry.blockAddr @@ B(0, cfg.offsetWidth bits)
                stream.payload.wrEn     := False
                stream.payload.wData    := 0
            }
        }
        stream
    }
    //-----------------------内存请求生成-----------------------//

    //-----------------------内存请求仲裁-----------------------//
    val memReqArbiter   = StreamArbiter.roundRobin(memReqStreams)
    io.memReq   << memReqArbiter.io.output
    //-----------------------内存请求仲裁-----------------------//

    //-----------------------内存响应-----------------------//
    io.memResp.ready := False
    for (i <- 0 until cfg.mshrEntries) {
        val entry = mshr(i)
        when (io.memResp.valid && io.memResp.id === i) {
            when (entry.state === MshrState.EVICT) {
                // 写回完成，不需要接受什么数据
                entry.state         := MshrState.WAIT_FILL
                io.memResp.ready    := True
            }

            when (entry.state === MshrState.WAIT_FILL) {
                // 读取数据完成，接收数据FillData
                entry.state         := MshrState.FILL
                io.memResp.ready    := True
                entry.fillData      := io.memResp.rData
            }
        }
    }
    //-----------------------内存响应-----------------------//

    //-----------------------MSHR FILL-----------------------//
    val mshrRespStreams = for (i <- 0 until cfg.mshrEntries) yield {
        val entry = mshr(i)
        val stream = Stream(CpuResp(cfg))

        stream.valid            := False
        stream.payload.id       := 0
        stream.payload.rData    := 0


        when(entry.valid && entry.state === MshrState.FILL) {
            // 填充时先写入cache行
            // valid(entry.allocWay)(entry.index)  := True
            // tag(entry.allocWay)(entry.index)    := entry.blockAddr(entry.blockAddr.high downto cfg.indexWidth)
            // dirty(entry.allocWay)(entry.index)  := False    // 最先是内存数据，这时候数据是干净的


            // 填充时先写入cache行
            ways(entry.allocWay)(entry.index).tag    := entry.blockAddr(entry.blockAddr.high downto cfg.indexWidth)
            ways(entry.allocWay)(entry.index).dirty  := False    // 最先是内存数据，这时候数据是干净的

            ways(entry.allocWay)(entry.index).data := entry.fillData
            // for (w <- 0 until cfg.wordsPerBlock) {
            //     dataMem(entry.allocWay)(entry.index)(w) := entry.fillData(w*cfg.dataWidth, cfg.dataWidth)
            // }

            entry.state := MshrState.SLOTFILL
        }

        when(entry.valid && entry.state === MshrState.SLOTFILL) {
            // 再处理等待槽位
            when (entry.wrPtr =/= entry.rdPtr) {
                val slot = entry.pendingSlots(entry.rdPtr(pendingWidth-1 downto 0))
                when (slot.isWrite) { // 写操作
                    // dataMem(entry.allocWay)(entry.index)(slot.wordOff) := slot.wData
                    // dirty(entry.allocWay)(entry.index) := True
                    ways(entry.allocWay)(entry.index).data((slot.wordOff)*cfg.dataWidth, cfg.dataWidth) := slot.wData
                    ways(entry.allocWay)(entry.index).dirty := True
                }

                stream.valid            := True
                stream.payload.id       := slot.respId
                stream.payload.rData    := slot.isWrite ? B(0, cfg.dataWidth bits) | ways(entry.allocWay)(entry.index).data((slot.wordOff)*cfg.dataWidth, cfg.dataWidth)

                when (stream.fire){
                    entry.rdPtr := entry.rdPtr+1
                }
            }

            when (entry.wrPtr === entry.rdPtr) {
                entry.start := MshrState.IDLE
                entry.valid := False
                ways(entry.allocWay)(entry.index).state  := CacheState.VALID
            }

            // entry.state := (entry.wrPtr === entry.rdPtr) ? MshrState.IDLE | MshrState.SLOTFILL
            // entry.valid := (entry.wrPtr === entry.rdPtr) ? False | True
            
        }

        stream
    }
    //-----------------------MSHR FILL-----------------------//

    val allRespStreams  = hitRespFifo.io.pop +: mshrRespStreams
    val respArbiter     = StreamArbiter.roundRobin(allRespStreams, waitForReady = true)
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