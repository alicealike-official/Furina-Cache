// ============================================================
// 文件名   : Mshr.scala
// 描述     : MSHR —— 未命中登记、合并、发送、填充、重放
// 文档依据 : 《Cache 架构设计文档 v2》§7
//
// 状态机：IDLE -> SEND -> MISS_WAIT -> FILL -> IDLE
//   - 分配与发送解耦（SEND）
//   - SEND / MISS_WAIT 可合并；FILL 不可合并
//   - 发送仲裁：低位优先 + 保持寄存器（载荷锁存到握手）
//   - 填充：FILL 首拍写合并后的整行，之后逐 Slot 重放
//   - 重放：条目级轮询，条目内 Slot 从低到高
//   - 重放读数据 = fillData + 该 Slot 之前同字写（不读 Cache）
// ============================================================

package furina.dcache

import spinal.core._
import spinal.lib._

class Mshr(cfg: CacheConfig) extends Component {
    import cfg._

    private val N = MSHR_ENTRIES
    private val P = MSHR_MAX_PENDING
    private val slotCnt = N * P
    private val slotSelWidth = log2Up(slotCnt) max 1
    private val replayCntWidth = log2Up(P) max 1
    private val slotOneWidth = log2Up(P) max 1

    // 状态编码
    private val ST_IDLE = 0
    private val ST_SEND = 1
    private val ST_MISS_WAIT = 2
    private val ST_FILL = 3

    val io = new Bundle {
        // Stage2 分配新条目
        val alloc = in(new Bundle {
            val en = Bool()
            val tag = UInt(tagWidth bits)
            val index = UInt(indexWidth bits)
            val way = UInt(wayWidth bits)
            val isWrite = Bool()
            val wData = Bits(DATA_WIDTH bits)
            val wordOff = UInt(wordOffWidth bits)
            val respId = UInt(ID_WIDTH bits)
            val wbSlot = UInt(wbbIdWidth bits)
            val hasWb = Bool()
        })

        // Stage2 合并进已有条目
        val merge = in(new Bundle {
            val en = Bool()
            val entry = UInt(mshrIdWidth bits)
            val isWrite = Bool()
            val wData = Bits(DATA_WIDTH bits)
            val wordOff = UInt(wordOffWidth bits)
            val respId = UInt(ID_WIDTH bits)
        })

        // 两个查询口：q0 给 Stage1（估计），q1 给 Stage2（权威）
        val q0 = in(MshrQuery(cfg))
        val m0 = out(MshrMatch(cfg))
        val q1 = in(MshrQuery(cfg))
        val m1 = out(MshrMatch(cfg))

        val hasFree = out Bool()
        val freeEntry = out UInt(mshrIdWidth bits)

        // 内存读通道
        val memReadReq = master Stream (MemReadReq(cfg))
        val memReadResp = slave Stream (MemReadResp(cfg))

        // 填充写 Cache（W2）
        val fill = out(new Bundle {
            val en = Bool()
            val index = UInt(indexWidth bits)
            val way = UInt(wayWidth bits)
            val tag = UInt(tagWidth bits)
            val dirty = Bool()
            val line = Bits(lineWidth bits)
        })
        val fillReady = in Bool()

        // 重放响应
        val replay = master Stream (MshrReplay(cfg))

        // Way Lock：与条目同生同死
        val lockMask = out Vec (Vec(Bool(), NUM_WAYS), NUM_SETS)
    }

