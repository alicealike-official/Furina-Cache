// mem_tb.sv - 可配置延迟内存的验证环境
`timescale 1ns/1ps

module mem_tb;
    
    // 参数定义
    parameter MEM_SIZE = 1024*1024;
    parameter Cache_Block_Size = 64;
    parameter DATA_WIDTH = 8*Cache_Block_Size;  // 512 bits
    
    // 时钟和复位
    logic clk;
    logic rst_n;
    
    // 延迟配置
    logic [31:0] latency_in;
    
    // DUT 接口信号
    logic                   mem_req_valid;
    logic                   mem_req_ready;
    logic                   mem_wr_en;
    logic [31:0]            mem_addr;
    logic [DATA_WIDTH-1:0]  mem_wdata;
    logic                   mem_resp_valid;
    logic                   mem_resp_ready;
    logic [DATA_WIDTH-1:0]  mem_rdata;
    
    // 实例化 DUT
    configurable_delay_mem #(
        .MEM_SIZE(MEM_SIZE),
        .Cache_Block_Size(Cache_Block_Size)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .latency_in(latency_in),
        .mem_req_valid(mem_req_valid),
        .mem_req_ready(mem_req_ready),
        .mem_wr_en(mem_wr_en),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_resp_valid(mem_resp_valid),
        .mem_resp_ready(mem_resp_ready),
        .mem_rdata(mem_rdata)
    );
    
    // 时钟生成
    always #5 clk = ~clk;  // 100MHz
    
    // 参考内存模型（用于比对）
    logic [7:0] ref_mem [0:MEM_SIZE-1];
    
    // 监控和比对的数据结构
    typedef struct {
        time timestamp;
        logic [31:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic is_write;
        int latency;
    } transaction_t;
    
    transaction_t expected_q[$];
    int total_checks = 0;
    int error_count = 0;
    
    // ========== 初始化 ==========
    initial begin
        // 初始化信号
        clk = 0;
        rst_n = 0;
        latency_in = 0;
        mem_req_valid = 0;
        mem_wr_en = 0;
        mem_addr = 0;
        mem_wdata = 0;
        mem_resp_ready = 1;  // 默认准备好接收响应
        
        // 清空参考内存
        for (int i = 0; i < MEM_SIZE; i++) begin
            ref_mem[i] = 8'h00;
        end
        
        // 复位
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
        
        $display("=========================================");
        $display("Memory Testbench Started");
        $display("=========================================");
        
        // 运行测试
        run_tests();
        
        // 结束仿真
        $display("=========================================");
        $display("Tests Completed: Total Checks = %0d, Errors = %0d", total_checks, error_count);
        $display("=========================================");
        
        if (error_count == 0) begin
            $display("PASSED!");
        end else begin
            $display("FAILED!");
        end
        
        #100;
        $finish;
    end
    
    // ========== 测试主程序 ==========
    task run_tests();
        // 测试1：基本读写（零延迟）
        test_basic_read_write(0);
        
        // 测试2：固定延迟读写
        //test_basic_read_write(3);
        
        // 测试3：随机延迟
        //test_random_latency();
        
        // 测试4：握手信号测试（backpressure）
        //test_backpressure();
        
        // 测试5：地址边界测试
        //test_address_boundary();
        
        // 测试6：随机读写测试
        //test_random_read_write();
    endtask
    
    // ========== 测试1：基本读写功能 ==========
    task test_basic_read_write(int latency);
            
        logic [31:0] addr;
        logic [DATA_WIDTH-1:0] wdata;
        logic [DATA_WIDTH-1:0] expected;
        logic [DATA_WIDTH-1:0] actual;

        $display("\n--- Test: Basic Read/Write (latency=%0d) ---", latency);
        latency_in = latency;



        // 写操作
        for (int i = 0; i < 1000; i++) begin
            addr = i * Cache_Block_Size;
            wdata = $urandom();
            write_mem(addr, wdata);
            update_ref_mem(addr, wdata);
            repeat(latency_in)@(posedge clk);
        end
        
        repeat(latency_in+1)@(posedge clk);
        // 读操作并比对
        for (int i = 0; i < 1000; i++) begin
            addr = i * Cache_Block_Size;
            expected = read_ref_mem(addr);
            repeat(latency_in)@(posedge clk);
            read_mem(addr, actual);
            compare_data(addr, expected, actual);
        end
        
        wait_for_idle();
        $display("Test Basic Read/Write Completed\n");
    endtask
    
    // ========== 测试2：随机延迟 ==========
    // task test_random_latency();
    //     $display("\n--- Test: Random Latency ---");
        
    //     for (int test = 0; test < 20; test++) begin
    //         int latency = $urandom_range(0, 10);
    //         latency_in = latency;

    //         // 随机写
    //         logic [31:0] addr;
    //         addr = $urandom_range(0, MEM_SIZE - Cache_Block_Size);
    //         logic [DATA_WIDTH-1:0] wdata = {$random(), $random(), $random(), $random(),
    //                                          $random(), $random(), $random(), $random()};
    //         write_mem(addr, wdata);
    //         update_ref_mem(addr, wdata);
            
    //         #10;
            
    //         // 随机读
    //         addr = $urandom_range(0, MEM_SIZE - Cache_Block_Size);
    //         logic [DATA_WIDTH-1:0] expected = read_ref_mem(addr);
    //         logic [DATA_WIDTH-1:0] actual;
    //         read_mem(addr, actual);
    //         compare_data(addr, expected, actual);
    //     end
        
    //     wait_for_idle();
    //     $display("Test Random Latency Completed\n");
    // endtask
    
    // ========== 测试3：背压测试 ==========
    // task test_backpressure();
    //     $display("\n--- Test: Backpressure ---");
    //     latency_in = 2;
        
    //     // 写操作队列
    //     for (int i = 0; i < 5; i++) begin
    //         logic [31:0] addr = i * Cache_Block_Size;
    //         logic [DATA_WIDTH-1:0] wdata = i;
    //         write_mem(addr, wdata);
    //         update_ref_mem(addr, wdata);
    //     end
        
    //     #50;
        
    //     // 读操作，但 mem_resp_ready 随机拉低
    //     fork
    //         for (int i = 0; i < 10; i++) begin
    //             logic [31:0] addr = i * Cache_Block_Size;
    //             logic [DATA_WIDTH-1:0] expected = read_ref_mem(addr);
    //             logic [DATA_WIDTH-1:0] actual;
    //             read_mem_with_backpressure(addr, actual);
    //             compare_data(addr, expected, actual);
    //             #($urandom_range(1, 10));
    //         end
    //     join_none
        
    //     // 背压生成器
    //     begin
    //         for (int i = 0; i < 100; i++) begin
    //             @(posedge clk);
    //             if ($urandom_range(0, 3) == 0) begin
    //                 mem_resp_ready = 0;
    //                 repeat($urandom_range(1, 5)) @(posedge clk);
    //                 mem_resp_ready = 1;
    //             end
    //         end
    //     end
        
    //     wait_for_idle();
    //     mem_resp_ready = 1;
    //     $display("Test Backpressure Completed\n");
    // endtask
    
    // // ========== 测试4：地址边界测试 ==========
    // task test_address_boundary();
    //     $display("\n--- Test: Address Boundary ---");
    //     latency_in = 0;
        
    //     // 测试地址边界
    //     logic [31:0] test_addrs[] = {
    //         0,                                    // 起始地址
    //         MEM_SIZE - Cache_Block_Size,         // 最后一块
    //         MEM_SIZE - 1,                        // 边界内
    //         MEM_SIZE,                            // 边界外（应该被截断或出错）
    //         32'hFFFF_FFF0                        // 超大地址
    //     };
        
    //     foreach (test_addrs[i]) begin
    //         logic [31:0] addr = test_addrs[i];
    //         logic [DATA_WIDTH-1:0] wdata = i;
    //         logic [DATA_WIDTH-1:0] actual;
            
    //         $display("Testing address 0x%0h", addr);
    //         write_mem(addr, wdata);
            
    //         // 只有合法地址才更新参考内存
    //         if (addr + Cache_Block_Size <= MEM_SIZE) begin
    //             update_ref_mem(addr, wdata);
    //         end
            
    //         read_mem(addr, actual);
            
    //         // 检查读回的数据
    //         if (addr + Cache_Block_Size <= MEM_SIZE) begin
    //             logic [DATA_WIDTH-1:0] expected = read_ref_mem(addr);
    //             compare_data(addr, expected, actual);
    //         end
    //     end
        
    //     wait_for_idle();
    //     $display("Test Address Boundary Completed\n");
    // endtask
    
    // ========== 测试5：随机读写测试 ==========
    // task test_random_read_write();
    //     $display("\n--- Test: Random Read/Write ---");
        
    //     for (int iter = 0; iter < 100; iter++) begin
    //         // 随机延迟
    //         latency_in = $urandom_range(0, 5);
            
    //         // 随机操作：0=写，1=读
    //         int op = $urandom_range(0, 1);
    //         logic [31:0] addr = $urandom_range(0, MEM_SIZE - Cache_Block_Size);
            
    //         if (op == 0) begin  // 写
    //             logic [DATA_WIDTH-1:0] wdata = {$random(), $random(), $random(), $random(),
    //                                              $random(), $random(), $random(), $random()};
    //             write_mem(addr, wdata);
    //             update_ref_mem(addr, wdata);
    //             $display("[RAND] Write addr=0x%0h, latency=%0d", addr, latency_in);
    //         end else begin  // 读
    //             logic [DATA_WIDTH-1:0] expected = read_ref_mem(addr);
    //             logic [DATA_WIDTH-1:0] actual;
    //             read_mem(addr, actual);
    //             compare_data(addr, expected, actual);
    //             $display("[RAND] Read addr=0x%0h, latency=%0d, match=%s", 
    //                      addr, latency_in, (expected == actual) ? "YES" : "NO");
    //         end
            
    //         #($urandom_range(1, 20));
    //     end
        
    //     wait_for_idle();
    //     $display("Test Random Read/Write Completed\n");
    // endtask
    
    // ========== 写操作任务 ==========
    task write_mem(input logic [31:0] addr, input logic [DATA_WIDTH-1:0] data);
        // 等待 DUT 准备好接收请求
        @(posedge clk);
        mem_req_valid = 1;
        mem_wr_en = 1;
        mem_addr = addr;
        mem_wdata = data;
        
        // 等待 ready 信号
        while (!mem_req_ready) begin
            @(posedge clk);
        end
        
        @(posedge clk);
        mem_req_valid = 0;
        mem_wr_en = 0;
        
        $display("[WRITE] addr=0x%0h, latency=%0d, data=%0d", addr, latency_in, data);
    endtask
    
    // ========== 读操作任务 ==========
    task read_mem(input logic [31:0] addr, output logic [DATA_WIDTH-1:0] data);
        // 发送读请求
        @(posedge clk);
        mem_req_valid = 1;
        mem_wr_en = 0;
        mem_addr = addr;
        
        while (!mem_req_ready) begin
            @(posedge clk);
        end
        
        @(posedge clk);
        mem_req_valid = 0;
        
        // 等待响应数据
        while (!mem_resp_valid) begin
            @(posedge clk);
        end
        
        data = mem_rdata;
        
        $display("[READ] addr=0x%0h, data=%0d, latency=%0d", addr, data, latency_in);
    endtask
    
    // ========== 带背压的读操作 ==========
    task read_mem_with_backpressure(input logic [31:0] addr, output logic [DATA_WIDTH-1:0] data);
        @(posedge clk);
        mem_req_valid = 1;
        mem_wr_en = 0;
        mem_addr = addr;
        
        while (!mem_req_ready) @(posedge clk);
        @(posedge clk);
        mem_req_valid = 0;
        
        while (!mem_resp_valid) @(posedge clk);
        data = mem_rdata;
    endtask
    
    // ========== 参考内存操作 ==========
    function void update_ref_mem(input logic [31:0] addr, input logic [DATA_WIDTH-1:0] data);
        for (int i = 0; i < Cache_Block_Size; i++) begin
            if (addr + i < MEM_SIZE) begin
                ref_mem[addr + i] = data[i*8 +: 8];
            end
        end
    endfunction
    
    function logic [DATA_WIDTH-1:0] read_ref_mem(input logic [31:0] addr);
        logic [DATA_WIDTH-1:0] data = 0;
        for (int i = 0; i < Cache_Block_Size; i++) begin
            if (addr + i < MEM_SIZE) begin
                data[i*8 +: 8] = ref_mem[addr + i];
            end
        end
        return data;
    endfunction
    
    // ========== 数据比对 ==========
    function void compare_data(input logic [31:0] addr, 
                                input logic [DATA_WIDTH-1:0] expected,
                                input logic [DATA_WIDTH-1:0] actual);
        total_checks++;
        
        if (expected !== actual) begin
            error_count++;
            $display("ERROR at addr=0x%0h:", addr);
            $display("  Expected: %0d", expected);
            $display("  Actual:   %0d", actual);
            
            // 逐字节显示差异
            for (int i = 0; i < Cache_Block_Size; i++) begin
                if (expected[i*8 +: 8] !== actual[i*8 +: 8]) begin
                    $display("  Byte %0d: Expected=%0d, Actual=%0d", 
                             i, expected[i*8 +: 8], actual[i*8 +: 8]);
                end
            end
        end else begin
            $display("MATCH at addr=0x%0h: data=%0d", addr, actual);
        end
    endfunction
    
    // ========== 等待所有操作完成 ==========
    task wait_for_idle();
        repeat(10) @(posedge clk);
        // 等待所有响应完成
        while (mem_req_valid || mem_resp_valid) begin
            @(posedge clk);
        end
    endtask
    
    // ========== 监控波形 ==========
    initial begin
        $display("Dumping waveform...");
        $fsdbDumpfile();
        $fsdbDumpvars();
        $fsdbDumpMDA();
    end
    
endmodule