# MSHR IP 验证 case 规划

版本：v1.2（功能case落地并登记replay保持失败）；更新日期：2026-11-24。

MSHR 验证分成 **21组功能case和复位、长跑2组配套场景**。先打通单条目读写，再分别检查Entry容量、Slot合并、数据版本、发送/填充/重放、锁和并发，最后做随机压力与长时间复用。当前C01～C21已有独立test/sequence，并新增S04的`mshr_long_run_test`；默认`mshr_base_test`仍只做空态启动。修复后完整矩阵52/52通过，原replay保持问题已复核关闭；修复前失败记录保留在文末历史中。复位及未确认扩展本轮不执行。

验证点编号对应 [MSHR IP验证](MSHR_IP验证.md)，独立接口契约见 [MSHR IP架构文档](../../Architecture/MSHR_IP架构设计文档.md)，其依据为 [Cache架构文档v2](../../Architecture/Cache架构设计文档v2.md) §4、§7、§10.4、§13、用户确认事项及 [设计取舍记录](../../Architecture/设计问题与取舍记录.md)。已有 [C++ MSHR模型](../../RefModel/Cache/MSHR.hpp)继续作为参考模型；[C++模型单测](../../RefModel/test/test_mshr.cpp)可供适配自检参考，其结果不替代RTL的UVM验证。

## 验证范围和接口约定

本计划只列DUT行为场景。输入合法性、模型调度和检查器实现属于验证方法，在实际验证及缺陷定位中检查；不设置独立环境验收矩阵，也不将其完成作为DUT验证点闭合条件。参数生成负例和非默认硬件配置不在当前固定规格DUT范围内。

MSHR独立环境直接驱动alloc、merge、q0/q1、内存读响应、fillReady及replay.ready，观察查询结果、内存读请求、fill、replay和lockMask。CPU流水线、Stage2冻结、victim选择、WBB写回和CacheMem实际写端口连接由DCache顶层验证。本阶段不实例化整个DCache，也不改动WBB环境。

设 `N=MSHR_ENTRIES`、`P=MSHR_MAX_PENDING`、`W=WORDS_PER_BLOCK`。首轮使用默认N=4、P=4、32个set、4个way、64 B行、32位字/地址、5位CPU ID、4位总线ID。所有等待、响应和超时均用周期数；时钟配置仍由TB顶层创建并逐级传递。

| 接口 | 提交与比较规则 |
| --- | --- |
| alloc | 只有en，没有ready。沿前存在空Entry，块地址不与有效Entry重复，且目标set/way未被占用，才允许单拍提交；记录沿前freeEntry作为实际分配位置。满时请求留在driver中等待，不能持续拉高alloc.en试探。 |
| merge | 只有en，没有ready。按沿前命中条目确认SEND/MISS_WAIT且有空Slot后单拍提交；`mergeable`表示状态允许，还必须同时满足`slotFree`。Slot满或FILL时不得继续提交。 |
| q0/q1 | 没有使能，持续携带合法tag/index；两口独立。hit=0时不硬比entry/slotFree/freeSlot等无意义字段；slotFree=0时freeSlot无效；hasFree=0时freeEntry无效。不能拿C++的-1哨兵直接比较SV无效索引。 |
| memReadReq / memReadResp | 只在valid&&ready计一次事务；发送方在背压期间保持valid与整个payload。正常场景响应最早安排在请求握手后下一拍，每拍最多一个读响应。 |
| fill | 以fill.en&&fillReady作为一次填充接受；fill没有Entry ID，通过原alloc的tag/index/way识别所属条目。en承担valid语义，背压时必须保持选择及全部载荷到握手。 |
| replay | 以valid&&ready接受一笔Slot完成；接口只有类型、CPU ID和数据，通过CPU ID记录追溯Entry/Slot。读响应比较数据；写响应数据不作功能值要求，但背压期间仍遵循整个Stream载荷保持。 |
| lockMask | 当前公开端口为打包Bits，映射`lockMask[set * NUM_WAYS + way]`。逐拍检查所有位，不能只检查被访问的那一位。 |

以E[n]表示上升沿。所有接受条件按沿前状态判定，状态变化从该沿后可见，clocking block沿前采样在E[n+1]检查更新结果。alloc在E[n]生效后最早E[n+1]发送；读响应在E[n]接受后最早E[n+1]接受fill；同Entry的fill在E[n]接受后最早E[n+1]接受首个replay。最后replay在E[n]握手后才释放Entry及锁；沿前已满时不要求同沿分配刚释放的Entry。不同Entry的fill和replay可以同拍。

一笔上游transaction对应一个Slot请求，保存读写类型、块/字位置、写数据、CPU ID和两个查询地址；driver按场景选择alloc或merge，提交后即可item_done，不等待整条Entry完成。这样连续请求自然能形成多Slot、多Entry在途，不需要把一笔请求从alloc到最终replay都串行等待。请求随机化和场景调度放在sequence，test只做配置、启动、观察和通过判定。

## 实施前需要区分的契约

| 事项 | 先执行的范围 | 暂不作通过结论的部分 |
| --- | --- | --- |
| MSHR复位 | 用户已明确统一为异步低有效；MSHR两个生成入口均显式ASYNC/LOW，TB直接连接resetn，基础复位SVA启用 | 不再采用高有效兼容取反。停钟异步复位、重复复位及热复位取消仍需要专门场景，热复位沿用Q-04待确认。 |
| alloc与merge同拍 | 每周期只提交一笔CPU请求，alloc与merge互斥 | 双提交不支持；发送、响应、fill、replay仍可与单上游提交并发 |
| fillReady反压，Q-02（已确认） | 阻塞不推进、不丢fill；en及全部载荷保持到握手，动态新候选不能抢占 | 不要求低下标优先或轮询；现有保持SVA和动态候选证据待补 |
| 最快读响应，Q-03（已确认） | 最小延迟1拍，按实际握手测量 | 不支持零拍；内存侧保证响应最早在请求握手后下一拍有效。 |
| 运行中复位，Q-04 | 空态复位及正常排空单独执行 | SEND、等待响应、待fill、重放中取消如何处理，迟到响应及CPU ID如何隔离，先明确后运行。 |

MSA-002按黑盒范围检查分配后的IO行为。hasWb/wbSlot不增加内部保存检查；未来有性能或扩展需求再定义内部探测。MSA-003等状态/计数要求同样通过查询、事件顺序、数据和排空检查外部行为。

<a id="c00"></a>

## 公共检查方法和模型接入 C00

复用已有C++ MSHR模型和 [C++稀疏内存](../../RefModel/MEM/SparseMemory.hpp)，新增MSHR专用的DPI适配及SV封装，不另写完整MSHR行为模型。内存代理的SV driver负责ready、响应延迟、顺序和握手，C++稀疏内存只负责数据存储。预置行数据由sequence准备，经内存代理写入外部MEM模型，不通过后门修改DUT。

内存读请求握手时保存`{ID, 块地址, 原始行R0, 接受周期, 计划响应周期}`，以后按ID返回该快照。可以配置FIFO、逆序、指定ID、随机响应和连续拍返回；一旦响应valid呈现，在握手前固定ID及整行数据。正常MSHR IP没有写内存端口，Slot写只影响fill行，**不得把合并写直接写回这份后端内存**。fill的实际/期望记录与外部MEM分开保存。

