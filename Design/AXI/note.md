# AXI信号:



## 全局信号
| 信号名 | 位宽 | 源头 | 描述 |
| :--- | :--- | :--- | :--- |
| ACLK | 1 | 时钟源 | 全局时钟，所有信号在上升沿采样 |
| ARESETn | 1 | 复位源 | 全局复位，低电平有效 |

---

## 低功耗接口(可选)
| 信号名 | 位宽 | 源头 | 描述 |
| :--- | :--- | :--- | :--- |
| CCLKEN | 1 | 总线时钟 | 时钟使能信号 |
| CSYSREQ | 1 | 系统时钟控制器 | 系统低功耗请求 |
| CSYSACK | 1 | 外设 | 低功耗请求确认 |
| CACTIVE | 1 | 外设 | 时钟活跃指示 |

---


## 写地址通道(AW)
| 信号名 | 位宽 | 源头 | 描述 |
| :--- | :--- | :--- | :--- |
| AWID | 可配置(如4位) | Master | 写地址ID，标识一组写事务 |
| AWADDR | 可配置(如32位) | Master | 写起始地址 |
| AWLEN | 8位 | Master | 突发长度，实际长度 = AWLEN + 1 |
| AWSIZE | 3位 | Master | 突发大小，每拍字节数 = 2^AWSIZE |
| AWBURST | 2位 | Master | 突发类型(FIXED/INCR/WRAP) |
| AWLOCK | 1位(AXI4) | Master | 原子操作锁定 |
| AWCACHE | 4位 | Master | 内存类型(缓存/缓冲策略) |
| AWPROT | 3位 | Master | 保护类型(特权/安全/数据/指令) |
| AWQOS | 4位 | Master | 服务质量标识符 |
| AWREGION | 4位 | Master | 区域标识符，单物理接口的多逻辑接口 |
| AWUSER | 用户自定义 | Master | 用户自定义扩展信号 |
| AWVALID | 1 | Master | 写地址有效，指示地址和控制信息已就绪 |
| AWREADY | 1 | Slaver  | 写地址就绪，从机准备好接收地址信息 |

---

## 写数据通道(W)
| 信号名 | 位宽 | 源头 | 描述 |
| :--- | :--- | :--- | :--- |
| WDATA | 可配置(如32/64位) | Master | 写数据 |
| WSTRB | WDATA_WIDTH/8 | Master | 写选通，每比特对应一字节有效标志 |
| WLAST | 1 | Master | 最后一拍指示，标识当前为突发最后一拍数据 |
| WUSER | 用户自定义 | Master | 用户自定义扩展信号 |
| WVALID | 1 | Master | 写数据有效，指示数据已就绪 |
| WREADY | 1 | Slaver  | 写数据就绪，从机准备好接收数据 |

---

## 写响应通道(B)
| 信号名 | 位宽 | 源头 | 描述 |
| :--- | :--- | :--- | :--- |
| BID | 可配置(如4位) | Slaver  | 写响应ID，与对应的AWID匹配 |
| BRESP | 2位 | Slaver  | 写响应状态(OKAY/EXOKAY/SLVERR/DECERR) |
| BUSER | 用户自定义 | Slaver  | 用户自定义扩展信号 |
| BVALID | 1 | Slaver  | 写响应有效，指示响应已就绪 |
| BREADY | 1 | Master | 写响应就绪，主机准备好接收响应 |

---

## 读地址通道(AR)
| 信号名 | 位宽 | 源头 | 描述 |
| :--- | :--- | :--- | :--- |
| ARID | 可配置(如4位) | Master | 读地址ID，标识一组读事务 |
| ARADDR | 可配置(如32位) | Master | 读起始地址 |
| ARLEN | 8位 | Master | 突发长度，实际长度 = ARLEN + 1 |
| ARSIZE | 3位 | Master | 突发大小，每拍字节数 = 2^ARSIZE |
| ARBURST | 2位 | Master | 突发类型(FIXED/INCR/WRAP) |
| ARLOCK | 1位(AXI4) | Master | 原子操作锁定 |
| ARCACHE | 4位 | Master | 内存类型(缓存/缓冲策略) |
| ARPROT | 3位 | Master | 保护类型(特权/安全/数据/指令) |
| ARQOS | 4位 | Master | 服务质量标识符 |
| ARREGION | 4位 | Master | 区域标识符，单物理接口的多逻辑接口 |
| ARUSER | 用户自定义 | Master | 用户自定义扩展信号 |
| ARVALID | 1 | Master | 读地址有效，指示地址和控制信息已就绪 |
| ARREADY | 1 | Slaver  | 读地址就绪，从机准备好接收地址信息 |

---

