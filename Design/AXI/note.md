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