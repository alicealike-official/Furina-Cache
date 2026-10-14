// Replacement.scala
package cache

import spinal.core._
import spinal.lib._

// 统一接口
trait ReplacementPolicy {
  def getVictimWay(setIndex: UInt): UInt
  def updateOnAccess(setIndex: UInt, way: UInt): Unit
  def updateOnFill(setIndex: UInt, way: UInt): Unit
}

// ----------------------------------------------------------------
// 1. 随机替换 (Unfinished)
// ----------------------------------------------------------------
class RandomReplacement(NumWays: Int, NumSets: Int) extends Area with ReplacementPolicy {
  require(NumWays > 0)
  def getVictimWay(setIndex: UInt): UInt = {}
  def updateOnAccess(setIndex: UInt, way: UInt): Unit = {}
  def updateOnFill(setIndex: UInt, way: UInt): Unit = {}
  def lfsrsNext(prev: UInt): UInt = {}
}

// ----------------------------------------------------------------
// 2. FIFO 替换 (循环队列)
// ----------------------------------------------------------------
class FifoReplacement(NumWays: Int, NumSets: Int) extends Area with ReplacementPolicy {
  require(NumWays > 0)
  val WayWidth = log2Up(NumWays)
  val counters = Vec(Reg(UInt(WayWidth bits)) init 0, NumSets)

  def getVictimWay(setIndex: UInt): UInt = {
    counters(setIndex)
  }

  def updateOnAccess(setIndex: UInt, way: UInt): Unit = {
  }

  def updateOnFill(setIndex: UInt, way: UInt): Unit = {
    counters(setIndex) := counters(setIndex) + 1
    when(counters(setIndex) === NumWays - 1) {
      counters(setIndex) := 0
    }
  }
}

// ----------------------------------------------------------------
// 3. 伪 LRU(Unfinished)
// ----------------------------------------------------------------
class PLRUReplacement(NumWays: Int, NumSets: Int) extends Area with ReplacementPolicy {
  require(NumWays > 0 && isPow2(NumWays), "PLRU requires NumWays to be a power of 2")
  def getVictimWay(setIndex: UInt): UInt = {}
  def updateOnAccess(setIndex: UInt, way: UInt): Unit = {}
  def updateOnFill(setIndex: UInt, way: UInt): Unit = {}
}

// ----------------------------------------------------------------
// 4. LRU (Unfinished)
// ----------------------------------------------------------------
class LRUReplacement(NumWays: Int, NumSets: Int) extends Area with ReplacementPolicy {
  require(NumWays > 0)
  def getVictimWay(setIndex: UInt): UInt = {}
  def updateOnAccess(setIndex: UInt, way: UInt): Unit = {}
  def updateOnFill(setIndex: UInt, way: UInt): Unit = {}
}

// ----------------------------------------------------------------
// 工厂方法：根据配置字符串创建替换策略
// ----------------------------------------------------------------
object ReplacementFactory {
  def apply(kind: String, NumWays: Int, NumSets: Int): ReplacementPolicy = {
    kind match {
      // case "RANDOM" => new RandomReplacement(NumWays, NumSets)
      case "FIFO"   => new FifoReplacement(NumWays, NumSets)
      case "PLRU"   => new PLRUReplacement(NumWays, NumSets)
      case "LRU"    => new LRUReplacement(NumWays, NumSets)
      case _        => throw new IllegalArgumentException(s"Unknown replacement policy: $kind")
    }
  }
}