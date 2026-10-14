package furina.cache
import spinal.core._
import spinal.lib._

// ============================================================//
//                                                             //
//                            参数配置                          //
//                                                             //
// ============================================================//
case class CacheConfig(
    NUM_SETS:               Int = 32,
    BLOCK_SIZE:             Int = 64,   // 字节
    NUM_WAYS:               Int = 4,
    DATA_WIDTH:             Int = 32,
    ADDR_WIDTH:             Int = 32,
    MSHR_ENTRIES:           Int = 4,    // MSHR 条目数
    MSHR_MAX_PENDING:       Int = 4,     // 每个 MSHR 最多挂起的请求数
    ID_WIDTH:               Int = 12,
    NUM_BUS_OUTSTANDING:    Int = 16   //总线最大支持的宽度
) {
    require(BLOCK_SIZE % (DATA_WIDTH / 8) == 0, "BLOCK_SIZE 必须是 word 大小的整数倍")
    require(isPow2(NUM_SETS), "NUM_SETS 必须是 2 的幂")
    require(isPow2(BLOCK_SIZE), "BLOCK_SIZE 必须是 2 的幂")
    require(isPow2(DATA_WIDTH / 8), "字大小必须是 2 的幂")
    val indexWidth  = log2Up(NUM_SETS)
    val offsetWidth = log2Up(BLOCK_SIZE)
    val tagWidth    = ADDR_WIDTH - offsetWidth - indexWidth
    val wordsPerBlock = BLOCK_SIZE / (DATA_WIDTH / 8)
    val wordOffWidth  = log2Up(wordsPerBlock)

    // MSHR 条目 ID 宽度 (用于内存请求/响应匹配)
    val mshrIdWidth = log2Up(MSHR_ENTRIES)
    // 请求标签宽度（区分 CPU 未完成的请求）
    // val reqTagWidth = log2Up(MSHR_ENTRIES * MSHR_MAX_PENDING + 1)
}