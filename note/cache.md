# Description

本D-Cache是一个参数可配置的写回、写分配、组相联数据缓存，面向RISC-V处理器设计。

---

# Parameters # 


| prefix | identifier | description |
| - | - | - |
| `parameter` | [Num_Cache_Set](#Num_Cache_Set) | Number of cache sets. Must be power of 2 |
| `parameter` | [Cache_Block_Size](#Cache_Block_Size) | Size of each cache block in bytes. Must be power of 2 |
| `parameter` | [Num_Cache_Way](#Num_Cache_Way) | Number of ways in each set (associativity) |
| `parameter` | [DataAddrBus](#DataAddrBus) | Address bus width in bits |
| `parameter` | [DataWidth](#DataWidth) | Data bus width between CPU and Cache in bits |

---

# Local Parameters #

| prefix | identifier | description |
| - | - | - |
| `localparam` | [Index_Width](#Index_Width) | Number of bits for cache set index |
| `localparam` | [Offset_Width](#Offset_Width) | Number of bits for block offset |
| `localparam` | [Way_Width](#Way_Width) | Number of bits for way selection|
| `localparam` | [Tag_Width](#Tag_Width) | Number of bits for address tag|


---

# Ports #


| direction | identifier | description |
| - | - | - |
| `input` | [clk](#clk) | System clock. All operations synchronous to rising edge. |
| `input` | [reset](#reset) | Asynchronous active-low reset. Clears all cache valid bits.|
| `input` | [cpu_req](#cpu_req) | CPU access request. Active high. Stalls CPU when low.
|
| `input` | [cpu_wr_en](#cpu_wr_en) | CPU write enable. `1=write`, `0=read`. |
| `input` | [cpu_req_addr](#cpu_req_addr) | CPU access address. Decomposed into {tag, index, offset}.|
| `input` | [cpu_wdata](#cpu_wdata) | CPU write data. Valid when `cpu_wr_en=1`.|
| `output` | [cache_rdata](#cache_rdata) | Cache read data returned to CPU.|
| `output` | [ready](#ready) | Access completion signal. CPU can proceed when high.
|
| `output` | [mem_req](#mem_req) | Memory request. Active high when cache needs memory access.|
| `output` | [mem_wr_en](#mem_wr_en) | Memory write enable. `1=write-back`, `0=read-fill`.|
| `output` | [mem_addr](#mem_addr) | Memory address. Word-aligned for fill, block-aligned for write-back.|
| `output` | [mem_wdata](#mem_wdata) | Memory write data. Full cache block (`8*Cache_Block_Size` bits).|
| `input` | [mem_resp](#mem_resp) | Memory response. Indicates `read/write` completion.|
| `input` | [mem_rdata](#mem_rdata) | Memory read data. Full cache block width.|

---

# Feature #

>- **可配置架构**：组数（Num_Cache_Set）、路数（Num_Cache_Way）、缓存行大小（Cache_Block_Size）、数据总线宽度（DataWidth）、地址总线宽度（DataAddrBus）均可通过参数定制
>- **组相联结构**：支持2的幂次组数，任意正整数路数，总容量 = 组数 × 路数 × 缓存行大小
>- **写回策略**：写操作只更新缓存并标记脏位，不立即写内存
>- **写分配策略**：写未命中时先从内存读取整行到缓存，再合并写入
>- **FIFO替换策略**：采用先进先出算法选择被替换的缓存行
>- **有限状态机控制**：包含空闲（IDLE）、脏行检查（DIRTY_CHECK）、写回（WB）、等待填充（MISS_WAIT）四个状态
>- **读命中**：直接返回缓存数据
>- **读未命中**：被替换行脏时先写回再填充，否则直接填充
>- **写命中**：直接更新缓存行并标记脏位
>- **写未命中**：读内存填充整行后合并写数据，并标记脏位