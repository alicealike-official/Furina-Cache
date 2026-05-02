# Eva-RISCⅤ Cache 子系统技术文档

## 1. 概述

Eva-RISCⅤ 处理器采用独立的 **Harvard 架构**，指令缓存（I-Cache）与数据缓存（D-Cache）分离设计。两者均为 **N 路组相联（N-way Set-Associative）** 架构，支持可配置的组数、块大小和相联度，采用 **FIFO 替换策略**。

### 1.1 通用参数

| 参数 | 默认值 | 描述 |
|------|--------|------|
| `Num_Cache_Set` | 32 | Cache 组数 |
| `Cache_Block_Size` | 64 | 每个 Cache 块的字节数 |
| `Num_Cache_Way` | 4 | 相联度（路数） |
| `DataAddrBus` | 32 | 地址总线宽度 |
| `DataWidth` | 32 | 数据总线宽度 |

### 1.2 地址分解

所有 Cache 将 32 位物理地址分解为三个字段：

```
|    Tag (tag_in)     |  Index (index_in)  |  Offset (offset_in)  |
+----------------------+--------------------+-----------------------+
| 32 - I - O bits      |  log2(Num_Cache_Set)  |  log2(Cache_Block_Size) |
```

- **Tag**: 地址高位，用于比较是否命中
- **Index**: 选择 Cache 组
- **Offset**: 块内字节偏移

字偏移（选择块内哪个字）：`word_offset = offset_in >> log2(DataWidth/8)`

---

## 2. 指令缓存（I-Cache）

**文件**: `I_cache.v`

### 2.1 架构特性

- **只读缓存**：无需 dirty 位，无需写回操作
- **写分配（Write-Allocate）**：缺失时从内存加载整块
- **FIFO 替换策略**：每路有独立 FIFO 指针

### 2.2 存储结构

```verilog
reg valid [Num_Cache_Way][Num_Cache_Set];           // 有效位
reg tag  [Num_Cache_Way][Num_Cache_Set];            // 标签
reg [8*Cache_Block_Size-1:0] cache_data [Num_Cache_Way][Num_Cache_Set];  // 块数据
```

### 2.3 状态机

采用 2 状态有限状态机：

```
          CPU请求且未命中
IDLE ──────────────────────────► MISS_WAIT
  ▲                                │
  │◄───────────────────────────────┘
  │    内存响应（mem_resp）
  │
  │  CPU请求且命中：IDLE自循环
```

| 状态 | 描述 |
|------|------|
| `IDLE` | 空闲，接受 CPU 请求。命中则一拍返回数据；未命中则发出内存请求并跳转 |
| `MISS_WAIT` | 等待内存响应。收到 `mem_resp` 后更新 Cache 行并返回 IDLE |

### 2.4 关键信号

| 信号 | 功能 |
|------|------|
| `cpu_req` | CPU 请求有效 |
| `ready` | 命中时或 miss 完成后拉高，表示数据有效 |
| `rdata` | 返回给 CPU 的指令数据 |
| `mem_req` | 向内存发出的读块请求（仅 miss 时产生） |
| `mem_addr` | 请求的内存地址（= `cpu_req_addr`） |
| `way_hits[i]` | 第 i 路命中判断：`valid && tag match` |
| `hit_way` | 命中路号（组合逻辑） |

### 2.5 命中/缺失行为

- **命中（hit_sign 为 1）**：`ready` 立即拉高，`rdata = cache_data[hit_way][index_in][8*offset_in +: DataWidth]`
- **缺失（hit_sign 为 0）**：拉高 `mem_req`，进入 `MISS_WAIT`；内存返回后填充 Cache 行，设置 valid 和 tag，然后返回数据

---

## 3. 数据缓存（D-Cache）

**文件**: `D_Cache.v`

### 3.1 架构特性

- **写回（Write-Back）策略**：写命中仅更新 Cache，标记 dirty；替换脏块时写回内存
- **写分配（Write-Allocate）策略**：写缺失时从内存加载整块后再写入
- **脏块替换检测**：替换前检查目标路是否 dirty，若是则先写回
- **FIFO 替换策略**
- **分离的请求/响应通道**：支持 valid/ready 握手协议

