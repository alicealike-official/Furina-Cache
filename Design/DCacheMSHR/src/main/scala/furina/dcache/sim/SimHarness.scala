// ============================================================
// 文件名   : SimHarness.scala
// 描述     : 仿真驱动与独立 scoreboard（不依赖任何参考模型）
//
// 维护两套存储：
//   arch : 架构可见内存（按程序顺序在请求被接收时更新）
//   back : Cache 看到的后端内存（在内存写握手时更新、填充读时读取）
// 读响应按 ID 与"发请求时的架构值"比对。
// ============================================================

package furina.dcache.sim

import spinal.core._
import spinal.core.sim._
import furina.dcache._

import scala.collection.mutable

case class CpuOp(addr: Long, wr: Boolean, data: BigInt, id: Int)

class SimHarness(
    dut: DCache,
    val cfg: CacheConfig,
    seed: Int = 1,
    var memLatency: Int = 3,
    var memJitter: Int = 2,
    var memReadyProb: Double = 1.0,
    var respReadyProb: Double = 1.0
) {
    import cfg._

    private val rnd = new scala.util.Random(seed)
    private val memWords = 1 << 16
    private val arch = Array.fill[Int](memWords)(0)
    private val back = Array.fill[Int](memWords)(0)

    private val idCount = 1 << ID_WIDTH
    private val freeIds = mutable.Queue[Int](rnd.shuffle((0 until idCount).toList): _*)
    private val reserved = mutable.Set[Int]()
    private val expectedRead = mutable.Map[Int, Int]()
    private val opIsWrite = mutable.Map[Int, Boolean]()

    private val cpuQueue = mutable.Queue[CpuOp]()
    private var cpuPending: Option[CpuOp] = None

    // 随机流量
    var autoTraffic = false
    var autoLineCount = 128
    var autoMaxOutstanding = 10

    // 内存模型
    private case class Pend(deliverAt: Long, id: Int, line: Seq[Int])
    private val pendingResp = mutable.ArrayBuffer[Pend]()
    private var respInFlight: Option[Pend] = None

    private val pendingWriteResp = mutable.ArrayBuffer[(Long, Int)]()
    private var writeRespInFlight: Option[(Long, Int)] = None
    var writeRespCountMem = 0

    var cycle: Long = 0
    var readRespCount = 0
    var writeRespCount = 0
    val readOrder = mutable.ArrayBuffer[(Int, Long)]()
    val seenWriteback = mutable.ArrayBuffer[(Long, Seq[Int])]()
    val memReadCnt = mutable.Map[Long, Int]().withDefaultValue(0)
    val memWriteCnt = mutable.Map[Long, Int]().withDefaultValue(0)

    // ---------------- 地址辅助 ----------------
    private def wordIdx(addr: Long): Int = ((addr >> 2) & (memWords - 1)).toInt
    private def lineBase(blockAddr: Long): Int = ((blockAddr >> 2) & (memWords - 1)).toInt
    private def readLine(blockAddr: Long): Seq[Int] = {
        val b = lineBase(blockAddr)
        (0 until wordsPerBlock).map(w => back(b + w))
    }
    private def writeLine(blockAddr: Long, line: Seq[Int]): Unit = {
        val b = lineBase(blockAddr)
        for (w <- 0 until wordsPerBlock) back(b + w) = line(w)
    }
    private def lineToBigInt(line: Seq[Int]): BigInt = {
        var acc = BigInt(0)
        for (w <- 0 until line.length) {
            acc = acc | ((BigInt(line(w).toLong & 0xffffffffL)) << (32 * w))
        }
        acc
    }

    private def hex(v: Long): String = f"0x$v%08x"

    def archWord(addr: Long): Int = arch(wordIdx(addr))
    def backWord(addr: Long): Int = back(wordIdx(addr))
    def memReadCount(lineAddr: Long): Int = memReadCnt(lineAddr & ~((1L << offsetWidth) - 1))
    def memWriteCount(lineAddr: Long): Int = memWriteCnt(lineAddr & ~((1L << offsetWidth) - 1))
    def writebackLine(lineAddr: Long): Option[Seq[Int]] = {
        val a = lineAddr & ~((1L << offsetWidth) - 1)
        seenWriteback.reverse.find(_._1 == a).map(_._2)
    }

    // ---------------- 请求入队 ----------------
    def send(addr: Long, wr: Boolean, data: BigInt = BigInt(0)): Int = {
        require(freeIds.nonEmpty, "CPU 请求 ID 已耗尽")
        val id = freeIds.dequeue()
        reserved += id
        val mask = BigInt(0xffffffffL)
        cpuQueue.enqueue(CpuOp(addr & 0xffffffffL, wr, data & mask, id))
        id
    }

    private def genRandomRequest(): Unit = {
        val line = rnd.nextInt(autoLineCount)
        val word = rnd.nextInt(wordsPerBlock)
        val addr = line.toLong * BLOCK_SIZE + word.toLong * (DATA_WIDTH / 8)
        val wr = rnd.nextBoolean()
        val data = BigInt(rnd.nextInt().toLong & 0xffffffffL)
        send(addr, wr, data)
    }

    private def maskWord(v: BigInt): BigInt = v & BigInt(0xffffffffL)

    // ---------------- 单拍驱动 ----------------
    def tick(): Unit = {
        // 1) CPU 请求
        if (cpuPending.isEmpty) {
            if (cpuQueue.nonEmpty) cpuPending = Some(cpuQueue.dequeue())
            else if (autoTraffic && reserved.size < autoMaxOutstanding && freeIds.nonEmpty) {
                // 直接在队列里生成，下一拍取
                genRandomRequest()
            }
        }
        cpuPending match {
            case Some(r) =>
                dut.io.cpu.valid #= true
                dut.io.cpu.payload.addr #= r.addr
                dut.io.cpu.payload.wrEn #= r.wr
                dut.io.cpu.payload.wData #= r.data
                dut.io.cpu.payload.id #= r.id
            case None =>
                dut.io.cpu.valid #= false
                dut.io.cpu.payload.addr #= 0
                dut.io.cpu.payload.wrEn #= false
                dut.io.cpu.payload.wData #= 0
                dut.io.cpu.payload.id #= 0
        }

        // 2) 反压
        dut.io.memReadReq.ready #= (rnd.nextDouble() < memReadyProb)
        dut.io.memWriteReq.ready #= (rnd.nextDouble() < memReadyProb)
        dut.io.cpuReadResp.ready #= (rnd.nextDouble() < respReadyProb)
        dut.io.cpuWriteResp.ready #= (rnd.nextDouble() < respReadyProb)

        // 3) 内存读响应（可乱序：按各自完成时刻取最早者）
        if (respInFlight.isEmpty) {
            val readyNow = pendingResp.filter(_.deliverAt <= cycle)
            if (readyNow.nonEmpty) {
                val p = readyNow.minBy(_.deliverAt)
                pendingResp -= p
                respInFlight = Some(p)
            }
        }
        respInFlight match {
            case Some(p) =>
                dut.io.memReadResp.valid #= true
                dut.io.memReadResp.payload.id #= p.id
                dut.io.memReadResp.payload.rData #= lineToBigInt(p.line)
            case None =>
                dut.io.memReadResp.valid #= false
                dut.io.memReadResp.payload.id #= 0
                dut.io.memReadResp.payload.rData #= 0
        }

        // 3b) 内存写响应（延迟返回）
        if (writeRespInFlight.isEmpty) {
            val due = pendingWriteResp.filter(_._1 <= cycle)
            if (due.nonEmpty) {
                val p = due.minBy(_._1)
                pendingWriteResp -= p
                writeRespInFlight = Some(p)
            }
        }
        writeRespInFlight match {
            case Some(p) =>
                dut.io.memWriteResp.valid #= true
                dut.io.memWriteResp.payload.id #= p._2
            case None =>
                dut.io.memWriteResp.valid #= false
                dut.io.memWriteResp.payload.id #= 0
        }

        sleep(1)

        // 4) CPU 请求握手
        if (dut.io.cpu.valid.toBoolean && dut.io.cpu.ready.toBoolean) {
            val r = cpuPending.get
            if (r.wr) {
                arch(wordIdx(r.addr)) = (r.data & 0xffffffffL).toInt
                opIsWrite(r.id) = true
            } else {
                expectedRead(r.id) = arch(wordIdx(r.addr))
                opIsWrite(r.id) = false
            }
            cpuPending = None
        }

        // 5) 内存读请求握手：在握手时刻取数，延迟后返回
        if (dut.io.memReadReq.valid.toBoolean && dut.io.memReadReq.ready.toBoolean) {
            val blockAddr = dut.io.memReadReq.payload.addr.toBigInt.toLong & ~((1L << offsetWidth) - 1)
            val id = dut.io.memReadReq.payload.id.toBigInt.toInt
            memReadCnt(blockAddr) = memReadCnt(blockAddr) + 1
            val delay = memLatency + (if (memJitter > 0) rnd.nextInt(memJitter + 1) else 0)
            pendingResp += Pend(cycle + delay, id, readLine(blockAddr))
        }

        // 6) 内存写请求握手：更新后端内存
        if (dut.io.memWriteReq.valid.toBoolean && dut.io.memWriteReq.ready.toBoolean) {
            val addr = dut.io.memWriteReq.payload.addr.toBigInt.toLong & ~((1L << offsetWidth) - 1)
            val data = dut.io.memWriteReq.payload.wData.toBigInt
            val line = (0 until wordsPerBlock).map { w =>
                ((data >> (32 * w)) & BigInt(0xffffffffL)).toInt
            }
            writeLine(addr, line)
            seenWriteback += ((addr, line))
            memWriteCnt(addr) = memWriteCnt(addr) + 1
            val wid = dut.io.memWriteReq.payload.id.toBigInt.toInt
            pendingWriteResp += ((cycle + memLatency, wid))
        }

        // 7) 内存读响应握手
        if (dut.io.memReadResp.valid.toBoolean && dut.io.memReadResp.ready.toBoolean) {
            respInFlight = None
        }

        // 7b) 内存写响应握手
        if (dut.io.memWriteResp.valid.toBoolean && dut.io.memWriteResp.ready.toBoolean) {
            writeRespInFlight = None
            writeRespCountMem += 1
        }

        // 8) CPU 读响应
        if (dut.io.cpuReadResp.valid.toBoolean && dut.io.cpuReadResp.ready.toBoolean) {
            val id = dut.io.cpuReadResp.payload.id.toBigInt.toInt
            val data = dut.io.cpuReadResp.payload.rData.toBigInt
            require(reserved.contains(id), s"读到未知 ID $id")
            require(opIsWrite.getOrElse(id, true) == false, s"ID $id 的类型不匹配（应为读）")
            val exp = expectedRead(id)
            val got = (data & 0xffffffffL).toInt
            require(got == exp, f"读数据错误 id=$id addr? got=0x$got%08x exp=0x$exp%08x")
            readRespCount += 1
            readOrder += ((id, cycle))
            reserved -= id
            expectedRead -= id
            opIsWrite -= id
            freeIds.enqueue(id)
        }

        // 9) CPU 写响应
        if (dut.io.cpuWriteResp.valid.toBoolean && dut.io.cpuWriteResp.ready.toBoolean) {
            val id = dut.io.cpuWriteResp.payload.id.toBigInt.toInt
            require(reserved.contains(id), s"写响应未知 ID $id")
            require(opIsWrite.getOrElse(id, false) == true, s"ID $id 的类型不匹配（应为写）")
            writeRespCount += 1
            reserved -= id
            opIsWrite -= id
            freeIds.enqueue(id)
        }

        cycle += 1
        dut.clockDomain.waitSampling()
    }

    // ---------------- 等待辅助 ----------------
    def waitUntil(cond: => Boolean, maxCycles: Int, what: String): Unit = {
        var n = 0
        while (!cond) {
            tick()
            n += 1
            if (n > maxCycles) sys.error(s"等待超时：$what（已等待 $n 拍）")
        }
    }

    def waitIds(ids: Seq[Int], maxCycles: Int = 4000): Unit =
        waitUntil(ids.forall(id => !reserved.contains(id)), maxCycles, s"响应 $ids")

    def waitAllIdle(maxCycles: Int = 20000): Unit =
        waitUntil(
            reserved.isEmpty && cpuQueue.isEmpty && cpuPending.isEmpty &&
                respInFlight.isEmpty && pendingResp.isEmpty &&
                writeRespInFlight.isEmpty && pendingWriteResp.isEmpty,
            maxCycles,
            "所有请求完成"
        )

    def waitForWriteback(lineAddr: Long, maxCycles: Int = 4000): Unit =
        waitUntil(writebackLine(lineAddr).isDefined, maxCycles, s"写回 0x${lineAddr.toHexString}")

    def runCycles(n: Int): Unit = for (_ <- 0 until n) tick()
}
