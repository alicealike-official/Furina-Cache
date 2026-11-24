# AXI 接口集成：带宽匹配分析与实施方案

## 1. 项目现状

### 1.1 Cache 架构参数

| 参数 | 值 | 说明 |
|------|------|------|
| 架构 | Harvard | 独立 I-Cache + D-Cache |
| `Num_Cache_Set` | 32 | 组数 |
| `Cache_Block_Size` | 64 bytes | 块大小 |
| `Num_Cache_Way` | 4 | 相联度 |
| `DataWidth` | 32 bits | 数据总线宽度 |
| `Words_Per_Block` | 16 | 每块字数（64/4） |
| 替换策略 | FIFO | 每路循环计数器 |
| D-Cache 写策略 | Write-Back + Write-Allocate | |
| Cache FSM | 非流水线 | miss 期间完全阻塞 |

### 1.2 内存接口信号

Cache 对外内存接口（`mem_*`）特性：

| 信号 | 位宽 | 说明 |
|------|------|------|
| `mem_req_valid/ready` | 1 | 请求通道 handshake |
| `mem_wr_en` | 1 | 写使能（0=读，1=写） |
| `mem_addr` | 32 | 块对齐地址 |
| `mem_wdata` | 512 | 写数据（8×64） |
| `mem_resp_valid/ready` | 1 | 响应通道 handshake |
| `mem_rdata` | 512 | 读数据（8×64） |

**关键特征**：单次 handshake 传输整个 cache line（512 bits = 64 bytes）。

### 1.3 AXI 适配器参数

| 参数 | 值 | 说明 |
|------|------|------|
| `AXI_DATA_WIDTH` | 32 bits | 每拍数据宽度 |
| `AXI_ADDR_WIDTH` | 32 bits | 地址宽度 |
| `AXI_ID_WIDTH` | 4 bits | 事务 ID 宽度 |
| `AXI_BURST_LEN` | 16 | 最大 burst 拍数 |
| `MAX_OSD` | 4 | 最大 outstanding 事务数 |
| 通道 | AR/R/AW/W/B | 完整 AXI4 通道 |

AXI 适配器微端接口：

| 信号 | 说明 |
|------|------|
| `rd_req_valid/ready` | 读请求启动 |
| `rdata_o[31:0]/valid/ready` | 读数据逐拍返回 |
| `read_done` | 读 burst 完成 |
| `wr_req_valid/ready` | 写请求启动 |
| `wdata_i[31:0]/valid/ready` | 写数据逐拍发送 |
| `write_done` | 写 burst 完成 |
| `addr/burst_len/size/type/id` | 地址和控制信息 |

### 1.4 当前状态

AXI 适配器 RTL 已实现（`Design/AXI/`），但未连接到 Cache 核心。当前 Cache 直接通过 `mem_*` 接口连接 `configurable_delay_mem` 行为模型。

---

## 2. 带宽匹配分析

### 2.1 单事务容量匹配

| 维度 | Cache 内存接口 | AXI 适配器微端 |
|------|---------------|----------------|
| 单次传输粒度 | 1 cache line = **512 bits** | 单 burst = 16 beats × 32 bits = **512 bits** |
| 地址对齐 | 64B 对齐 | 64B 对齐（burst_size=2, 16 beats） |
| **结论** | ✅ **完美匹配**：1 burst 正好传输 1 cache line |

AXI 参数设置：
- `ARLEN/AWLEN = 15`（16 beats）
- `ARSIZE/AWSIZE = 2`（4 bytes/beat）
- `ARBURST/AWBURST = INCR`

### 2.2 传输时序不匹配

| 对比项 | Cache 内存接口 | AXI 总线 |
|--------|---------------|----------|
| 数据位宽 | **512 bits**（单周期并行） | **32 bits**（串行） |
| 传完 1 line 所需周期 | 1 handshake + mem_latency | 1（地址） + 16（数据拍）+ slave_latency |
| 理想传输周期数 | ~1-10 cycles | ~17+ cycles |
| **带宽比** | **16:1**（AXI 慢 16×，不算 slave 延迟） | |

### 2.3 Outstanding 能力利用率

