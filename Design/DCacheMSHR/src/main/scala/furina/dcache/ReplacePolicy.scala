// ============================================================
// 文件名   : ReplacePolicy.scala
// 描述     : 可插拔替换策略
// 文档依据 : 《Cache 架构设计文档 v2》§10.1 - §10.5
//
// 接口契约（§10.3）：
//   allocWay(setIndex)                  : 给出候选替换路
//   onHit(setIndex, way, enable)        : Stage2 命中判定成立那一拍触发
//   onFill(setIndex, way, enable)       : 填充写 Cache 那一拍触发
//
// "优先空路 / 跳过 Way Lock" 由顶层按 §10.4 完成，策略本身只负责
// 维护自己的顺序信息，不感知 valid / locked。
// ============================================================

package furina.dcache

import spinal.core._
import spinal.lib._

trait ReplacePolicy {
    def allocWay(setIndex: UInt): UInt
    def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit
    def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit
}

/** 顺序队列策略基类：order(set)(0) 为最老（候选 victim） */
abstract class OrderedPolicy(cfg: CacheConfig) extends Area with ReplacePolicy {
    import cfg._

    protected val order = Vec(Vec(Reg(UInt(wayWidth bits)), NUM_WAYS), NUM_SETS)
    for (s <- 0 until NUM_SETS) {
        for (i <- 0 until NUM_WAYS) {
            order(s)(i).init(i)
        }
    }

    override def allocWay(setIndex: UInt): UInt = order(setIndex)(0)

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

/** 轮询：每 set 一个指针，填充后前移 */
class RoundRobinPolicy(cfg: CacheConfig) extends Area with ReplacePolicy {
    import cfg._

    private val counter = Vec(Reg(UInt(wayWidth bits)) init 0, NUM_SETS)

    override def allocWay(setIndex: UInt): UInt = counter(setIndex)

    override def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit = {}

    override def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit = {
        when(enable) {
            counter(setIndex) := Mux(
                counter(setIndex) === U(NUM_WAYS - 1, wayWidth bits),
                U(0, wayWidth bits),
                counter(setIndex) + U(1, wayWidth bits)
            )
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

object RoundRobinPolicyFactory extends (CacheConfig => ReplacePolicy) {
    def apply(cfg: CacheConfig): ReplacePolicy = new RoundRobinPolicy(cfg)
}
