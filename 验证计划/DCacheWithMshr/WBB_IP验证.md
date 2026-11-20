# WBB IP验证

版本：v3.2（模块目录迁移与构建入口验证）；更新日期：2026-11-20。

## 1. 范围与使用方法

本文件承接WBR-001～015和WBS-001～012共27项专属验证点，并纳入通用条目中的WBB部分。
输入由上游淘汰侧和内存侧构成，主要检查reserve、push、send、写响应、full和两路地址查询。
上游成功预留的同址唯一性、合法push及合法内存响应需要环境断言保护。
Cache victim选择、R2取数、清valid原子性、MSHR分配和Stage2冻结的实现证据归DCache顶层文件。

当前执行口径以[WBB IP架构文档](../../Architecture/WBB_IP架构设计文档.md)及用户确认事项为准。
复位为异步低有效，默认reserve成功后下一拍push，延迟push显式启用。
原WBR-001的最低空槽和WBS-007的精确仲裁顺序保留供追溯，IP规格允许的选择范围与当前模型精确检查需要分别登记。
WBR-006的全reserved子场景（N>1）及WBR-008的长延迟子场景归延迟模式。
WBR-009流水重叠已由strict配置下的wbb_pipeline_test执行，默认4槽在10 ns/4 ns下回归通过；其他参数仍需另行登记。

保留原验证点编号、优先级、检查方式和历史通过条件；“本文件检查范围”限定本层职责，“当前证据与剩余项”登记实际完成情况。状态按当前证据更新，不再沿用拆分时的历史状态。原条目的文字作为追溯基线，遇到后来确认的接口约定时按本文件范围说明执行。

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
| 参数、地址与生成配置 | 9 |
| 通用接口协议 | 7 |
| WBB 预留、push 与地址查询 | 15 |
| WBB 发送、响应与仲裁 | 12 |
| 系统不变量与进展 | 5 |
| 端到端收尾与后端一致性 | 3 |
| 性能与资源利用 | 2 |
| 随机压力与交叉场景 | 3 |
| 验证环境、覆盖率与构建自检 | 12 |

本文件共 75 条。三个文件的原始编号并集为276个，共享条目按各层分别登记。

<a id="status"></a>

### 当前状态口径（2026-11-20）