MSHR模型每拍按照“输入沿前快照→读取预测输出→比较→tick”调用。`sendReq()`会记录呈现的选择，`fillReq()`会设置本拍呈现标志，两者不是纯getter，必须在tick前按固定流程调用，不能由不同checker反复随意查询。响应输入使用实际握手，模型的fill_ready/replay_ready使用相同沿前输入；四态有效载荷先检查X/Z，再转换为C++数据。

| 公共检查 | 记录和通过要求 |
| --- | --- |
| 协议和归属 | SVA检查有效字段、Stream保持、合法Entry/Slot、唯一块、唯一set/way、ID空间及响应前提；按IO事件建立生命周期，区分DUT错误与环境错误。 |
| 正确性 | C++逐拍比较查询、发送、fill和replay；独立接口断言检查容量、顺序、保持和释放。模型与DUT同样输出不代表符合规格，特别是replay保持风险Q-01。 |
| 槽顺序与历史读值 | 接受alloc/merge时保存不可变Slot顺序、ID及写操作记录。拿到R0后确定各读的期望值，后续Slot写不能改掉旧读期望。写Slot已replay后，其写历史仍保留至整个Entry释放，以供后续读检查。 |
| 锁 | 现有C++模型没有lockMask输出；从实际alloc和该Entry最后replay事件维护IO占用记录，计算set/way锁矩阵作独立协议检查，不复制完整模型。 |
| ID与生命周期 | 同一Entry位次复用时增加环境侧生命周期编号，记录不能被新事务覆盖。CPU ID在该Slot replay握手后才可复用；IP把replay sink视为消费端，顶层响应队列后的ID寿命另验。 |
| 守恒与收尾 | 无取消场景下：alloc数=内存读请求数=读响应数=fill接受数=Entry释放数；alloc数+merge数=replay接受数，读写类型分别核对。停止激励、放行全部接收后，Entry/Slot、读pending、预期replay与lockMask全空。 |
| 场景有效性 | 每个case除了数据/协议通过，还必须达到自己的场景计数；例如ready低但没有valid，不能算发生背压。状态覆盖由事件推导，不能把模型state当作观测到的DUT状态。 |

## 功能 case 清单

各命名case已实现；表中目的为验证责任，实际执行结果及尚未覆盖的条件见文末记录。

基础case使用`mshr_smoke_sequence`，其余case配套对应的`*_sequence`，公共激励方法放在`mshr_base_sequence`；公共等待、计数、排空、错误报告放在`mshr_base_test`，子test不重复实现。C08是确定性位置遍历，避免把所有Entry/Slot覆盖寄托给随机激励。