### 3.2 存储结构

```verilog
reg valid [Num_Cache_Way][Num_Cache_Set];                              // 有效位
reg dirty [Num_Cache_Way][Num_Cache_Set];                              // 脏位
reg tag   [Num_Cache_Way][Num_Cache_Set];                              // 标签
reg [DataWidth-1:0] cache_data [Num_Cache_Way][Num_Cache_Set][Words_Per_Block]; // 以字为粒度的块数据
```

**注意**：D-Cache 的块数据按 **字（Word）** 组织（区别于 I-Cache 的按字节组织），便于字粒度读写。

### 3.3 状态机

采用 4 状态有限状态机：

```
          CPU请求且未命中
IDLE ──────────────────────────► DIRTY_CHECK
  ▲                                  │
  │                       ┌──────────┼──────────┐
  │                       │ 不脏     │ 脏        │
  │                       ▼          ▼           │
  │                   MISS_WAIT     WB           │
  │                       ▲          │           │
  │                       │          │           │
  │                       └──────────┘           │
  │                       内存响应               │
  │                                              │
  │◄─────────────────────────────────────────────┘
  │         WB完成后进入MISS_WAIT
  │
  │  CPU命中：IDLE自循环（一拍完成）
```

| 状态 | 描述 |
|------|------|
| `IDLE` | 空闲。命中时一拍完成读写；未命中时进入 `DIRTY_CHECK` |
| `DIRTY_CHECK` | 检查 FIFO 选中的替换路是否 dirty。脏则进入 `WB` 写回，否则直接进入 `MISS_WAIT` |
| `WB` | 写回脏块到内存。完成后进入 `MISS_WAIT` |
| `MISS_WAIT` | 等待内存返回数据。收到后填充 Cache 行，返回 IDLE |

### 3.4 读写操作细节

#### 3.4.1 读命中

- 一拍完成：`cache_rdata = cache_data[hit_way][index_in][word_offset]`
- `cpu_resp_valid` 拉高
- 状态保持 `IDLE`

#### 3.4.2 写命中

- 更新对应字数据：`cache_data[hit_way][index_in][word_offset] <= cpu_wdata`
- 标记 dirty：`dirty[hit_way][index_in] <= 1'b1`
- 一拍完成，状态保持 `IDLE`

#### 3.4.3 读缺失

1. `IDLE` → `DIRTY_CHECK`
2. FIFO 选中的路不脏 → 直接进入 `MISS_WAIT`
3. 向内存发出读请求（地址 = `{tag_in, index_in, 0}`，即块对齐地址）
4. 内存返回数据后，填充所有字到 Cache 行，标记 valid、清除 dirty
5. `cpu_resp_valid` 拉高，数据返回 CPU

#### 3.4.4 写缺失

1. `IDLE` → `DIRTY_CHECK`
2. 若替换路 dirty，先进入 `WB` 写回
3. `MISS_WAIT` 中内存返回数据后，将 CPU 写数据 **合并** 到对应字位置
4. 其余字从内存读取，整块写入 Cache
5. 标记 dirty（因为写了新数据）

### 3.5 握手协议

| 通道 | 信号 | 描述 |
|------|------|------|
| CPU 请求 | `cpu_req_valid` / `cpu_req_ready` | 请求握手 |
| CPU 响应 | `cpu_resp_valid` / `cpu_resp_ready` | 响应握手 |
| 内存请求 | `mem_req_valid` / `mem_req_ready` | Cache 向内存发请求 |
| 内存响应 | `mem_resp_valid` / `mem_resp_ready` | 内存向 Cache 返回数据 |

**注意**：`cpu_req_ready` 在 `IDLE` 状态有效；`cpu_resp_valid` 在命中或 miss_done 时拉高。

---

## 4. FIFO 替换策略

**文件**: `fifo_counter.v`

### 4.1 原理

每路（way）使用一个循环计数器作为 FIFO 指针：

```verilog
reg [Counter_Width-1:0] fifo_ptr;
```

- 复位时 `fifo_ptr = 0`
- 每次分配（`alloc_enable` 有效）时，指针循环递增
- `replace_way_out = fifo_ptr` 指示下一次应替换的路号

