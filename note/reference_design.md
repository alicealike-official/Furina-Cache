# Description

这里用于添加设计的简要描述，更复杂的描述添加到`feature`里

---

# Parameter/Localparameter
这里用于描述模块用到的参数，包括本地参数，如果没有可以忽略，如果参数描述太长(不建议写太长的描述)，可以将描述更详细地写在`Detailed Documentation`里
>例:
>| prefix | identifier | description |
>| - | - | - |
>| `parameter` | [Num_Cache_Set](#Num_Cache_Set) | Number of cache sets. Must be power of 2 |
>| `parameter` | [Cache_Block_Size](#Cache_Block_Size) | Size of each cache block in bytes. Must be power of 2 |
>| `parameter` | [Num_Cache_Way](#Num_Cache_Way) | Number of ways in each set (associativity) |
>| `parameter` | [DataAddrBus](#DataAddrBus) | Address bus width in bits |
>| `parameter` | [DataWidth](#DataWidth) | Data bus width between CPU and Cache in bits |

## Detailed Documentation

> `参数1` : 详细描述

>`参数2` : 详细描述

---

# Ports

这里用于描述IO接口

>| direction | identifier | description |
>| - | - | - |
>| `input` | [clk](#clk) | System clock. All operations synchronous to rising edge. |
>| `input` | [reset](#reset) | Asynchronous active-low reset. Clears all cache valid bits.|
>| `input` | [cpu_req](#cpu_req) | CPU access request. Active high. Stalls CPU when low.|
>| `input` | [cpu_wr_en](#cpu_wr_en) | CPU write enable. `1=write`, `0=read`. |
>| `input` | [cpu_req_addr](#cpu_req_addr) | CPU access address. Decomposed into {tag, index, offset}.|
>| `input` | [cpu_wdata](#cpu_wdata) | CPU write data. Valid when `cpu_wr_en=1`.|
>| `output` | [cache_rdata](#cache_rdata) | Cache read data returned to CPU.|
>| `output` | [ready](#ready) | Access completion signal. CPU can proceed when high.|
>| `output` | [mem_req](#mem_req) | Memory request. Active high when cache needs memory access.|
>| `output` | [mem_wr_en](#mem_wr_en) | Memory write enable. `1=write-back`, `0=read-fill`.|
>| `output` | [mem_addr](#mem_addr) | Memory address. Word-aligned for fill, block-aligned for write-back.|
>| `output` | [mem_wdata](#mem_wdata) | Memory write data. Full cache block (`8*Cache_Block_Size` bits).|
>| `input` | [mem_resp](#mem_resp) | Memory response. Indicates `read/write` completion.|
>| `input` | [mem_rdata](#mem_rdata) | Memory read data. Full cache block width.|

---

# Feature #
这里用来详细描述模块的各种特性


