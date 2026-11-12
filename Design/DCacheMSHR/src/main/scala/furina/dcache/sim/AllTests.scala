// ============================================================
// 文件名   : AllTests.scala
// 描述     : 定向 + 随机 scoreboard 验证
// 运行     : sbt "runMain furina.dcache.sim.AllTests"
//
// 不依赖任何参考模型：读数据用"发请求时的架构影子内存"比对，
// 写回完整性用后端内存与架构内存间接比对。
// ============================================================

package furina.dcache.sim

import spinal.core._
import spinal.core.sim._
import furina.dcache._

object AllTests extends App {

    val cfg = CacheConfig()

    private val policies: Seq[(String, CacheConfig => ReplacePolicy)] = Seq(
        ("FIFO", FifoPolicyFactory),
        ("LRU", LruPolicyFactory),
        ("PLRU", PlruPolicyFactory)
    )

    def withHarness(dut: DCache, seed: Int)(body: SimHarness => Unit): Unit = {
        dut.clockDomain.forkStimulus(10)
        dut.io.cpu.valid #= false
        dut.io.memReadResp.valid #= false
        dut.io.memWriteResp.valid #= false
        dut.io.memReadReq.ready #= false
        dut.io.memWriteReq.ready #= false
        dut.io.cpuReadResp.ready #= false
        dut.io.cpuWriteResp.ready #= false
        dut.clockDomain.waitSampling(10)
        body(new SimHarness(dut, cfg, seed))
    }

    private def hex(v: Long): String = f"0x$v%08x"

    // ------------------------------------------------------------
    // 1. 基本命中读写
    // ------------------------------------------------------------
    def testBasic(h: SimHarness): Unit = {
        h.memLatency = 2
        h.memJitter = 2
        h.memReadyProb = 1.0
        h.respReadyProb = 1.0

        val r0 = h.send(0x000L, wr = false)
        h.waitIds(Seq(r0))
        require(h.archWord(0x000L) == 0, "复位后应为 0")
        require(h.memReadCount(0x000L) == 1, "首次读应产生一次整行读")

        val w0 = h.send(0x004L, wr = true, BigInt(0x11112222L))
        h.waitIds(Seq(w0))
        val r1 = h.send(0x004L, wr = false)
        h.waitIds(Seq(r1))
        require(h.archWord(0x004L) == 0x11112222, "写命中数据应可读回")

        val r2 = h.send(0x000L, wr = false)
        h.waitIds(Seq(r2))
        require(h.memReadCount(0x000L) == 1, "第二次读应命中，不应再访问内存")

        // 写后读旁路（§6.6）：写命中后紧接着读同一字
        val w1 = h.send(0x008L, wr = true, BigInt(0xA5A50001L))
        val r3 = h.send(0x008L, wr = false)
        h.waitIds(Seq(w1, r3))
        require(h.archWord(0x008L) == 0xA5A50001, "写后读旁路数据错误")

        h.waitAllIdle()
        println(f"[PASS] basic hit/miss/write  cycle=${h.cycle}")
    }

    // ------------------------------------------------------------
    // 2. 同一冷行合并 + 重放旁路
    // ------------------------------------------------------------
    def testMissMerge(h: SimHarness): Unit = {
        h.memLatency = 12
        h.memJitter = 0
        h.memReadyProb = 1.0
        h.respReadyProb = 1.0

        val base = 0x400L // 行对齐，index=16
        val a = BigInt(0xAAAA0001L)
        val b = BigInt(0xBBBB0002L)

        val iw1 = h.send(base, wr = true, a)
        val ir1 = h.send(base, wr = false)
        val iw2 = h.send(base, wr = true, b)
        val ir2 = h.send(base, wr = false)

        h.waitIds(Seq(iw1, ir1, iw2, ir2))
        h.waitAllIdle()

        require(h.memReadCount(base) == 1,
            s"同一行的 4 个请求应只发 1 次内存读，实际 ${h.memReadCount(base)}")
        require(h.memWriteCount(base) == 0, "不应发生写回")
        println(f"[PASS] miss merge & replay bypass  cycle=${h.cycle}")
    }

    // ------------------------------------------------------------
    // 3. 脏行淘汰写回
    // ------------------------------------------------------------
    def testDirtyEviction(h: SimHarness): Unit = {
        h.memLatency = 2
        h.memJitter = 0
        h.memReadyProb = 1.0
        h.respReadyProb = 1.0

        // 同一个 set（index=0）的 5 条不同 tag 行
        val lines = Seq(0x0000L, 0x0800L, 0x1000L, 0x1800L, 0x2000L)
        val values = Seq(0x11110001L, 0x22220002L, 0x33330003L, 0x44440004L)

        for (i <- 0 until 4) {
            val id = h.send(lines(i), wr = true, BigInt(values(i)))
            h.waitIds(Seq(id))
        }
        // 淘汰前先读回，确认填充/合并数据正确
        for (i <- 0 until 4) {
            val id = h.send(lines(i), wr = false)
            h.waitIds(Seq(id))
        }

        // 第 5 行触发淘汰；FIFO 队头为第一条行
        val id4 = h.send(lines(4), wr = false)
        h.waitIds(Seq(id4))

        // 立刻重新读取被淘汰的行：此时写回可能仍在途，
        // 同地址检查应让该请求等待写回完成后再填充（§8.7）
        val idr = h.send(lines(0), wr = false)
        h.waitIds(Seq(idr))
        h.waitForWriteback(lines(0))

        val wb = h.writebackLine(lines(0)).get
        require((wb(0).toLong & 0xffffffffL) == values(0),
            s"写回数据错误：${hex(wb(0).toLong & 0xffffffffL)} != ${hex(values(0))}")
        require(h.memWriteCount(lines(0)) == 1, "同一行应只写回一次")
        require(h.archWord(lines(0)) == (values(0) & 0xffffffffL).toInt, "写回后读回数据错误")

        h.waitAllIdle()
        println(f"[PASS] dirty eviction / writeback  cycle=${h.cycle}")
    }

