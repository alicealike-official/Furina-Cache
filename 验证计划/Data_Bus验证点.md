## HWDATA 写数据验证点

| 优先级 | 验证点ID | 验证点描述 | 时序/行为要求 | 预期结果 | 验证方法 |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **P0** | WDAT-HOLD-01 | 等待状态期间 HWDATA 必须保持稳定 | HREADYOUT=0 时，HWDATA 不能改变 | 数据保持不变 | 断言 |
| **P0** | WDAT-HOLD-02 | 传输完成拍 HWDATA 被采样 | HREADYOUT=1 时，从机采样 HWDATA | 数据正确写入 | 直接测试 |
| **P1** | WDAT-NARROW-01 | 窄传输时 Manager 只驱动有效字节通道 | 根据 HSIZE 和地址，未使用的字节通道可为任意值 | 不影响功能 | 断言 |
| **P1** | WDAT-NARROW-02 | 从机从正确的字节通道取数据 | 根据 HSIZE、地址、大小端配置，选择正确字节 | 数据正确 | 直接测试 |
| **P2** | WDAT-ENDIAN-01 | 大端模式下字节通道选择正确 | 大端配置时，窄传输使用高字节通道 | 数据正确 | 直接测试 |

## HRDATA 读数据验证点

| 优先级 | 验证点ID | 验证点描述 | 时序/行为要求 | 预期结果 | 验证方法 |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **P0** | RDAT-HOLD-01 | 读等待期间 HRDATA 可以为任意值 | HREADY=0 时，HRDATA 无要求 | 从机不驱动有效数据 | 断言（不检查） |
| **P0** | RDAT-HOLD-02 | 读传输完成拍 HRDATA 必须有效 | HREADY=1 且 HRESP=OKAY 时，HRDATA 有效 | 数据正确 | 直接测试 |
| **P1** | RDAT-NARROW-01 | 窄读传输时从机只驱动有效字节通道 | 根据 HSIZE 和地址，从机驱动正确字节通道 | Manager 读到正确数据 | 直接测试 |
| **P1** | RDAT-NARROW-02 | Manager 从正确的字节通道取数据 | Manager 根据 HSIZE、地址、大小端选择正确字节 | 数据正确 | 直接测试 |
| **P0** | RDAT-ERROR-01 | ERROR 响应时 HRDATA 可为任意值 | HRESP=ERROR 且 HREADY=1 时，HRDATA 无要求 | Manager 忽略数据 | 断言（不检查） |