    // ---------------- 条目存储 ----------------
    private val entryValid = Vec(Reg(Bool()) init False, N)
    private val entryTag = Vec(Reg(UInt(tagWidth bits)) init 0, N)
    private val entryIndex = Vec(Reg(UInt(indexWidth bits)) init 0, N)
    private val entryWay = Vec(Reg(UInt(wayWidth bits)) init 0, N)
    private val entryState = Vec(Reg(UInt(2 bits)) init ST_IDLE, N)
    private val entryFillData = Vec(Reg(Bits(lineWidth bits)) init 0, N)
    private val entryFillDone = Vec(Reg(Bool()) init False, N)
    private val entryReplayCnt = Vec(Reg(UInt(replayCntWidth bits)) init 0, N)
    private val entryValidCnt = Vec(Reg(UInt(pendingCntWidth bits)) init 0, N)
    private val entryHasWrite = Vec(Reg(Bool()) init False, N)
    private val entryWbSlot = Vec(Reg(UInt(wbbIdWidth bits)) init 0, N)
    private val entryHasWb = Vec(Reg(Bool()) init False, N)

    // Slot 展平存储，下标 = entry * P + slot
    private val slotValid = Vec(Reg(Bool()) init False, slotCnt)
    private val slotIsWrite = Vec(Reg(Bool()) init False, slotCnt)
    private val slotWData = Vec(Reg(Bits(DATA_WIDTH bits)) init 0, slotCnt)
    private val slotWordOff = Vec(Reg(UInt(wordOffWidth bits)) init 0, slotCnt)
    private val slotRespId = Vec(Reg(UInt(ID_WIDTH bits)) init 0, slotCnt)

    // ---------------- 组合工具 ----------------
    private def slotIdxDyn(e: UInt, s: Int): UInt =
        ((e * U(P)) + U(s, slotSelWidth bits)).resize(slotSelWidth)

    private def slotIdxDyn(e: UInt, s: UInt): UInt =
        ((e * U(P)) + s).resize(slotSelWidth)

    private def priorityLowest(vec: Seq[Bool], width: Int): UInt = {
        val res = UInt(width bits)
        res := U(0, width bits)
        for (i <- (vec.length - 1) to 0 by -1) {
            when(vec(i)) { res := U(i, width bits) }
        }
        res
    }

    // ---------------- 匹配查询 ----------------
    private def buildMatch(query: MshrQuery): MshrMatch = {
        val res = MshrMatch(cfg)
        val hitVec = Vec((0 until N).map { e =>
            entryValid(e) && entryTag(e) === query.tag && entryIndex(e) === query.index
        })
        val hit = hitVec.orR
        val entry = priorityLowest(hitVec, mshrIdWidth)

        val slotFreeVec = Vec((0 until P).map(s => !slotValid(slotIdxDyn(entry, s))))
        res.hit := hit
        res.entry := entry
        res.mergeable := hit && ((entryState(entry) === U(ST_SEND, 2 bits)) ||
            (entryState(entry) === U(ST_MISS_WAIT, 2 bits)))
        res.slotFree := slotFreeVec.orR
        res.freeSlot := priorityLowest(slotFreeVec, slotOneWidth)
        res
    }

    private val match0 = buildMatch(io.q0)
    private val match1 = buildMatch(io.q1)
    io.m0 := match0
    io.m1 := match1

    // ---------------- 空闲条目 ----------------
    private val freeVec = Vec((0 until N).map(e => !entryValid(e)))
    io.hasFree := freeVec.orR
    io.freeEntry := priorityLowest(freeVec, mshrIdWidth)

    // ---------------- 发送仲裁（低位优先 + 保持） ----------------
    private val sendCand = Vec((0 until N).map(e => entryValid(e) && entryState(e) === U(ST_SEND, 2 bits)))
    private val sendCandValid = sendCand.orR
    private val sendCandIdx = priorityLowest(sendCand, mshrIdWidth)

    private val sendHold = Reg(Bool()) init False
    private val sendHoldIdx = Reg(UInt(mshrIdWidth bits)) init 0
    private val sendIdx = Mux(sendHold, sendHoldIdx, sendCandIdx)
    private val sendValid = sendHold || sendCandValid

    io.memReadReq.valid := sendValid
    io.memReadReq.payload.addr := Cat(
        entryTag(sendIdx),
        entryIndex(sendIdx),
        U(0, offsetWidth bits)
    ).asUInt
    io.memReadReq.payload.id := sendIdx.resize(busIdWidth)

