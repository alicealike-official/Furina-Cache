// ============================================================
// 文件名   : CacheConfig.scala
// 描述     : Cache 参数、地址分解与位宽派生
// 文档依据 : 《Cache 架构设计文档 v2》§3、§4.5、§5.1
// ============================================================

package furina.dcache

import spinal.core._

/**
 * Cache 参数（默认值取文档 §3.1，全部可配置）。
 *
 * 地址布局（ADDR_WIDTH = 32, NUM_SETS = 32, BLOCK_SIZE = 64）：
 *   [ tag(21) | index(5) | wordOff(4) | byte(2) ]
 */
case class CacheConfig(
    NUM_SETS: Int = 32,
    BLOCK_SIZE: Int = 64,
    NUM_WAYS: Int = 4,
    DATA_WIDTH: Int = 32,
    ADDR_WIDTH: Int = 32,
    MSHR_ENTRIES: Int = 4,
    MSHR_MAX_PENDING: Int = 4,
    WBB_ENTRIES: Int = 4,
    RESP_QUEUE_DEPTH: Int = 4,
    ID_WIDTH: Int = 5,
    NUM_BUS_OUTSTANDING: Int = 16
) {
    // ---------- 参数约束（文档 §3.3） ----------
    private val byteWidth = DATA_WIDTH / 8
    require(byteWidth >= 1 && isPow2(byteWidth), "字大小必须是 2 的幂")
    require(BLOCK_SIZE % byteWidth == 0, "BLOCK_SIZE 必须是字大小的整数倍")
    require(isPow2(NUM_SETS) && NUM_SETS >= 2, "NUM_SETS 必须是 2 的幂")
    require(isPow2(BLOCK_SIZE) && BLOCK_SIZE >= byteWidth, "BLOCK_SIZE 必须是 2 的幂")
    require(isPow2(NUM_WAYS) && NUM_WAYS >= 2, "NUM_WAYS 必须是 2 的幂")
    require(isPow2(MSHR_ENTRIES) && MSHR_ENTRIES >= 1, "MSHR_ENTRIES 必须是 2 的幂")
    require(isPow2(MSHR_MAX_PENDING) && MSHR_MAX_PENDING >= 1, "MSHR_MAX_PENDING 必须是 2 的幂")
    require(isPow2(WBB_ENTRIES) && WBB_ENTRIES >= 1, "WBB_ENTRIES 必须是 2 的幂")
    require(WBB_ENTRIES <= NUM_BUS_OUTSTANDING, "WBB_ENTRIES 不能超过总线未完成事务数")
    require(isPow2(NUM_BUS_OUTSTANDING), "NUM_BUS_OUTSTANDING 必须是 2 的幂")
    require(RESP_QUEUE_DEPTH >= 1, "响应队列深度至少为 1")
    require(ID_WIDTH >= 1, "ID_WIDTH 至少为 1")

    // ---------- 派生参数（文档 §3.2） ----------
    val byteWidthLog2: Int = log2Up(byteWidth)
    val indexWidth: Int = log2Up(NUM_SETS)
    val offsetWidth: Int = log2Up(BLOCK_SIZE)
    val tagWidth: Int = ADDR_WIDTH - offsetWidth - indexWidth
    val wordsPerBlock: Int = BLOCK_SIZE / byteWidth
    val wordOffWidth: Int = log2Up(wordsPerBlock)
    val wayWidth: Int = log2Up(NUM_WAYS) max 1
    val lineWidth: Int = wordsPerBlock * DATA_WIDTH

    val mshrIdWidth: Int = log2Up(MSHR_ENTRIES) max 1
    val wbbIdWidth: Int = log2Up(WBB_ENTRIES) max 1
    val busIdWidth: Int = log2Up(NUM_BUS_OUTSTANDING) max 1
    val pendingCntWidth: Int = log2Up(MSHR_MAX_PENDING + 1) max 1

    require(tagWidth > 0, "地址宽度不足以容纳 tag/index/offset")
    require(wordsPerBlock >= 2, "块内至少需要 2 个字，才能定义 wordOff")
    require(mshrIdWidth <= busIdWidth, "MSHR 位次必须能用总线 ID 表示")
    require(wbbIdWidth <= busIdWidth, "WBB 位次必须能用总线 ID 表示")

    // ---------- 地址分解（文档 §5.1） ----------
    def indexOf(addr: UInt): UInt =
        addr(offsetWidth + indexWidth - 1 downto offsetWidth)

    def tagOf(addr: UInt): UInt =
        addr(ADDR_WIDTH - 1 downto offsetWidth + indexWidth)

    def wordOffOf(addr: UInt): UInt =
        addr(offsetWidth - 1 downto byteWidthLog2)

    /** 块对齐地址：低 offsetWidth 位清零 */
    def blockAddrOf(addr: UInt): UInt =
        ((addr >> offsetWidth) << offsetWidth).resize(ADDR_WIDTH)

    /** 由 tag/index 还原块对齐地址（用于写回与内存读） */
    def blockAddrFromTagIndex(tag: UInt, index: UInt): UInt =
        Cat(tag, index, U(0, offsetWidth bits)).asUInt.resize(ADDR_WIDTH)
}
