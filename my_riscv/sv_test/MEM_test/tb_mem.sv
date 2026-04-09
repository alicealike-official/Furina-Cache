module tb_mem;
    reg clk = 0;
    reg clk_enable = 1;
    always #5 clk = ~clk;

    // DUT 实例化
    logic [31:0] address;
    logic [31:0] rom_read_data;
    logic memory_read, memory_write;
    logic [2:0] funct3;
    logic [31:0] register_file_read_data;
    logic [31:0] register_file_write_data;
    logic [31:0] rom_address;
    logic [31:0] written_data, written_address;

    MEM dut (
        .clk(clk),
        .clk_enable(clk_enable),
        .address(address),
        .rom_read_data(rom_read_data),
        .memory_read(memory_read),
        .memory_write(memory_write),
        .funct3(funct3),
        .register_file_read_data(register_file_read_data),
        .register_file_write_data(register_file_write_data),
        .rom_address(rom_address),
        .written_data(written_data),
        .written_address(written_address)
    );

    // 任务：读测试
    task test_read(input [31:0] addr, input [2:0] f3, input [31:0] expected);
        address = addr;
        funct3 = f3;
        memory_read = 1;
        memory_write = 0;
        #10;
        if (register_file_write_data !== expected) begin
            $error("Read: addr=%h, funct3=%b, expected=%h, got=%h", addr, f3, expected, register_file_write_data);
        end else begin
            $display("Read OK: addr=%h, funct3=%b, data=%h", addr, f3, register_file_write_data);
        end
        memory_read = 0;
    endtask

    // 任务：写测试
    task test_write(input [31:0] addr, input [2:0] f3, input [31:0] wdata, input [31:0] expected_after, input [31:0] exp_written_data, input [31:0] exp_written_addr);
        address = addr;
        funct3 = f3;
        register_file_read_data = wdata;
        memory_write = 1;
        memory_read = 0;
        #10;
        // 检查写入后的值（需再读一次）
        memory_write = 0;
        memory_read = 1;
        #10;
        if (register_file_write_data !== expected_after) begin
            $error("Write: addr=%h, funct3=%b, wdata=%h, after read=%h, expected=%h", addr, f3, wdata, register_file_write_data, expected_after);
        end else if (written_data !== exp_written_data || written_address !== exp_written_addr) begin
            $error("Write debug mismatch: written_data=%h, exp=%h; written_addr=%h, exp=%h", written_data, exp_written_data, written_address, exp_written_addr);
        end else begin
            $display("Write OK: addr=%h, funct3=%b, wdata=%h, after read=%h", addr, f3, wdata, register_file_write_data);
        end
        memory_read = 0;
    endtask

    initial begin
        // 初始化
        address = 0;
        rom_read_data = 32'h12345678;
        memory_read = 0;
        memory_write = 0;
        funct3 = 0;
        register_file_read_data = 0;
        #20;

        // 1. 读 ROM
        rom_read_data = 32'hA5A5A5A5;
        address = 32'h00001000;  // ROM 范围
        test_read(address, 3'b010, 32'hA5A5A5A5); // LW

         // 2. 读 RAM（先写入数据）
         address = 32'h10001000; // RAM 范围，字对齐
         // 直接写 memory 初始值？这里简单用写操作设值
         // 写 SW
         test_write(32'h10001000, 3'b010, 32'h11223344, 32'h11223344, 32'h11223344, 14'h400); // ram_address = 14'h400

        // 3. 读 LB（地址 0x10001001）
        // 预期：从 0x10001000 读出 32'h11223344，地址低 2 位 01 → byte1 = 0x33
        test_read(32'h10001001, 3'b000, 32'h00000033); // LB 符号扩展
        test_read(32'h10001001, 3'b100, 32'h00000033); // LBU 零扩展（一样）

        // 4. 读 LH（地址 0x10001002）
        // 预期：低 1 位 1 → 高半字 0x1122，符号扩展 0xFFFF1122
        test_read(32'h10001002, 3'b001, 32'h00001122); // LH
        test_read(32'h10001002, 3'b101, 32'h00001122); // LHU

        // 5. 写 SB（地址 0x10001001，数据 0xAB）
        // 原值 0x11223344，写 byte1 为 AB → 0x11AB3344
        test_write(32'h10001001, 3'b000, 32'h000000AB, 32'hFFFFFFAB, 32'h1122AB44, 14'h400);

        // 6. 写 SH（地址 0x10001002，数据 0xDEAD）
        // 原值 0x11AB3344，地址低 2 位 10 → 高半字 = DEAD → 0xDEAD3344
        test_write(32'h10001002, 3'b001, 32'h0000DEAD, 32'hFFFFDEAD, 32'hDEADAB44, 14'h400);

        // 7. 写 SW（地址 0x10001000，数据 0xFFFFFFFF）
        test_write(32'h10001000, 3'b010, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, 14'h400);

        // 8. 边界：读未对齐 LW
        //test_read(32'h10001001, 3'b010, 32'b0); // 应返回 0（因为未对齐？但代码未禁止，会从 memory[ram_address] 读，地址低 2 位丢弃）

        // 9. 写未对齐 SW（应无效果，掩码 0）
        test_write(32'h10001001, 3'b010, 32'h12345678, 32'hFFFFFFFF, 32'hFFFFFFFF, 14'h400); // 不变

        // 10. clk_enable=0 时写
        clk_enable = 0;
        test_write(32'h10001000, 3'b010, 32'h0, 32'hFFFFFFFF, 32'hFFFFFFFF, 14'h400); // 不应改变
        clk_enable = 1;

        $finish;
    end

    initial begin
                // 根据命令行参数决定是否dump波形
                    $display("Dumping waveform...");
                    $fsdbDumpfile("wave.fsdb");
                    $fsdbDumpvars(0, tb_mem);
    end
    // 断言：检查 ROM 地址传递
    assert property (@(posedge clk) (rom_address === address)) else $error("rom_address mismatch");
endmodule