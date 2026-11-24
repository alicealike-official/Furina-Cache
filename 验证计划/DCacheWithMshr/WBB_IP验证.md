# WBB IP验证

版本：v3.7（RND-010长跑闭合）；更新日期：2026-11-24。

## 1. 范围与使用方法

验证点必须描述DUT在约定输入下应有的行为。输入合法性是激励前提，模型、driver、monitor、检查器与报告工具的正确性在日常验证和缺陷定位中检查，不另设递归的环境验收清单。场景命中用于说明DUT实际经历了什么，不单独作为“覆盖工具正确”的验证点。无明确规格判据的等待/水位分布只作辅助分析；容量边界、吞吐和有限集合进展仍按相应DUT条目验证。

本文件包含14项WBR预留/查询验证点、12项WBS发送/响应验证点，以及通用条目中的WBB DUT验证要求。删除的编号不重新分配。
当前验证对象是固定规格的生成后WBB DUT。本清单只登记DUT功能、协议、状态和性能要求；环境构建、模型/检查器自检、激励合法性保障及报告工具不作为DUT验证点。
输入由上游淘汰侧和内存侧构成，主要检查reserve、push、send、写响应、full和两路地址查询。
上游成功预留的同址唯一性、合法push及合法内存响应需要环境断言保护。
Cache victim选择、R2取数、清valid原子性、MSHR分配和Stage2冻结的实现证据归DCache顶层文件。

当前执行口径以[WBB IP架构文档](../../Architecture/WBB_IP架构设计文档.md)及用户确认事项为准。
复位为异步低有效，默认reserve成功后下一拍push，延迟push显式启用。
原WBR-001的最低空槽和WBS-007的精确仲裁顺序保留供追溯，IP规格允许的选择范围与当前模型精确检查需要分别登记。
WBR-006的全reserved子场景（N>1）及WBR-008的长延迟子场景归延迟模式。
WBR-009流水重叠已由strict配置下的wbb_pipeline_test执行，默认4槽在10 ns/4 ns下回归通过。

保留已有编号供历史记录追溯；“本文件检查范围”限定WBB DUT职责，“当前证据与剩余项”登记实际完成情况。状态按DUT运行证据更新。环境自检通过不作为DUT验证点闭合依据。关键事件组合由WBR/WBS、反压、查询及RND-008已有DUT条目覆盖，不另列环境交叉验收项。

共享编号可同时出现在多个文件，分别对应模块与集成责任。执行记录使用“文件名＋编号”标识，某一层通过后仍需分别完成其他层的检查。P0为功能/协议必测，P1为重要边界与配置，P2为扩展性能统计。

相关文件：[MSHR_IP验证.md](MSHR_IP验证.md)、[DCache顶层验证.md](DCache顶层验证.md)。

后续 case 的场景划分、编号映射和实施状态见 [WBB case规划 note](WBB_case规划_note.md)。

## 2. 规格依据

- [Cache架构设计文档v2](../../Architecture/Cache架构设计文档v2.md)
- [设计问题与取舍记录](../../Architecture/设计问题与取舍记录.md)
- [CacheConfig参数定义](../../Design/DCacheMSHR/src/main/scala/furina/dcache/CacheConfig.scala)
- [WBB IP架构设计文档](../../Architecture/WBB_IP架构设计文档.md)
- [WBB模型](../../RefModel/Cache/WriteBackBuffer.hpp)

## 3. 分类索引

| 分类 | 本文件条目数 |
| --- | --- |
| 复位与初始化 | 7 |
| 地址、数据与ID | 4 |
| 通用接口协议 | 6 |
| WBB 预留、push 与地址查询 | 14 |
| WBB 发送、响应与仲裁 | 12 |
| 系统不变量与进展 | 4 |
| 写回版本与收尾 | 2 |
| 随机压力与交叉场景 | 3 |

本文件共52条，仅统计本模块DUT要求；共享条目按各层分别登记。

<a id="status"></a>

### 当前状态口径（2026-11-24）