    // ------------------------------------------------------------
    // 4. hit-under-miss
    // ------------------------------------------------------------
    def testHitUnderMiss(h: SimHarness): Unit = {
        h.memLatency = 15
        h.memJitter = 0
        h.memReadyProb = 1.0
        h.respReadyProb = 1.0

        // 预热 A
        val ida = h.send(0x000L, wr = false)
        h.waitIds(Seq(ida))

        // B 冷行（同 set，不同 tag），A 再读应命中并先返回
        val idb = h.send(0x0800L, wr = false)
        val ida2 = h.send(0x000L, wr = false)

        h.waitIds(Seq(ida2))
        val cycleA = h.readOrder.find(_._1 == ida2).get._2
        h.waitIds(Seq(idb))
        val cycleB = h.readOrder.find(_._1 == idb).get._2

        require(cycleA < cycleB, s"命中请求应先返回：A=$cycleA B=$cycleB")
        h.waitAllIdle()
        println(f"[PASS] hit-under-miss  (hit@$cycleA < miss@$cycleB)")
    }

    // ------------------------------------------------------------
    // 5. 反压（CPU 响应 / 内存就绪随机拉低）
    // ------------------------------------------------------------
    def testBackpressure(h: SimHarness): Unit = {
        h.memLatency = 3
        h.memJitter = 3
        h.memReadyProb = 0.55
        h.respReadyProb = 0.45
        h.autoLineCount = 64
        h.autoMaxOutstanding = 8
        h.autoTraffic = true

        h.runCycles(4000)
        h.autoTraffic = false
        h.memReadyProb = 1.0
        h.respReadyProb = 1.0
        h.waitAllIdle(20000)

        println(f"[PASS] backpressure  read=${h.readRespCount} write=${h.writeRespCount} cycle=${h.cycle}")
    }

    // ------------------------------------------------------------
    // 6. 随机 scoreboard
    // ------------------------------------------------------------
    def testRandom(h: SimHarness): Unit = {
        h.memLatency = 3
        h.memJitter = 3
        h.memReadyProb = 0.9
        h.respReadyProb = 0.9
        h.autoLineCount = 128
        h.autoMaxOutstanding = 10
        h.autoTraffic = true

        val target = 2000
        var guard = 0
        while (h.readRespCount + h.writeRespCount < target) {
            h.tick()
            guard += 1
            if (guard > 200000) sys.error("随机测试超时")
        }
        h.autoTraffic = false
        h.memReadyProb = 1.0
        h.respReadyProb = 1.0
        h.waitAllIdle(20000)

        println(f"[PASS] random  read=${h.readRespCount} write=${h.writeRespCount} cycle=${h.cycle}")
    }

    // ------------------------------------------------------------
    // 执行（可选参数：只跑某个用例名）
    // ------------------------------------------------------------
    val only = if (args.nonEmpty) args(0) else ""
    def want(name: String): Boolean = only.isEmpty || only == name

    for ((policyName, factory) <- policies) {
        println(s"================ policy = $policyName ================")
        val compiled = SimConfig
            .withVCS()
            .workspacePath("simWorkspace")
            .workspaceName(s"dcache_$policyName")
            .compile(new DCache(cfg, factory))

        if (want("basic")) compiled.doSim(s"${policyName}_basic") { dut =>
            withHarness(dut, seed = 11)(testBasic)
        }
        if (want("merge")) compiled.doSim(s"${policyName}_merge") { dut =>
            withHarness(dut, seed = 22)(testMissMerge)
        }
        if (want("evict")) compiled.doSim(s"${policyName}_evict") { dut =>
            withHarness(dut, seed = 33)(testDirtyEviction)
        }
        if (want("hum")) compiled.doSim(s"${policyName}_hum") { dut =>
            withHarness(dut, seed = 44)(testHitUnderMiss)
        }
        if (want("bp")) compiled.doSim(s"${policyName}_bp") { dut =>
            withHarness(dut, seed = 55)(testBackpressure)
        }
        if (want("random")) compiled.doSim(s"${policyName}_random") { dut =>
            withHarness(dut, seed = 66)(testRandom)
        }
    }

    println("ALL TESTS PASSED")
}