    when(sendValid && !io.memReadReq.ready) {
        sendHold := True
        sendHoldIdx := sendIdx
    }
    when(sendValid && io.memReadReq.ready) {
        sendHold := False
        entryState(sendIdx) := U(ST_MISS_WAIT, 2 bits)
    }

    // ---------------- 内存读响应 ----------------
    io.memReadResp.ready := True
    when(io.memReadResp.valid) {
        val rid = io.memReadResp.payload.id(mshrIdWidth - 1 downto 0)
        when(entryState(rid) === U(ST_MISS_WAIT, 2 bits)) {
            entryFillData(rid) := io.memReadResp.payload.rData
            entryState(rid) := U(ST_FILL, 2 bits)
            entryFillDone(rid) := False
            entryReplayCnt(rid) := U(0, replayCntWidth bits)
        }
    }

    // ---------------- 分配 / 合并 ----------------
    when(io.alloc.en && io.hasFree) {
        val e = io.freeEntry
        val base = slotIdxDyn(e, 0)
        entryValid(e) := True
        entryTag(e) := io.alloc.tag
        entryIndex(e) := io.alloc.index
        entryWay(e) := io.alloc.way
        entryState(e) := U(ST_SEND, 2 bits)
        entryFillDone(e) := False
        entryReplayCnt(e) := U(0, replayCntWidth bits)
        entryValidCnt(e) := U(1, pendingCntWidth bits)
        entryHasWrite(e) := io.alloc.isWrite
        entryWbSlot(e) := io.alloc.wbSlot
        entryHasWb(e) := io.alloc.hasWb

        slotValid(base) := True
        slotIsWrite(base) := io.alloc.isWrite
        slotWData(base) := io.alloc.wData
        slotWordOff(base) := io.alloc.wordOff
        slotRespId(base) := io.alloc.respId
    }

    private val mergeFree = Vec((0 until P).map(s => !slotValid(slotIdxDyn(io.merge.entry, s))))
    private val mergeHasFree = mergeFree.orR
    private val mergeSlot = priorityLowest(mergeFree, slotOneWidth)

    when(io.merge.en && mergeHasFree) {
        val k = slotIdxDyn(io.merge.entry, mergeSlot)
        slotValid(k) := True
        slotIsWrite(k) := io.merge.isWrite
        slotWData(k) := io.merge.wData
        slotWordOff(k) := io.merge.wordOff
        slotRespId(k) := io.merge.respId

        entryValidCnt(io.merge.entry) := (entryValidCnt(io.merge.entry) + 1).resize(pendingCntWidth)
        entryHasWrite(io.merge.entry) := entryHasWrite(io.merge.entry) || io.merge.isWrite
    }

    // ---------------- 合并后的整行数据 ----------------
    private def mergedLine(e: Int): Bits = {
        val words = Vec(Bits(DATA_WIDTH bits), wordsPerBlock)
        for (w <- 0 until wordsPerBlock) {
            var acc: Bits = entryFillData(e)(w * DATA_WIDTH, DATA_WIDTH bits)
            for (s <- 0 until P) {
                val k = e * P + s
                acc = Mux(
                    slotValid(k) && slotIsWrite(k) && slotWordOff(k) === U(w, wordOffWidth bits),
                    slotWData(k),
                    acc
                )
            }
            words(w) := acc
        }
        Cat(words)
    }

    private val mergedLines = Vec((0 until N).map(e => mergedLine(e)))

    // ---------------- 填充（W2） ----------------
    private val fillCand = Vec((0 until N).map { e =>
        entryValid(e) && entryState(e) === U(ST_FILL, 2 bits) && !entryFillDone(e)
    })
    private val fillEn = fillCand.orR
    private val fillIdx = priorityLowest(fillCand, mshrIdWidth)