本次逐项核对的是默认 **4槽、64 B行、32位地址/字、2位槽号、4位总线ID**，对应下文 [R42](#r42) 的 DUT/模型版本。功能回归包含10 ns/4 ns时钟、strict/delayed编译配置以及适用case的serial/pipeline输入。正常回归与环境负例分开登记，合成自检不作为真实DUT功能运行。

| 状态 | 条目数 | 含义 |
| --- | --- | --- |
| 本配置已闭合 | 57 | 本文件限定的IP子条件已有激励、正确性检查和场景证据；不外推到其他硬件配置、顶层集成或内部寄存器实现。 |
| 部分覆盖 | 12 | 已有部分证据，但当前栏明确列出的子条件或自检仍缺失。 |
| 未验证 | 4 | 尚无该目标场景的执行证据，已有checker代码也不等于运行通过。 |
| 待确认契约 | 2 | 尚需确定接口或配置规则，再安排对应验证。 |

本次75项中，WBR的15项和WBS的12项均已在上述配置及本层范围闭合。跨参数验证独立记在CFG-007～010，重复/运行中复位仍按RST条目处理。当前覆盖计数是指定场景的命中证据，不是代码覆盖率百分比。

每个验证点按必要子条件判定：一个case完整覆盖即可支持该点闭合；多个case分别覆盖不同子条件时需要合并证据。关联case的数量不决定闭合，也不要求与本点无关的所有case都通过。

## 4. 验证点

### 4.1 复位与初始化

| 编号 | 验证点 | 原验证层级 | 优先级 | 原检查内容与通过条件 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RST-001 | 异步高有效复位 | 模块 IP + 集成 | P0 | 时钟停止时拉高 reset，带复位的控制寄存器进入初态；TB rst_n 取反连接正确 | 离沿复位 + 状态断言 | 部分覆盖 | 按后来确认的WBB规格检查异步低有效rst_n；核对DUT/TB映射。原条目高有效描述作为历史口径保留。 | [E01](#e01)、[E13](#e13)：启动复位及 a_reset_outputs 通过，TB 以 reset=~rst_n 映射当前高有效 DUT 端口；尚缺真实 DUT 已占用时停钟、离沿拉低 rst_n 的定向证据，SVA 合成自检不能替代。 |
| RST-002 | 复位释放后的首次请求 | 模块 IP + 集成 | P0 | 按约定释放复位后首笔读写均正确，无伪响应、无上次事务残留 | 定向 + 事务检查 | 本配置已闭合 | 检查复位后首次reserve、push和写回，不涉及CPU读请求。 | [E01](#e01)：启动复位后完成首笔及第二笔写回，逐拍模型/协议检查与四类事件计数均通过；释放首拍/次拍边界另记 RST-009。 |
| RST-005 | WBB 初态 | 模块 IP | P0 | valid/reserved/issued 清零、发送轮询指针为初值、无有效发送 | 状态检查 | 本配置已闭合 | 检查IP可见空态和无有效发送；内部valid/reserved/issued编码及轮询指针不作后门观察目标。 | [E01](#e01)：a_reset_outputs 检查空态（full=0、reserveOk=1、send_valid=0、两查询不命中）；复位释放后模型逐拍比较通过。仅闭合 IP 可见初态，不声称直接读取内部状态位。 |
| RST-008 | 重复空闲复位 | 模块 IP + 集成 | P1 | 多次复位不产生锁、Slot、WBB 槽或响应泄漏 | 定向循环 | 未验证 | 仅重复空闲复位后的WBB槽和发送状态；当前环境需补重复复位支持。 | 当前 predictor/memory driver 在首次解除复位后再次遇到复位均报 TB_RESET；需先支持重复空闲复位，再检查复位后的槽与请求响应。 |
| RST-009 | 复位与外部输入边界 | 模块 IP + 集成 | P1 | 复位期间输入由 TB 约束为空闲；释放首拍、次拍分别覆盖；不对未门控 ready 强加为零要求 | 协议监视 + 边沿定向 | 部分覆盖 | 仅WBB输入空闲约束及复位释放后的接口行为。 | [E01](#e01)：a_reset_inputs 已检查复位期间源端空闲；base_test 释放后等待两个下降沿，尚未定向覆盖释放首拍、次拍请求。 |
| RST-010 | 运行中复位取消事务 | 模块 IP + 集成 | P1 | 覆盖 SEND、MISS_WAIT、重放、WBB 预留/已发送及 FIFO 非空；取消和迟到响应的系统约定先确认 Q-04 | 待确认后定向 + epoch 检查 | 待确认契约 | 仅WBB预留、待发、已发送阶段的取消与旧写响应隔离；契约确认后执行。 | Q-04 未确定取消与旧响应隔离规则；环境当前拒绝再次复位，未执行预留/待发/已发送三个阶段的热复位。 |
| RST-011 | 复位释放时序 | 模块 IP + 集成 | P1 | 常规仿真避开时钟有效沿释放；异步释放的 recovery/removal 由实现时序检查，不用 RTL 仿真代替 | TB 检查 + 实现时序分析 | 部分覆盖 | 检查WBB复位释放安排和恢复；recovery/removal保留为实现时序检查。 | [E01](#e01)：clk_rst_driver 在下降沿释放复位，两种时钟下运行通过；尚无实现阶段 recovery/removal 时序报告。 |

### 4.2 参数、地址与生成配置

| 编号 | 验证点 | 原验证层级 | 优先级 | 原检查内容与通过条件 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CFG-001 | 默认配置一致 | 配置检查 + 集成 | P0 | 32 set、4 way、64 B 行、32 b 字、4 Entry×4 Slot、4 WBB、双响应 FIFO 深度4，TB 与 RTL 一致 | 生成报告 + 端口检查 | 本配置已闭合 | 核对WBB槽数、块大小、行宽、地址宽、槽ID和总线ID，三方RTL/SV/C++一致。 | [E15](#e15)：当前 RTL 端口、生成的 SV 常量及 wbb_ref_create 的 C++ 参数校验一致：4槽、64 B行、32位地址/字、2位槽号、4位总线ID；42组初始化与运行通过。 |
| CFG-004 | 内存块对齐与重构 | 配置检查 + 集成 | P0 | 读地址为请求块地址；写地址为 victim tag/index 拼接；低 offsetWidth 位为零 | 事务检查 | 本配置已闭合 | 检查块对齐输入和发送地址保真；victim tag/index重构归顶层。 | [E02](#e02)、[E05](#e05)：不同块地址逐次与 send 比较；a_env_reserve_address/a_dut_send_payload 检查对齐，复用前后数据归属正确。victim 地址重构不属本层。 |
| CFG-005 | 行内字序与端序 | 配置检查 + 集成 | P0 | word0 对应 line[DATA_WIDTH-1:0]，首末字及每个字均无颠倒、截断 | 不同字不同图样 | 本配置已闭合 | 检查push行到send行及后端存储的逐字/字节映射。 | [E02](#e02)：逐字/逐字节递增及 walking-1/0 遍历512位，serial/pipeline 各1063笔原始数据回读通过；C++ 原始字节端序单测历史记录见 E02。 |
| CFG-006 | 读写总线 ID 映射 | 配置检查 + 集成 | P0 | MSHR/WBB 位次零扩展到 busIdWidth，数值相同的读写 ID 属于独立命名空间 | 端口断言 + 并发响应 | 本配置已闭合 | 仅WBB槽号到写ID的映射；读写同值ID隔离归顶层。 | [E03](#e03)、[E08](#e08)：四槽均使用，send ID 与预留槽对应；a_dut_send_payload 检查完整4位ID规范范围（高位零扩展），乱序响应按完整ID释放。 |
| CFG-007 | 参数合法性拒绝 | 配置检查 + 集成 | P1 | 非幂次组数/路数/Entry/Slot/WBB、零深度、tagWidth不足、ID装不下位次等按 require 拒绝 | Scala elaboration 负例 | 未验证 | 仅WBB槽数、行/地址/ID宽相关参数的生成拒绝与合法配置。 | 尚无 WBB 槽数、行/地址/ID 宽非法参数的 Scala elaboration 负例记录；SV/DPI 初始化拒绝不能替代生成阶段 require 的验证。 |
| CFG-008 | 数据宽度约束完整性 | 配置检查 + 集成 | P1 | DATA_WIDTH 必须整字节且为支持字宽；当前 DATA_WIDTH/8 整数除法可能遗漏非8倍数检查，见 Q-09 | 配置静态检查 + 负例 | 待确认契约 | 覆盖WBB行数据和共享字类型的宽度约束，关联Q-09。 | Q-09 的支持字宽/整字节宽约束仍待确认并用生成负例验证；仅当前32位字配置有运行证据。 |
| CFG-009 | 最小合法容量 | 配置检查 + 集成 | P1 | SETS=2、WAYS=2、Entry=1、Slot=1、WBB=1、FIFO=1；单条目索引编码和动态寻址不越界 | 生成 + 模块/集成回归 | 未验证 | WBB_ENTRIES=1及有效的一位槽端口/ID约束，不要求其他模块采用最小配置。 | 未生成并运行 WBB_ENTRIES=1 的 DUT/SV/C++ 一致配置；现有4槽结果不能替代。 |
| CFG-010 | 非默认合法容量 | 配置检查 + 集成 | P1 | 覆盖2/4/8路、不同 set/块/字宽、FIFO非幂次合法深度；按组合生成，不假定全笛卡尔积 | 配置回归 | 未验证 | 覆盖不同WBB槽数、块大小和可支持的数据/地址/ID宽。 | 尚无非默认槽数、块大小或数据/地址/ID宽回归；10 ns/4 ns 只属于时钟周期变化。 |
| CFG-012 | 总线资源约束 | 配置检查 + 集成 | P1 | 读在途不超过 Entry，写在途不超过 WBB；总线总容量语义见 Q-08 | 请求响应计数 | 本配置已闭合 | 只检查写在途数与槽数/写通道容量；读写共享总额度由顶层确认。 | [E03](#e03)、[E08](#e08)：写在途达到4，等待响应期间仍占满；响应按ID释放，driver/SVA 检查在途唯一与合法生命周期。仅闭合本层写容量，Q-08 的读写共享总额度留在顶层。 |

### 4.3 通用接口协议

| 编号 | 验证点 | 原验证层级 | 优先级 | 原检查内容与通过条件 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| IF-001 | 七条外部流握手 | 模块 IP + 集成 | P0 | cpu、cpuReadResp、cpuWriteResp、memReadReq、memWriteReq、memReadResp、memWriteResp 仅 valid&&ready 计一次传输 | 逐通道协议断言 | 本配置已闭合 | 仅send与memWriteResp两个Stream；reserve和push按各自使能契约检查。 | [E01](#e01)：42组真实 DUT 回归仅按 valid&&ready 计 send/response，四事件计数一致；[E14](#e14)另检查内存代理在响应背压期间不提前计接受。 |
| IF-002 | 外部反压保持 | 模块 IP + 集成 | P0 | valid&&!ready 时下一拍 valid 不撤回、payload 全字段稳定；不要求 valid=0 时稳定 | SVA + 随机反压 | 本配置已闭合 | 仅写请求与写响应两条流的保持要求。 | [E06](#e06)、[E12](#e12)：真实 DUT 发送背压保持通过 a_dut_send_stable/WBB_STABILITY 检查；[E14](#e14)检查响应源保持，[E13](#e13)含响应保持负例。当前 DUT 的响应 ready 恒高，响应背压证据属于环境自检。 |
| IF-004 | 一次传输一次副作用 | 模块 IP + 集成 | P0 | valid 连续高且 ready 连续高允许每拍不同事务；无 ready 时不重复计数、不提前释放 | 事务计数 + 状态断言 | 本配置已闭合 | 检查预留/push使能及写请求/响应各次接受只产生一次副作用。 | [E03](#e03)、[E07](#e07)、[E11](#e11)：满槽拒绝、连续逐拍发送、连续 reserve/push 均命中；模型、生命周期 SVA、握手计数及排空检查通过。 |
| IF-006 | X/Z 检测 | 模块 IP + 集成 | P0 | 复位结束后有效事务载荷、握手控制及动态索引无 X/Z，未初始化无效 RAM 数据除外 | 四态协议断言 | 本配置已闭合 | 仅WBB IO控制和有效载荷；无效发送载荷不强加已知值要求。 | [E01](#e01)：控制及有效地址/数据/ID/槽号均由四态 SVA 检查；[E13](#e13)的 unknown DUT control 负例确实触发 WBB_DUT_CONTROL_X。无效 send 载荷不要求已知。 |
| IF-008 | 无效周期隔离 | 模块 IP + 集成 | P1 | valid=0 时扰动 payload 不产生状态更新；查询口组合变化不视为事务 | 定向 + 状态检查 | 部分覆盖 | 检查reserve/push使能为0、写流valid为0时的载荷扰动和查询无副作用。 | [E04](#e04)已有纯查询及空态查询，无新增分配；尚缺 reserve_en/push_en/memWriteResp_valid=0 时主动扰动相应载荷的专项，目前 drive_idle 将其置零。 |
| IF-009 | 最快合法响应 | 模块 IP + 集成 | P1 | 覆盖请求后下一拍响应；请求响应同拍零延迟按 Q-03 确认后再要求 | 内存时序定向 | 部分覆盖 | 按WBB新规格检查最早下一拍写响应；同拍首次send与响应属于输入违约。 | 最早下一拍响应的契约已明确。[E09](#e09)配置1拍、[E12](#e12)允许1～8拍；缺少真实 DUT 上按ID配对并要求恰好1拍的命中检查。[E14](#e14)的精确1拍自检仅证明内存driver能力。 |
| IF-010 | 输入协议违规归因 | 环境自检 | P1 | TB 对错误ID、重复响应、未发先回、非法 alloc/merge/push 报环境错误；不要求当前DUT纠错 | TB 自检/负向测试 | 部分覆盖 | 自检非法push、未知/重复/提前写响应及非法地址是否归因到环境。 | [E13](#e13)已有无预留/错槽push、同一事务首次reserve与push同拍、重复地址、非法ID、未发先回、零拍响应和不对齐等负例及归因检查；尚缺独立的重复响应负例。 |

### 4.4 WBB 预留、push 与地址查询

| 编号 | 验证点 | 原验证层级 | 优先级 | 原检查内容与通过条件 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WBR-001 | 空槽选择 | 模块 IP | P0 | 首次及部分占用时 reserveOk 正确，reserveSlot 指向最低空闲位；槽号遍历 | 逐槽定向 + 模型 | 本配置已闭合 | IP契约按WBB规格检查合法空槽；最低下标是当前参考模型的精确条件，需单独标注口径。 | [E03](#e03)、[E05](#e05)：capacity首次填满覆盖4个不同槽，last_free=1；reuse每槽3次。空槽候选每拍检查。 检查：a_dut_reserve_slot + scoreboard精确比较C++ reserveSlot。 IP允许任意空槽；最低下标只登记为当前模型一致性通过，不提升为IP契约。 |
| WBR-002 | 预留接收条件 | 模块 IP | P0 | 仅 reserve.en&&reserveOk 建立预留；满时 reserve.en 不改已有槽 | 状态断言 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E03](#e03)、[E11](#e11)：capacity满时额外reserve被阻塞23拍；响应同拍仍拒绝，下一拍恢复；pipeline额外覆盖blocked_reserve=7。 检查：a_dut_capacity + capacity逐拍检查 + C++模型。 |
| WBR-003 | 预留立即记录地址 | 模块 IP | P0 | 预留后下一拍 q0/q1 均匹配该地址，push 前也能阻止同址读 | 双查询口定向 | 本配置已闭合 | 检查预留地址的两个查询结果及时可见；MSHR是否据此阻止读归顶层。 | [E04](#e04)：query覆盖reserved的双命中/仅q0/仅q1；流水在成功reserve下一拍的旧push沿观测对应地址命中。 检查：a_dut_query0/1 + check_overlap_queries。 仅地址查询立即可见已闭合；MSHR据此阻止读属于顶层。 |
| WBR-004 | 占用包含 reserved | 模块 IP | P0 | 只有 reserved 无 valid 也占槽；连续预留不同槽，不双重分配 | 状态模型 + 满边界 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E11](#e11)、[E10](#e10)：delayed全4槽只有reserved的满状态保持7拍；pipeline连续预留未复用旧push槽。 检查：a_dut_capacity/reserve_slot/overlap_slot + C++模型。 |
| WBR-005 | 占用包含 valid | 模块 IP | P0 | push 后 reserved 清零、valid 置位，占用连续无空窗 | 逐拍断言 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E03](#e03)、[E04](#e04)：capacity最后一个槽push时full仍高，full_push=1；query覆盖pending和issued占用。 检查：a_dut_capacity/query0/query1 + C++逐拍比较。 从IO验证占用连续及对应行为；不声称直接观察内部valid/reserved寄存器编码。 |
| WBR-006 | 满空组合 | 模块 IP | P0 | 全reserved、全valid、reserved/valid混合、仅剩一槽分别检查 full/reserveOk | 状态组合覆盖 | 本配置已闭合 | 严格下一拍模式检查全loaded/issued及混合占用；N>1的全reserved仅在显式延迟模式执行。 | [E03](#e03)、[E10](#e10)、[E07](#e07)：capacity覆盖仅剩一槽和reserved/loaded混合；arbitration覆盖全pending；capacity全issued仍full23拍；delayed全reserved7拍。 检查：容量SVA + full_push/all_sent_full/full_reserved/max_pending计数。 |
| WBR-007 | push 地址数据归属 | 模块 IP | P0 | push.slot 对应预留槽，保存整行数据且不改该槽地址或其他槽 | 不同地址/图样比对 | 本配置已闭合 | 检查本槽的地址/数据关联，并关联a_env_push_next检查严格下一拍的push槽号。 | [E05](#e05)、[E11](#e11)、[E02](#e02)：data_pattern九类模式1063笔；pipeline与reuse覆盖4槽并存、不同地址/数据及复用。逐笔保存reserve地址和push数据。 检查：a_env_push_next + a_dut_send_content + C++逐拍比较 + 输入原始记录/稀疏内存。 |
| WBR-008 | 仅预留不发送 | 模块 IP | P0 | reserved&&!valid 不成为发送候选，延迟 push 不发送旧数据 | 长延迟 push | 本配置已闭合 | 默认模式检查一拍reserved窗口；显式延迟模式已有driver及case，检查长延迟与全reserved窗口。 | [E11](#e11)、[E04](#e04)、[E10](#e10)：delayed的5笔均延迟push，最大13拍，全reserved7拍期间不得出现send。strict另检查一拍reserved窗口。 检查：a_dut_send_owner + C++send_valid比较。 |
| WBR-009 | push 槽与预留槽不同 | 模块 IP | P0 | 同拍 push 旧预留槽、reserve 新槽，两者各自生效 | 并发定向 | 本配置已闭合 | strict模式13笔写回、8次重叠；逐笔槽号/数据/下一拍push检查，覆盖满槽停顿恢复与尾部；新增a_dut_overlap_slot，详见[case记录](WBB_case规划_note.md)。 | [E11](#e11)：pipeline13笔、8次reserve/push重叠，覆盖满槽停顿恢复与尾部；双模式case进一步覆盖流水。 检查：a_dut_overlap_slot + 每笔槽/数据/下一拍检查。 |
| WBR-010 | 双查询口独立 | 模块 IP | P0 | q0/q1 同址、异址、各命中不同槽、只命中其一均正确 | 组合扫描 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E04](#e04)：query两种输入模式均命中同址双命中、异址双命中、单口命中和双miss；reserved/pending/issued均检查。 检查：check_query_coverage/check_overlap_queries + query SVA。 |
| WBR-011 | issued 仍参与查询 | 模块 IP | P0 | 写已发送未响应时同址仍被匹配且槽仍占用 | 状态/查询断言 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E04](#e04)、[E08](#e08)：query覆盖issued阶段双/单口命中；response_order逐次释放后仍查询其余issued地址。 检查：a_dut_query0/1 + query_matrix[3][3]/[3][0]/[0][3]。 |
| WBR-012 | 查询地址粒度 | 模块 IP | P1 | 输入均为块对齐地址；模块全地址比较由上层提供正确粒度，不让字地址误用 | 输入契约断言 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E01](#e01)、[E13](#e13)：所有正常case的查询逐拍要求已知且块对齐；SVA自检含misaligned query负例。 检查：a_env_queries。 检查上游输入契约，不要求WBB把未对齐地址自动转换为块地址。 |
| WBR-013 | 预留和释放并发 | 模块 IP | P1 | 旧槽响应释放与另一空槽预留同拍互不覆盖；满状态释放不要求组合旁路同拍再分配 | 边界定向 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E03](#e03)、[E11](#e11)、[E09](#e09)：event_collision串行reserve+response=1；流水=2。capacity满响应沿reserve仍阻塞，下一拍恢复。 检查：a_dut_capacity/reserve_slot + C++模型 + 交叉计数。 |
| WBR-014 | push 和释放并发 | 模块 IP | P1 | 不同槽同拍 push/响应释放正确；同槽冲突属于非法生命周期输入 | 并发 + TB 约束 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E09](#e09)：event_collision串行push+response=1；流水=2，含三/四事件同拍；push及response均有沿前归属检查。 检查：a_env_push_owner/response_owner + C++模型 + 交叉计数。 |
| WBR-015 | 槽复用 | 模块 IP | P1 | 槽释放后重新预留新地址和数据，无旧 issued/查询命中/数据污染 | 多轮循环 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E05](#e05)、[E11](#e11)：reuse三轮A/B/A，每槽3次；旧址miss/新issued地址hit=12，排空查询=33；串行与流水均通过。 检查：每槽reserve_uses + query SVA + 逐次send内容及最终内存。 |

### 4.5 WBB 发送、响应与仲裁

| 编号 | 验证点 | 原验证层级 | 优先级 | 原检查内容与通过条件 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WBS-001 | 有效发送候选 | 模块 IP | P0 | 仅 valid&&!issued 可发送，地址/整行数据/总线ID对应所选槽 | 模型 + 事务检查 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E04](#e04)、[E10](#e10)、[E07](#e07)、[E02](#e02)：reserved/pending/issued阶段均覆盖；多槽并存与1063笔数据模式，发送有效时逐槽比较保存地址/数据/ID。 检查：a_dut_send_owner/content/payload + C++模型。 |
| WBS-002 | 写请求反压保持 | 模块 IP | P0 | send.valid&&!ready 时保持所选槽及全部payload；反压期间插入新候选，专项 Q-01 | SVA + 插入候选 | 本配置已闭合 | 用户修复DUT及C++模型后，背压、延迟push及random seed1/2/3在10 ns/4 ns下全部通过，目标仍命中；详见[case记录](WBB_case规划_note.md)。 | [E10](#e10)、[E06](#e06)、[E12](#e12)：用户修复后backpressure仍命中held_id=3、competing_id=0、10拍stall及1次候选插入；random与delayed均通过。 检查：a_dut_send_stable + scoreboard WBB_STABILITY。 历史DUT问题已由用户修复；结论限本轮DUT哈希，保留修复记录。 |
| WBS-003 | 发送后不重发 | 模块 IP | P0 | 只有握手才置 issued，已发送槽在响应前不重复发送 | 发送ID集合 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E03](#e03)、[E07](#e07)、[E08](#e08)：capacity4槽发送后未响应持续23拍；每槽已发集合和send_owner拒绝已issued重复发送。 检查：a_dut_send_owner + memory outstanding唯一性 + 四事件计数。 |
| WBS-004 | 响应按 ID 释放 | 模块 IP | P0 | 乱序写响应释放对应 issued 槽，其他槽不变；读侧同值ID不干扰 | 乱序 + 独立模型 | 本配置已闭合 | 仅按写ID乱序释放；读侧同值ID不干扰由DCache顶层检查。 | [E12](#e12)、[E08](#e08)：按实际send ID逆序响应4笔，reordered=3；释放地址miss/其他issued地址hit查询6次。 检查：按ID pending表 + response_owner/query SVA + C++模型。 读侧同值ID隔离归DCache顶层，不阻止WBB写ID子项闭合。 |
| WBS-005 | 发送握手不等于释放 | 模块 IP | P0 | 发送后直到写响应握手仍占槽，不允许提前复用 | 状态断言 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E03](#e03)、[E11](#e11)：capacity全部4笔已send但仍保持full23拍，额外reserve不获准，收到response后才释放。 检查：a_dut_capacity + all_sent_full/full_response/recovery检查。 |
| WBS-006 | 释放清理 | 模块 IP | P0 | 响应后 valid/issued 清零，同址查询解除；下一次复用不携带旧数据 | 状态 + 复用 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E05](#e05)、[E08](#e08)：response_order逐次释放查询；reuse三轮每槽3次，旧址失效且新版本数据正确。 检查：query/send_content SVA + C++模型 + 稀疏内存。 从端口行为验证释放清理，不声称直接观察内部valid/issued编码。 |
| WBS-007 | 轮询顺序与回绕 | 模块 IP | P1 | 从 rrPtr 起选第一个候选，仅发送握手更新指针，覆盖末槽到首槽 | 独立RR模型 | 本配置已闭合 | IP检查轮询公平和回绕；精确起点/rrPtr次序属于当前模型一致性检查。 | [E07](#e07)、[E06](#e06)：arbitration统一放行4个pending候选，4个不同ID逐拍发送并末槽到首槽回绕1次；背压期间不改变已选择请求。 检查：check_send_burst + a_dut_rr_bound + C++精确顺序。 轮询公平和回绕为IP契约；精确起点和rrPtr更新由当前C++模型一致性另记。 |
| WBS-008 | 有限候选公平性 | 模块 IP | P1 | 候选集合固定、ready持续有效时，每个候选均发一次；公平性不替代反压载荷稳定检查 | 有界计数 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E07](#e07)：固定4个pending、ready放行后每槽恰好一次，slots=1111且burst=4。 检查：check_send_burst + a_dut_rr_bound。 |
| WBS-009 | 全满恢复 | 模块 IP | P1 | 全槽已发送等待响应，任意合法响应后容量恢复且其他事务保留 | 满负载定向 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E03](#e03)、[E11](#e11)、[E08](#e08)：capacity全issued/full时响应释放，下一沿接受等待项并使用刚释放ID；response_order逆序释放保持其余槽。 检查：full_response/recovered计数 + capacity/query SVA。 |
| WBS-010 | 不同槽发送与释放同拍 | 模块 IP | P1 | send一个槽并释放另一个槽，计数、候选、rrPtr正确 | 交叉时序 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E09](#e09)：event_collision串行send+response=1；流水四事件同拍包含不同槽send与response。 检查：send/response owner + C++模型 + send_response_cycles。 |
| WBS-011 | 持续吞吐 | 模块 IP | P1 | 多个槽已就绪且ready有效时连续发送；记录是否出现非必要空泡 | 性能统计 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E07](#e07)：arbitration的4个pending候选连续4拍发送，相邻send_cycles差1，全部4槽及回绕命中。 检查：check_send_burst/max_send_burst。 |
| WBS-012 | 长期往返 | 模块 IP | P1 | 重复预留/push/发送/乱序释放后回到空态，无容量泄漏 | 模块随机 + 排空 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E05](#e05)、[E12](#e12)：random每次32批128笔，批间排空复用，随机ready/响应延迟/响应ID；seed1/2/3×两模式×两周期通过。 检查：逐笔C++/SVA + 四事件128计数 + 每批wait_until_empty/最终排空。 |

### 4.6 系统不变量与进展

| 编号 | 验证点 | 原验证层级 | 优先级 | 原检查内容与通过条件 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| INV-005 | 资源计数守恒 | 模块 IP + 集成 | P0 | Entry、Slot、WBB、FIFO各自分配/接受/释放数量一致，计数不负不越界 | 独立计数模型 | 本配置已闭合 | 仅WBB reserve/push/send/ack及槽占用守恒。 | [E03](#e03)、[E11](#e11)：所有42次运行reserve/push/send/response数量相等；capacity/pipeline覆盖0..满以及释放恢复。 检查：scoreboard计数 + IO槽生命周期 + memory pending容量。 |
| INV-006 | ID唯一在途 | 模块 IP + 集成 | P0 | CPU同ID在响应前不复用；内存读写分别无重复在途ID；TB和DUT责任分开 | ID集合断言 | 本配置已闭合 | 仅写ID在途唯一及响应前禁止复用。 | [E03](#e03)、[E12](#e12)、[E08](#e08)：多槽在途和乱序响应下，memory outstanding集合检查发送ID不重复；SVA发送必须尚未issued，reserve必须空槽。 检查：a_dut_send_owner/reserve_slot + memory outstanding检查。 |
| INV-007 | 有条件排空 | 模块 IP + 集成 | P0 | 停止新请求、所有ready最终允许、每笔内存响应最终返回时，FIFO/Entry/WBB最终排空 | watchdog + 收尾断言 | 本配置已闭合 | 停止新写回、外部最终接收并返回响应后，WBB及内存待响应队列排空。 | [E01](#e01)：每个case停止激励并放行响应后，由watchdog保护排空；C++模型空态及内存pending/outstanding/active均空。 检查：wait_for_drain + predictor/memory driver check_phase + 四事件计数。 |
| INV-010 | 无饥饿断言前提 | 模块 IP + 集成 | P1 | 固定优先发送/命中优先重放不保证无限新流量下公平；检查有限集合进展，持续负载只统计 | 约束活性 + 性能统计 | 本配置已闭合 | WBB轮询的有限集合进展；不采用MSHR固定优先级的饥饿豁免。 | [E07](#e07)：固定4候选统一放行且逐拍服务完毕；IO公平断言计其他槽成功发送而不计外部反压周期。 检查：check_send_burst + a_dut_rr_bound。 |
| INV-011 | 断言非空触发 | 环境自检 | P1 | cover对应前件确实发生；reset disable条件不把所有窗口屏蔽 | assert/cover配对审查 | 部分覆盖 | WBB 验证环境的对应自检项，按本文件接口和模型实例执行。 | [E01](#e01)：本轮13个现有cover实例均有非零match，包括四槽reserved/issued query、reserve_push/full_release/overlap/stall_release/send_and_response。 检查：SVA cover汇总 + case场景计数。 现有场景非空已证实；尚无每条assert前件到cover的完整配对与自动闭合审查，不能把13个cover当全部断言前件覆盖率。 |

### 4.7 端到端收尾与后端一致性

| 编号 | 验证点 | 原验证层级 | 优先级 | 原检查内容与通过条件 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| END-003 | 响应与ID配对 | 环境自检 + 集成 | P0 | 按类型/ID查pending，不按全局FIFO配对，不把跨行乱序当错误 | 乱序事务自检 | 本配置已闭合 | 仅WBB写响应按ID配对，支持乱序完成。 | [E12](#e12)、[E08](#e08)：response_order真实逆序4个send ID，memory通过find_pending_index(id)删除对应项，后续查询保留其余槽。 检查：memory按ID配对 + expected_ids顺序检查。 |
| END-007 | 逐次写回版本检查 | 集成 + 环境自检 | P0 | 写回事务数据按该次victim版本比对，不能拿未来CPU写后的最终值直接比较 | 事件/版本模型 | 本配置已闭合 | 比较每次接受的push版本与对应send；Cache victim版本构造归顶层。 | [E05](#e05)、[E02](#e02)、[E12](#e12)：reuse A/B/A及random重复地址更换数据，C++与IO checker按各次push存储版本，每次send立即比较；最终内存另按末版本比较。 检查：a_dut_send_content + predictor/scoreboard逐次比较 + 原始输入记录。 WBB push到send版本已闭合；Cache victim内容从CPU历史重建归顶层。 |
| END-009 | 结束前无挂起事务 | 集成 + 环境自检 | P1 | CPU pending、后端读写pending、模型队列和未检查FIFO均排空，错误数为零 | check/report阶段 | 本配置已闭合 | 仅WBB模型、实际/期望内存检查、写请求/响应及在途ID收尾。 | [E01](#e01)：42次运行均通过check_phase排空、reserve/push/send/response守恒、实际/期望稀疏内存比较和UVM错误统计。 检查：predictor/memory/scoreboard check_phase + WBB_TEST_PASS + 回归错误扫描。 |

### 4.8 性能与资源利用

| 编号 | 验证点 | 原验证层级 | 优先级 | 原检查内容与通过条件 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PER-008 | 仲裁等待分布 | 模块 IP + 集成 | P2 | 记录发送/填充/重放/写回等待，区分外部反压与内部优先级，持续命中饥饿仅记录见Q-07 | 直方图 + 极值 | 部分覆盖 | 仅预留等待、待发仲裁和写响应等待分布。 | [E03](#e03)、[E10](#e10)、[E11](#e11)记录阻塞拍数、最大push延迟及事件拍数；尚缺预留等待、发送仲裁、写响应等待的完整直方图，以及内外部等待原因分类。 |
| PER-009 | 资源水位分布 | 模块 IP + 集成 | P2 | Entry/Slot/WBB/FIFO从0到满及持续满周期，确认压力确实打到目标 | 功能覆盖 + 统计 | 部分覆盖 | 仅WBB与内存待响应队列的水位、满状态和恢复。 | [E03](#e03)、[E07](#e07)、[E10](#e10)已命中满槽、最大pending、全reserved及恢复；尚缺 WBB/内存待响应队列各水位的完整分布。 |

### 4.9 随机压力与交叉场景

| 编号 | 验证点 | 原验证层级 | 优先级 | 原检查内容与通过条件 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RND-001 | WBB约束随机 | 模块 IP | P0 | 合法reserve/push/发送/乱序写响应交错，随机反压，独立槽模型检查 | 多种子模块回归 | 本配置已闭合 | WBB 独立IP端口、合法输入前提及对应模型/断言检查。 | [E12](#e12)：seed1/2/3在串行/流水和10ns/4ns均通过；每次32批128笔，ready随机60%，响应延迟1..8拍，响应ID随机选择。 检查：C++模型 + IO SVA + 原始数据与内存检查 + 随机阶段31批重叠检查。 |
| RND-008 | 资源临界交叉 | 模块 IP + 集成 | P0 | Entry/Slot/way/WBB/FIFO最后一个空位与分配/释放、响应/merge同拍 | 定向偏置随机 | 本配置已闭合 | 仅WBB最后空槽、分配/释放及写通道交叉。 | [E03](#e03)、[E11](#e11)、[E12](#e12)、[E09](#e09)：capacity最后空槽接受1次、满时response后恢复；pipeline满时旧push/阻塞reserve共存；event_collision覆盖释放与reserve/push/send及四事件同拍。 检查：last_free/full_response/recovery/blocked_push/三四事件计数 + C++/SVA。 |
| RND-010 | 长跑与可重现 | 模块 IP + 集成 | P1 | 记录seed、配置、RTL版本；多轮排空/复用后无容量、ID和数据泄漏 | 固定seed+扩展seed | 部分覆盖 | WBB合法随机流量长跑，多轮复用后排空并保存seed/配置。 | [E12](#e12)：本轮保存seed/config/RTL哈希与独立日志波形，seed1/2/3各32批128笔、每批排空并复用地址，两输入模式通过。 检查：inputs.json/summary.json + completed_batches=32/lines=128 + 排空检查。 seed/配置/版本记录及32批128笔复用排空已验证；长跑规模尚未量化，需确定规模并补对应运行证据，不能自定128笔即达到长跑要求。 |

### 4.10 验证环境、覆盖率与构建自检

| 编号 | 验证点 | 原验证层级 | 优先级 | 原检查内容与通过条件 | 检查方式 | 状态 | 本文件检查范围 | 当前证据与剩余项 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ENV-001 | 握手边沿采样 | 环境自检 | P0 | monitor使用mon_cb input #1step，不在握手后半拍读已变化payload；同拍双响应均采集 | monitor事务自检 | 本配置已闭合 | WBB 验证环境的对应自检项，按本文件接口和模型实例执行。 | [E09](#e09)真实 DUT 同拍send/response已命中；monitor 的 mon_cb input #1step 保留沿前载荷。[E14](#e14)使用真实monitor独立检查周期/数据。WBB只有一个响应端口，不套用“同拍双响应”。 |
| ENV-002 | driver持有请求 | 环境自检 | P0 | 请求到握手保持字段，item_done代表请求接受而非响应完成 | driver协议断言 | 本配置已闭合 | 串行单笔或流水批次的reserve/push完成后item_done；写响应由内存代理独立处理，不作为item_done条件。 | [E03](#e03)、[E11](#e11)：满槽reserve保持、阻塞时旧push继续、尾部push和恢复均检查；item_done 在单笔/整批reserve与push完成后返回，内存响应独立完成。 |
| ENV-003 | 对象生命周期 | 环境自检 | P0 | 每个发布事务独立对象，FIFO和pending表不被复用句柄覆盖 | TLM对象自检 | 本配置已闭合 | WBB 验证环境的对应自检项，按本文件接口和模型实例执行。 | [E01](#e01)、[E05](#e05)、[E11](#e11)：monitor每拍创建新sample；activity保存只读历史，base在sequence结束后逐笔与原始地址/槽/数据比较，旧记录未被后续对象覆盖。 |
| ENV-004 | 激励合法性 | 环境自检 | P0 | 单拍单CPU请求、对齐、ID唯一、模块alloc/merge/push前提、后端响应合法均检查 | TB前提断言 | 本配置已闭合 | 块对齐、成功预留同址唯一、push归属、合法写ID和响应时机。 | [E01](#e01)、[E13](#e13)：SVA检查地址对齐、成功预留同址唯一、push归属/下一拍时序、写ID唯一及响应前提；42组合法回归和对应输入违约负例通过。尚缺的负例分别登记 IF-010/ENV-005。 |
| ENV-005 | scoreboard负例 | 环境自检 | P0 | 注入错误数据、错误ID、重复响应、漏响应、错误写回确保检查器报错；负例为环境测试非DUT功能 | 检查器单测 | 部分覆盖 | WBB 验证环境的对应自检项，按本文件接口和模型实例执行。 | [历史缺陷记录](../../Architecture/DebugNote/WBB-DUT-001_发送背压保持问题.md)验证 WBB_STABILITY 能报真实错误；[E13](#e13)验证SVA。尚缺完整 scoreboard 错误数据/ID、重复或遗漏响应、错误写回的注入单测。 |
| ENV-006 | 超时和结束 | 环境自检 | P0 | 每阶段/全局watchdog有限且明确，objection不提前结束，超时必须使回归判失败 | 超时自检 | 部分覆盖 | WBB 验证环境的对应自检项，按本文件接口和模型实例执行。 | 已有全局周期watchdog、reserve超时、进程超时和42组正常收尾记录；尚缺故意阻塞并验证超时最终被回归报告为FAIL的自检。 |
| ENV-007 | 回归结果判定 | 环境自检 | P0 | 不能只依赖simv进程退出码；检查UVM_ERROR/FATAL及case成功标记，避免fatal被误记pass | 日志判定脚本自检 | 本配置已闭合 | WBB 验证环境的对应自检项，按本文件接口和模型实例执行。 | [E16](#e16)：历史6组 simv exit_code=0 仍被判FAIL；当前脚本检查UVM错误、成功标记、事件摘要和输入模式，最新42组判PASS。不以进程退出码代替结果检查。 |
| ENV-008 | 覆盖采样有效性 | 环境自检 | P1 | 状态、资源水位、仲裁冲突、每Entry/Slot/set/way仅在相关有效事件采样 | covergroup审查 | 本配置已闭合 | 槽号、reserved/pending/issued、查询命中、容量与发送反压覆盖。 | [E03](#e03)、[E04](#e04)、[E06](#e06)、[E11](#e11)：activity按沿前状态分类查询/资源，在有效握手时采槽号与事件；各case要求具体计数命中。查询无使能，逐拍采样合理；完整水位分布另记PER-009。 |
| ENV-009 | 关键交叉闭合 | 环境自检 | P1 | merge状态×读写序列×word关系；反压×候选新增；淘汰×末拍写；满资源×释放；policy×lockmask | 交叉覆盖 | 本配置已闭合 | 反压×新增候选、槽水位×预留结果、释放×预留/push/send、槽状态×查询。 | [E03](#e03)、[E04](#e04)、[E06](#e06)、[E09](#e09)、[E11](#e11)：背压×新增候选、水位×预留结果、释放×reserve/push/send、三/四事件同拍、槽阶段×查询均有专项必命中计数。 |
| ENV-010 | 模块/IP构建隔离 | 环境自检 | P1 | WBB/MSHR/CacheMem/Policy wrapper与顶层使用独立top/filelist，无重名顶层和过期RTL | 编译/生成检查 | 本配置已闭合 | WBB 验证环境的对应自检项，按本文件接口和模型实例执行。 | [E15](#e15)、[E17](#e17)：WBB独立sim_wbb入口和generated/wbb输入一致；generate、默认冷编译/仿真、strict/delayed构建、DPI/SVA/内存自检全部通过，旧路径缺口已修复。 |
| ENV-011 | 波形与版本对应 | 环境自检 | P1 | Verdi KDB、FSDB、log、seed、参数、策略对应同一轮构建，case波形名区分 | 构建记录 | 本配置已闭合 | WBB 验证环境的对应自检项，按本文件接口和模型实例执行。 | [R42](#r42)：同轮独立log/FSDB/TCL及seed/input/profile/clock/DUT哈希均可追溯，18个记录输入哈希在R42登记时核对一致。目录迁移后保留原记录，工具路径/源码版本变化另记E17；迁移后的首次构建不复用旧simv。 |
| ENV-012 | 状态与证据可追溯 | 环境自检 | P1 | 每个验证点绑定test/sequence/checker/coverage/log；一个case可覆盖多点，但不能由smoke推定全部通过 | 闭合审查 | 本配置已闭合 | WBB 验证环境的对应自检项，按本文件接口和模型实例执行。 | 本次对75项逐条登记状态、case/检查器/场景与证据入口；缺口明确列出，历史记录与当前R42区分。此项表示追溯关系已同步，不代表其他未完成点自动闭合。 |

## 5. 待确认契约与专项风险

以下保留原Q编号和原问题描述，原问题涉及其他层的内容按“本文件处理范围”限定。源码阅读提出的风险仍需定向验证，不能据此直接判断DUT失败。

| 编号 | 原问题 | 原关联验证点 | 原处理与判定 | 本文件处理范围 |
| --- | --- | --- | --- | --- |
| Q-01 | WBB send 和 MSHR replay 当前由候选集合及 rrPtr 组合选取，未见独立的挂起选择锁存；反压期间新增更靠前候选可能改变输出 | IF-002/003、WBS-002、MSC-013 | 增加“反压 + 新候选”模块定向和稳定性断言。MSHR memReadReq 已有 sendHold，不能由此推定另两条流也安全 | WBB历史问题已复现并由用户补充保持逻辑；修复后26组复核通过，当前含流水变体的R42共42组通过，背压新增候选仍命中。MSHR部分仍需其IP验证，不能从WBB结果推定。 |
| Q-04 | 运行中复位后的迟到读写响应、CPU ID复用以及已接收写的取消语义未统一 | RST-010、IF-010 | 系统须约定清空后端pending、隔离epoch或等效措施。仅清DUT状态不足以安全接收旧ID响应；未定义前不声称热复位通过 | WBB取消与旧写响应隔离。 |
| Q-08 | NUM_BUS_OUTSTANDING用于ID位宽/约束，但未见读写总量共享额度控制；若设为小于Entry+WBB，不能仅凭参数名断言总量受限 | CFG-012 | 明确该值为每通道ID空间还是共享容量。共享上限由接收方ready或DUT额度管理保证后，再设置对应断言 | 仅写ID空间与写在途容量，读写共享额度见顶层。 |
| Q-09 | DATA_WIDTH/8使用整数除法，缺少显式DATA_WIDTH%8==0可能允许无效字宽通过部分require | CFG-008 | 补参数负例确认；将整字节宽和支持字宽列为约束完整性检查，文档不替代实现修复 | WBB行/字宽及DPI模型配置一致性。 |

原关联编号若未在本文件列出，可在另外两个文件按编号查找。

## 6. 证据与闭合登记

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

这些计数证明已定义场景确实发生；INV-011仍需补每条assert前件与cover、disable条件的完整配对审查。

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

[回归脚本](../../verif_mshr/sim_wbb/script/run_wbb_regression.py)同时检查进程状态、UVM_ERROR/FATAL汇总和实际报错行、case成功标记、事件摘要及输入模式。[修复前报告](../../verif_mshr/sim_wbb/work/regression/reports/run_20261119_080300_487790/summary.json)包含6组`exit_code=0`却被正确判为FAIL的真实记录，证明没有仅依赖simv退出码。

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
