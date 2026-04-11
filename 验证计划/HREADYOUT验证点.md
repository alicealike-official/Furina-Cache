## HREADYOUT 完整验证点

### 表1：基础行为验证点

| 优先级 | 验证点ID | 验证点描述 | 时序/行为要求 | 预期结果 | 验证方法 |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **P0** | HRDY-BAS-01 | 复位后 HREADYOUT 默认为 1 | 复位释放后，无传输时 HREADYOUT=1 | 总线不阻塞 | 断言 |
| **P0** | HRDY-BAS-02 | 从机可拉低 HREADYOUT 插入等待 | 从机需要更多周期时，HREADYOUT=0 | 传输延长 | 直接测试 |
| **P0** | HRDY-BAS-03 | 传输完成拍 HREADYOUT=1 | 最后一个等待周期结束后 HREADYOUT 拉高 | 数据正确采样 | 断言 |
| **P1** | HRDY-BAS-04 | 单周期等待 | 从机可拉低 HREADYOUT 仅 1 个周期 | 最小等待 | 直接测试 |
| **P1** | HRDY-BAS-05 | 多周期连续等待 | 从机可连续多个周期 HREADYOUT=0 | 传输延长 N 个周期 | 直接测试 |
| **P2** | HRDY-BAS-06 | 背靠背传输的 HREADYOUT | 前一拍传输完成后下一拍立即开始 | 无额外空闲周期 | 直接测试 |

---

### 表2：地址行为验证点

| 优先级 | 验证点ID | 验证点描述 | 时序/行为要求 | 预期结果 | 验证方法 |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **P0** | HRDY-ADDR-01 | 正常等待时地址必须保持稳定 | HREADYOUT=0 且 HTRANS=NONSEQ/SEQ 且 HRESP=OKAY 时，HADDR 不能改变 | 地址保持不变 | 断言 |
| **P0** | HRDY-ADDR-02 | 等待结束后地址才能更新 | HREADYOUT 由 0→1 的下一拍，HADDR 才能变为下一笔传输地址 | 地址变化发生在 HREADYOUT=1 之后 | 断言 |
| **P0** | HRDY-ADDR-03 | IDLE 传输允许改变地址 | HREADYOUT=0 且 HTRANS=IDLE 时，HADDR 允许变化 | 地址变化被从机忽略 | 断言 |
| **P0** | HRDY-ADDR-04 | 切换到 NONSEQ 后地址必须保持 | HTRANS 由 IDLE 变为 NONSEQ 后，即使 HREADYOUT=0，HADDR 也必须保持不变直到 HREADY=1 | 地址稳定 | 断言 |
| **P0** | HRDY-ADDR-05 | ERROR 响应期间允许改变地址 | HREADYOUT=0 且 HRESP=ERROR 时，HADDR 可变为 IDLE 或新 NONSEQ 地址 | 当前传输被取消 | 断言 |
| **P0** | HRDY-ADDR-06 | ERROR 响应期间地址变化不视为违例 | ERROR+HREADYOUT=0 时不应报告地址变化违例 | ERROR 例外生效 | 断言 |
| **P1** | HRDY-ADDR-07 | 多周期等待期间地址始终不变 | HREADYOUT=0 持续 N 个周期，HADDR 在 N 个周期内全部保持相同值 | 地址冻结 | 断言 |
| **P1** | HRDY-ADDR-08 | 等待状态与突发地址计算的关系 | HREADYOUT=0 时，下一拍突发地址不提前输出 | 等待结束后才按 HSIZE 更新地址 | 直接测试 |
| **P1** | HRDY-ADDR-09 | ERROR 响应后 Manager 可选择保持地址 | HREADYOUT=0 且 HRESP=ERROR 时，Manager 也可保持地址不变以继续剩余突发 | 两种行为均合法 | 直接测试 |
| **P2** | HRDY-ADDR-10 | 等待状态与 WRAP 边界地址的交互 | WRAP 突发中插入等待，地址在等待期间保持，结束后正确回环 | 地址计算不受等待影响 | 直接测试 |

---

### 表3：与 HTRANS 交互验证点

| 优先级 | 验证点ID | 验证点描述 | 时序/行为要求 | 预期结果 | 验证方法 |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **P0** | HRDY-HTR-01 | BUSY 传输时从机 HREADYOUT=1 | HTRANS=BUSY 时，从机必须返回 HREADYOUT=1 | 零等待响应 | 断言 |
| **P0** | HRDY-HTR-02 | BUSY 与 HREADYOUT=0 组合非法 | 同一周期内 HTRANS=BUSY 且 HREADYOUT=0 | 断言触发违例 | 断言 |
| **P0** | HRDY-HTR-03 | 等待状态期间 HTRANS 不能从 IDLE/BUSY 变为 NONSEQ/SEQ | 新传输只能在 HREADYOUT=1 时发起 | 协议合规 | 断言 |
| **P1** | HRDY-HTR-04 | 等待状态期间 HTRANS 可在 IDLE 间变化 | HREADYOUT=0 时，HTRANS 可在 IDLE 值范围内变化 | 无影响 | 直接测试 |

---

### 表4：与 HRESP 交互验证点

| 优先级 | 验证点ID | 验证点描述 | 时序/行为要求 | 预期结果 | 验证方法 |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **P0** | HRDY-RSP-01 | 等待状态期间 HRESP 只能为 OKAY | HREADYOUT=0 且 HRESP 不为 ERROR 时，HRESP 必须为 OKAY | 协议合规 | 断言 |
| **P0** | HRDY-RSP-02 | ERROR 可配合 HREADYOUT=0 插入等待 | ERROR 响应期间 HREADYOUT 可拉低 | 与 ERR-PROT-09 对应 | 直接测试 |
| **P1** | HRDY-RSP-03 | ERROR 响应结束后 HREADYOUT 拉高 | ERROR 响应最后一个周期 HREADYOUT=1 | ERROR 完成 | 断言 |

---

### 表5：边界与异常场景验证点

| 优先级 | 验证点ID | 验证点描述 | 时序/行为要求 | 预期结果 | 验证方法 |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **P1** | HRDY-ERR-01 | 等待状态期间地址变化与 ERROR 的隔离 | ERROR 响应期间的地址变化不影响其他传输 | 其他传输正常 | 系统级测试 |
| **P2** | HRDY-ERR-02 | 多 Master 场景下等待状态隔离 | Master A 插入等待时，Master B 可正常传输 | 其他 Master 不受影响 | 系统级测试 |
| **P2** | HRDY-ERR-03 | 等待状态与 SPLIT/RETRY 交互 | SPLIT/RETRY 响应时 HREADYOUT 行为 | 协议合规 | 直接测试 |