## 读数据通道(R)
| 信号名 | 位宽 | 源头 | 描述 |
| :--- | :--- | :--- | :--- |
| RID | 可配置(如4位) | Slaver  | 读数据ID，与对应的ARID匹配 |
| RDATA | 可配置(如32/64位) | Slaver  | 读回的数据 |
| RRESP | 2位 | Slaver  | 读响应状态(OKAY/EXOKAY/SLVERR/DECERR) |
| RLAST | 1 | Slaver  | 最后一拍指示，标识当前为突发最后一拍数据 |
| RUSER | 用户自定义 | Slaver  | 用户自定义扩展信号 |
| RVALID | 1 | Slaver  | 读数据有效，指示数据已就绪 |
| RREADY | 1 | Master | 读数据就绪，主机准备好接收数据 |

# AXI 读适配器 Outstanding 机制笔记

---

## 一、整体架构：三大组件

读适配器内部由三个核心模块协同工作：

| 组件 | 功能 |
|------|------|
| **命令 FIFO** (`u_cmd_fifo`) | 暂存上游发来的读事务请求（地址、长度、ID 等），实现请求入口与地址发送的速率解耦 |
| **事务槽表** (`entry_*` 寄存器组) | 记录每个正在 AXI 总线上执行的事务状态（ID、剩余拍数、错误），支持最多 `MAX_OSD` 个事务并发跟踪 |
| **读数据 FIFO** (`u_rdata_fifo`) | 缓存从 AXI R 通道返回的数据，实现数据接收与下游取走的异步解耦 |

```
        start_read & rd_req_ready
                │
                ▼
         ┌──────────┐
         │ 命令 FIFO │    ← 缓存待发送的读地址
         └────┬─────┘
              │ 弹出 (pop)
              ▼
         AR 状态机 ───────────► AXI AR 通道 (发送地址)
              │                       │
              │ 分配槽位               │ 握手成功
              ▼                       ▼
         ┌──────────┐          ┌──────────┐
         │ 事务槽表  │◄─────────┤ R 通道   │  数据返回 (RID/RDATA/RLAST)
         └────┬─────┘          └────┬─────┘
              │ 释放槽位            │ 数据写入
              │                     ▼
              │              ┌──────────┐
              │              │ 读数据FIFO│ → rdata_o/rdata_valid
              │              └──────────┘
              │
              ▼
         read_done / error_resp
```

---

## 二、Outstanding 如何实现

**Outstanding = 多个未完成事务并发**。该适配器通过 **命令 FIFO + 事务槽表** 的双重解耦实现。

### 2.1 命令 FIFO —— 请求与发送的解耦

- 上游只要 `rd_req_ready` 为高（FIFO 未满且有空闲槽位），就可以连续发送读请求。
- 请求被打包后写入命令 FIFO，**不关心 AR 通道是否忙碌**。
- AR 状态机按照自己的节奏从 FIFO 中取出命令发送，只要 FIFO 非空且有空闲槽位即可。
- FIFO 深度为 `MAX_OSD`，可以暂存最多 4 个等待发送的请求。

### 2.2 事务槽表 —— 多事务独立跟踪

- 事务槽表是一个寄存器组，共有 `MAX_OSD` 个“槽位”，每个槽位记录一个已发出但尚未完成的事务。
- 每个槽位包含：
  - `entry_valid` ：该槽位是否被占用
  - `entry_id` ：事务的 AXI ID
  - `entry_len`：剩余数据拍数（初始为突发长度）
  - `entry_err`：最终错误响应
- **分配时机**：AR 通道握手成功（地址被从设备接受）时，从命令 FIFO 弹出命令，同时分配一个空闲槽位，将 `ar_id_r`、`ar_len_r` 写入。
- **跟踪过程**：R 通道每返回一拍数据，根据 `RID` 匹配对应槽位，将其 `entry_len` 减 1。
- **释放时机**：最后一拍数据（`RLAST=1`）握手成功后，清除该槽位的 `entry_valid`。

因为槽位是独立更新的，所以多个事务可以同时存在于总线上，无论它们的响应顺序如何。

---

## 三、AR 通道与 R 通道的交接

### 3.1 AR 通道：发送地址 & 分配槽位

**状态机**：`AR_IDLE` ↔ `AR_SEND`

```verilog
// AR_IDLE 状态下，满足条件则装载命令并跳转
if (!cmd_fifo_empty && (|(~entry_valid))) begin
    m_axi_arid_r    <= cmd_id;
    m_axi_araddr_r  <= cmd_addr;
    m_axi_arlen_r   <= cmd_len;
    m_axi_arsize_r  <= cmd_size;
    m_axi_arburst_r <= cmd_burst;
    m_axi_arvalid_r <= 1'b1;
    ar_next_state = AR_SEND;
end
```

- **条件**：命令 FIFO 非空且事务槽表有空闲位。
- **动作**：将当前 FIFO 队首的命令信息锁存到 AR 输出寄存器，并将 `arvalid` 置为有效。
- **握手成功**（`arvalid & arready`）时：
  ```verilog
  cmd_fifo_pop = (ar_cur_state == AR_SEND) && m_axi_arhandshake;
  ```
  命令从 FIFO 中移除，同时 `entry_allocate = cmd_fifo_pop` 触发槽位分配：
  ```verilog
  entry_valid <= entry_valid | free_mask;
  entry_id[空闲位]   <= m_axi_arid_r;   // 锁存的 ID
  entry_len[空闲位]  <= m_axi_arlen_r;  // 初始突发长度
  ```

