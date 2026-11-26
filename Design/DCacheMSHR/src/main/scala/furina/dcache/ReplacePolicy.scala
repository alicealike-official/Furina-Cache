// ============================================================
// 文件名   : ReplacePolicy.scala
// 描述     : 可插拔替换策略（FIFO / LRU / Tree-PLRU）
// 文档依据 : 《Cache 架构设计文档 v2》§10.1 - §10.5
//
// 接口契约（§10.3）：
//   allocWay(setIndex, lockMask)        : 给出候选替换路
//   onHit(setIndex, way, enable)        : Stage2 命中提交那一拍触发
//   onFill(setIndex, way, enable)       : 填充写 Cache 那一拍触发
//
// victim 选择（§10.4）：
//   1) 优先 "valid=0 且未锁" 的路（由顶层完成，所有策略一致）；
//   2) 否则由策略在**自身的偏好顺序**中先剔除本拍被 Way Lock 锁定的路，
//      再取剩余顺序中最靠前的一路。策略因此需要 lockMask 入参。
//      不允许退化为"按 way 编号向后扫描"——那会丢掉策略的年龄/树偏好语义。
//   3) 全部被锁时顶层判为不可接收（本模块输出 don't-care）。
// ============================================================

package furina.dcache

import spinal.core._
import spinal.lib._

trait ReplacePolicy {
    /** 在策略偏好序中跳过被锁定的路，返回最靠前的候选 */
    def allocWay(setIndex: UInt, lockMask: Vec[Bool]): UInt
    /** 所选路是否满足属性；策略可直接从候选产生，避免等待路号编码。 */
    def allocWayMatches(setIndex: UInt, lockMask: Vec[Bool], matches: Vec[Bool]): Bool =
        matches(allocWay(setIndex, lockMask))
    def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit
    def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit
}

/** 顺序队列策略基类：order(set)(0) 为最老（首选 victim） */
abstract class OrderedPolicy(cfg: CacheConfig) extends Area with ReplacePolicy {
    import cfg._

    protected val order = Vec(Vec(Reg(UInt(wayWidth bits)), NUM_WAYS), NUM_SETS)
    for (s <- 0 until NUM_SETS) {
        for (i <- 0 until NUM_WAYS) {
            order(s)(i).init(i)
        }
    }

    /** 队列中第一个未被锁定的路（剔除锁定项，保持年龄序） */
    override def allocWay(setIndex: UInt, lockMask: Vec[Bool]): UInt = {
        val cand = Vec((0 until NUM_WAYS).map(i => !lockMask(order(setIndex)(i))))
        val k = priorityLowest(cand, wayWidth)
        order(setIndex)(k)
    }

    override def allocWayMatches(setIndex: UInt, lockMask: Vec[Bool], matches: Vec[Bool]): Bool = {
        val ways = order(setIndex)
        val cand = Vec((0 until NUM_WAYS).map(i => !lockMask(ways(i))))
        val selectedMatches = (0 until NUM_WAYS).map { i =>
            val grant = if (i == 0) cand(i) || !cand.orR
                        else cand(i) && !cand.take(i).reduce(_ || _)
            grant && matches(ways(i))
        }
        selectedMatches.reduce(_ || _)
    }

    /** 低位下标优先的优先编码器（cand 可能多位为 1，不能用 OHToUInt） */
    private def priorityLowest(vec: Seq[Bool], width: Int): UInt = {
        val res = UInt(width bits)
        res := U(0, width bits)
        for (i <- (vec.length - 1) to 0 by -1) {
            when(vec(i)) { res := U(i, width bits) }
        }
        res
    }

    /** 把 way 从队列中移除并放到队尾（即变为最新） */
    protected def moveToTail(setIndex: UInt, way: UInt): Unit = {
        val posVec = Vec((0 until NUM_WAYS).map(i => order(setIndex)(i) === way))
        val pos = OHToUInt(posVec)
        val next = Vec(UInt(wayWidth bits), NUM_WAYS)
        for (i <- 0 until NUM_WAYS) {
            next(i) := order(setIndex)(i)
        }
        for (p <- 0 until NUM_WAYS) {
            when(pos === U(p, log2Up(NUM_WAYS) bits)) {
                for (i <- p until (NUM_WAYS - 1)) {
                    next(i) := order(setIndex)(i + 1)
                }
                next(NUM_WAYS - 1) := way
            }
        }
        for (i <- 0 until NUM_WAYS) {
            order(setIndex)(i) := next(i)
        }
    }
}

