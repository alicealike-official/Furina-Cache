// ============================================================
// 文件名   : PolicyTests.scala
// 描述     : 替换策略定向测试（不经过 CacheTop）
// 文档依据 : 《Cache 架构设计文档 v2》§10.3 / §10.4
//
// 目的：把两条最容易被实现"优化掉"的语义钉死——
//   1) 锁定路必须在**策略自身的偏好序**中被剔除（不是按 way 编号扫描）；
//   2) Tree-PLRU 的树位更新与回退规则。
//
// 运行：sbt "runMain furina.dcache.sim.PolicyTests"
// ============================================================

package furina.dcache.sim

import spinal.core._
import spinal.core.sim._
import furina.dcache._

/** 只例化一个策略，暴露 allocWay 与 onHit/onFill 的驱动口 */
class PolicyHarness(cfg: CacheConfig, mk: CacheConfig => ReplacePolicy) extends Component {
    import cfg._

    val io = new Bundle {
        val set     = in UInt (indexWidth bits)
        val lock    = in Vec (Bool(), NUM_WAYS)
        val fillEn  = in Bool()
        val fillWay = in UInt (wayWidth bits)
        val hitEn   = in Bool()
        val hitWay  = in UInt (wayWidth bits)
        val way     = out UInt (wayWidth bits)
    }

    val policy = mk(cfg)
    io.way := policy.allocWay(io.set, io.lock)
    policy.onFill(io.set, io.fillWay, io.fillEn)
    policy.onHit(io.set, io.hitWay, io.hitEn)
}

object PolicyTests extends App {

    val cfg = CacheConfig()
    import cfg._

    private def clearLock(dut: PolicyHarness): Unit =
        for (w <- 0 until NUM_WAYS) dut.io.lock(w) #= false

    private def alloc(dut: PolicyHarness): Int = {
        sleep(1)
        dut.io.way.toInt
    }

    /** 驱动一次填充（onFill 生效一拍） */
    private def fill(dut: PolicyHarness, way: Int): Unit = {
        dut.io.fillEn  #= true
        dut.io.fillWay #= way
        dut.clockDomain.waitSampling()
        dut.io.fillEn  #= false
        dut.clockDomain.waitSampling()
    }

    /** 驱动一次命中（onHit 生效一拍） */
    private def hit(dut: PolicyHarness, way: Int): Unit = {
        dut.io.hitEn  #= true
        dut.io.hitWay #= way
        dut.clockDomain.waitSampling()
        dut.io.hitEn  #= false
        dut.clockDomain.waitSampling()
    }

    private def withHarness(name: String, factory: CacheConfig => ReplacePolicy)
                           (body: PolicyHarness => Unit): Unit = {
        println(s"---- policy = $name ----")
        SimConfig
            .withVCS()
            .workspacePath("simWorkspace")
            .workspaceName(s"policy_$name")
            .compile(new PolicyHarness(cfg, factory))
            .doSim { dut =>
                dut.clockDomain.forkStimulus(10)
                dut.io.set #= 0
                clearLock(dut)
                dut.io.fillEn #= false
                dut.io.hitEn  #= false
                dut.clockDomain.waitSampling(5)
                body(dut)
            }
    }

    // ---------------------------------------------------------
    // FIFO / LRU：顺序 [2,0,3,1]，锁 way2 -> 必须选 way0（次老）
    // 旧实现（按下标旋转）会错选 way3。
    // ---------------------------------------------------------
    private def orderedPolicyBody(dut: PolicyHarness): Unit = {
        // 从 [0,1,2,3] 依次 touch 2,0,3,1 -> [2,0,3,1]
        fill(dut, 2); fill(dut, 0); fill(dut, 3); fill(dut, 1)
        assert(alloc(dut) == 2, s"队首应为 way2，实际 ${alloc(dut)}")

        dut.io.lock(2) #= true
        val got = alloc(dut)
        assert(got == 0, s"锁定队首后应选次老 way0，实际 way$got")
        println("  [PASS] locked head -> next in policy order")
    }

    // ---------------------------------------------------------
    // Tree-PLRU：复位偏好序 0..3；访问把路径位指向"远离该路"
    //   复位            -> way0
    //   fill way2       -> way0
    //   hit  way0       -> way3
    //   锁 way3         -> 回退到同父的 way2
    // ---------------------------------------------------------
    private def plruBody(dut: PolicyHarness): Unit = {
        assert(alloc(dut) == 0, s"复位后应为 way0，实际 ${alloc(dut)}")

        fill(dut, 2)
        assert(alloc(dut) == 0, s"fill way2 后应仍为 way0，实际 ${alloc(dut)}")

        hit(dut, 0)
        assert(alloc(dut) == 3, s"hit way0 后应为 way3，实际 ${alloc(dut)}")

        dut.io.lock(3) #= true
        val got = alloc(dut)
        assert(got == 2, s"锁定 way3 后应回退到 way2，实际 way$got")
        println("  [PASS] tree preference + locked fallback")
    }

    withHarness("FIFO", FifoPolicyFactory)(orderedPolicyBody)
    withHarness("LRU", LruPolicyFactory)(orderedPolicyBody)
    withHarness("PLRU", PlruPolicyFactory)(plruBody)

    println("ALL POLICY TESTS PASSED")
}