| 编号 | case | 主要目的 | 主要验证点 |
| --- | --- | --- | --- |
| [C01](#c01) | `mshr_smoke_test`（继承`mshr_base_test`） | 单读、单写完整生命周期 | MSA-002、MSA-003、MSB-001、MSB-006、MSB-007、MSC-001、MSC-003、MSC-004、MSC-007、MSC-010、MSC-014 |
| [C02](#c02) | `mshr_query_test` | 双查询口、匹配键及阶段边界 | MSA-001、MSA-004、MSA-005、MSA-008 |
| [C03](#c03) | `mshr_entry_capacity_test` | Entry从空到满及满表合并 | MSA-001、MSA-010、MSA-011、MSA-017 |
| [C04](#c04) | `mshr_slot_capacity_test` | SEND和MISS_WAIT各填满Slot | MSA-003、MSA-006、MSA-007、MSA-009、MSB-006、PER-003 |
| [C05](#c05) | `mshr_merge_matrix_test` | 读写组合和写标志累积 | MSA-006、MSA-007、MSA-012、MSA-015、MSB-006、MSC-002、MSC-003、MSC-009、PER-003 |
| [C06](#c06) | `mshr_data_pattern_test` | 返回行及合并行的数据完整性 | MSB-011、CFG-005、MSC-001、MSC-002、MSC-003、MSC-009 |
| [C07](#c07) | `mshr_read_view_test` | 每个读Slot只见前序写 | MSC-002、MSC-003、MSC-008、MSC-009、MSC-010、MSC-011、MSC-012 |
| [C08](#c08) | `mshr_entry_slot_sweep_test` | 确定性遍历所有Entry和Slot | MSA-002、MSA-016、CFG-002、CFG-006 |
| [C09](#c09) | `mshr_send_backpressure_test` | 挂起读请求期间插入更低位候选 | MSB-002、MSB-005、MSB-006、IF-002、IF-004 |
| [C10](#c10) | `mshr_send_arbitration_test` | 发送低位优先与仅选中者推进 | MSB-003、MSB-004、MSB-006、MSB-007、INV-010 |
| [C11](#c11) | `mshr_response_order_test` | 按ID乱序及连续拍响应 | MSB-008、MSB-009、MSA-011 |
| [C12](#c12) | `mshr_response_latency_test` | 真实DUT的最快和可变响应 | MSB-013、IF-009、LCK-003 |
| [C13](#c13) | `mshr_fill_backpressure_test` | 待填充阻塞与恢复 | MSC-004、MSC-005、MSC-007、LCK-003、IF-004 |
| [C14](#c14) | `mshr_fill_arbitration_test` | 多条待填充行的归属和顺序 | MSC-001、MSC-004、MSC-006、MSC-007、INV-010 |
| [C15](#c15) | `mshr_replay_backpressure_test` | 挂起replay及动态候选插入 | MSC-010、MSC-012、MSC-013、MSC-014、IF-003、IF-002、LCK-004 |
| [C16](#c16) | `mshr_replay_arbitration_test` | Entry间轮询和Entry内顺序 | MSC-010、MSC-012、MSC-016、MSC-017、INV-010 |
| [C17](#c17) | `mshr_lock_test` | 锁建立、保持、释放及全矩阵 | LCK-001、LCK-002、LCK-003、LCK-004、LCK-008、LCK-009、MSC-014 |
| [C18](#c18) | `mshr_reuse_test` | Entry、Slot和CPU ID多轮复用 | MSC-014、MSC-015、MSA-017、INV-005、END-009 |
| [C19](#c19) | `mshr_event_collision_test` | 接受边沿的同拍组合 | MSA-014、MSA-017、MSB-010、MSC-018、RND-008 |
| [C20](#c20) | `mshr_random_test` | 合法随机交错和资源边界 | RND-002、RND-008、RND-010 |
| [C21](#c21) | `mshr_idle_payload_test` | 无效载荷扰动和查询无副作用 | IF-008、IF-006 |

## 各 case 的场景与通过条件

<a id="c01"></a>

### C01 单读、单写完整生命周期

`mshr_smoke_test`。当前基础实现已通过10 ns/4 ns两组运行，见下方框架证据。

- 激励：预置两个逐字不同的内存块，依次提交一笔读和另一块的单字写，各自完成全部生命周期。请求ready、fillReady、replay.ready先保持有效，响应延迟2拍；上游提交后不强制等第一条Entry排空才提交第二条。
- 检查：读返回对应字，纯读fill为原行且dirty=0；写未命中同样先读整行，只覆盖目标字且dirty=1，写replay只核对类型和CPU ID。两条生命周期的目标tag/index/way正确，最后查询miss、锁解除。
- 必须命中：读/写各1个Entry生命周期；总alloc/readReq/readResp/fill/release各2，replay=2；每条均满足先响应、再fill、再replay。

<a id="c02"></a>

### C02 双查询口、匹配键及阶段边界

`mshr_query_test`。

- 激励：分别把条目停在SEND、MISS_WAIT、待fill和重放阶段；q0/q1轮流查询同块、不同已占块、未占块、同tag异index、同index异tag。通过相同tag/index但不同wordOff的Slot验证同行合并。
- 检查：两个口独立且同址一致；SEND/MISS_WAIT可合并，FILL直到释放前仍hit但mergeable=0。先按有效条件屏蔽索引字段，不要求未命中时输出固定零。
- 必须命中：两个查询口×各阶段×单口/双口命中或miss；同tag异index、同index异tag、首末index和tag边界均有记录。

<a id="c03"></a>

### C03 Entry从空到满及满表合并

`mshr_entry_capacity_test`。

- 激励：使用N个不同块和合法set/way填满Entry，保持至少4拍满状态。选一个有空Slot的旧Entry继续merge；额外新块请求保留在driver中等待。只完成一个Entry的最后replay，再提交额外新块。
- 检查：全满时hasFree=0但已有Entry仍能合法merge；N个条目各自发送/填充/重放不串扰。释放当拍按沿前满状态不提交alloc，下一合法拍使用释放后的空位；其余锁与事务保留。
- 必须命中：Entry水位0..N、最后空Entry分配、满表期间merge、满状态持续、单Entry释放后恢复各命中。当前P=4，必须实际覆盖满表期间的合法merge。

<a id="c04"></a>

### C04 SEND和MISS_WAIT各填满Slot

`mshr_slot_capacity_test`。

- 激励：分别在请求未发送和已发送未响应两个阶段，将同一Entry从首Slot补至P个Slot；轮换目标Entry。填满后继续查询并保持至少4拍，merge.en保持0，然后响应、fill、重放和复用。
- 检查：freeSlot按请求接受顺序推进，最后空Slot写入后slotFree=0；mergeable仍由状态决定，不能把slot满误解为必须mergeable=0。P笔Slot请求只产生一次内存读和一次fill，P次replay按序完成。
- 必须命中：SEND/MISS_WAIT两阶段×各Entry的最后空Slot/满Slot；当前P=4，首Slot及后续三个合并位置均应覆盖。

<a id="c05"></a>

### C05 读写组合和写标志累积

`mshr_merge_matrix_test`。

- 激励：分别在SEND和MISS_WAIT追加请求，组织RR、RW、WR、WW；同字和异字各一组，并将访问放到首字、末字及中间字。数据取不同值，另安排写后连续读及同字多写。
- 检查：同一块不新增Entry、不额外读内存；任意写使最终dirty=1，后续读不能清掉写标志。整行按所有写的顺序合成，未写字保持R0，读的前缀写视图交由C07细查。
- 必须命中：合并阶段×RR/RW/WR/WW×同字/异字必要组合全部命中；纯读/含写dirty各覆盖。单次生命周期的序列长度不超过当前4个Slot。

<a id="c06"></a>

### C06 返回行及合并行的数据完整性

`mshr_data_pattern_test`。

- 激励：sequence预置全0、全1、逐字递增、逐字节递增、0xAA/0x55交替位、walking-1/0和随机整行。walking表示单个1或0遍历LINE_WIDTH每一位。先做纯读，再用不同写数据覆盖选中字；不同Entry使用可区分的行。
- 检查：完整比较收到的原始行、fill整行及有效replay读字，检查每个字/字节位置及未写字保持。逐字递增子场景遍历全部wordOff；当P<W时分多次生命周期完成，不能用只检查P个Slot代替整行读字覆盖。
- 必须命中：九类数据分别计数；walking-1/0各遍历LINE_WIDTH位；每个wordOff实际被读到，首末字及跨字边界均命中；所有Entry均承载过非相同数据。

<a id="c07"></a>

### C07 每个读Slot只见前序写

`mshr_read_view_test`。

- 激励：同字构造R-W、W-R-W、W-R-W-R、R-W-R-W；再插入异字写，并换到word0和末字。每个写值与R0、其他写值不同。至少一组在写Slot已经replay完成后继续检查后续读。
- 检查：每个读只返回此前最近同字写，否则返回R0对应字；fill却使用所有写的最终结果。写Slot只完成一次类型/ID响应，不增加fill次数。同Entry的Slot严格按接受顺序replay，其他Entry允许穿插。
- 必须命中：上述序列×首末字及同字/异字关系分别命中；前后读值必须实际不同，避免数据相同掩盖“后写穿越”。上述序列均在当前4个Slot内完成。

例如原始返回行的字w为M，依次接受下列四个Slot，且M、A、B互不相同：

| Slot | 请求 | 该Slot的replay期望 |
| --- | --- | --- |
| 0 | R(w) | 返回M |
| 1 | W(w,A) | 返回写类型和该Slot的CPU ID |
| 2 | R(w) | 返回A |
| 3 | W(w,B) | 返回写类型和该Slot的CPU ID |

这一Entry的fill.line[w]应为B、dirty=1，但两次读分别为M和A。对写Slot完成响应后删除所有历史，会使Slot2读的期望丢失；将最终B作为所有读的期望，则会漏掉顺序错误。

<a id="c08"></a>

### C08 确定性遍历所有Entry和Slot

`mshr_entry_slot_sweep_test`。

- 激励：利用占位和释放控制实际freeEntry，遍历每个Entry×Slot位置；每个位置轮换读、写、word0、末字，轮换CPU ID 0与最大值，并覆盖各set/way边界。ID在前一笔replay前不得复用。
- 检查：内存读ID等于实际Entry位次零扩展，replay透传CPU ID与类型；fill落点匹配原alloc，地址重构按参数计算。hasWb/wbSlot遵守合法输入约束，不要求探测内部保存。
- 必须命中：entry×slot×读写×首末word交叉的每个合法格必须命中；CPU ID边界、tag/index/way边界均命中。不得只用随机case的总事务数替代位置覆盖。

<a id="c09"></a>

### C09 挂起读请求期间插入更低位候选

`mshr_send_backpressure_test`。

- 激励：先让低位Entry发出读并等响应，只留下较高位Entry待发；拉低请求ready并确认它已呈现。持续背压时完成一个低位旧Entry的响应/fill/replay并释放，再向该低位分配新块；最后恢复ready。
- 检查：旧请求valid、地址和完整ID持续保持，新的低位候选不能抢占；只在实际请求握手时登记发送，未选者仍待发送。恢复后旧请求和新候选各发送一次。
- 必须命中：真实valid&&!ready至少4拍；挂起ID大于新候选ID；新候选在旧握手前出现；插入后至少继续阻塞1拍。N>=2，且检查准备阶段的释放及新分配确实发生。

<a id="c10"></a>

### C10 发送低位优先与仅选中者推进

`mshr_send_arbitration_test`。

- 激励：积累多个SEND条目后放行。已被呈现并挂起的首项先完成，再在后续无挂起选择的仲裁沿检查最低候选；另构造稀疏候选和所有Entry候选集合。
- 检查：当前已挂起请求不能被低位优先规则重选；新的仲裁才取最低Entry。每个Entry恰好发一次，只有实际握手ID进入等待响应记录。停止新增并持续ready后有限集合全部完成。
- 必须命中：至少一次“无旧挂起且候选数>=2”的真实选择；所有Entry各发送一次，稀疏集合跳过无效Entry。无限持续新增下不要求固定优先发送无饥饿。

<a id="c11"></a>

### C11 按ID乱序及连续拍响应

`mshr_response_order_test`。

- 激励：N个读请求实际握手后暂停返回，分别按发送顺序、逆序和指定排列响应；每条数据由其请求地址快照生成。包含至少两笔不同ID在相邻拍响应，后续叠加随机排列。
- 检查：原始行进入正确Entry，fill目标/dirty/整行及每Slot replay均匹配该生命周期；不能按全局请求FIFO比对跨Entry响应。每ID只响应一次，响应结束也不表示Entry已释放。
- 必须命中：全部Entry返回、逆序/指定序列、乱序计数>0、相邻两拍不同ID响应；至少两个Entry同时等待响应和同时存活。

<a id="c12"></a>

### C12 真实DUT的最快和可变响应

`mshr_response_latency_test`。

- 激励：以每个请求真实握手沿为起点，分别安排1、2、7、32拍响应，以及1..32拍随机延迟；每种固定延迟先在无响应排队阻塞条件下执行，再加队列竞争。
- 检查：按ID独立计算请求/响应握手间隔：无阻塞时恰好L拍，有排队或反压时不早于L拍并记录实际原因。等待期间查询、可合并性和锁正确，不能把内存driver自检的1拍结果代替DUT命中。
- 必须命中：真实DUT每个固定L至少一次精确命中，随机延迟范围有分布；零拍不属于支持范围，不纳入正常case。

<a id="c13"></a>

### C13 待填充阻塞与恢复

`mshr_fill_backpressure_test`。

- 激励：接收一个读响应后保持fillReady=0至少4拍，期间保持replay.ready=1，直接暴露提前replay。恢复并排空；多候选变体在阻塞期间再返回其他Entry。
- 检查：未接受fill的Entry不得replay、释放或丢行；恢复后每Entry接受一次fill。单候选下目标/数据应始终对应它；多候选下必须检查挂起fill的en和全部载荷保持到握手，新增候选不能替换它。
- 必须命中：fill.en&&!fillReady实际持续>=4拍，单候选和多候选分别命中，阻塞期间该Entry replay=0，恢复fill次数正确；多候选保持契约已明确，需新增对应SVA和必命中场景后再登记闭合。

<a id="c14"></a>

### C14 多条待填充行的归属和顺序

`mshr_fill_arbitration_test`。

- 激励：暂停fillReady，按与Entry编号不同的顺序返回多个行，积累至少两个待fill候选后统一放行；候选使用不同tag/index/way和数据，另安排间隔返回。
- 检查：每个候选恰好填充一次且目标数据正确，有限集合全部处理完。低下标优先仅是当前C++模型选择，不是接口必过条件；fill不要求独立仲裁器或轮询，挂起保持是接口要求。
- 必须命中：至少2个待fill候选、所有候选接受、逆序到达、不同落点；只验证每拍接受一个fill，不借“每拍最多一个读响应”排除积压场景。

<a id="c15"></a>

### C15 挂起replay及动态候选插入

`mshr_replay_backpressure_test`。

- 激励：将低位Entry停在MISS_WAIT，先让最高Entry的一笔准备事务replay并释放，从已观察到的握手建立轮询起点0；重新分配该最高Entry为A，完成fill后挂起其replay。持续背压中返回低位B并完成fill，让它成为更靠前的新候选，再放行。
- 检查：A的valid、类型、CPU ID及Stream载荷保持到握手，B不能抢占；背压期间A的Slot计数、Entry与锁不能提前释放。握手后才推进轮询。首/中/末Slot及读/写挂起分别执行，不依赖后门读rrPtr。
- 必须命中：A先真实stall、B在stall中完成fill并具备replay资格、随后仍stall至少1拍、A最后确实先握手；读/写及首、中、末Slot的阻塞恢复均命中（中间Slot要求P>=3）。发现Q-01违约时报告DUT问题，不能改比较规则放行。

<a id="c16"></a>

### C16 Entry间轮询和Entry内顺序

`mshr_replay_arbitration_test`。

- 激励：先将多个Entry填充完成并阻塞replay，记录已呈现的选择；统一放行后检查后续轮询。每个Entry安排不同Slot数，另构造稀疏候选、候选加入/退出和末Entry到首Entry回绕。
- 检查：已挂起选择先完成；每次握手后才更新轮询，跳过不具备重放条件的Entry，同Entry内严格按Slot顺序。固定候选且持续ready时，一个仍有待重放Slot的Entry在至多N次成功replay服务内获得服务。
- 必须命中：所有Entry被服务，首末回绕、无效Entry跳过、不同Slot数量、同Entry顺序和有界服务全部命中；不把外部ready低的拍数算作内部饥饿。

<a id="c17"></a>

### C17 锁建立、保持、释放及全矩阵

`mshr_lock_test`。

- 激励：同set不同way并发分配，另安排不同set；逐个在SEND、MISS_WAIT、待fill、已fill重放和最后Slot阻塞阶段停留。先释放一条并保留其他Entry，再复用对应set/way。
- 检查：alloc后建立锁，fill接受不能提前清锁，最后replay握手后只清相应占用；全矩阵的其他位不受影响。上游保证set/way唯一。只检查lockMask，不要求IP产生cpuReady或执行victim选择。
- 必须命中：各生命周期阶段×锁持续、全路锁定、仅解除一路、多set独立和首末set/way位。当前N=4、NUM_WAYS=4，必须实际命中全路锁定。

<a id="c18"></a>

### C18 Entry、Slot和CPU ID多轮复用

`mshr_reuse_test`。

- 激励：每个实际Entry至少执行三轮：多Slot含写→单Slot纯读→新数据多Slot，可用A/B/A块地址并切换set/way。新一轮在前生命周期最后replay后才alloc，CPU ID也只在对应replay后复用。
- 检查：第二轮dirty恢复0，Slot数按新请求数重放，fill不会被旧fillDone跳过；历史写数据不污染新读，旧查询与锁解除。保持同Entry生命周期记录相互隔离。
- 必须命中：每Entry至少3次使用，写转纯读、长Slot队列转短队列、同址不同数据和异址/异set/way复用均命中。

<a id="c19"></a>

### C19 接受边沿的同拍组合

`mshr_event_collision_test`。

- 激励：分别安排同Entry merge+读响应、merge+读请求握手；不同Entry读响应+发送、响应+alloc或merge、fill+普通replay、fill+最后replay释放、最后replay+沿前另一空Entry alloc。条件允许时再组合三个独立事件。
- 检查：按沿前状态判断合法性。同Entry最后空Slot在响应当拍追加的读/写必须进入本次fill与replay，写要影响dirty/合成行；不同Entry事件各自生效，释放不清其他锁。满表释放沿不要求同时alloc。
- 必须命中：merge+响应按新Slot读/写分别命中且覆盖最后空Slot；其他各组合独立计数，普通/最后replay分别计数。alloc+merge及包含二者的组合不属于合法输入，不列入覆盖目标。

<a id="c20"></a>

### C20 合法随机交错和资源边界

`mshr_random_test`。

- 激励：固定种子起步，每轮选择合法空Entry/未占set-way，或SEND/MISS_WAIT有空Slot的已有块；随机读写、word、ID、ready、响应延迟/顺序、fill/replay反压。纯定向预热与随机阶段分别计数。
- 检查：随机约束只生成合法输入，尤其FILL不merge、重复块不alloc、满时不提交、CPU ID不提前复用。C++与SVA持续检查；停止新增后放行并排空。fill保持作为明确协议要求，需补专门检查和动态候选证据。
- 必须命中：每种子随机阶段至少128批，每批经历N个Entry生命周期；要求SEND/MISS_WAIT合并、Entry满、Slot满、真实请求/replay反压、乱序、复用均命中。对缺失bin增加定向偏置并明确未命中失败，不能只看无UVM_ERROR。

<a id="c21"></a>

### C21 无效载荷扰动和查询无副作用

`mshr_idle_payload_test`。

- 激励：在空态及有Entry在途时，令alloc.en/merge.en/memReadResp.valid为0，持续改变相应地址、类型、数据、ID和索引载荷，同时切换合法q0/q1；保持有效控制与查询已知。
- 检查：无效载荷不新增Entry/Slot、不修改原有fill/replay结果、不影响锁或计数；查询本身不构成事务。必要时暂停其他进展，随后正常排空，检查原数据仍正确。
- 必须命中：空态/占用态×三个输入通道的无效扰动均覆盖；查询单独变化且事件计数不增加。有效DUT输出的X/Z检查保持开启。

## 配套验证

<a id="s01"></a>

### S01 复位验证

拟用`mshr_reset_test`及独立复位控制sequence覆盖启动、空闲重复复位、复位后首拍/次拍请求。MSHR复位已确认为异步低有效，生成器、TB和基础断言采用这一约定；复位控制仍只有一个驱动来源。

- 启动和重复空闲复位后，查询无命中、hasFree有效、无发送/fill/replay、lockMask全零，再各完成一次读写；不要求没有门控的ready在复位时为0。
- 补停钟、离有效沿拉低resetn的控制状态清空检查，证明无需时钟边沿即可复位；释放安排在非有效沿。
- 运行中复位分SEND、MISS_WAIT、待fill、replay阻塞四种状态，须先解决Q-04。模型、内存pending、Slot期望和ID记录必须采用同一取消规则，不能只复位DUT后接着返回旧ID。
- recovery/removal等实现时序检查单独留档，不由RTL仿真替代。

<a id="s04"></a>

### S04 长跑和统计

使用`mshr_random_test`的独立长跑profile。当前明确规模为每组 **1024轮×4 Entry×4 Slot＝16384笔Slot请求**，seed=1/2/3，各10 ns/4 ns共6组。每轮停止响应、形成多Entry多Slot占用，随后随机放行并完全排空，再复用地址和CPU ID；它检查多轮复用，不声称包含连续1024轮不排空的流量。等待可配置，但所有单位为拍，随机ready需设置最长连续阻塞上限以保留明确的进展前提。

分别统计发送等待、读响应等待、待fill和replay等待，区分外部ready阻塞与内部仲裁；记录Entry、每Entry Slot数、总Slot数及锁位数量从0到上限的分布。只填满过一次不能代表水位分布完整，固定优先发送/填充也不承诺无限新增流量下无饥饿。

长跑每种子至少经过3轮“全Entry占用→全部排空→重新使用”的过程，完成后检查所有计数、数据、ID及锁。等待及水位统计用于定位瓶颈，不作为独立闭合目标；长跑检查数据、资源和锁无泄漏。

## 实施顺序和回归安排

| 阶段 | 先完成什么 | 进入下一阶段的依据 |
| --- | --- | --- |
| 1 | 已确认异步低有效复位，建立MSHR专用配置/接口/DPI、C01 | 单读/单写数据与计数正确，采样和模型调度对齐，DUT输出满足协议和数据要求 |
| 2 | C02～C08 | 查询、Entry/Slot容量、合并矩阵、数据/历史视图和位置遍历具备明确命中记录 |
| 3 | C09～C18 | 三个输出阶段的反压/仲裁、响应顺序/延迟、锁和复用；Q-02子项保持单独状态 |
| 4 | C19、C21及S01可执行部分 | 关键沿前边界、无效载荷和复位不被随机流量掩盖；热复位待定子项不伪报通过 |
| 5 | C20短随机、S04长跑 | 按配置保存seed、命中条件和完整排空证据，补齐缺失bin后再登记验证点闭合 |

默认先跑10 ns/4 ns，定向case使用固定seed=1；短随机和长跑使用seed=1/2/3。当前矩阵及失败证据见文末。本轮按固定N=4、P=4执行；不把WBB的serial/pipeline模式名机械套到MSHR，MSHR的并发重点是上游提交与读发送、响应、fill、replay在不同Entry上的重叠。

每次运行报告必须包含test/sequence、参数、seed、时钟、模型/DUT版本、case必命中计数、assertion错误、读请求/响应/fill/replay统计、日志和波形入口。终端沿用已有回归报告形式，PASS/FAIL用对应颜色。确定DV错误后修环境并重跑；确定DUT错误则报告最小轨迹和违反的契约，不自行修改DUT。

## 验证点到 case 的完整映射

下表覆盖主表81个DUT验证点。映射表示计划责任，不表示已执行；同一点可以由多个DUT场景共同覆盖。`C00`为公共检查方法，S01为复位、S04为长跑；原参数生成及环境验收组已删除，保留剩余编号。对待确认契约及物理时序检查保留范围限制，不能以一个基础case通过替代。

| 验证点 | 名称 | 计划case / 配套组 | 范围或条件 |
| --- | --- | --- | --- |
| RST-001 | 异步低有效复位 | [S01](#s01) | 用户已确认ASYNC/LOW；停钟及离沿复位仍需专项证据 |
| RST-002 | 复位释放后的首次请求 | [C01](#c01)、[S01](#s01) | 按对应case的激励、正确性检查及必须命中条件登记 |
| RST-004 | MSHR 初态 | [C00](#c00)、[S01](#s01) | IO初态及后续行为，不能声称观测全部内部状态位 |
| RST-008 | 重复空闲复位 | [S01](#s01) | 按对应case的激励、正确性检查及必须命中条件登记 |
| RST-009 | 复位释放请求边界 | [S01](#s01) | 按对应case的激励、正确性检查及必须命中条件登记 |
| RST-010 | 运行中复位取消事务 | [S01](#s01) | Q-04取消与迟到响应隔离待确认 |
| RST-011 | 复位释放时序 | [S01](#s01) | 实现recovery/removal报告单列 |
| CFG-002 | 地址字段分界处不会选错 | [C02](#c02)、[C08](#c08) | 按对应case的激励、正确性检查及必须命中条件登记 |
| CFG-004 | 内存块对齐与重构 | [C01](#c01)、[C08](#c08)、[C11](#c11) | 按对应case的激励、正确性检查及必须命中条件登记 |
| CFG-005 | 整行中的字和字节位置正确 | [C06](#c06)、[C07](#c07) | 按对应case的激励、正确性检查及必须命中条件登记 |
| CFG-006 | 读写总线 ID 映射 | [C08](#c08)、[C11](#c11)、[C18](#c18) | 按对应case的激励、正确性检查及必须命中条件登记 |
| CFG-012 | 总线资源约束 | [C00](#c00)、[C03](#c03)、[C11](#c11) | 仅读在途容量；Q-08共享读写额度归顶层 |
| IF-001 | MSHR接口握手 | [C00](#c00)、[C01](#c01)、[C11](#c11) | 按对应case的激励、正确性检查及必须命中条件登记 |
| IF-002 | DUT输出反压保持 | [C09](#c09)、[C15](#c15) | 按对应case的激励、正确性检查及必须命中条件登记 |
| IF-003 | 内部 replay 握手保持 | [C15](#c15) | 按对应case的激励、正确性检查及必须命中条件登记 |
| IF-004 | 每次接受只执行一次 | [C00](#c00)、[C03](#c03)、[C04](#c04)、[C09](#c09)、[C13](#c13)、[C15](#c15)、[C19](#c19) | 按对应case的激励、正确性检查及必须命中条件登记 |
| IF-005 | CPU 请求字段 | [C05](#c05)、[C07](#c07)、[C08](#c08) | 按对应case的激励、正确性检查及必须命中条件登记 |
| IF-006 | 有效输出无X/Z | [C00](#c00)、[C21](#c21) | 按对应case的激励、正确性检查及必须命中条件登记 |
| IF-008 | 无效载荷变化不能触发动作 | [C21](#c21) | 按对应case的激励、正确性检查及必须命中条件登记 |
| IF-009 | 最快合法响应 | [C12](#c12) | 1拍已通过；Q-03已确认不支持零拍 |
| MSA-001 | 空闲 Entry 查询 | [C02](#c02)、[C03](#c03) | 合法空Entry与当前模型精确选择分开检查 |
| MSA-002 | 分配字段的可观察行为 | [C01](#c01)、[C08](#c08) | 只检查IO行为，现有证据已闭合，不检查内部保存 |
| MSA-003 | 首 Slot 与计数 | [C01](#c01)、[C04](#c04) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-004 | 查询匹配键 | [C02](#c02) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-005 | q0/q1 独立一致 | [C02](#c02) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-006 | SEND 合并 | [C04](#c04)、[C05](#c05) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-007 | MISS_WAIT 合并 | [C04](#c04)、[C05](#c05) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-008 | FILL不可合并指示 | [C02](#c02) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-009 | Slot 满 | [C04](#c04) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-010 | Entry 满 | [C03](#c03) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-011 | 独立地址并行 | [C03](#c03)、[C11](#c11) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-012 | 合并读写组合 | [C05](#c05) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-014 | 合并与响应同拍 | [C19](#c19) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-015 | 写标志累积 | [C05](#c05) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSA-016 | 所有 Entry/Slot 覆盖 | [C08](#c08) | 逐Entry×Slot×读写×首末字命中 |
| MSA-017 | Entry释放与另Entry分配同拍 | [C03](#c03)、[C18](#c18)、[C19](#c19) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSB-001 | 完整状态迁移 | [C01](#c01) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSB-002 | 分配后可以等待内存接收 | [C09](#c09) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSB-003 | 只有已发送Entry进入等响应阶段 | [C10](#c10) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSB-004 | 低位优先编码 | [C10](#c10) | 低位优先用于新仲裁，不抢占挂起项 |
| MSB-005 | 发送保持 | [C09](#c09) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSB-006 | 内存读次数 | [C01](#c01)、[C04](#c04)、[C05](#c05)、[C09](#c09)、[C10](#c10) | 同一Entry即使合并多个Slot，仍只成功发送一次内存读 |
| MSB-007 | 块地址与 ID | [C01](#c01)、[C10](#c10) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSB-008 | 乱序接收 | [C11](#c11) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSB-009 | 相邻拍返回 | [C11](#c11) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSB-010 | 读响应与其他动作并发 | [C19](#c19) | alloc与merge互斥，只检查合法并发组合 |
| MSB-011 | 不同数据内容都能正确返回 | [C06](#c06) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSB-013 | 可变延迟 | [C12](#c12) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-001 | 填充目标 | [C01](#c01)、[C06](#c06)、[C14](#c14) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-002 | 填充整行合成 | [C05](#c05)、[C06](#c06)、[C07](#c07) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-003 | fill的脏标志正确 | [C01](#c01)、[C05](#c05)、[C06](#c06)、[C07](#c07) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-004 | 填充次数 | [C01](#c01)、[C13](#c13)、[C14](#c14) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-005 | fill反压保持与恢复 | [C13](#c13) | 阻塞恢复已通过；选择/载荷保持契约明确，待补SVA及动态候选证据 |
| MSC-006 | fill归属与一次性接受 | [C14](#c14) | 只验目标、数据、一次性接受和进展，不要求模型的低下标顺序 |
| MSC-007 | 先填充再重放 | [C01](#c01)、[C13](#c13)、[C14](#c14) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-008 | 读请求只看到它之前的写 | [C07](#c07) | 读前缀视图不能用最终fill行替代 |
| MSC-009 | 不同字写隔离 | [C05](#c05)、[C06](#c06)、[C07](#c07) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-010 | 重放类型和ID | [C01](#c01)、[C07](#c07)、[C15](#c15)、[C16](#c16) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-011 | 重放不再写 Cache | [C07](#c07) | IP检查一次fill与写Slot仅响应；实际CacheMem端口连接归顶层 |
| MSC-012 | 按Slot接受顺序返回 | [C07](#c07)、[C15](#c15)、[C16](#c16) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-013 | 重放反压保持 | [C15](#c15) | Q-01是待验证风险，Stream保持要求本身不豁免 |
| MSC-014 | 最后一个响应接受后才释放 | [C01](#c01)、[C15](#c15)、[C17](#c17)、[C18](#c18) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-015 | 复用Entry时不带入旧状态 | [C18](#c18) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-016 | 不同Entry轮流返回请求 | [C16](#c16) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-017 | 有限集合重放进展 | [C16](#c16) | 按对应case的激励、正确性检查及必须命中条件登记 |
| MSC-018 | 填充与重放不同Entry同拍 | [C19](#c19) | 按对应case的激励、正确性检查及必须命中条件登记 |
| LCK-001 | 锁与Entry对应 | [C17](#c17) | 按对应case的激励、正确性检查及必须命中条件登记 |
| LCK-002 | 分配即建立锁 | [C17](#c17) | 只查锁可见时机，Stage2是否使用锁归顶层 |
| LCK-003 | 锁覆盖完整生命周期 | [C12](#c12)、[C13](#c13)、[C17](#c17) | 按对应case的激励、正确性检查及必须命中条件登记 |
| LCK-004 | 最后重放才解锁 | [C15](#c15)、[C17](#c17) | 按对应case的激励、正确性检查及必须命中条件登记 |
| LCK-008 | 全路锁定 | [C17](#c17) | 全路锁需N>=NUM_WAYS；cpuReady联动归顶层 |
| LCK-009 | 多set独立 | [C17](#c17) | 全矩阵输出独立性，命中路径归顶层 |
| INV-005 | 分配和释放数量对得上 | [C00](#c00)、[C03](#c03)、[C04](#c04)、[C18](#c18)、[C20](#c20) | 按对应case的激励、正确性检查及必须命中条件登记 |
| INV-006 | 读ID唯一在途 | [C00](#c00)、[C08](#c08)、[C11](#c11)、[C18](#c18) | 按对应case的激励、正确性检查及必须命中条件登记 |
| INV-007 | 放行后所有请求都能完成 | [C00](#c00)、[C20](#c20) | 按对应case的激励、正确性检查及必须命中条件登记 |
| INV-010 | 已有请求最终都能完成 | [C10](#c10)、[C14](#c14)、[C16](#c16)、[S04](#s04) | 有限集合/ready允许前提；固定优先不作无限负载无饥饿承诺 |
| END-009 | 收尾无残留占用 | [C00](#c00)、[C18](#c18)、[C20](#c20)、[S04](#s04) | 按对应case的激励、正确性检查及必须命中条件登记 |
| PER-003 | 同行合并节省读带宽 | [C04](#c04)、[C05](#c05) | 按对应case的激励、正确性检查及必须命中条件登记 |
| RND-002 | MSHR约束随机 | [C20](#c20) | 按对应case的激励、正确性检查及必须命中条件登记 |
| RND-008 | 资源快满或释放时的并发动作 | [C03](#c03)、[C04](#c04)、[C19](#c19)、[C20](#c20) | 按对应case的激励、正确性检查及必须命中条件登记 |
| RND-010 | 长期运行与复用 | [C20](#c20)、[S04](#s04) | 短随机不替代S04的明确长跑规模 |

## 后续闭合登记

每个验证点逐项补`配置/版本、test和sequence、seed、checker/SVA、必命中计数、日志/波形、结果及剩余项`。一个case可以覆盖多个点，一个点也可以由多个case拼齐子条件；只完成其中一个子场景就登记部分覆盖，不按关联case个数机械打勾。

当前状态以主表和本文末尾2026-11-24完整回归为准；早期框架记录仅保留历史。发现模型与规格不一致时单独记录；模型比较、IO断言和原始数据检查各自保留，不能为让DUT通过而改掉规格要求。


## 框架实施及基础证据 2026-11-20

独立环境说明与运行命令见 [MSHR_README](../../verif_mshr/MSHR_README.md)。生成目录`generated/mshr`、仿真目录`sim_mshr`与WBB分离；复用原有C++ MSHR和SparseMemory，未另写完整参考模型。两个MSHR生成入口采用用户确认的异步低有效复位，功能RTL和原模型算法未修改。

- [框架4组报告](../../verif_mshr/sim_mshr/work/framework/run_20261120_103457_803704/summary.md)：无testname默认空态及两笔读写smoke，分别在10 ns/4 ns通过；各组UVM_WARNING/ERROR/FATAL=0。smoke的alloc/readReq/readResp/fill/replay/release均为2，merge=0，读/写replay各1。
- [41个实际输入文件哈希](../../verif_mshr/sim_mshr/work/framework/run_20261120_103457_803704/inputs.json)：DUT SHA-256为`3888ebef9474d60048905ed96081d61079e6e009005e5eb811bb9f295afdff1b`；原C++模型为`3ab418857b6acda3f4ae7410265e2baf217539384570360e01d2e49be77e3ecc`。
- [SV DPI自检](../../verif_mshr/sim_mshr/work/dpi/run.log)：适配、模型历史读视图和非法ID等通过；不作为真实DUT合并证据。
- [内存代理7组自检](../../verif_mshr/sim_mshr/work/memory_timing/summary.json)：六组正常周期/背压/快照检查通过，零拍配置按预期报错；均不实例化MSHR DUT。

已实现ALLOC/MERGE/QUERY/IDLE基础驱动，但真实DUT的本轮smoke只提交ALLOC。C02～C21、完整复位场景及长跑未展开，尤其不能把DPI的R-W-R自检当作DUT已经完成MSC-008。CPU ID目前按沿前在途集合约束，完成replay后的后续提交才能复用，不支持同沿旧ID完成与同ID新请求并发。


## 2026-11-24 功能验证实现与回归

本轮只依据MSHR IP架构文档、现有验证计划及公开IO编写场景；未读取DUT内部实现、未修改DUT或原C++模型。沿用WBB当前范围，不补复位case。alloc+merge双提交不支持；热复位取消继续待确认；零拍读响应现已明确不支持，不能把缺少契约的场景算PASS。

实现了C02～C21的20个功能case和`mshr_long_run_test`。每个test只启动对应sequence并调用公共检查；场景和随机数据由sequence产生。公共工具在`mshr_scenario_sequence`和`mshr_scenario_test`，IO计数/时序观察在`mshr_activity_monitor`。原C++ MSHR逐拍预测与原有IO SVA保留；另按sequence原始请求记录逐次核对fill整行、dirty、way，以及各CPU ID的读历史/写响应，外部MEM仍用原C++ SparseMemory。

内存代理新增FIFO、逆序、随机和指定ID响应，随机ready、随机1～32拍延迟及固定1/2/7/32拍延迟；响应一旦呈现就锁定到握手。fill/replay可独立反压或随机接收。无效载荷case只在enable/valid为0时扰动字段。定向同拍通过采样周期调度放行，不使用硬编码ns或DUT内部状态。

[本轮52组报告](../../verif_mshr/sim_mshr/work/regression/run_20261124_141613_912476/summary.md)：19个定向case×两种时钟共38组PASS；replay反压2组、随机6组、长跑6组共14组FAIL，均触发`MSHR_DUT_REPLAY_STABLE`。完整运行启用`--max-errors 0`保留报错并继续收尾，错误仍判FAIL。所有组均完成数据与事件计数检查，不据此豁免协议失败。

| case组 | 主要实际执行内容 | 结果/范围 |
| --- | --- | --- |
| 查询、容量、合并矩阵、读历史 | SEND/MISS_WAIT/FILL查询；全Entry及全Slot；满表merge；RR/RW/WR/WW；读只看前序同字写 | 两时钟通过 |
| data_pattern | 九类模式；walking-1/0各遍历512位；每个模式先纯读验证原始整行，再单字写及读回 | 每组2272次Entry生命周期、4544笔Slot请求；两时钟通过 |
| entry_slot_sweep | Entry×Slot×读写×首末word实际交叉；32个set、各way、tag为0/1/最大减1/最大及CPU ID轮换 | 每组256次Entry、1024笔Slot；两时钟通过 |
| 发送、响应、填充 | 新低位候选不能抢占挂起发送；全候选/稀疏发送；逆序/指定/连续拍响应；实际1/2/7/32拍；单/多候选fill反压 | 两时钟通过；fill保持现已明确，旧结果不代表新增保持检查已经执行 |
| replay仲裁、锁、复用 | 全候选及稀疏Entry、不同Slot数、有界轮询；同set全锁及多set独立；多Slot含写→单Slot纯读→新多Slot | 两时钟通过；仅公开IO行为 |
| event_collision | 最后读/写Slot分别与响应同拍；merge/send、fill/replay、alloc/response、不同ID send/response、旧Entry释放/新Entry alloc | 每组7个阶段、13 Entry、24 Slot；必命中计数检查通过 |
| idle_payload | 空态/占用态各16次无效alloc/merge/response载荷扰动 | 两时钟通过，最终仅1笔合法Slot |
| replay_backpressure | 读/写首、中、末Slot单独阻塞；旧高位候选挂起时低位Entry完成fill | 动态候选替换导致DUT保持违约；两时钟均FAIL |
| random | 每组128轮、512 Entry、随机Slot数、随机接收和乱序响应 | 6组完成，但存在保持违约，FAIL |
| long_run | 每组1024轮、4096 Entry、16384 Slot；多轮同址换数据、CPU ID复用和排空 | 6组完成，但存在保持违约，RND-010不闭合 |

缺陷详见[MSHR-DUT-001](../../Architecture/DebugNote/MSHR-DUT-001_replay背压保持问题.md)。本轮确定的DV问题只有新增task的`ref`参数方向继承造成的编译错误，已用显式`input`修正；没有为规避DUT失败修改激励或比较规则。

运行命令：

```bash
# 默认21个功能case：两时钟，random为3个种子；每个case失败后继续其他组合。
python3 verif_mshr/sim_mshr/script/run_mshr_regression.py --color always

# 长跑：保留所有错误并运行到各组收尾，仍按错误判FAIL。
python3 verif_mshr/sim_mshr/script/run_mshr_regression.py \
    --tests mshr_long_run_test --max-errors 0 --color always
```

每轮独立保存编译日志、输入哈希、命令、UVM计数、场景计数和FSDB；终端显示彩色PASS/FAIL。当前没有因为case已实现就把待确认、不可观察或失败点自动闭合。


## replay修复后复核

[本轮52组报告](../../verif_mshr/sim_mshr/work/regression/run_20261124_152738_869276/summary.md)：重新生成RTL、冷编译后52/52 PASS；所有UVM warning/error/fatal均为0。测试矩阵、激励和断言保持原样，原失败14组全部通过。长跑6组完成98304笔Slot请求，RND-010按每组16384笔的当前规模闭合。复位、未确认协议及其他缺口仍按主表保留。


fill契约同步：C14的历史类名`mshr_fill_arbitration_test`保留，但它验证多待填充事务的IO归属和完成，不要求DUT实现仲裁器或特定顺序。C13需增加fill保持SVA及背压中新候选场景。现有scoreboard仍精确比较C++模型的fill选择；该比较比spec更严格，后续调整检查器时需按合法IO归属裁决，不能仅凭选择顺序不同归因DUT错误。此次仅更新文档，没有修改模型、检查器或运行新case。


## MSC-005保持验证实现

新增a_fill_stable，检查阻塞到接受沿的en及tag/index/way/dirty/整行保持。C13拆分单候选和动态新候选两个阶段；活动监视器增加fill_new_candidate、fill_stall_release及前后拍IO诊断。公共原始数据、计数及锁检查继续启用。

[本轮10组报告](../../verif_mshr/sim_mshr/work/regression/run_20261124_165306_312976/summary.md)全部FAIL，唯一错误为MSHR_DUT_FILL_STABLE；定向实际命中新候选1次、反压32拍、恢复2次。见[MSHR-DUT-002](../../Architecture/DebugNote/MSHR-DUT-002_fill背压保持问题.md)。DUT与C++模型未修改，MSC-005不能闭合。


## fill保持修复后复核

[最新52组报告](../../verif_mshr/sim_mshr/work/regression/run_20261124_172220_492146/summary.md)全部通过，UVM warning/error/fatal均为0。重新生成RTL并冷编译，保留现有fill保持SVA和动态候选激励；两种时钟均实际命中新候选1次、反压32拍、恢复2次。三种子随机和六组长跑通过，每组长跑16384笔请求。MSHR-DUT-002按当前配置关闭，MSC-005闭合；原失败记录保留为修复前历史。


## MSB-010多事件覆盖矩阵

沿用C19 `mshr_event_collision_test`，增加五个独立阶段，合计12阶段。令A=alloc、G=merge、S=读请求握手、R=读响应握手、F=fill握手、P=replay握手。下面均以同一采样沿的实际事件计数，不能用相邻周期的事件拼接。

| 必须命中的最大组合 | 各事件的Entry关系 | 最低命中数/每组 |
| --- | --- | --- |
| A+S+R+F | 分配新Entry，其余三个旧Entry分别发送、响应、填充 | 1 |
| A+S+R+P | 分配新Entry，其余三个旧Entry分别发送、响应、重放 | 1 |
| A+R+F+P | 分配新Entry，其余三个旧Entry分别响应、填充、重放 | 1 |
| G+S+R+F+P，G作用于R所属Entry | 沿前MISS_WAIT合法merge与响应同沿，其余三Entry各自推进 | 1 |
| G+S+R+F+P，G作用于S所属Entry | 沿前SEND合法merge与首次发送同沿，其余三Entry各自推进 | 1 |

口径：本点的组合覆盖针对“包含R的三事件及以上接口事件集合”，允许在更大组合中命中子组合。前三行覆盖A+R分别与S/F/P组成的三事件集合及可达四事件集合；后两行覆盖G+R与S/F/P的各三/四事件集合，以及无上游的R+S/F/P组合。另用两个独立计数区分G的同Entry目标。原有两事件和最后读/写Slot响应边界阶段继续保留；本矩阵不宣称穷举所有数据、Slot水位、ID排列和资源交叉，那些仍由各自验证点负责。

沿前资格约束：A与G互斥；S/R/F/P对同一事务不能跨越生命周期在同沿连跳；F与P若同沿，必须属于不同Entry。A+S+R+F+P需要五个独立Entry位置，默认四Entry下不可构造，不计缺失。G只能追加SEND或MISS_WAIT的Entry，因此在上述四旧Entry并存时分别覆盖G与S/G与R同属即可，不向待fill或replay的Entry非法merge。

激励先将旧Entry分别停在待replay、待fill、待响应、待发送阶段，再按采样周期对齐上游提交与下游放行。所有准备与随机数据仍在sequence；monitor仅统计真实IO事件；公共模型、原始数据、锁、顺序和保持断言继续检查。此处没有后门访问，也没有新增DUT或模型修改。

[本轮报告](../../verif_mshr/sim_mshr/work/regression/run_20261124_172737_613004/summary.md)：10 ns/4 ns均PASS；各组33次alloc、13次merge、33次send/response/fill/release、46次replay，UVM warning/error/fatal均为0。三个A四事件计数均至少1，G五事件计数为2，两个G同Entry目标各1。MSB-010按上述明确范围闭合，RND-008资源临界交叉仍保留。


## RND-008资源临界交叉闭合矩阵

本点限定为当前四Entry、每Entry四Slot的MSHR IP，检查下列架构相关边界；不包含WBB/FIFO资源，也不承诺资源水位与所有数据/ID/事件的全笛卡尔积。alloc与merge互斥，同Entry首次发送/响应零拍、满表同沿使用刚释放Entry均不作为合法激励。

| 边界与事件 | 负责case | 实际命中（每个时钟组合） |
| --- | --- | --- |
| Entry全满，旧Entry仍有Slot时合法merge | entry_capacity | boundary_full_merge=1 |
| Entry全满，最后replay释放；下一采样沿hasFree恢复 | entry_capacity | full_release及full_release_recovery各2 |
| SEND阶段使用最后一个Slot | slot_capacity | last_slot_stage_1=4，四Entry遍历 |
| MISS_WAIT阶段使用最后一个Slot | slot_capacity | last_slot_stage_2=4，四Entry遍历 |
| 最后一个空Entry分配与另一Entry响应同拍 | event_collision | last_entry_response=3 |
| 最后一个空Entry分配与另一Entry最后replay释放同拍 | event_collision | last_entry_release=2 |
| 最后Slot为读/写，merge与本Entry响应同拍 | event_collision | last_slot_response_read=1、write=2 |
| 全Entry占用、目标只剩一个Slot，merge/send/response/fill/最后replay同拍 | event_collision | full_last_slot_five_events=2，merge分别属于发送/响应Entry |

前三个既有case复用公共检查工具。monitor在更新事件历史前，用沿前真实alloc/merge/replay记录计算占用及Slot数量；同拍命中按实际握手计数，不读取DUT内部状态或模型状态。新增下一拍hasFree检查确认满表释放实际恢复；锁矩阵、其他Entry归属、Slot顺序、逐次fill/replay数据和计数守恒继续由既有检查链核对。

新增激励仅在五事件阶段把merge目标预填至剩一个空Slot，再在目标同拍沿提交最后Slot。其余边界由已有场景补命中条件，不重复建test。扩展后event_collision每组33 Entry、17 merge、50 replay，原MSB-010组合仍全部命中。

[定向6/6报告](../../verif_mshr/sim_mshr/work/regression/run_20261124_173224_692693/summary.md)及[完整52/52报告](../../verif_mshr/sim_mshr/work/regression/run_20261124_173257_750855/summary.md)均通过，UVM warning/error/fatal全为0。完整回归复用定向轮刚编译的同一验证程序，源码哈希一致；随机/长跑也启用新增公共释放恢复检查。RND-008按上述有限矩阵闭合，DUT及C++模型未修改。