/** FIFO：命中不改变顺序，填充时把该路移到队尾 */
class FifoPolicy(cfg: CacheConfig) extends OrderedPolicy(cfg) {
    override def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit = {}
    override def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit = {
        when(enable) { moveToTail(setIndex, way) }
    }
}

/** LRU：命中和填充都把该路移到队尾（队头即最久未使用） */
class LruPolicy(cfg: CacheConfig) extends OrderedPolicy(cfg) {
    override def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit = {
        when(enable) { moveToTail(setIndex, way) }
    }
    override def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit = {
        when(enable) { moveToTail(setIndex, way) }
    }
}

/**
 * Tree-PLRU：每 set 一棵完全二叉树。
 *   - 内部节点编号 1 .. NUM_WAYS-1（堆式），叶子编号 NUM_WAYS + way；
 *   - bit(node) = 0 表示优先左子树，1 表示优先右子树；
 *   - 访问某 way 时，把它到根路径上的每一位都指向"远离该 way"的一侧；
 *   - 复位时所有位为 0，故初始偏好序为 0,1,...,NUM_WAYS-1（与 FIFO/LRU 一致）。
 *
 * 锁定处理（§10.4 语义 A）：按树偏好序挑第一个未锁定的叶子；
 * 若首选子树已无未锁叶子，则回退到同父的另一支，再逐层向上回退。
 * 这等价于"先剔除锁定路，再取树偏好序中最靠前的一路"。
 */
class PlruPolicy(cfg: CacheConfig) extends Area with ReplacePolicy {
    import cfg._

    private val nodeCount = NUM_WAYS - 1
    private val bits = Vec(Vec(Reg(Bool()) init False, nodeCount), NUM_SETS)

    override def allocWay(setIndex: UInt, lockMask: Vec[Bool]): UInt =
        pick(setIndex, lockMask, 1)

    override def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit = {
        when(enable) { access(setIndex, way) }
    }

    override def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit = {
        when(enable) { access(setIndex, way) }
    }

    /** 子树内是否还有未被锁定的叶子 */
    private def subtreeHasUnlocked(lockMask: Vec[Bool], node: Int): Bool =
        if (node >= NUM_WAYS) !lockMask(node - NUM_WAYS)
        else subtreeHasUnlocked(lockMask, 2 * node) || subtreeHasUnlocked(lockMask, 2 * node + 1)

    /** 在子树 node 中按树偏好序挑第一个未锁定的叶子（全锁时输出 don't-care） */
    private def pick(setIndex: UInt, lockMask: Vec[Bool], node: Int): UInt = {
        if (node >= NUM_WAYS) {
            U(node - NUM_WAYS, wayWidth bits)
        } else {
            val goRight = bits(setIndex)(node - 1)
            val l = 2 * node
            val r = 2 * node + 1
            val leftWay  = pick(setIndex, lockMask, l)
            val rightWay = pick(setIndex, lockMask, r)
            val leftOk   = subtreeHasUnlocked(lockMask, l)
            val first    = Mux(goRight, rightWay, leftWay)
            val firstOk  = Mux(goRight, subtreeHasUnlocked(lockMask, r), leftOk)
            val second   = Mux(goRight, leftWay, rightWay)
            Mux(firstOk, first, second)
        }
    }

    /** 访问 way：路径上的每一位都指向"远离该 way"的一侧 */
    private def access(setIndex: UInt, way: UInt): Unit = {
        for (w <- 0 until NUM_WAYS) {
            when(way === U(w, wayWidth bits)) {
                var node = NUM_WAYS + w
                while (node > 1) {
                    val parent = node / 2
                    // 访问的是左孩子(node 偶数) -> 位设为 1（指向右），反之设为 0
                    bits(setIndex)(parent - 1) := Bool(node % 2 == 0)
                    node = parent
                }
            }
        }
    }
}

// ---------------- 工厂 ----------------
object FifoPolicyFactory extends (CacheConfig => ReplacePolicy) {
    def apply(cfg: CacheConfig): ReplacePolicy = new FifoPolicy(cfg)
}

object LruPolicyFactory extends (CacheConfig => ReplacePolicy) {
    def apply(cfg: CacheConfig): ReplacePolicy = new LruPolicy(cfg)
}

object PlruPolicyFactory extends (CacheConfig => ReplacePolicy) {
    def apply(cfg: CacheConfig): ReplacePolicy = new PlruPolicy(cfg)
}
