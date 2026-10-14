package furina.cache.policy

import spinal.core._
import spinal.lib._
import furina.cache.CacheConfig

// ============================================================//
//                                                             //
//                    替换策略统一接口                          //
//                                                             //
// ============================================================//
/**
 * 替换策略接口。
 *
 * 所有具体策略都继承这个 trait，并在 Area 中实现硬件逻辑。
 * Cache 顶层通过工厂函数接收策略，实现编译期可配置。
 *
 * 使用方式：
 *   val policy = new FifoPolicy(cfg)
 *   val allocWay = policy.allocWay(setIndex)
 *   policy.onFill(setIndex, way, enable)
 *   policy.onHit(setIndex, way, enable)
 */
trait ReplacePolicy {
    def allocWay(setIndex: UInt): UInt
    def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit
    def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit
}


// ============================================================//
//                                                             //
//                        轮询策略                              //
//                                                             //
// ============================================================//
class RoundRobinPolicy(cfg: CacheConfig) extends Area with ReplacePolicy {
    private val wayWidth = (log2Up(cfg.NUM_WAYS) max 1)

    // 每个 set 一个指针
    val counters = Vec(
        Reg(UInt(wayWidth bits)) init 0,
        cfg.NUM_SETS
    )

    override def allocWay(setIndex: UInt): UInt = counters(setIndex)

    override def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit = {
        when(enable) {
            counters(setIndex) := Mux(
                counters(setIndex) === U(cfg.NUM_WAYS - 1),
                U(0),
                counters(setIndex) + U(1)
            )
        }
    }

    // 轮询不关心命中
    override def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit = {}
}


// ============================================================//
//                                                             //
//                         FIFO 策略                            //
//                                                             //
// ============================================================//
class FifoPolicy(cfg: CacheConfig) extends Area with ReplacePolicy {
    private val wayWidth = (log2Up(cfg.NUM_WAYS) max 1)

    // 每个 set 一个队列
    val order = Vec(
        Vec(Reg(UInt(wayWidth bits)), cfg.NUM_WAYS),
        cfg.NUM_SETS
    )

    // 初始化：set s 的队列为 [0, 1, ..., NUM_WAYS-1]
    for (s <- 0 until cfg.NUM_SETS) {
        for (i <- 0 until cfg.NUM_WAYS) {
            order(s)(i).init(i)
        }
    }

    // 替换目标：队头
    override def allocWay(setIndex: UInt): UInt = order(setIndex)(0)

    // 填充时：队列左移，新 way 入队尾
    override def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit = {
        when(enable) {
            for (i <- 0 until cfg.NUM_WAYS - 1) {
                order(setIndex)(i) := order(setIndex)(i + 1)
            }
            order(setIndex)(cfg.NUM_WAYS - 1) := way
        }
    }

    // FIFO 不关心命中
    override def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit = {}
}


// ============================================================//
//                                                             //
//                         LRU 策略                             //
//                                                             //
// ============================================================//
class LruPolicy(cfg: CacheConfig) extends Area with ReplacePolicy {
    private val wayWidth = (log2Up(cfg.NUM_WAYS) max 1)

    // 每个 set 一个顺序队列，队头 = 最久未使用
    val order = Vec(
        Vec(Reg(UInt(wayWidth bits)), cfg.NUM_WAYS),
        cfg.NUM_SETS
    )

    // 初始化：[0, 1, ..., NUM_WAYS-1]
    for (s <- 0 until cfg.NUM_SETS) {
        for (i <- 0 until cfg.NUM_WAYS) {
            order(s)(i).init(i)
        }
    }

    override def allocWay(setIndex: UInt): UInt = order(setIndex)(0)

    /** 把某个 way 移到队尾（标记为最新） */
    private def moveToTail(setIndex: UInt, way: UInt): Unit = {
        // 生成：把 way 从当前位置移除，其余前移，way 放队尾
        val newOrder = Vec(UInt(wayWidth bits), cfg.NUM_WAYS)
        // 简化示意：实际实现可用两个队列拼接或循环移位
        // 这里用「命中时把该 way 放到队尾，其余保持相对顺序」的逻辑
        for (i <- 0 until cfg.NUM_WAYS) {
            newOrder(i) := order(setIndex)(i)
        }
        // 找到 way 的位置
        val posVec = Vec((0 until cfg.NUM_WAYS).map { i =>
            order(setIndex)(i) === way
        })
        val pos = OHToUInt(posVec)
        // 重新排列：pos 之后的元素前移，way 放队尾
        for (i <- 0 until cfg.NUM_WAYS) {
            when(pos === U(i)) {
                for (j <- 0 until cfg.NUM_WAYS) {
                    when(U(j) < U(i)) {
                        newOrder(j) := order(setIndex)(j)
                    } .elsewhen(U(j) < U(cfg.NUM_WAYS - 1)) {
                        newOrder(j) := order(setIndex)(j + 1)
                    } .otherwise {
                        newOrder(j) := way
                    }
                }
            }
        }
        for (i <- 0 until cfg.NUM_WAYS) {
            order(setIndex)(i) := newOrder(i)
        }
    }

    override def onFill(setIndex: UInt, way: UInt, enable: Bool): Unit = {
        when(enable) {
            moveToTail(setIndex, way)
        }
    }

    override def onHit(setIndex: UInt, way: UInt, enable: Bool): Unit = {
        when(enable) {
            moveToTail(setIndex, way)
        }
    }
}


// ============================================================//
//                                                             //
//                    策略工厂（可选）                          //
//                                                             //
// ============================================================//
/**
 * 策略工厂：把「策略类型」抽象成一个函数，便于 Cache 顶层参数化。
 *
 * 使用：
 *   val cache = new DCacheWithMSHR(cfg, FifoPolicyFactory)
 *   val cache2 = new DCacheWithMSHR(cfg, RoundRobinPolicyFactory)
 */
object FifoPolicyFactory       extends (CacheConfig => ReplacePolicy) {
    def apply(cfg: CacheConfig): ReplacePolicy = new FifoPolicy(cfg)
}

object RoundRobinPolicyFactory extends (CacheConfig => ReplacePolicy) {
    def apply(cfg: CacheConfig): ReplacePolicy = new RoundRobinPolicy(cfg)
}

object LruPolicyFactory        extends (CacheConfig => ReplacePolicy) {
    def apply(cfg: CacheConfig): ReplacePolicy = new LruPolicy(cfg)
}