| 因素 | 分析 |
|------|------|
| Cache FSM | 非流水线，miss 期间阻塞，每 cache **最多 1** outstanding miss |
| Harvard 架构 | I$ + D$ 可同时各有一个 miss，最多 **2** concurrent |
| `MAX_OSD = 4` | **充足**，且有 2 个槽位余量 |
| **结论** | ✅ 当前 cache 架构无法充分利用 AXI 的 outstanding 能力 |

### 2.4 综合匹配结论

| 维度 | 匹配情况 | 影响 |
|------|---------|------|
| 单 burst 容量 | ✅ 完美匹配 | 1:1 映射，无需拆分 line |
| 传输带宽 | ⚠️ 不匹配（16:1） | miss penalty 放大 ~16× |
| Outstanding | ✅ 充足 | 非流水线 cache 用不满 |
| 时钟域 | ✅ 同频同步 | 无需 CDC 处理 |

**核心问题**：Cache 内部 512-bit 总线是单周期完成的，而 AXI 需要 16 个周期串行化。Cache FSM 在 miss 期间完全阻塞 CPU，AXI 的慢速传输直接转化为 CPU stall 周期，显著增大 AMAT。

---

## 3. RTL 集成方案：Cache-AXI Bridge

### 3.1 模块定位

在 Cache 的 `mem_*` 接口与 AXI 适配器微端接口之间插入 Bridge 模块：

```
┌──────────┐  512-bit line xfer    ┌──────────────────┐  32-bit beat x16   ┌───────────────┐
│          │ ◄───────────────────► │                  │ ◄────────────────► │               │
│  D_Cache │  mem_req/mem_resp    │  Cache_AXI_Bridge │  rd_req/wr_req    │  AXI 适配器   │
│  I_cache │  handshake           │  (line↔burst)     │  rdata/wdata      │  (Master)     │
│          │                       │                   │  逐拍 valid/ready │               │
└──────────┘                       └──────────────────┘                    └───────────────┘
```

### 3.2 信号映射

| Cache 侧 | Bridge 内部 | AXI 适配器微端 |
|----------|-------------|---------------|
| `mem_req_valid` | 触发 FSM 启动 | `rd_req_valid` / `wr_req_valid` |
| `mem_addr[31:0]` | 锁存至 addr_reg | `addr` |
| `mem_wr_en` | 选择读/写通道 | 控制 rd/wr 通道选择 |
| `mem_wdata[511:0]` | 拆分为 16×32bit data_buffer | `wdata_i[31:0]`（逐拍） |
| `mem_req_ready` | FSM 在 IDLE 时且适配器可接收时拉高 | `rd_req_ready` / `wr_req_ready` |
| `mem_resp_valid` | 所有 beat 完成时拉高 | `read_done` / `write_done` |
| `mem_rdata[511:0]` | 从 16×32bit buffer 拼接输出 | `rdata_o[31:0]`（逐拍收集） |
| `mem_resp_ready` | 响应被 cache 接收 | — |

### 3.3 内部存储

```verilog
reg [31:0] data_buffer [0:15];   // 16-word buffer，用于拆/拼 line 数据
reg [4:0]  beat_counter;         // 逐拍计数（0~15）
reg        bridge_busy;          // 忙标志，控制 mem_req_ready
```

### 3.4 读操作状态机

```
IDLE:
  if mem_req_valid && !mem_wr_en:   // 读 miss
    锁存 addr → addr_reg
    rd_req_valid = 1, addr = addr_reg, burst_len=15, burst_size=2, burst_type=INCR
    bridge_busy = 1
    跳转 → RD_ADDR_WAIT

  else:
    mem_req_ready = 1（空闲时可接收新请求）

RD_ADDR_WAIT:
  if rd_req_ready:                   // AXI 接受地址
    rd_req_valid = 0
    beat_counter = 16
    跳转 → RD_DATA_COLLECT

  else:
    保持 rd_req_valid

RD_DATA_COLLECT:
  if rdata_valid:                    // 每拍数据到来
    data_buffer[16 - beat_counter] = rdata_o
    beat_counter--
    if beat_counter == 0:            // 16 拍收齐
      等待 read_done（寄存一拍）
      跳转 → RD_DONE

RD_DONE:
  mem_rdata = {data_buffer[15], data_buffer[14], ..., data_buffer[0]}
  mem_resp_valid = 1
  if mem_resp_ready:
    bridge_busy = 0
    跳转 → IDLE
```