### 4.2 特性

- **简单循环**：相当于 round-robin，公平分配
- 每 **组** 有独立的 FIFO 计数器实例
- 与相联度解耦，通过参数 `Num_Cache_Way` 自动适配

---

## 5. 可配置延迟内存模型

**文件**: `configurable_delay_mem.sv`

### 5.1 功能

用于仿真验证的行为级内存模型，支持：

- **可配置访问延迟**：通过 `latency_in` 动态设置延迟周期
- **动态内存分配**：使用 SystemVerilog 关联数组 `block_mem[bit[31:0]]`，按需分配
- **随机初始化**：首次访问未存在的块时，用 `$urandom` 随机初始化

### 5.2 状态机

```
IDLE ──► WAIT ──► IDLE
  ▲          │
  └──────────┘
```

- `IDLE`：接收请求，锁存地址/数据/写使能
- `WAIT`：延迟计数器递减，归零时返回响应

### 5.3 关键实现细节

- **写操作**：写回操作在 `mem_resp_handshake && mem_wr_en_r` 时执行 `block_mem[block_addr] = mem_wdata_r`
- **读操作**：组合逻辑输出 `mem_rdata = block_mem[get_block_addr(mem_addr_r)]`（当 `mem_resp_valid && !mem_wr_en_r` 时）
- **延迟控制**：`current_latency` 寄存器在每个 WAIT 周期递减，到 1 时在下一周期拉高 `mem_resp_valid`

---

## 6. D-Cache 备选版本

**文件**: `D_Cache_bak.v`

此版本为 D-Cache 的早期/备选实现，与主版本的主要差异：

| 特性 | `D_Cache.v`（主版本） | `D_Cache_bak.v`（备选） |
|------|----------------------|------------------------|
| 握手协议 | valid/ready 分离通道 | 单周期 req/resp 信号 |
| 块数据粒度 | 按字（Word）组织 | 按字节组织 |
| 写合并 | 字粒度直接写入 | 字节级移位/掩码合并 |
| 控制逻辑 | 状态机驱动 + 锁存器 | 组合逻辑直接驱动 |

备选版本采用不同的控制信号生成方式（如 `mem_req` 为复杂的组合逻辑表达式），以及不同的数据合并方式：

```verilog
// 备选版本的写合并（字节级别）
cache_data[alloc_way][index_in] <= 
    (mem_rdata & ~(({DataWidth{1'b1}} << (offset_in * 8)))) |
    ({cpu_wdata} << (offset_in * 8));
```

---

## 7. 整体数据流

```
┌──────────┐   指令请求     ┌───────────┐   块请求     ┌──────────────┐
│          │ ──────────────►│           │ ────────────►│              │
│  CPU     │                │  I-Cache  │              │   Memory     │
│          │◄──────────────┤           │◄──────────────┤ (configurable│
│          │   指令数据      │           │   块数据      │  delay mem)  │
│          │                └───────────┘              │              │
│          │                                           │              │
│          │   数据请求      ┌───────────┐   块请求     │              │
│          │ ──────────────►│           │ ────────────►│              │
│          │                │  D-Cache  │              │              │
│          │◄──────────────┤           │◄──────────────┤              │
│          │   数据          │ (写回策略) │   块数据      │              │
└──────────┘                └───────────┘              └──────────────┘
```

- **I-Cache**：CPU 发送取指地址，I-Cache 返回指令（命中）或从 Memory 加载
- **D-Cache**：CPU 发送读写请求，D-Cache 返回数据（读命中）或写入 Cache（写命中）；缺失时从 Memory 加载/写回脏块

---

## 8. 参数配置指南

修改 `D_Cache.v` / `I_cache.v` 模块实例化时的参数即可：

```verilog
D_cache #(
    .Num_Cache_Set(32),
    .Cache_Block_Size(64),
    .Num_Cache_Way(4)
) u_d_cache (
    ...
);
```

**参数约束**：
- `Num_Cache_Set` 必须是 2 的幂
- `Cache_Block_Size` 必须是 `DataWidth/8` 的整数倍
- `DataAddrBus` ≥ `log2(Num_Cache_Set) + log2(Cache_Block_Size)`
