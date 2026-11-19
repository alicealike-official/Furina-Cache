# 稀疏内存 C++ 模型

`dcache::SparseMemory` 定义于 `SparseMemory.hpp`，使用 C++17 和 Cache 模型公共类型。
没有 SystemC、TLM、线程、时钟或延迟调度依赖。
旧实现及其 testbench/helper 已归档到 `RefModel/legacy/systemc`，不参与有效构建。

## API

| 接口 | 语义 |
| --- | --- |
| `SparseMemory(pageSize = 4096)` | 页面大小为正的2次幂，否则抛 invalid_argument |
| `read(uint64_t addr, uint8_t* dst, size_t size) const` | 字节区间读取；未分配区域读零，不分配页面 |
| `write(uint64_t addr, const uint8_t* src, size_t size)` | 字节区间写入，按需分配页面，支持跨任意多页 |
| `readLine(Addr)` / `writeLine(Addr, const Line&)` | Cache公共Line类型，要求块对齐 |
| `reset()` | 释放所有页面，回到全零逻辑内存 |
| `allocatedPages()` / `pageSize()` | 观测分配页数与页面大小 |

字节接口为64位地址；整行接口使用当前32位 `Addr`。
地址区间不能发生64位溢出；长度为零时允许空指针且不做操作。
非零长度的空指针、未对齐整行访问会抛异常，调用者负责处理。
每字显式按低字节在低地址转换，不依赖CPU主机端序。
最低字节地址对应 `Line[0][7:0]`，也对应 SV packed line 的 `[7:0]`。

本模型是数据存储，不提供 `tick()`。在 UVM 中，写请求握手时写入，
响应时刻由 memory agent 调度；其他C++使用者同样自行管理时间。

```sh
make -C RefModel run-memory
make -C RefModel run-dpi
make -C RefModel run-wbb
```

`run-memory` 覆盖跨页读写、初值、覆盖写、实例隔离、字节顺序、reset和非法参数。
`run-dpi` 检查 C ABI 参数匹配、模型沿前输出/沿后更新、数据和句柄生命周期。
这些是模型/适配检查，不是新增加的 WBB RTL 功能测试用例。

## 后续可选扩展

2026-11-18 已确认当前职责划分可接受：`SparseMemory` 负责存储访问，
UVM memory driver 负责请求握手、响应延迟和响应信号驱动。

- [ ] 后续评估增加内存总线控制层，复用现有稀疏存储核心，处理请求接收和响应生成。
  可讨论的内容包括握手与反压、请求 ID、在途事务及响应时序。
  具体总线协议、控制层放在 C++ 还是 SV、与现有 memory driver 的分工，留待后续确定。

此项作为后续讨论记录，尚未排入当前实现范围。