### 3.5 写操作状态机

```
IDLE:
  if mem_req_valid && mem_wr_en:     // 写回
    锁存 addr → addr_reg
    拆分 mem_wdata[511:0] → data_buffer[0..15]
    wr_req_valid = 1, addr = addr_reg, burst_len=15, ...
    bridge_busy = 1
    跳转 → WR_ADDR_WAIT

WR_ADDR_WAIT:
  if wr_req_ready:
    wr_req_valid = 0
    beat_counter = 16
    跳转 → WR_DATA_SEND

WR_DATA_SEND:
  wdata_valid = 1
  wdata_i = data_buffer[16 - beat_counter]
  if wdata_ready:                    // 每拍被接受
    beat_counter--
    if beat_counter == 0:
      wdata_valid = 0
      跳转 → WR_RESP_WAIT

WR_RESP_WAIT:
  if write_done:
    跳转 → WR_DONE

WR_DONE:
  mem_resp_valid = 1
  if mem_resp_ready:
    bridge_busy = 0
    跳转 → IDLE
```

### 3.6 关键时序考虑

- `mem_req_ready` 必须在 `bridge_busy=0` 且 AXI 适配器有空闲槽位时才能拉高
- 读数据 FIFO（适配器内部）深度为 64 拍，足以缓冲一次完整的 16 拍 burst
- Bridge 不需要额外 FIFO，data_buffer 即可完成拆/拼

---

## 4. TLM 带宽模拟方案

### 4.1 Level 1：统计级（快速验证）

**修改位置**：`TLM/MEM/sparse_memory.cpp` → `b_transport`

**核心逻辑**：在响应给 cache 之前，根据传输长度累加等效 AXI 周期数。

```cpp
// 在 sparse_memory::b_transport 末尾，返回前添加：

unsigned int data_len = trans.get_data_length();
unsigned int axi_beat_size = 4;                           // 32-bit AXI = 4 bytes
unsigned int num_beats = data_len / axi_beat_size;        // 64/4 = 16

// 累加时序：1 地址拍 + N 数据拍
sc_time axi_timing(1 + num_beats, SC_NS);                 // 假设 1ns/cycle
delay += axi_timing;

// 累加统计
stats.total_axi_beats += num_beats;
stats.total_axi_transactions++;
```

**优点**：修改量小，立即运行，快速获得带宽 baseline。
**缺点**：无法区分读/写通道差异，无法建模反压。

### 4.2 Level 2：逐拍级（精确建模）

**新建模块**：`TLM/AXI/axi_bus_channel.h` 和 `TLM/AXI/axi_bus_channel.cpp`

#### 模块定义

```cpp
class AXI_Bus_Channel : public sc_core::sc_module {
public:
    // TLM 接口
    tlm_utils::simple_target_socket<AXI_Bus_Channel> cache_side_socket;
    tlm_utils::simple_initiator_socket<AXI_Bus_Channel> mem_side_socket;

    // 可配置参数
    unsigned int data_width    = 32;    // AXI 数据位宽
    unsigned int addr_cycles   = 1;     // 地址通道延迟（周期数）
    unsigned int beat_cycles   = 1;     // 每拍数据延迟
    unsigned int resp_cycles   = 1;     // 写响应通道延迟
    double       clock_period  = 1.0;   // 时钟周期（ns）
    bool         backpressure_enabled = false;
    double       backpressure_prob    = 0.1;  // 反压概率
    unsigned int bp_max_cycles         = 3;     // 最大反压周期数

    // 构造函数
    AXI_Bus_Channel(sc_module_name name, unsigned int dw = 32);

    // b_transport 实现
    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay);

private:
    // 统计信息
    struct AXIStats {
        unsigned long long total_cycles   = 0;
        unsigned long long busy_cycles    = 0;
        unsigned long long total_beats    = 0;
        unsigned long long total_bytes    = 0;
        unsigned long long total_bursts   = 0;
        unsigned long long addr_cycles    = 0;
        unsigned long long data_cycles    = 0;
        unsigned long long resp_cycles    = 0;
        unsigned long long stall_cycles   = 0;
        unsigned long long idle_cycles    = 0;

        // 总线利用率
        double utilization() const {
            return (double)busy_cycles / total_cycles;
        }
        // 平均 burst 长度（拍数）
        double avg_burst_len() const {
            return (double)total_beats / total_bursts;
        }
        // 有效吞吐量（MB/s）
        double throughput_MBps(double clk_period_ns) const {
            double time_us = total_cycles * clk_period_ns / 1000.0;
            return (double)total_bytes / time_us;
        }
        // 反压占比
        double stall_ratio() const {
            return (double)stall_cycles / data_cycles;
        }
    } stats;
};
```

