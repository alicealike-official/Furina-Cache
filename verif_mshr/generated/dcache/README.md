# DCache生成目录

`make -C verif_mshr/sim_dcache generate`调用现有DCacheVerilog生成入口，成功后仅核对顶层公开端口，再复制RTL及保存哈希。生成失败不会复制旧RTL。

当前要求固定32位地址/字、64字节行、5位CPU ID、4位总线ID、异步低有效resetn；容量和FIFO策略需与架构和原C++模型一致。端口检查不能证明内部容量或策略配置，参数包位于src/dcache/pkg，DPI另外校验C++编译期参数。

当前生成与低有效resetn端口检查已通过。test/dcache/dcache_port_stub.sv仅供编译，不提供功能行为，运行会立即fatal；不能作为本目录的DUT。
