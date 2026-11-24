# MSHR-DUT-001：replay受阻时被新候选替换

日期：2026-11-24。状态：**设计方修复后重新生成RTL，52/52完整回归通过；按当前配置关闭。**

最初的问题报告依据规格与公开 IO 确认接口违约。随后已检查设计源码和参考模型，根因与修复记录如下；后文保留修复前的复现过程及历史证据。

## 已确认的实现问题

问题位于 [Mshr.scala 的 replay 仲裁](../../Design/DCacheMSHR/src/main/scala/furina/dcache/Mshr.scala)。原逻辑根据当前候选组合计算 rotK 和 replayIdx，然后直接选择该 Entry 当前 Slot 的类型、CPU ID 和数据，没有保持已经被背压的选择。

Entry3 挂起时，Entry0 接受 fill，使 entryFillDone(0) 在沿后置位，Entry0 随即成为重放候选。从轮询起点0重新扫描时，选择由 Entry3 变成 Entry0。fill 接受是合法事件，但它不能替换尚未握手的 replay。这里 rotK 只是候选相对扫描起点的偏移，计算本身没有出错，缺少的是输出选择保持。

entryReplayCnt 和 rrPtr 原本都只在 replay 握手后更新，没有提前推进。保持计数只能保证某个 Entry 内部没有换到下一个 Slot，不能保证出口仍选这个 Entry。因此本问题不是 Slot 计数提前增加，也不是旧 Slot 数据被覆盖。记录中的 CPU ID 0→24 与 Entry 3→0 是两种不同编号。

[MSHR.hpp](../../RefModel/Cache/MSHR.hpp) 的 pickReplay() 原来同样每次重新扫描候选，因此 DUT 与模型都可能切换到 Entry0。模型比对一致不能证明满足保持协议，独立 SVA 据此发现了违约。

## 已采用的解决方法

设计增加 replayHold 和 replayHoldIdx，把组合候选与实际输出选择分开。首次出现 replay.valid 且非 replay.ready 时记住当前 Entry；保持期间始终输出该 Entry 的当前 Slot。真正握手时才解除保持，并对实际输出的 Entry 推进重放计数、更新轮询指针；若是最后一个 Slot，则沿用原有释放 Entry 和锁的逻辑。复位清除新增保持状态。

合法协议下 FILL 条目不再合并，Slot 内容不再变化，重放计数也仅在握手后推进，所以保持 Entry 索引即可保持当前 Slot 的响应，无需另存一份载荷。其他 Entry 完成 fill 后仍可进入候选，但必须等挂起响应被接受后再参与出口选择。

参考模型同步增加 replayHoldValid_ 和 replayHoldEntry_。pickReplay() 优先返回锁定的 Entry；tick() 先取得沿前 replaySel，再按握手情况解除或建立保持。即使本沿另一个 Entry 完成 fill，记录的也仍是沿前已呈现的请求。reset 清除新增状态，replayReq() 保持纯查询语义。

## 编译结果与后续状态

本次仅执行 Scala 的 sbt compile 和 C++ 模型的 g++ -std=c++17 -Wall -Wextra -c 编译，两者均通过。没有执行测试或仿真，没有访问验证文件夹，没有修改验证环境。

本次没有重新生成 Verilog，也没有编译或运行仿真程序。后续由用户重新生成 RTL、重新编译使用新参考模型的仿真程序，并执行验证。下文 52 组结果是修复前的历史证据，不能作为本次修复通过验证的结论。源码修改及编译完成后，相关验证点仍待回归确认。

## 要求和实际表现

[MSHR IP架构文档](../MSHR_IP架构设计文档.md)规定replay为Stream：valid=1且ready=0后，valid、类型、CPU ID和载荷必须保持到握手。另一Entry完成fill并成为候选不能替换已经挂起的请求。

修复前复现中，Entry3的一笔读replay被反压；Entry0完成fill后，下一拍在ready仍为0的情况下，输出改为Entry0的读replay。两次输出都没有在变化前握手。

