# DCACHE-CHECK-001：CPU响应与参考模型相差一拍

日期：2026-11-25。状态：**设计方已修正原C++顶层模型的响应FIFO同步读延迟；真实DUT四组UVM复核全部通过，本差异按当前基础场景关闭。**

当前DCache生成及低有效resetn端口检查均通过，真实RTL的默认空态启动在10 ns/4 ns通过。smoke完成全部请求，但逐拍CPU响应valid与C++模型不一致。

## 修复前的公开 IO 证据

smoke在地址0x1000依次提交读ID0、写0x12345678/ID1、读ID2。10 ns时钟的实际请求接受时间为75、95、115 ns。

| 返回 | 模型valid时间 | DUT实际握手时间 | 实际结果 |
| --- | --- | --- | --- |
| 读ID0 | 145 ns | 155 ns | 数据0 |
| 写ID1 | 155 ns | 165 ns | ID1 |
| 读ID2 | 165 ns | 175 ns | 数据0x12345678 |

4 ns也表现为一拍差异。实际CPU结果与这三笔原始激励的顺序语义相符，最终计数为3请求、2读响应、1写响应；原模型逐拍valid比较仍不通过，不能凭最终完成就关闭时序差异。

## 已确认并修正的DV问题

原scoreboard在仅模型valid为1、DUT valid为0时还比较DUT载荷，产生无效X/旧值的附带错误。已改为仅双方valid均为1时比较载荷，valid本身仍逐拍严格比较。修正后每个smoke只剩6次CPU响应valid差异，没有把整体结果改成PASS。

当时新增DCACHE_CPU_TRACE记录实际请求和响应握手，用于按ID/数据定位差异。当时的诊断仅依据公开 IO，未读取 DUT 内部实现，归因尚未确定。后续源码检查和模型修改见下文；原 valid 检查不应因此被屏蔽。

## 修改前的运行证据

[修改前报告](../../verif_mshr/sim_dcache/work/framework/run_20261125_100532/summary.md)：base两时钟PASS，smoke两时钟FAIL。

[10 ns日志](../../verif_mshr/sim_dcache/work/framework/run_20261125_100532/dcache_smoke_test_p10.log) / [波形](../../verif_mshr/sim_dcache/work/framework/run_20261125_100532/dcache_smoke_test_p10.fsdb)。报告目录另有4 ns日志、FSDB、输入哈希和生成/编译日志。

上述 FAIL 是模型修改前的历史结果。模型修改后尚未回归，不能把历史结果改标为 PASS。

## 已确认的结构差异

[设计顶层](../../Design/DCacheMSHR/src/main/scala/furina/dcache/DCache.scala)的读写响应分别使用默认 StreamFifo。检查实际生成的 `Design/DCacheMSHR/rtl/DCache.v`，发现队列存储使用时钟沿同步读，队首数据进入读出寄存器，对应 valid 也经过寄存。空队列接受响应后，先变成非空，再在后续时钟沿完成读取，CPU 才能接受响应。

原 [C++ CacheTop 模型](../../RefModel/Cache/CacheTop.hpp)直接使用 `!readQ_.empty()`、`readQ_.front()` 产生读响应，写队列同理。tick 中入队后，下次 eval 就能直接观察队首，没有同步读出的那一拍。这是能解释记录中整齐一拍偏移的明确模型差异。CacheMem 的 R1/R2 同步读已有建模，这次补的是 CPU 响应队列的存储读出阶段。

这里确认的是源码结构差异；本次没有访问验证文件夹，未检查 DPI 的采样/推进是否还有独立问题，也没有证明其他顶层时序全部一致。

## 本次模型修改

修改文件：`RefModel/Cache/CacheTop.hpp`。没有修改 Scala 设计。

- 读写队列各增加输出寄存器及有效位：readOut_/readOutValid_、writeOut_/writeOutValid_。
- CPU 响应由输出寄存器产生；输出有效且 ready 为0时保持数据和 valid。
- tick 先从沿前已有的队列内容进行同步读出，再处理本沿新入队响应，避免把新响应直接旁路到输出。
- 输出为空或旧响应被接受时，可以加载下一笔已有响应，支持已有积压下的连续输出。
- 总容量按“尚未读出的队列项数 + 有效输出寄存器”计算，预取本身不释放容量；仅实际 CPU 接受响应才释放位置。满判断、队列数量查询和诊断输出同步使用这个计数，避免无意增加一项容量。
- reset 清空新增数据和有效状态。深度为1时保留 StreamFifo 单寄存器的路径，不另加同步读级。

这次修改对响应 FIFO 的行为建模，不是在比较器上统一延迟输出，也没有放宽 valid 检查。其他顶层准入和冻结策略不在本次修改范围内。

## 编译结果和待确认事项

已用 `g++ -std=c++17 -Wall -Wextra -c` 编译包含 CacheTop.hpp 的编译单元，并显式实例化默认 FIFO 替换策略的 CacheTopT，编译通过；修改文件的空白差异检查通过。

本次未运行测试或仿真，未访问验证文件夹。尚不能认定 DCACHE-CHECK-001 已解决。后续由用户重新编译使用新头文件的仿真程序，确认没有链接旧 DPI 对象，再回归检查原三笔响应、空到非空、连续响应、背压保持、满槽与释放、复位等场景。编译通过只证明本次源码可编译，不代替功能及时序验证。

## 问题修改记录约定

每次发现问题并作相关修改，都在对应 DebugNote 中记录：问题与依据、修改文件和方法、实际完成的检查、当前结果及尚未确认的部分。无论修改已经验证有效、只通过编译，还是尝试后仍未解决，都保留记录；没有新验证证据时，不将问题自动标为已解决。


## 修复后UVM复核

[最新四组报告](../../verif_mshr/sim_dcache/work/framework/run_20261125_104508/summary.md)：重新生成RTL并冷编译当前模型，base/smoke在10 ns及4 ns均PASS，UVM warning/error/fatal均为0。smoke仍提交原两读一写，CPU请求与响应计数分别为3/2/1，原逐拍valid及有效载荷比较通过。验证侧未延迟模型期望、未屏蔽差异，也未改变case激励；旧失败记录保留为历史。