**交接关系**：  
AR 通道将“事务身份（ID）”和“预期数据量（长度）”移交给事务槽表，由槽表负责跟踪后续数据返回。

### 3.2 R 通道：数据返回 & 槽位更新/释放

R 通道每拍返回 `RID`, `RDATA`, `RRESP`, `RLAST`。

- **反压控制**：`m_axi_rready = !rdata_fifo_full;` 只要读数据 FIFO 未满就接收。
- **数据缓存**：握手成功的数据立即写入读数据 FIFO（`rdata_fifo_din = m_axi_rdata`）。
- **槽位更新**：同一拍，根据 `RID` 匹配槽位：
  ```verilog
  rdata_match = find_by_id(m_axi_rid);
  if (m_axi_rhandshake) begin
      if (rdata_match[k] && entry_valid[k]) begin
          entry_len[k] <= entry_len[k] - 1;
          if (m_axi_rlast)
              entry_err[k] <= m_axi_rresp;
      end
  end
  ```
- **事务完成**：当 `RLAST` 握手成功时，`read_done_condition` 被触发：
  ```verilog
  read_done_condition = m_axi_rhandshake && m_axi_rlast && (|rdata_match);
  ```
  - 产生 `read_done` 脉冲（寄存器输出）。
  - 释放对应槽位：`release_mask = rdata_match`，`entry_valid <= entry_valid & ~release_mask`。
  - 输出错误响应：`error_resp <= entry_err[匹配位]`。

**交接完成**：R 通道通过 `RID` 告知槽表“哪个事务的数据到了”，槽表完成最后一拍记录后，移交完成信号给上游。

---

## 四、Outstanding 流程实例（MAX_OSD=4）

假设上游连续发送 4 个读请求（ID=A, B, C, D），每个突发长度=16。

| 时间 | AR 通道 | 命令 FIFO | 事务槽表 | R 通道 | 说明 |
|------|---------|-----------|----------|--------|------|
| T1 | 发地址 A | 弹出 A | 分配槽0 (ID=A, len=16) | — | 第一个事务启动 |
| T2 | 发地址 B | 弹出 B | 分配槽1 (ID=B, len=16) | — | 第二个事务启动 |
| T3 | 发地址 C | 弹出 C | 分配槽2 (ID=C, len=16) | — | 第三个事务启动 |
| T4 | 发地址 D | 弹出 D | 分配槽3 (ID=D, len=16) | — | 第四个事务启动，槽表满 |
| T5 | **等待** (槽表满) | 暂存新请求？FIFO 可能空 | 4个槽位全部占用 | 返回数据 (ID=B, 第1拍) | B 开始返回数据 |
| T6 | **等待** | — | 槽1 len=15 | 返回数据 (ID=A, 第1拍) | A 也开始返回 |
| ... | ... | ... | ... | ... | 多个事务交替返回数据 |
| Txx | — | — | 槽1 len=0 (最后一拍) | ID=B 最后一拍握手 | B 完成，释放槽1 |
| Txx+1 | 发地址 E (如果 FIFO 有新请求) | 弹出 E | 分配槽1 (ID=E) | — | 槽1 被新事务重用 |

- **Outstanding 体现**：在 T4～Txx 之间，4 个事务的数据同时在总线上返回，地址通道可以空闲或发送新请求（一旦有空槽）。
- **顺序无关**：R 通道返回的数据顺序（A、B、C、D）不必与发送顺序一致，槽表通过 `find_by_id` 实现乱序匹配。

---

## 五、关键设计要点

1. **双重背压**  
   `rd_req_ready = !cmd_fifo_full && (|(~entry_valid))`  
   上游只有在 FIFO 有余量且槽表有空位时才能发送新请求，避免丢失请求或槽位溢出。

2. **AR 预装载**  
   `ar_id_r` 等在 `AR_IDLE→AR_SEND` 时锁存，使得握手当拍槽表分配时使用的是稳定的值，消除了组合逻辑延迟。

3. **读数据 FIFO 解耦**  
   AXI R 通道数据先进入 FIFO，下游通过 `rdata_o/rdata_valid` 读取，即使下游暂停取数也不会阻塞总线（只要 FIFO 未满）。

4. **完成信号寄存**  
   `read_done` 寄存器输出，避免组合逻辑毛刺，确保干净的一周期脉冲。

---

## 六、总结

**Outstanding 的核心 = 命令 FIFO（流水线缓冲） + 事务槽表（独立状态跟踪）**  
- FIFO 让请求可以提前入队，不阻塞地址通道。  
- 槽表让多个事务可以同时存在于总线上，各自独立推进。  
- AR 与 R 通道通过 ID 进行“交接”，完成地址到数据的映射。  

这种结构可以轻松扩展到任意 `MAX_OSD`，实现高吞吐的 AXI 读操作。