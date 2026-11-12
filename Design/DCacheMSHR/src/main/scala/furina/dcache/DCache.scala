// ============================================================
// 文件名   : DCache.scala
// 描述     : 带 MSHR 的非阻塞数据 Cache 顶层
// 文档依据 : 《Cache 架构设计文档 v2》§6、§9、§10、§11
//
// 两级流水：
//   Stage1：接收、地址分解、驱动 R1、并行准入检查 -> cpuReady
//   Stage2：命中判断 / 合并 / 淘汰分配 / Stage2 冻结
//
// 反压与冻结严格按 §11.1 / §11.2；响应队列任一满即反压（§9.3）。
// ============================================================

package furina.dcache

import spinal.core._
import spinal.lib._

class DCache(
    cfg: CacheConfig,
    makePolicy: CacheConfig => ReplacePolicy
) extends Component {
    import cfg._

    val io = new Bundle {
        val cpu = slave(Stream(CpuReq(cfg)))
        val cpuReadResp = master(Stream(CpuReadResp(cfg)))
        val cpuWriteResp = master(Stream(CpuWriteResp(cfg)))

        val memReadReq = master(Stream(MemReadReq(cfg)))
        val memWriteReq = master(Stream(MemWriteReq(cfg)))
        val memReadResp = slave(Stream(MemReadResp(cfg)))
        val memWriteResp = slave(Stream(MemWriteResp(cfg)))
    }
    noIoPrefix()

    // ---------------- 子模块 ----------------
    val cache = new CacheMem(cfg)
    val mshr = new Mshr(cfg)
    val wbb = new WriteBackBuffer(cfg)
    val policy = makePolicy(cfg)

    val rdFifo = StreamFifo(CpuReadResp(cfg), RESP_QUEUE_DEPTH)
    val wrFifo = StreamFifo(CpuWriteResp(cfg), RESP_QUEUE_DEPTH)

    io.cpuReadResp << rdFifo.io.pop
    io.cpuWriteResp << wrFifo.io.pop
    io.memReadReq << mshr.io.memReadReq
    io.memWriteReq << wbb.io.send

    // 从端流：显式连接，避免方向歧义
    mshr.io.memReadResp.valid := io.memReadResp.valid
    mshr.io.memReadResp.payload := io.memReadResp.payload
    io.memReadResp.ready := mshr.io.memReadResp.ready

    wbb.io.memWriteResp.valid := io.memWriteResp.valid
    wbb.io.memWriteResp.payload := io.memWriteResp.payload
    io.memWriteResp.ready := wbb.io.memWriteResp.ready

    mshr.io.fillReady := True

    // ---------------- Stage2 流水寄存器 ----------------
    val s1Valid = Reg(Bool()) init False
    val s1Tag = Reg(UInt(tagWidth bits)) init 0
    val s1Index = Reg(UInt(indexWidth bits)) init 0
    val s1WordOff = Reg(UInt(wordOffWidth bits)) init 0
    val s1BlockAddr = Reg(UInt(ADDR_WIDTH bits)) init 0
    val s1WrEn = Reg(Bool()) init False
    val s1WData = Reg(Bits(DATA_WIDTH bits)) init 0
    val s1Id = Reg(UInt(ID_WIDTH bits)) init 0

    // ---------------- 小工具 ----------------
    def priorityLowest(vec: Seq[Bool], width: Int): UInt = {
        val res = UInt(width bits)
        res := U(0, width bits)
        for (i <- (vec.length - 1) to 0 by -1) {
            when(vec(i)) { res := U(i, width bits) }
        }
        res
    }

    // ---------------- CPU 地址分解（Stage1） ----------------
    val cpuTag = tagOf(io.cpu.payload.addr)
    val cpuIndex = indexOf(io.cpu.payload.addr)
    val cpuWordOff = wordOffOf(io.cpu.payload.addr)
    val cpuBlockAddr = blockAddrOf(io.cpu.payload.addr)

    // ---------------- Stage1 并行检查（§11.1） ----------------
    mshr.io.q0.tag := cpuTag
    mshr.io.q0.index := cpuIndex
    wbb.io.q0Addr := cpuBlockAddr

    val lock0 = Vec((0 until NUM_WAYS).map(w => mshr.io.lockMask(cpuIndex)(w)))
    val hasWay0 = !lock0.andR

    val canMerge0 = mshr.io.m0.mergeable && mshr.io.m0.slotFree
    val hitMshr0 = mshr.io.m0.hit
    val missPath0 = !hitMshr0 && mshr.io.hasFree && !wbb.io.full && !wbb.io.q0Same && hasWay0
    val respFullAny = !rdFifo.io.push.ready || !wrFifo.io.push.ready
    val cpuReadyComb = !respFullAny && (canMerge0 || missPath0)

    // ---------------- Stage2 命中判断（§6.3） ----------------
    mshr.io.q1.tag := s1Tag
    mshr.io.q1.index := s1Index
    wbb.io.q1Addr := s1BlockAddr
    cache.io.inspect.index := s1Index

    val lock1 = Vec((0 until NUM_WAYS).map(w => mshr.io.lockMask(s1Index)(w)))
    val hitVec = Vec((0 until NUM_WAYS).map { w =>
        cache.io.r1.valid(w) && (cache.io.r1.tag(w) === s1Tag) && !lock1(w)
    })
    val hit = hitVec.orR
    val hitWay = priorityLowest(hitVec, wayWidth)

    // ---------------- victim 选择（§10.4） ----------------
    // 优先 "valid=0 且未锁"；否则由策略在其自身偏好序中剔除锁定路后给出候选。
    val curValid = Vec((0 until NUM_WAYS).map(w => cache.io.inspect.valid(w)))
    val curDirty = Vec((0 until NUM_WAYS).map(w => cache.io.inspect.dirty(w)))

    val emptyVec = Vec((0 until NUM_WAYS).map(w => !curValid(w) && !lock1(w)))
    val hasEmpty = emptyVec.orR
    val emptyWay = priorityLowest(emptyVec, wayWidth)

    // 策略内部先剔除被锁定的路，再按自己的顺序取最靠前者（§10.4）
    val policyWay = policy.allocWay(s1Index, lock1)
    val hasRot = !lock1.andR

    val hasVictim = hasEmpty || hasRot
    val victimWay = Mux(hasEmpty, emptyWay, policyWay)
    val victimTag = cache.io.r1.tag(victimWay)
    val victimBlockAddr = blockAddrFromTagIndex(victimTag, s1Index)
    // 只有"有效且脏"的行才需要写回；无效行的 dirty 可能是历史残留
    val victimDirty = curValid(victimWay) && curDirty(victimWay)
    val evictDirty = hasVictim && victimDirty

    // ---------------- Stage2 冻结条件（§11.2） ----------------
    val canMerge1 = mshr.io.m1.mergeable && mshr.io.m1.slotFree
    val hitMshr1 = mshr.io.m1.hit
    val needEvict = !hit && !hitMshr1
    val reserveFail = needEvict && evictDirty && !wbb.io.reserveOk

    val s2StuckCond =
        respFullAny ||
            (!hit && hitMshr1 && !canMerge1) ||
            (needEvict && (!mshr.io.hasFree || !hasVictim)) ||
            (!hit && wbb.io.q1Same) ||
            reserveFail

    val s2Stuck = s1Valid && s2StuckCond
    val commit = s1Valid && !s2Stuck

    io.cpu.ready := !s2Stuck && cpuReadyComb
    val accept = io.cpu.valid && io.cpu.ready

    // ---------------- 读通道 R1（冻结期间保持刷新，§6.8） ----------------
    cache.io.r1.en := accept || s2Stuck
    cache.io.r1.index := Mux(s2Stuck, s1Index, cpuIndex)
    cache.io.r1.wordOff := Mux(s2Stuck, s1WordOff, cpuWordOff)

    // ---------------- Stage2 提交动作 ----------------
    val hitRead = commit && hit && !s1WrEn
    val hitWrite = commit && hit && s1WrEn
    val doMerge = commit && !hit && hitMshr1 && canMerge1
    val doAlloc = commit && needEvict && mshr.io.hasFree && hasVictim &&
        !(evictDirty && !wbb.io.reserveOk)

    // ---- 命中写（W1） ----
    cache.io.w1.en := hitWrite
    cache.io.w1.index := s1Index
    cache.io.w1.way := hitWay
    cache.io.w1.wordOff := s1WordOff
    cache.io.w1.data := s1WData

    // ---- 淘汰原子组（清 valid / R2 / WBB 预留 / MSHR 分配 / Way Lock） ----
    cache.io.clr.en := doAlloc
    cache.io.clr.index := s1Index
    cache.io.clr.way := victimWay

    cache.io.r2.en := doAlloc && evictDirty
    cache.io.r2.index := s1Index
    cache.io.r2.way := victimWay

    wbb.io.reserve.en := doAlloc && evictDirty
    wbb.io.reserve.addr := victimBlockAddr

    mshr.io.alloc.en := doAlloc
    mshr.io.alloc.tag := s1Tag
    mshr.io.alloc.index := s1Index
    mshr.io.alloc.way := victimWay
    mshr.io.alloc.isWrite := s1WrEn
    mshr.io.alloc.wData := s1WData
    mshr.io.alloc.wordOff := s1WordOff
    mshr.io.alloc.respId := s1Id
    mshr.io.alloc.wbSlot := wbb.io.reserveSlot
    mshr.io.alloc.hasWb := evictDirty

    // ---- 合并 ----
    mshr.io.merge.en := doMerge
    mshr.io.merge.entry := mshr.io.m1.entry
    mshr.io.merge.isWrite := s1WrEn
    mshr.io.merge.wData := s1WData
    mshr.io.merge.wordOff := s1WordOff
    mshr.io.merge.respId := s1Id

    // ---- 替换策略 ----
    policy.onHit(s1Index, hitWay, commit && hit)
    policy.onFill(mshr.io.fill.index, mshr.io.fill.way, mshr.io.fill.en && mshr.io.fillReady)

    // ---- 填充写（W2） ----
    cache.io.w2.en := mshr.io.fill.en && mshr.io.fillReady
    cache.io.w2.index := mshr.io.fill.index
    cache.io.w2.way := mshr.io.fill.way
    cache.io.w2.tag := mshr.io.fill.tag
    cache.io.w2.dirty := mshr.io.fill.dirty
    cache.io.w2.line := mshr.io.fill.line

    // ---- victim 整行 -> WBB push（预留的下一拍） ----
    val pushPend = Reg(Bool()) init False
    val pushSlot = Reg(UInt(wbbIdWidth bits)) init 0
    when(doAlloc && evictDirty) {
        pushPend := True
        pushSlot := wbb.io.reserveSlot
    } elsewhen (pushPend) {
        pushPend := False
    }
    wbb.io.push.en := pushPend
    wbb.io.push.slot := pushSlot
    wbb.io.push.line := cache.io.r2.line

    // ---------------- 写后读旁路（§6.6） ----------------
    val p1Valid = Reg(Bool()) init False
    val p1Tag = Reg(UInt(tagWidth bits)) init 0
    val p1Index = Reg(UInt(indexWidth bits)) init 0
    val p1Way = Reg(UInt(wayWidth bits)) init 0
    val p1WordOff = Reg(UInt(wordOffWidth bits)) init 0
    val p1Data = Reg(Bits(DATA_WIDTH bits)) init 0

    when(hitWrite) {
        p1Valid := True
        p1Tag := s1Tag
        p1Index := s1Index
        p1Way := hitWay
        p1WordOff := s1WordOff
        p1Data := s1WData
    } elsewhen (!s2Stuck) {
        p1Valid := False
    }

    val bypass = hitRead && p1Valid &&
        (p1Tag === s1Tag) && (p1Index === s1Index) &&
        (p1Way === hitWay) && (p1WordOff === s1WordOff)
    val hitReadData = Mux(bypass, p1Data, cache.io.r1.data(hitWay))

    // ---------------- 响应队列（§9.3，命中优先） ----------------
    val replay = mshr.io.replay
    val replayIsWrite = replay.payload.isWrite
    val replayReadFire = replay.valid && !replayIsWrite && rdFifo.io.push.ready && !hitRead
    val replayWriteFire = replay.valid && replayIsWrite && wrFifo.io.push.ready && !hitWrite
    replay.ready := Mux(replayIsWrite, wrFifo.io.push.ready && !hitWrite, rdFifo.io.push.ready && !hitRead)

    rdFifo.io.push.valid := hitRead || replayReadFire
    rdFifo.io.push.payload.rData := Mux(hitRead, hitReadData, replay.payload.rData)
    rdFifo.io.push.payload.id := Mux(hitRead, s1Id, replay.payload.id)

    wrFifo.io.push.valid := hitWrite || replayWriteFire
    wrFifo.io.push.payload.id := Mux(hitWrite, s1Id, replay.payload.id)

    // ---------------- 流水寄存器更新 ----------------
    when(accept) {
        s1Valid := True
        s1Tag := cpuTag
        s1Index := cpuIndex
        s1WordOff := cpuWordOff
        s1BlockAddr := cpuBlockAddr
        s1WrEn := io.cpu.payload.wrEn
        s1WData := io.cpu.payload.wData
        s1Id := io.cpu.payload.id
    } elsewhen (s1Valid && !s2Stuck) {
        s1Valid := False
    }
}