    io.fill.en := fillEn
    io.fill.index := entryIndex(fillIdx)
    io.fill.way := entryWay(fillIdx)
    io.fill.tag := entryTag(fillIdx)
    io.fill.dirty := entryHasWrite(fillIdx)
    io.fill.line := mergedLines(fillIdx)

    when(fillEn && io.fillReady) {
        entryFillDone(fillIdx) := True
    }

    // ---------------- 重放（条目级轮询） ----------------
    private val rrPtr = Reg(UInt(mshrIdWidth bits)) init 0

    private val replayCand = Vec((0 until N).map { e =>
        entryValid(e) && entryState(e) === U(ST_FILL, 2 bits) && entryFillDone(e) &&
            entryReplayCnt(e).resize(pendingCntWidth) < entryValidCnt(e)
    })

    private val rotCand = Vec(Bool(), N)
    for (k <- 0 until N) {
        val idx = (rrPtr + U(k, mshrIdWidth bits)).resize(mshrIdWidth)
        rotCand(k) := replayCand(idx)
    }
    private val replayValid = rotCand.orR
    private val rotK = priorityLowest(rotCand, mshrIdWidth)
    private val replayIdx = (rrPtr + rotK).resize(mshrIdWidth)

    private val replaySlotCnt = entryReplayCnt(replayIdx)
    private val replaySlotAddr = slotIdxDyn(replayIdx, replaySlotCnt.resize(slotSelWidth))

    // 每个 Slot 的重放读数据：fillData + 该 Slot 之前的同字写
    private val slotRData = Vec(Bits(DATA_WIDTH bits), slotCnt)
    for (e <- 0 until N) {
        for (s <- 0 until P) {
            val k = e * P + s
            val wo = slotWordOff(k)
            val fillWord = Vec((0 until wordsPerBlock).map(w => entryFillData(e)(w * DATA_WIDTH, DATA_WIDTH bits)))(wo)
            var acc: Bits = fillWord
            for (j <- 0 until s) {
                val jk = e * P + j
                acc = Mux(
                    slotValid(jk) && slotIsWrite(jk) && slotWordOff(jk) === wo,
                    slotWData(jk),
                    acc
                )
            }
            slotRData(k) := acc
        }
    }

    io.replay.valid := replayValid
    io.replay.payload.rData := slotRData(replaySlotAddr)
    io.replay.payload.id := slotRespId(replaySlotAddr)
    io.replay.payload.isWrite := slotIsWrite(replaySlotAddr)

    when(replayValid && io.replay.ready) {
        val isLast = (replaySlotCnt.resize(pendingCntWidth) + 1) === entryValidCnt(replayIdx)
        when(isLast) {
            entryValid(replayIdx) := False
            entryState(replayIdx) := U(ST_IDLE, 2 bits)
            entryFillDone(replayIdx) := False
            entryValidCnt(replayIdx) := U(0, pendingCntWidth bits)
            entryReplayCnt(replayIdx) := U(0, replayCntWidth bits)
            entryHasWrite(replayIdx) := False
            entryHasWb(replayIdx) := False
            for (k <- 0 until slotCnt) {
                when(U(k / P, mshrIdWidth bits) === replayIdx) {
                    slotValid(k) := False
                }
            }
        } otherwise {
            entryReplayCnt(replayIdx) := (replaySlotCnt + 1).resize(replayCntWidth)
        }
        rrPtr := (replayIdx + 1).resize(mshrIdWidth)
    }

    // ---------------- Way Lock ----------------
    for (s <- 0 until NUM_SETS) {
        for (w <- 0 until NUM_WAYS) {
            val locked = Vec((0 until N).map { e =>
                entryValid(e) &&
                    entryIndex(e) === U(s, indexWidth bits) &&
                    entryWay(e) === U(w, wayWidth bits)
            })
            io.lockMask(s)(w) := locked.orR
        }
    }
}
