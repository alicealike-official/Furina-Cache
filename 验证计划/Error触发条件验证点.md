### ERROR 验证点 ###
| 优先级 | 验证点ID | 验证点描述 | 时序:行为要求 | 预期结果 | 验证方法 |
|:---:|:---|:---|:---|:---|:---|
| P0 | ERR-PROT-01 | ERROR 响应必须持续至少 2 个 HCLK 周期 | Slave 返回 ERROR 时，HRESP 保持 ERROR 值至少 2 个连续周期 | 仿真检查 ERROR 宽度 ≥ 2 | 断言 |
| P0 | ERR-PROT-02 | ERROR 仅在 HREADY=1 时被 Master 采样 | ERROR 响应必须与 HREADY=1 对齐 | Master 仅在 HREADY=1 时看到 ERROR | 断言 |
| P1 | ERR-PROT-03 | ERROR 不能与 BUSY 在同一拍出现 | 同一周期内 HRESP=ERROR 且 HTRANS=BUSY | 断言触发违例 | 断言 |
| P1 | ERR-PROT-04 | ERROR 不能与 IDLE 在同一拍出现 | 同一周期内 HRESP=ERROR 且 HTRANS=IDLE | 断言触发违例 | 断言 |
| P0 | ERR-PROT-05 | Master 可在 ERROR 响应期间取消剩余突发 | Master 在 ERROR 响应期间将 HTRANS 改为 IDLE | 剩余拍数被取消，总线进入空闲 | 直接测试 |
| P0 | ERR-PROT-06 | Master 可选择继续剩余突发 | Master 在 ERROR 响应后继续发 SEQ | 剩余拍数正常传输 | 直接测试 |
| P1 | ERR-PROT-07 | Master 取消时，HTRANS 必须在 ERROR 周期内变为 IDLE | Master 决定取消突发，HTRANS 在 ERROR 持续的 2 周期内为 IDLE | 时序符合协议 | 断言 |
| P2 | ERR-PROT-08 | ERROR 响应后，Master 不要求重建被取消的突发 | Master 取消部分突发后，后续访问不补传缺失拍数 | 新突发地址与之前无关 | 直接测试 |
| P1 | ERR-PROT-09 | ERROR 响应期间，Slave 可将 HREADY 拉低 | ERROR 可配合 HREADY=0 扩展超过 2 周期 | ERROR 保持，直到 HREADY=1 后的第 2 周期结束 | 直接测试 |
| P2 | ERR-PROT-10 | 多 Master 场景下，ERROR 不影响其他 Master | Master A 收到 ERROR 时，Master B 可正常传输 | 其他 Master 不受影响 | 系统级测试 |