本次逐项核对的是默认 **4槽、64 B行、32位地址/字、2位槽号、4位总线ID**，原有条目对应下文 [R42](#r42) 的 DUT/模型版本，IF-008/009及RND-010新增证据对应2026-11-24各自回归，各轮实际版本以各自报告为准。功能回归包含10 ns/4 ns时钟、strict/delayed编译配置以及适用case的serial/pipeline输入。正常回归与环境负例分开登记，合成自检不作为真实DUT功能运行。

| 状态 | 条目数 | 含义 |
| --- | --- | --- |
| 本配置已闭合 | 47 | 本文件限定的IP子条件已有激励、正确性检查和场景证据；不外推到其他硬件配置、顶层集成或内部寄存器实现。 |
| 部分覆盖 | 3 | 已有部分证据，但当前栏明确列出的DUT子场景或实现时序证据仍缺失。 |
| 未验证 | 1 | 尚无该目标场景的执行证据，已有checker代码也不等于运行通过。 |
| 待确认契约 | 1 | 尚需确定接口或配置规则，再安排对应验证。 |

本次52项中，WBR的14项和WBS的12项均已在上述配置及本层范围闭合。重复/运行中复位仍按RST条目处理。当前覆盖计数是指定场景的命中证据，不是代码覆盖率百分比。

每个验证点按必要子条件判定：一个case完整覆盖即可支持该点闭合；多个case分别覆盖不同子条件时需要合并证据。关联case的数量不决定闭合，也不要求与本点无关的所有case都通过。

阅读说明：每行先说明要制造什么场景，再说明应出现什么结果。“握手”指valid和ready在同一采样沿都为1；“反压”指接收方暂不接收；“排空”指已有请求全部完成并释放占用。Entry保存一条未命中行的处理信息，Slot保存其中一笔读写请求；fill是填充整行，replay是逐笔返回这些请求的结果。编号、状态、层级和证据仍按原记录保留，具体模块责任看范围列。

## 4. 验证点

### 4.1 复位与初始化

| 编号 | 验证点 | 验证层级 | 优先级 | 什么情况下检查、怎样才算正确 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RST-001 | 异步低有效复位 | 模块 IP | P0 | 在非时钟有效沿拉低复位，即使时钟停止，控制状态也应回到初态，体现异步低有效复位。 | 离沿复位 + 状态断言 | 部分覆盖 | 检查异步低有效复位下的DUT初态和离沿清空行为。 | [E01](#e01)、[E13](#e13)：启动复位及 a_reset_outputs 通过，TB 以 reset=~rst_n 映射当前高有效 DUT 端口；尚缺真实 DUT 已占用时停钟、离沿拉低 rst_n 的定向证据，SVA 合成自检不能替代。 |
| RST-002 | 复位释放后的首次请求 | 模块 IP | P0 | 解除复位后提交第一笔读写请求，检查结果正确，没有旧请求残留或凭空产生的响应。 | 定向 + 事务检查 | 本配置已闭合 | 检查复位后首次reserve、push和写回，不涉及CPU读请求。 | [E01](#e01)：启动复位后完成首笔及第二笔写回，逐拍模型/协议检查与四类事件计数均通过；释放首拍/次拍边界另记 RST-009。 |
| RST-005 | WBB 初态 | 模块 IP | P0 | 复位后WBB应没有预留或待写回的槽，不输出有效写请求；内部轮询初值按本文件范围检查。 | 状态检查 | 本配置已闭合 | 检查IP可见空态和无有效发送；内部valid/reserved/issued编码及轮询指针不作后门观察目标。 | [E01](#e01)：a_reset_outputs 检查空态（full=0、reserveOk=1、send_valid=0、两查询不命中）；复位释放后模型逐拍比较通过。仅闭合 IP 可见初态，不声称直接读取内部状态位。 |
| RST-008 | 重复空闲复位 | 模块 IP | P1 | 在空闲状态多次复位，每次释放后都能重新工作，没有残留槽、锁或响应，也不会逐次丢失可用容量。 | 定向循环 | 未验证 | 仅重复空闲复位后的WBB槽和发送状态；当前环境需补重复复位支持。 | 当前 predictor/memory driver 在首次解除复位后再次遇到复位均报 TB_RESET；需先支持重复空闲复位，再检查复位后的槽与请求响应。 |
| RST-009 | 复位释放请求边界 | 模块 IP | P1 | 在复位释放后的第一拍、第二拍分别提交合法请求，检查都按接口约定处理，不产生伪事务；不额外要求未门控的ready在复位时为0。 | 协议监视 + 边沿定向 | 部分覆盖 | 在合法空闲输入及约定释放时序下，释放首拍/次拍的请求被正确处理，无伪发送或残留占用。 | [E01](#e01)：base_test释放后等待两个下降沿再请求，尚未定向覆盖DUT释放首拍、次拍接受请求。 |
| RST-010 | 运行中复位取消事务 | 模块 IP | P1 | 在事务尚未完成时复位，检查取消和旧响应隔离遵守约定。先明确Q-04，再覆盖本模块有关的等待、填充、重放或写回阶段。 | 待确认后定向 + epoch 检查 | 待确认契约 | 仅WBB预留、待发、已发送阶段的取消与旧写响应隔离；契约确认后执行。 | Q-04 未确定取消与旧响应隔离规则；环境当前拒绝再次复位，未执行预留/待发/已发送三个阶段的热复位。 |
| RST-011 | 复位释放时序 | 模块 IP | P1 | 检查复位释放后的功能恢复；异步复位的recovery/removal时序约束要由实现时序报告确认，不能用RTL仿真代替。 | 定向仿真 + 实现时序分析 | 部分覆盖 | RTL功能恢复与实现时序证据分别登记。 | [E01](#e01)：clk_rst_driver 在下降沿释放复位，两种时钟下运行通过；尚无实现阶段 recovery/removal 时序报告。 |

### 4.2 地址、数据与ID

| 编号 | 验证点 | 验证层级 | 优先级 | 什么情况下检查、怎样才算正确 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CFG-004 | 内存块对齐与重构 | 模块 IP | P0 | 输入为合法块对齐地址时，发出的写回地址必须与预留地址一致，不能丢高位或改动块号；旧tag和组号的拼接由顶层验证。 | 事务检查 | 本配置已闭合 | 检查块对齐输入和发送地址保真；victim tag/index重构归顶层。 | [E02](#e02)、[E05](#e05)：不同块地址逐次与 send 比较；a_env_reserve_address/a_dut_send_payload 检查对齐，复用前后数据归属正确。victim 地址重构不属本层。 |
| CFG-005 | 整行中的字和字节位置正确 | 模块 IP | P0 | 整行里的每个字和字节都要放在正确位置，word0位于最低DATA_WIDTH位；检查首尾字及中间位置，没有颠倒或截断。 | 不同字不同图样 | 本配置已闭合 | 检查push行到send行及后端存储的逐字/字节映射。 | [E02](#e02)：逐字/逐字节递增及 walking-1/0 遍历512位，serial/pipeline 各1063笔原始数据回读通过；C++ 原始字节端序单测历史记录见 E02。 |
| CFG-006 | 读写总线 ID 映射 | 模块 IP | P0 | 写请求ID必须对应实际预留槽，并按总线宽度补零；返回响应按完整ID释放槽，读写通道隔离由顶层验证。 | 端口断言 + 并发响应 | 本配置已闭合 | 仅WBB槽号到写ID的映射；读写同值ID隔离归顶层。 | [E03](#e03)、[E08](#e08)：四槽均使用，send ID 与预留槽对应；a_dut_send_payload 检查完整4位ID规范范围（高位零扩展），乱序响应按完整ID释放。 |
| CFG-012 | 总线资源约束 | 模块 IP | P1 | 检查尚未收到响应的写请求数不超过WBB槽数及写通道容量；读写共享额度由顶层确认。 | 请求响应计数 | 本配置已闭合 | 只检查写在途数与槽数/写通道容量；读写共享总额度由顶层确认。 | [E03](#e03)、[E08](#e08)：写在途达到4，等待响应期间仍占满；响应按ID释放，driver/SVA 检查在途唯一与合法生命周期。仅闭合本层写容量，Q-08 的读写共享总额度留在顶层。 |

### 4.3 通用接口协议

| 编号 | 验证点 | 验证层级 | 优先级 | 什么情况下检查、怎样才算正确 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| IF-001 | 写通道握手 | 模块 IP | P0 | 写请求真正握手后才算已发送，对应写响应真正握手后才释放槽；只拉高valid不代表已经完成。 | 逐通道协议断言 | 本配置已闭合 | DUT仅在send握手后登记已发送，仅在写响应握手后释放槽位。 | [E01](#e01)：42组真实 DUT 回归仅按 valid&&ready 计 send/response，四事件计数一致。 |
| IF-002 | 写请求反压保持 | 模块 IP | P0 | 输出有效而接收方不接收时，valid和全部载荷都必须保持到握手；输出无效时不要求载荷保持。 | SVA + 随机反压 | 本配置已闭合 | send.valid&&!ready时DUT保持valid及地址/数据/ID，直至握手。 | [E06](#e06)、[E12](#e12)：真实DUT发送反压及新增候选场景通过a_dut_send_stable/WBB_STABILITY检查。 |
| IF-004 | 一次接受一次状态变化 | 模块 IP | P0 | 一次成功预留、push、发送或响应只改变对应槽一次，不能丢失、重复或提前释放。 | 事务计数 + 状态断言 | 本配置已闭合 | 成功reserve、push、发送和响应握手分别只更新对应槽一次，不丢失、不重复、不提前释放。 | [E03](#e03)、[E07](#e07)、[E11](#e11)：满槽拒绝、连续逐拍发送、连续 reserve/push 均命中；模型、生命周期 SVA、握手计数及排空检查通过。 |
| IF-006 | 有效输出无X/Z | 模块 IP | P0 | 复位结束后，控制输出和有效事务字段不能含X/Z；无效数据或未初始化且不可见的RAM内容按接口范围处理。 | 四态协议断言 | 本配置已闭合 | 复位结束后DUT控制输出、有效reserveSlot及有效发送地址/数据/ID不得含X/Z；无效载荷不强制已知。 | [E01](#e01)：正常回归使用四态SVA检查DUT控制及有效输出载荷；所有已运行场景无未知输出错误。 |
| IF-008 | 无效载荷变化不能触发动作 | 模块 IP | P1 | 使能或valid为0时改变对应载荷，不能触发新事务或改坏已有状态；改变查询地址本身也不算提交请求。 | 定向 + 状态检查 | 本配置已闭合 | 检查reserve/push使能为0、写流valid为0时的载荷扰动和查询无副作用。 | [本轮报告](../../verif_mshr/sim_wbb/work/regression/reports/run_20261124_052027_970562/summary.md)：wbb_idle_payload_test在空态和保留一笔pending时扰动reserve地址、push槽号/整行、valid=0的响应ID；两个阶段各观察到四类字段变化（1111），最终恰好1笔正确写回，模型/SVA无副作用错误。 |
| IF-009 | 最快合法响应 | 模块 IP | P1 | 让写响应在请求握手后的下一拍返回，检查槽正确释放、数据正确；同ID请求与响应首次同拍不属于合法输入。 | 内存时序定向 | 本配置已闭合 | 按WBB新规格检查最早下一拍写响应；同拍首次send与响应属于输入违约。 | [本轮报告](../../verif_mshr/sim_wbb/work/regression/reports/run_20261124_052027_970562/summary.md)：wbb_response_latency_test用真实DUT逐笔排空，对实际send/response ID和采样周期配对；1/2/7/32拍分别精确命中，10 ns/4 ns均通过。 |

### 4.4 WBB 预留、push 与地址查询

| 编号 | 验证点 | 验证层级 | 优先级 | 什么情况下检查、怎样才算正确 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WBR-001 | 空槽选择 | 模块 IP | P0 | 空缓冲或部分占用时，reserveOk应正确表示是否还有位置；reserveSlot必须指向可用槽，具体选择要求以本文件范围为准。 | 逐槽定向 + 模型 | 本配置已闭合 | IP契约按WBB规格检查合法空槽；最低下标是当前参考模型的精确条件，需单独标注口径。 | [E03](#e03)、[E05](#e05)：capacity首次填满覆盖4个不同槽，last_free=1；reuse每槽3次。空槽候选每拍检查。 检查：a_dut_reserve_slot + scoreboard精确比较C++ reserveSlot。 IP允许任意空槽；最低下标只登记为当前模型一致性通过，不提升为IP契约。 |
| WBR-002 | 预留接收条件 | 模块 IP | P0 | 只有reserve_en和reserveOk同时有效才建立预留；已经满时再次请求预留，不能改动已有槽。 | 状态断言 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E03](#e03)、[E11](#e11)：capacity满时额外reserve被阻塞23拍；响应同拍仍拒绝，下一拍恢复；pipeline额外覆盖blocked_reserve=7。 检查：a_dut_capacity + capacity逐拍检查 + C++模型。 |
| WBR-003 | 预留立即记录地址 | 模块 IP | P0 | 预留成功后，下一拍两个查询口就应能查到这个地址，即使数据尚未push；顶层据此阻止过早读取同址内存。 | 双查询口定向 | 本配置已闭合 | 检查预留地址的两个查询结果及时可见；MSHR是否据此阻止读归顶层。 | [E04](#e04)：query覆盖reserved的双命中/仅q0/仅q1；流水在成功reserve下一拍的旧push沿观测对应地址命中。 检查：a_dut_query0/1 + check_overlap_queries。 仅地址查询立即可见已闭合；MSHR据此阻止读属于顶层。 |
| WBR-004 | 只预留地址也算占槽 | 模块 IP | P0 | 只预留了地址、尚未push数据的槽也算占用；后续预留不能把同一个槽再次分配出去。 | 状态模型 + 满边界 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E11](#e11)、[E10](#e10)：delayed全4槽只有reserved的满状态保持7拍；pipeline连续预留未复用旧push槽。 检查：a_dut_capacity/reserve_slot/overlap_slot + C++模型。 |
| WBR-005 | push前后槽始终占用 | 模块 IP | P0 | push写入数据时，这个槽应一直算占用，不能短暂显示空闲而被其他请求抢走。 | 逐拍断言 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E03](#e03)、[E04](#e04)：capacity最后一个槽push时full仍高，full_push=1；query覆盖pending和issued占用。 检查：a_dut_capacity/query0/query1 + C++逐拍比较。 从IO验证占用连续及对应行为；不声称直接观察内部valid/reserved寄存器编码。 |
| WBR-006 | 满空组合 | 模块 IP | P0 | 分别构造全预留、全有数据、两者混合以及只剩一个空槽，检查full和reserveOk都正确；场景遵守严格或延迟push模式的限制。 | 状态组合覆盖 | 本配置已闭合 | 严格下一拍模式检查全loaded/issued及混合占用；N>1的全reserved仅在显式延迟模式执行。 | [E03](#e03)、[E10](#e10)、[E07](#e07)：capacity覆盖仅剩一槽和reserved/loaded混合；arbitration覆盖全pending；capacity全issued仍full23拍；delayed全reserved7拍。 检查：容量SVA + full_push/all_sent_full/full_reserved/max_pending计数。 |
| WBR-007 | push 地址数据归属 | 模块 IP | P0 | push的数据必须进入它预留的槽，与该槽原来的地址配对，不能修改其他槽的地址或数据。 | 不同地址/图样比对 | 本配置已闭合 | 检查本槽的地址/数据关联，并关联a_env_push_next检查严格下一拍的push槽号。 | [E05](#e05)、[E11](#e11)、[E02](#e02)：data_pattern九类模式1063笔；pipeline与reuse覆盖4槽并存、不同地址/数据及复用。逐笔保存reserve地址和push数据。 检查：a_env_push_next + a_dut_send_content + C++逐拍比较 + 输入原始记录/稀疏内存。 |
| WBR-008 | 仅预留不发送 | 模块 IP | P0 | 只有预留、还没push的槽不能发出写请求；延迟push期间也不能把旧数据发出去。 | 长延迟 push | 本配置已闭合 | 默认模式检查一拍reserved窗口；显式延迟模式已有driver及case，检查长延迟与全reserved窗口。 | [E11](#e11)、[E04](#e04)、[E10](#e10)：delayed的5笔均延迟push，最大13拍，全reserved7拍期间不得出现send。strict另检查一拍reserved窗口。 检查：a_dut_send_owner + C++send_valid比较。 |
| WBR-009 | push 槽与预留槽不同 | 模块 IP | P0 | 同拍向旧预留槽push、同时预留另一个空槽，两个动作都要生效，不能串槽。 | 并发定向 | 本配置已闭合 | strict模式13笔写回、8次重叠；逐笔槽号/数据/下一拍push检查，覆盖满槽停顿恢复与尾部；新增a_dut_overlap_slot，详见[case记录](WBB_case规划_note.md)。 | [E11](#e11)：pipeline13笔、8次reserve/push重叠，覆盖满槽停顿恢复与尾部；双模式case进一步覆盖流水。 检查：a_dut_overlap_slot + 每笔槽/数据/下一拍检查。 |
| WBR-010 | 双查询口独立 | 模块 IP | P0 | 两个查询口可查同址或异址，分别覆盖都命中、仅一个命中和都不命中，检查结果互不影响。 | 组合扫描 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E04](#e04)：query两种输入模式均命中同址双命中、异址双命中、单口命中和双miss；reserved/pending/issued均检查。 检查：check_query_coverage/check_overlap_queries + query SVA。 |
| WBR-011 | issued 仍参与查询 | 模块 IP | P0 | 写请求已经发出但响应还没回来时，槽仍然占用，对该地址的查询仍应命中。 | 状态/查询断言 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E04](#e04)、[E08](#e08)：query覆盖issued阶段双/单口命中；response_order逐次释放后仍查询其余issued地址。 检查：a_dut_query0/1 + query_matrix[3][3]/[3][0]/[0][3]。 |
| WBR-013 | 预留和释放并发 | 模块 IP | P1 | 旧槽收到响应被释放，同时向另一个沿前空槽预留，双方都应正确处理；满时不要求同沿用掉刚释放的槽。 | 边界定向 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E03](#e03)、[E11](#e11)、[E09](#e09)：event_collision串行reserve+response=1；流水=2。capacity满响应沿reserve仍阻塞，下一拍恢复。 检查：a_dut_capacity/reserve_slot + C++模型 + 交叉计数。 |
| WBR-014 | push 和释放并发 | 模块 IP | P1 | 同拍向一个槽push、释放另一个槽，各自内容和占用都应正确；不构造同槽的非法冲突。 | 并发 + TB 约束 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E09](#e09)：event_collision串行push+response=1；流水=2，含三/四事件同拍；push及response均有沿前归属检查。 检查：a_env_push_owner/response_owner + C++模型 + 交叉计数。 |
| WBR-015 | 槽复用 | 模块 IP | P1 | 槽释放后再装入新地址、新数据，旧查询命中、旧发送状态和旧数据不能残留到新事务里。 | 多轮循环 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E05](#e05)、[E11](#e11)：reuse三轮A/B/A，每槽3次；旧址miss/新issued地址hit=12，排空查询=33；串行与流水均通过。 检查：每槽reserve_uses + query SVA + 逐次send内容及最终内存。 |

### 4.5 WBB 发送、响应与仲裁

| 编号 | 验证点 | 验证层级 | 优先级 | 什么情况下检查、怎样才算正确 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WBS-001 | 哪些槽可以发出写请求 | 模块 IP | P0 | 只有已经push数据、尚未发送的槽才能发出写请求；地址、整行数据和ID都必须属于被选择的槽。 | 模型 + 事务检查 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E04](#e04)、[E10](#e10)、[E07](#e07)、[E02](#e02)：reserved/pending/issued阶段均覆盖；多槽并存与1063笔数据模式，发送有效时逐槽比较保存地址/数据/ID。 检查：a_dut_send_owner/content/payload + C++模型。 |
| WBS-002 | 写请求反压保持 | 模块 IP | P0 | 写请求已经有效但内存不接收时，valid、地址、整行数据和ID保持到握手；新增候选也不能抢占。 | SVA + 插入候选 | 本配置已闭合 | 用户修复DUT及C++模型后，背压、延迟push及random seed1/2/3在10 ns/4 ns下全部通过，目标仍命中；详见[case记录](WBB_case规划_note.md)。 | [E10](#e10)、[E06](#e06)、[E12](#e12)：用户修复后backpressure仍命中held_id=3、competing_id=0、10拍stall及1次候选插入；random与delayed均通过。 检查：a_dut_send_stable + scoreboard WBB_STABILITY。 历史DUT问题已由用户修复；结论限本轮DUT哈希，保留修复记录。 |
| WBS-003 | 发送后不重发 | 模块 IP | P0 | 槽的写请求完成一次握手后，在响应回来之前不得重复发送；反压期间不算已发送。 | 发送ID集合 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E03](#e03)、[E07](#e07)、[E08](#e08)：capacity4槽发送后未响应持续23拍；每槽已发集合和send_owner拒绝已issued重复发送。 检查：a_dut_send_owner + memory outstanding唯一性 + 四事件计数。 |
| WBS-004 | 响应按 ID 释放 | 模块 IP | P0 | 写响应即使乱序返回，也只能释放其ID对应的槽，其他槽保留；读写同值ID的隔离按本层范围检查。 | 乱序 + 独立模型 | 本配置已闭合 | 仅按写ID乱序释放；读侧同值ID不干扰由DCache顶层检查。 | [E12](#e12)、[E08](#e08)：按实际send ID逆序响应4笔，reordered=3；释放地址miss/其他issued地址hit查询6次。 检查：按ID pending表 + response_owner/query SVA + C++模型。 读侧同值ID隔离归DCache顶层，不阻止WBB写ID子项闭合。 |
| WBS-005 | 发送握手不等于释放 | 模块 IP | P0 | 内存接受写请求后，槽仍要占用，直到对应写响应握手；不能提前交给下一笔写回。 | 状态断言 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E03](#e03)、[E11](#e11)：capacity全部4笔已send但仍保持full23拍，额外reserve不获准，收到response后才释放。 检查：a_dut_capacity + all_sent_full/full_response/recovery检查。 |
| WBS-006 | 释放清理 | 模块 IP | P0 | 收到响应后，旧地址查询应解除；槽再次使用时，不应带上旧数据或旧发送状态。 | 状态 + 复用 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E05](#e05)、[E08](#e08)：response_order逐次释放查询；reuse三轮每槽3次，旧址失效且新版本数据正确。 检查：query/send_content SVA + C++模型 + 稀疏内存。 从端口行为验证释放清理，不声称直接观察内部valid/issued编码。 |
| WBS-007 | 轮询顺序与回绕 | 模块 IP | P1 | 多个槽等待发送时，检查轮询服务及从末槽回到首槽的情况；只有发送握手才推进轮询，精确顺序要求见本文件范围。 | 独立RR模型 | 本配置已闭合 | IP检查轮询公平和回绕；精确起点/rrPtr次序属于当前模型一致性检查。 | [E07](#e07)、[E06](#e06)：arbitration统一放行4个pending候选，4个不同ID逐拍发送并末槽到首槽回绕1次；背压期间不改变已选择请求。 检查：check_send_burst + a_dut_rr_bound + C++精确顺序。 轮询公平和回绕为IP契约；精确起点和rrPtr更新由当前C++模型一致性另记。 |
| WBS-008 | 当前每个待发槽都能被服务 | 模块 IP | P1 | 停止新增写回且内存持续接收时，当前每个待发槽最终都应发送一次，不能漏掉某个槽或重复服务。 | 有界计数 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E07](#e07)：固定4个pending、ready放行后每槽恰好一次，slots=1111且burst=4。 检查：check_send_burst + a_dut_rr_bound。 |
| WBS-009 | 全满恢复 | 模块 IP | P1 | 所有槽都已发送并等待响应时，任意一个合法响应应释放对应位置，使后续预留恢复；其他事务继续保留。 | 满负载定向 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E03](#e03)、[E11](#e11)、[E08](#e08)：capacity全issued/full时响应释放，下一沿接受等待项并使用刚释放ID；response_order逆序释放保持其余槽。 检查：full_response/recovered计数 + capacity/query SVA。 |
| WBS-010 | 不同槽发送与释放同拍 | 模块 IP | P1 | 发送一个槽的写请求，同时释放另一个槽，两个动作应各自生效，不能串ID或改坏待发集合。 | 交叉时序 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E09](#e09)：event_collision串行send+response=1；流水四事件同拍包含不同槽send与response。 检查：send/response owner + C++模型 + send_response_cycles。 |
| WBS-011 | 持续吞吐 | 模块 IP | P1 | 多个槽都准备好且内存持续接收时，应连续发送，检查是否无故空一拍。 | 性能统计 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E07](#e07)：arbitration的4个pending候选连续4拍发送，相邻send_cycles差1，全部4槽及回绕命中。 检查：check_send_burst/max_send_burst。 |
| WBS-012 | 反复写回后仍能释放全部槽 | 模块 IP | P1 | 反复预留、push、发送和乱序响应后，缓冲应能完全回到空态，后续仍能使用全部槽。 | 模块随机 + 排空 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E05](#e05)、[E12](#e12)：random每次32批128笔，批间排空复用，随机ready/响应延迟/响应ID；seed1/2/3×两模式×两周期通过。 检查：逐笔C++/SVA + 四事件128计数 + 每批wait_until_empty/最终排空。 |

### 4.6 系统不变量与进展

| 编号 | 验证点 | 验证层级 | 优先级 | 什么情况下检查、怎样才算正确 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| INV-005 | WBB资源守恒 | 模块 IP | P0 | 逐笔核对资源分配与释放：使用数量不能为负或超过容量，不能漏释放，也不能把仍在处理的资源提前算成空闲。 | 独立计数模型 | 本配置已闭合 | WBB分配与释放计数守恒，占用不负不越界，reserve/push/send/response各生命周期不丢失。 | [E03](#e03)、[E11](#e11)：所有42次运行reserve/push/send/response数量相等；capacity/pipeline覆盖0..满以及释放恢复。 检查：scoreboard计数 + IO槽生命周期 + memory pending容量。 |
| INV-006 | 写ID唯一在途 | 模块 IP | P0 | 一个槽的写响应还没回来时，不能重复发送这个ID，也不能把同一ID分配给另一笔未完成写回。 | ID集合断言 | 本配置已闭合 | DUT同一写ID在响应前不得重复发送或分配给另一笔未完成写回。 | [E03](#e03)、[E12](#e12)、[E08](#e08)：多槽在途和乱序响应下，memory outstanding集合检查发送ID不重复；SVA发送必须尚未issued，reserve必须空槽。 检查：a_dut_send_owner/reserve_slot + memory outstanding检查。 |
| INV-007 | 放行后所有请求都能完成 | 模块 IP | P0 | 停止提交新写回，并让已有push、内存接收和响应最终完成后，所有槽都应释放，不能一直卡住。 | watchdog + 收尾断言 | 本配置已闭合 | 停止新写回，且合法push、内存接收和响应最终完成时，DUT所有占用最终释放。 | [E01](#e01)：每个case停止激励并放行响应后，由watchdog保护排空；C++模型空态及内存pending/outstanding/active均空。 检查：wait_for_drain + predictor/memory driver check_phase + 四事件计数。 |
| INV-010 | 已有请求最终都能完成 | 模块 IP | P1 | 对固定的一批待处理请求，下游持续允许后应全部完成；不把固定优先级在无限新增流量下的公平性当作额外保证。 | 约束活性 + 性能统计 | 本配置已闭合 | 固定待发集合且下游持续接收时，WBB轮询服务全部候选；外部反压不计为内部饥饿。 | [E07](#e07)：固定4候选统一放行且逐拍服务完毕；IO公平断言计其他槽成功发送而不计外部反压周期。 检查：check_send_burst + a_dut_rr_bound。 |

### 4.7 写回版本与收尾

| 编号 | 验证点 | 验证层级 | 优先级 | 什么情况下检查、怎样才算正确 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| END-007 | 每次写回使用对应版本的数据 | 模块 IP | P0 | 每次写回都比较这一笔事务应写出的地址和数据版本；不能拿后续写入的新值去比较先前的写回。 | 事件/版本模型 | 本配置已闭合 | 每次DUT发送必须等于对应生命周期接受的地址和push数据，复用地址不能串入未来或旧版本。 | [E05](#e05)、[E02](#e02)、[E12](#e12)：reuse A/B/A及random重复地址更换数据，C++与IO checker按各次push存储版本，每次send立即比较；最终内存另按末版本比较。 检查：a_dut_send_content + predictor/scoreboard逐次比较 + 原始输入记录。 WBB push到send版本已闭合；Cache victim内容从CPU历史重建归顶层。 |
| END-009 | 收尾无残留占用 | 模块 IP | P1 | 全部写回完成后，full为0、reserveOk为1，查询旧地址不再命中，也不能再发出多余写请求。 | check/report阶段 | 本配置已闭合 | 合法流量完成后DUT回到空态，full=0、reserveOk=1、旧址查询不命中且无额外发送。 | [E01](#e01)：正常回归收尾逐拍比较DUT空态输出，核对全部写回完成且无额外发送；环境队列只辅助判断何时收尾。 |

### 4.8 随机压力与交叉场景

| 编号 | 验证点 | 验证层级 | 优先级 | 什么情况下检查、怎样才算正确 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RND-001 | WBB约束随机 | 模块 IP | P0 | 随机安排合法预留、push、查询、内存接收和乱序响应，检查WBB数据、槽位归属和最终排空。 | 多种子模块回归 | 本配置已闭合 | 输入遵守接口约定，通过本模块的公开IO检查上述行为。 | [E12](#e12)：seed1/2/3在串行/流水和10ns/4ns均通过；每次32批128笔，ready随机60%，响应延迟1..8拍，响应ID随机选择。 检查：C++模型 + IO SVA + 原始数据与内存检查 + 随机阶段31批重叠检查。 |
| RND-008 | 资源快满或释放时的并发动作 | 模块 IP | P0 | 在资源只剩最后一个空位、已经满或刚释放时叠加合法并发动作，逐项核对case矩阵中的实际命中和正确结果。 | 定向偏置随机 | 本配置已闭合 | 仅WBB最后空槽、分配/释放及写通道交叉。 | [E03](#e03)、[E11](#e11)、[E12](#e12)、[E09](#e09)：capacity最后空槽接受1次、满时response后恢复；pipeline满时旧push/阻塞reserve共存；event_collision覆盖释放与reserve/push/send及四事件同拍。 检查：last_free/full_response/recovery/blocked_push/三四事件计数 + C++/SVA。 |
| RND-010 | 长期运行与复用 | 模块 IP | P1 | 长时间运行并反复复用地址、ID和槽位后，数据仍正确、容量没有减少；停止新增并放行后能完全排空，保存种子和版本便于重现。 | 固定seed+扩展seed | 本配置已闭合 | 长时间合法流量、多轮槽与地址复用后，DUT数据、ID、容量无泄漏并能够排空。 | [长跑报告](../../verif_mshr/sim_wbb/work/regression/reports/run_20261124_054804_914530/summary.md)：wbb_long_run_test每次3轮×4096笔=12288笔，seed1/2/3×serial/pipeline×10 ns/4 ns共12/12通过，总计147456笔。每轮先满槽再持续提交，轮末排空并回读全部4096行；同址三轮更换数据，各槽重复使用、背压及乱序逐轮命中。原C++模型与IO SVA持续检查，UVM warning/error/fatal均为0。本点闭合范围限定为这一明确长跑规模。 |

## 5. 待确认契约与专项风险

以下保留原Q编号和原问题描述，原问题涉及其他层的内容按“本文件处理范围”限定。源码阅读提出的风险仍需定向验证，不能据此直接判断DUT失败。

| 编号 | 原问题 | 原关联验证点 | 原处理与判定 | 本文件处理范围 |
| --- | --- | --- | --- | --- |
| Q-01 | WBB send 和 MSHR replay 当前由候选集合及 rrPtr 组合选取，未见独立的挂起选择锁存；反压期间新增更靠前候选可能改变输出 | IF-002/003、WBS-002、MSC-013 | 增加“反压 + 新候选”模块定向和稳定性断言。MSHR memReadReq 已有 sendHold，不能由此推定另两条流也安全 | WBB历史问题已复现并由用户补充保持逻辑；修复后26组复核通过，当前含流水变体的R42共42组通过，背压新增候选仍命中。MSHR部分仍需其IP验证，不能从WBB结果推定。 |
| Q-04 | 运行中复位后的迟到读写响应、CPU ID复用以及已接收写的取消语义未统一 | RST-010 | 系统须约定清空后端pending、隔离epoch或等效措施。仅清DUT状态不足以安全接收旧ID响应；未定义前不声称热复位通过 | WBB取消与旧写响应隔离。 |
| Q-08 | NUM_BUS_OUTSTANDING用于ID位宽/约束，但未见读写总量共享额度控制；若设为小于Entry+WBB，不能仅凭参数名断言总量受限 | CFG-012 | 明确该值为每通道ID空间还是共享容量。共享上限由接收方ready或DUT额度管理保证后，再设置对应断言 | 仅写ID空间与写在途容量，读写共享额度见顶层。 |

原关联编号若未在本文件列出，可在另外两个文件按编号查找。

## 6. 证据与闭合登记

本节保留运行证据及历史辅助记录。E13～E17中的环境自检、构建和报告记录不计入DUT验证点或闭合数量。

<a id="r42"></a>

### 当前功能回归 R42

主表功能状态使用 `run_20261120_013657_184228`：**12个test，42/42 PASS**，每组UVM_WARNING/ERROR/FATAL均为0。random使用seed=1/2/3，其余seed=1；所有case在10 ns/4 ns下运行。random、reuse、data_pattern、query、event_collision运行serial/pipeline两种输入；pipeline固定流水，其他case固定串行。delayed_push使用显式延迟push编译配置，其余使用strict。

- [回归汇总及逐组log/FSDB](../../verif_mshr/sim_wbb/work/regression/reports/run_20261120_013657_184228/summary.relocated.md)
- [JSON结果与场景计数](../../verif_mshr/sim_wbb/work/regression/reports/run_20261120_013657_184228/summary.json) / [18个输入文件哈希](../../verif_mshr/sim_wbb/work/regression/reports/run_20261120_013657_184228/inputs.json)
- DUT SHA-256：`7e55ed10a7f44bdcd8083c43010a7402ee6e4af62e454aaef1d50454c159b3f7`。
- C++ WBB模型 SHA-256：`4e388c0ee239f54ad2a2f86e31df649500bedc68e413d1f01f506d0b7ee29d89`。

R42状态同步时已只读核对42组log/FSDB存在、18个输入哈希与当时源码一致。其后的目录迁移保留原JSON、输入哈希及逐次日志；迁移展示页仅重定位链接，不把旧记录伪写成在新目录运行。以下E01～E12的运行日志统一从R42按test、输入模式、时钟、seed定位。E13/E14是单独的环境自检；E15是配置/构建审查；E16保留历史失败判定证据；E17登记目录迁移后的入口验证。

### Case、检查器与命中证据

共同正确性检查由 [C++模型的SV predictor](../../verif_mshr/src/wbb/model/wbb_predictor.sv)、[scoreboard](../../verif_mshr/src/wbb/component/scoreboard/wbb_scoreboard.sv)及 [IO SVA](../../verif_mshr/src/wbb/bind/wbb_io_assertions.sv)承担。原始激励数据比较、四事件计数和排空工具在 [base_test](../../verif_mshr/test/wbb/wbb_base_test.sv)，各case的命中数量由 [activity monitor](../../verif_mshr/src/wbb/component/monitor/wbb_activity_monitor.sv)及子test检查。

“内存回读”是经DPI读取 [C++稀疏内存的SV封装](../../verif_mshr/src/wbb/model/wbb_memory_store.sv)，实际内容来自send握手。每次send仍立即与该次push版本比较，最终内存回读只比较同址的最后一版，不代替逐次检查。内部槽状态的要求通过IO生命周期及外部行为验证，不声称后门检查了寄存器位。

| 证据 | test / sequence | 当前命中与正确性检查 |
| --- | --- | --- |
| <a id="e01"></a>E01 | [base_test](../../verif_mshr/test/wbb/wbb_base_test.sv) / [smoke_sequence](../../verif_mshr/src/wbb/sequence/wbb_smoke_sequence.sv)；全部R42共用检查 | base完成2笔；所有case按沿前采样运行C++/SVA、四事件计数和check_phase收尾。复位空态/源端空闲由a_reset_outputs/a_reset_inputs检查；不包含再次复位。 |
| <a id="e02"></a>E02 | [data_pattern_test](../../verif_mshr/test/wbb/wbb_data_pattern_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_data_pattern_sequence.sv) | serial/pipeline各1063笔（1062组数据+1笔预置）；九类数据数量逐类检查，walking-1/0各512笔，逐字/逐字节递增及原始整行回读通过；流水重叠796次。C++原始字节端序由[test_sparse_memory.cpp](../../RefModel/test/test_sparse_memory.cpp)检查，既有运行记录见[case note](WBB_case规划_note.md)，本次未重跑该单测。 |
| <a id="e03"></a>E03 | [capacity_test](../../verif_mshr/test/wbb/wbb_capacity_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_capacity_sequence.sv) | 5笔；slots=1111，last_free=1，full_push=1，blocked_cycles=23，all_sent_full_cycles=23，full_response=1，recovered=1。检查满状态沿前资源约束、响应次拍恢复及5行数据。 |
| <a id="e04"></a>E04 | [query_test](../../verif_mshr/test/wbb/wbb_query_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_query_sequence.sv) | 两种模式各8笔；reserved/pending/issued的双命中、单口命中与miss均检查。流水重叠6次，重叠期间reserved双命中2次、仅q0/仅q1各1次、异址双命中2次；逐拍query SVA核对结果。 |
| <a id="e05"></a>E05 | [reuse_test](../../verif_mshr/test/wbb/wbb_reuse_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_reuse_sequence.sv) | 两种模式各12笔、A/B/A三轮、每槽3次；旧地址miss且新issued地址hit共12次，排空查询33次；流水每轮重叠3次。逐次send内容和最终内存检查新版本。 |
| <a id="e06"></a>E06 | [send_backpressure_test](../../verif_mshr/test/wbb/wbb_send_backpressure_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_send_backpressure_sequence.sv) | 6笔；挂起ID=3，新候选ID=0，背压10拍、新候选插入1次；a_dut_send_stable及WBB_STABILITY检查valid和全部payload保持。用户修复WBB-DUT-001后通过。 |
| <a id="e07"></a>E07 | [arbitration_test](../../verif_mshr/test/wbb/wbb_arbitration_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_arbitration_sequence.sv) | 5笔；4个pending统一放行，连续4拍发送、slots=1111、回绕1次；check_send_burst与a_dut_rr_bound检查连续发送和有界进展。精确RR次序另由当前C++模型比较。 |
| <a id="e08"></a>E08 | [response_order_test](../../verif_mshr/test/wbb/wbb_response_order_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_response_order_sequence.sv) | 4笔按实际send ID逆序响应，乱序3次，已释放/仍issued地址对照查询6次；按ID pending查找、query SVA和模型检查释放目标及其他槽。 |
| <a id="e09"></a>E09 | [event_collision_test](../../verif_mshr/test/wbb/wbb_event_collision_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_event_collision_sequence.sv) | serial 6笔，reserve+response、push+response、send+response各1次；pipeline 7笔，三事件条件2次（含四事件）、四事件同拍1次。IO归属、模型和原始数据检查各槽互不污染。 |
| <a id="e10"></a>E10 | [delayed_push_test](../../verif_mshr/test/wbb/wbb_delayed_push_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_delayed_push_sequence.sv) | delayed配置5笔延迟push，最大13拍，全reserved维持7拍；send_owner及模型禁止未push发送，容量/查询持续检查。此证据不放宽strict的下一拍push要求。 |
| <a id="e11"></a>E11 | [pipeline_test](../../verif_mshr/test/wbb/wbb_pipeline_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_pipeline_sequence.sv) | strict 13笔、8次重叠；逐笔槽/地址/数据及push-reserve间隔1拍检查。满槽阶段blocked_push=1、blocked_reserve=7、满响应同拍阻塞1次、次拍恢复1次；另检查尾push、两段3拍空闲和再次启动。 |
| <a id="e12"></a>E12 | [random_test](../../verif_mshr/test/wbb/wbb_random_test.sv) / [sequence](../../verif_mshr/src/wbb/sequence/wbb_random_sequence.sv) | seed1/2/3×两模式×两周期，共12次；每次32批128笔，随机地址/数据/查询、ready、1～8拍响应与响应选择，逐批排空复用。流水随机阶段31批均重叠，总重叠96次；种子1流水背压103拍、乱序37次。此规模不直接视为RND-010长跑已完成。 |

<a id="e13"></a>

### E13：IO SVA环境自检

[test](../../verif_mshr/test/assertions/wbb_io_assertions_test.sv) / [bind test](../../verif_mshr/test/assertions/wbb_bind_test.sv) / [运行及判定脚本](../../verif_mshr/sim_wbb/script/check_wbb_sva.py)。这些测试使用合成接口轨迹，不实例化真实WBB DUT。

strict/delayed在10 ns/4 ns下各29场景通过，bind两种时钟均通过。负例按预期检查ENV/DUT错误类别，覆盖非法push、重复地址、地址/ID非法、提前响应、零拍响应、保持和控制X等；尚无独立重复响应轨迹，也不替代scoreboard负例单测。

- strict：[10 ns](../../verif_mshr/sim_wbb/work/assertions/strict/run.log) / [4 ns](../../verif_mshr/sim_wbb/work/assertions/strict/run_4ns.log)。
- delayed：[10 ns](../../verif_mshr/sim_wbb/work/assertions/delayed/run.log) / [4 ns](../../verif_mshr/sim_wbb/work/assertions/delayed/run_4ns.log)。
- bind：[10 ns](../../verif_mshr/sim_wbb/work/assertions/bind/run.log) / [4 ns](../../verif_mshr/sim_wbb/work/assertions/bind/run_4ns.log)。

R42真实DUT日志另有13个现存cover实例均命中。以下累计只读取各次正式log，不重复累计stdout.log：

| cover | 42次运行累计match |
| --- | --- |
| c_reserve_push | 5964 |
| c_full_release | 758 |
| c_overlap | 2218 |
| c_send_stall_release | 646 |
| c_send_and_response | 1278 |
| slot0 reserved / issued query | 1232 / 238 |
| slot1 reserved / issued query | 1174 / 46 |
| slot2 reserved / issued query | 48 / 20 |
| slot3 reserved / issued query | 576 / 20 |

这些计数证明已定义场景确实发生；检查器前件配对属于环境维护，不计入DUT验证点。

<a id="e14"></a>

### E14：内存代理周期与响应保持自检

[test](../../verif_mshr/test/adapter/wbb_memory_timing_check.sv) / [脚本](../../verif_mshr/sim_wbb/script/check_wbb_memory_timing.py)。使用真实monitor、memory driver和C++稀疏内存，不实例化WBB DUT。

10 ns/4 ns × 延迟1/2/32拍共6组通过，每组检查3笔精确周期响应、2笔响应背压与恢复、5笔数据回读；0拍配置负例按预期触发MEM_CONFIG fatal。

| 时钟 | 1拍 | 2拍 | 32拍 |
| --- | --- | --- | --- |
| 10 ns | [log](../../verif_mshr/sim_wbb/work/memory_timing/log/period_10_latency_1.log) | [log](../../verif_mshr/sim_wbb/work/memory_timing/log/period_10_latency_2.log) | [log](../../verif_mshr/sim_wbb/work/memory_timing/log/period_10_latency_32.log) |
| 4 ns | [log](../../verif_mshr/sim_wbb/work/memory_timing/log/period_4_latency_1.log) | [log](../../verif_mshr/sim_wbb/work/memory_timing/log/period_4_latency_2.log) | [log](../../verif_mshr/sim_wbb/work/memory_timing/log/period_4_latency_32.log) |

[0拍负例log](../../verif_mshr/sim_wbb/work/memory_timing/log/period_10_latency_0.log)。环境自检的1拍结果不替代IF-009所需的真实DUT按ID请求/响应间隔命中记录。

<a id="e15"></a>

### E15：当前配置与构建路径审查

[生成器](../../Design/DCacheMSHR/src/main/scala/furina/dcache/WbbVerificationVerilog.scala)由同一CacheConfig生成RTL及SV参数。[当前SV参数](../../verif_mshr/generated/wbb/wbb_params_pkg.sv)、DUT端口与[DPI创建时的C++参数检查](../../verif_mshr/dpi/wbb_dpi.cpp)对应一致；R42中strict/delayed实际编译均通过，编译日志可从JSON的builds条目定位。

现有[dut.f](../../verif_mshr/sim_wbb/dut.f)/[tb.f](../../verif_mshr/sim_wbb/tb.f)统一使用`generated/wbb/WriteBackBuffer.v`及`generated/wbb/wbb_params_pkg.sv`。[Makefile](../../verif_mshr/sim_wbb/Makefile)的generate与check_dpi也已使用同一目录。原先指向旧`src/wbb/pkg`参数包的路径缺口已修复，并由E17的实际生成、编译和自检验证。

<a id="e16"></a>

### E16：回归判定与历史缺陷

[回归脚本](../../verif_mshr/sim_wbb/script/run_wbb_regression.py)同时检查进程状态、UVM_ERROR/FATAL汇总和实际报错行、case成功标记、事件摘要及输入模式。[修复前报告](../../verif_mshr/sim_wbb/work/regression/reports/run_20261119_080300_487790/summary.json)包含6组`exit_code=0`却被正确判为FAIL的真实记录，记录当时回归工具的判定行为。

WBB-DUT-001已由用户修改DUT及C++模型，详见[缺陷记录](../../Architecture/DebugNote/WBB-DUT-001_发送背压保持问题.md)。[修复后26组复核](../../verif_mshr/sim_wbb/work/regression/reports/run_20261119_092126_919356/summary.relocated.md)、[增加pipeline后的28组](../../verif_mshr/sim_wbb/work/regression/reports/run_20261120_010402_307499/summary.relocated.md)及当前R42依次通过。早期两笔基础case、旧RTL数据/容量结果和开发过程仍保存在[case note](WBB_case规划_note.md)，仅作为历史记录，不再用旧状态覆盖当前判定。

所有运行产物位于可清理的`sim_wbb/work`；清理前应归档所引用的report/log/FSDB。共享编号在MSHR IP和DCache顶层仍使用各自证据，不从本文件自动同步为通过。


<a id="e17"></a>

### E17：WBB目录迁移后的入口验证

2026-11-20将`sim`迁为`sim_wbb`，将WBB的RTL和参数包移入`generated/wbb`；MSHR保持`sim_mshr`、`generated/mshr`。生成入口、filelist、DPI/SVA/内存自检、回归脚本及文档链接同步调整。

- `make generate`已在新目录生成RTL与参数；参数包内容未变，RTL只有文件头Git版本注释更新，逻辑内容与迁移前逐字节一致。新RTL SHA-256为`3999fe1c011a9978fe2603604c4a2fecca3a316028ccd0f5c5e997cb70b722a1`，不能把它写回旧R42的哈希记录。
- 默认入口冷编译及未指定TEST_NAME的仿真通过，[默认启动日志](../../verif_mshr/sim_wbb/work/log/layout_default.log)记录两笔写回与零UVM warning/error/fatal。
- [6组路径迁移回归](../../verif_mshr/sim_wbb/work/regression/reports/run_20261120_024923_117690/summary.md)：基础、流水、延迟push各10 ns/4 ns，strict/delayed均冷编译，6/6 PASS，所有UVM warning/error/fatal为0。这是入口检查，不替代R42的完整42组功能记录。
- [DPI自检](../../verif_mshr/sim_wbb/work/log/dpi_check.log)通过；[SVA strict](../../verif_mshr/sim_wbb/work/assertions/strict/run.log)、[delayed](../../verif_mshr/sim_wbb/work/assertions/delayed/run.log)、[bind](../../verif_mshr/sim_wbb/work/assertions/bind/run.log)通过；内存代理10 ns/4 ns×1/2/32拍及0拍预期拒绝全部通过。
- 两模块的`run_verdi`命令及对应filelist/波形路径已检查，未启动图形界面。

原有编译产物保存在`sim_wbb/work/before_layout_builds`；自检旧日志另存在`work/layout_checks/previous_selfcheck_logs`，迁移前latest总表保存在`work/layout_checks/previous_latest`。历史逐轮summary.json/summary.md/inputs.json保持原样，新增summary.relocated.md作为导航副本。后续新回归报告直接使用相对log/FSDB链接，避免再次搬目录时失效。


### 2026-11-24 新增case与剩余缺口

新增IF-008无效载荷扰动和IF-009真实DUT精确响应延迟证据；默认四槽状态为46项本配置闭合、4项部分覆盖、1项未验证、1项待确认契约。原有条目的运行证据仍按各自记录保存。

[本轮完整报告](../../verif_mshr/sim_wbb/work/regression/reports/run_20261124_052027_970562/summary.md)：14个test，10 ns/4 ns及既有串行/流水、随机种子组合共46/46通过。新增case均固定serial，原有case的检查保持。

首轮无效载荷case曾因覆盖计数使用q0Same判断占用而失败：query切换到未占用地址时会miss，但槽仍占用。已修正为独立记录实际reserve/响应事件形成的沿前占用，最终两个阶段的四类扰动均命中。这是新增DV覆盖统计问题，未修改DUT或参考模型。

该轮剩余项中的RND-010随后由下述长跑闭合。当前仍保留5项复位相关缺口：RST-001/008/009/010/011；本次不验证复位。


### 2026-11-24 RND-010长跑结果

[12组长跑报告](../../verif_mshr/sim_wbb/work/regression/reports/run_20261124_054804_914530/summary.md)全部通过，四事件计数每组均为12288，总计147456笔；每组完成3轮满槽、持续提交、排空和同址换数据。逐轮检查及版本说明见[case记录](WBB_case规划_note.md)。当前52项中47项本配置闭合、3项部分覆盖、1项未验证、1项待确认契约；未闭合的5项均属复位。

本次仅新增DV长跑sequence/test、package引用及回归入口，未修改DUT或C++模型。首次沙箱运行因无法连接许可证服务器未进入仿真；获得许可证访问后完成冷编译及上述12组运行，不将未运行的组合记为通过。