| IO采样周期 | replay.valid | replay.ready | isWrite | CPU ID | rData | 同拍相关事件 |
| --- | --- | --- | --- | --- | --- | --- |
| 200 | 1 | 0 | 0 | 0 | `0xfb0d9488` | fill.en=1、fillReady=1，tag=1、index=0 |
| 201 | 1 | 0 | 0 | 24 | `0x2ada3838` | 旧replay尚未握手，ID及数据已经改变 |

10 ns时钟在2045 ns报错，4 ns时钟在818 ns报错；二者都是相同的第201个复位后IO采样周期。对应断言为`MSHR_DUT_REPLAY_STABLE`，原始前后拍记录为`MSHR_STALL_TRACE`。

## 如何构造

`mshr_replay_backpressure_sequence`先单独覆盖读/写首、中、末Slot阻塞，再运行动态候选场景：

1. 填充四个Entry的上游请求，暂不返回内存响应。
2. 先完成最高Entry的填充与重放，使下一轮轮询起点由实际服务历史建立；不读取内部指针。
3. 将新块分配到刚释放的最高Entry，返回其内存行，保持replay.ready=0，观察至少4拍挂起请求。
4. 返回低Entry的内存行，使它完成fill，继续保持replay.ready=0。
5. 此时出现上述替换；随后放行，全部事务可以结束，但先前保持违约不会因此消失。

所有alloc/merge及内存响应合法性检查均未报错。原C++模型比较未报错，独立IO SVA发现了协议违约；因此不能仅凭模型与DUT一致判定正确。这轮历史验证执行时，模型和 DUT 均尚未修改。

## 复现和证据

在仓库根目录执行：

```bash
python3 verif_mshr/sim_mshr/script/run_mshr_regression.py \
    --tests mshr_replay_backpressure_test --periods 10 4 --color always
```

- [完整52组报告](../../verif_mshr/sim_mshr/work/regression/run_20261124_141613_912476/summary.md)：38 PASS、14 FAIL。
- [10 ns定向日志](../../verif_mshr/sim_mshr/work/regression/run_20261124_141613_912476/mshr_replay_backpressure_test_p10_s1.log) / [波形](../../verif_mshr/sim_mshr/work/regression/run_20261124_141613_912476/mshr_replay_backpressure_test_p10_s1.fsdb)。
- [4 ns定向日志](../../verif_mshr/sim_mshr/work/regression/run_20261124_141613_912476/mshr_replay_backpressure_test_p4_s1.log) / [波形](../../verif_mshr/sim_mshr/work/regression/run_20261124_141613_912476/mshr_replay_backpressure_test_p4_s1.fsdb)。
- [输入哈希](../../verif_mshr/sim_mshr/work/regression/run_20261124_141613_912476/inputs.json)记录实际RTL、C++模型和验证源码版本；哈希仅用于留档，没有解析DUT实现。

完整矩阵使用`--max-errors 0`让检查继续到case结束，不关闭断言、不设置错误豁免。定向测试各报1次该错误；随机与长跑亦出现同一错误。所有case最终事件计数守恒、原始fill/replay数据检查通过，不能据此豁免Stream保持错误。

## 影响和处理边界

修复前IF-002、IF-003、MSC-013、RND-002、RND-010不能闭合。其余功能点按自己的场景和检查独立登记，不把整个IP标为通过。

设计和参考模型已按既有契约修复；新版RTL已生成并完成后述复核。验证侧保留当前场景、SVA和数据检查；修复后重跑定向、随机和长跑。禁止通过改变ready策略、删除动态候选或放宽保持断言获得PASS。


## 修复后验证

[本轮52组回归](../../verif_mshr/sim_mshr/work/regression/run_20261124_152738_869276/summary.md)全部通过，UVM warning/error/fatal均为0。已重新生成RTL并冷编译当前C++模型，原动态候选、随机及长跑保持断言均通过，未修改验证激励或放宽检查。长跑6组每组16384笔Slot请求。IF-002/003、MSC-013、RND-002/010按本配置更新为闭合；前文失败记录为修复前历史。