#### 核心传输逻辑

```cpp
void AXI_Bus_Channel::b_transport(
    tlm::tlm_generic_payload& trans, sc_time& delay
) {
    bool is_write = (trans.get_command() == TLM_WRITE_COMMAND);
    unsigned int data_len = trans.get_data_length();
    unsigned int beat_size = data_width / 8;          // 4 bytes
    unsigned int num_beats = data_len / beat_size;     // 16

    stats.total_bursts++;
    stats.total_beats += num_beats;
    stats.total_bytes += data_len;

    // 阶段 1：地址通道（AR 或 AW）
    delay += sc_time(addr_cycles * clock_period, SC_NS);
    stats.addr_cycles += addr_cycles;

    // 阶段 2：数据通道 - 逐拍传输
    for (unsigned int i = 0; i < num_beats; i++) {
        delay += sc_time(beat_cycles * clock_period, SC_NS);

        // 可选：模拟反压
        if (backpressure_enabled) {
            std::mt19937_64 rng(std::random_device{}());
            if ((double)(rng() % 100) / 100.0 < backpressure_prob) {
                unsigned int wait = 1 + (rng() % bp_max_cycles);
                delay += sc_time(wait * clock_period, SC_NS);
                stats.stall_cycles += wait;
            }
        }
    }
    stats.data_cycles += num_beats * beat_cycles;

    // 阶段 3：写响应通道（仅写操作）
    if (is_write) {
        delay += sc_time(resp_cycles * clock_period, SC_NS);
        stats.resp_cycles += resp_cycles;
    }

    // 阶段 4：转发给真实 memory
    sc_time mem_delay = SC_ZERO_TIME;
    mem_side_socket->b_transport(trans, mem_delay);
    delay += mem_delay;

    // 更新总线统计
    stats.busy_cycles = stats.addr_cycles + stats.data_cycles
                      + stats.resp_cycles + stats.stall_cycles;
}
```

#### 连接拓扑

```cpp
// 在 testbench.cpp 的 sc_main 中：
CpuInitiator cpu("cpu");
CacheParams cache_params(4, 4, 16);
Cache_tlm_model cache("cache", cache_params);
AXI_Bus_Channel axi_bus("axi_bus", 32);      // 32-bit AXI
Sparse_Memory memory("memory", 4096, 10);

cpu.init_socket.bind(cache.cpu_socket);
cache.mem_socket.bind(axi_bus.cache_side_socket);
axi_bus.mem_side_socket.bind(memory.mem_receive_socket);
```

### 4.3 统计输出示例

仿真结束时打印：

```
=== AXI Bus Channel Statistics ===
Total cycles:       123456
Busy cycles:        76543
Idle cycles:        46913
  ├─ Addr cycles:   2345
  ├─ Data cycles:   69136
  ├─ Resp cycles:   1234
  └─ Stall cycles:  3828

Bus utilization:    62.0%
Avg burst length:  15.8 beats
Throughput:        891.2 MB/s
Stall ratio:        5.5%
==================================
```

---

## 5. 参数扫描计划

### 5.1 测试矩阵

| 测试名 | AXI_DATA_WIDTH | beat_cycles | slave_latency | backpressure | 预期 bus_utilization |
|--------|---------------|-------------|---------------|--------------|---------------------|
| 基线 | 32 | 1 | 0 | 否 | 60-80% |
| 宽总线 | 64 | 1 | 0 | 否 | 30-40% |
| 宽总线 128 | 128 | 1 | 0 | 否 | 15-25% |
| 慢总线 | 32 | 2 | 0 | 否 | 80-95% |
| 有延迟 | 32 | 1 | 5 | 否 | 40-60% |
| 有反压 | 32 | 1 | 0 | 是(10%) | 65-85% |
| 最坏情况 | 32 | 2 | 5 | 是(10%) | >90% |

### 5.2 瓶颈判断标准

| bus_utilization | 判断 |
|----------------|------|
| > 90% | AXI 带宽是瓶颈，需增加 data_width 或降低 beat_cycles |
| 60-90% | 带宽接近饱和，需关注 stall_ratio |
| 30-60% | 带宽充裕，当前设计合理 |
| < 30% | 带宽绰绰有余，可考虑缩小 data_width 以节省面积 |

### 5.3 TLM 参数与 RTL 参数的对应关系

| TLM 参数 | RTL 对应 | 说明 |
|----------|---------|------|
| `data_width` | `AXI_DATA_WIDTH` | 两者一致即可对齐 |
| `beat_cycles` | AXI slave 的 wready/rready 反压 | 模拟从机忙时插入等待周期 |
| `slave_latency` | memory controller 延迟 | 对应 configurable_delay_mem 的 latency_in |
| `backpressure` | 随机 wready/rready 抖动 | 模拟总线仲裁/竞争 |

---

## 6. 实施路线图

### Phase 1: TLM Level 1 快速验证（1 天）

1. 在 `sparse_memory.cpp` 中添加 AXI beats 时序累加
2. 添加基础统计计数器
3. 运行现有 testbench，确认时序影响
4. 在 32/64/128 bit data_width 下跑参数扫描

### Phase 2: TLM Level 2 精确建模（2 天）

1. 新建 `TLM/AXI/axi_bus_channel.h/.cpp`，实现逐拍传输逻辑
2. 实现反压模拟和统计收集
3. 集成到 `testbench.cpp` 的连接拓扑中
4. 跑完整参数扫描矩阵，收集 `bus_utilization` 等指标

### Phase 3: RTL Bridge 设计（3 天）

1. 编写 `Design/AXI/cache_axi_bridge.v`，实现读/写状态机
2. 编写 standalone 测试 bench 验证 bridge 单独工作
3. 在 UVM 环境中例化 bridge + AXI 适配器 + Cache
4. 运行所有 directed test（读/写 hit/miss，multi write, fifo fill 等）

### Phase 4: 联合仿真与回归（2 天）

1. 在 UVM 中配置 AXI slave model（替代 configurable_delay_mem）
2. 运行 random test 验证长时间稳定性
3. 对比 RTL 和 TLM 的 bandwidth metrics 一致性
4. 更新验证计划文档

---

## 附录 A：相关文件索引

| 文件 | 用途 |
|------|------|
| `Architecture/Cache_Technical_Report.md` | Cache 架构文档 |
| `Design/Cache/D_Cache.v` | D-Cache RTL |
| `Design/Cache/I_cache.v` | I-Cache RTL |
| `Design/AXI/axi_master_micro_adapter.v` | AXI 适配器顶层 |
| `Design/AXI/axi_master_micro_read_adapter.v` | AXI 读通道适配器 |
| `Design/AXI/axi_master_micro_write_adapter.v` | AXI 写通道适配器 |
| `Design/AXI/sync_fifo.v` | 同步 FIFO |
| `Design/memory_model/configurable_delay_mem.sv` | RTL 内存行为模型 |
| `verif_env/src/common/define/define.svh` | 全局参数配置 |
| `TLM/Cache/cache_tlm.h/.cpp` | TLM Cache 模型 |
| `TLM/MEM/sparse_memory.h/.cpp` | TLM 内存模型 |
| `TLM/test/testbench.h/.cpp` | TLM 测试平台 |
| `TLM/Makefile` | TLM 编译脚本 |

## 附录 B：TCL 脚本示例（VCS 编译 RTL Bridge）

```tcl
# dut.f 中添加
../Design/AXI/cache_axi_bridge.v
```

```makefile
# Makefile 中增加 bridge 测试目标
run_bridge_test:
    vlogan -sverilog ../simple_test/tb_cache_axi_bridge.sv
    vlogan -sverilog ../Design/AXI/cache_axi_bridge.v
    vcs -debug_access+all tb_cache_axi_bridge
    ./simv
```
