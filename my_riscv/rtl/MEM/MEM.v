`include "../define/define.vh"
module MEM (
    input clk,                                  //时钟
    input clk_enable,                           //时钟使能
    input [31:0] address,                       //访问地址
    input [31:0] rom_read_data,                 //从ROM读出的数据
    input memory_read,							//读内存信号
    input memory_write,							//写内存信号
    input [2:0] funct3,							//funct3
	input [31:0] register_file_read_data,		//从寄存器读出的数据
	
	output reg [31:0] register_file_write_data,	//写回寄存器堆的数据
    output [31:0] rom_address,                  //ROM地址
    output reg [31:0] written_data,             //已写入的数据（调试用）
    output reg [31:0] written_address           //已写入的地址（调试用）
);

//————————————————————数据预处理————————————————————//
    reg [7:0] byte_sel;                         //一个字节
    reg [15:0] half_sel;                        //半个字
    reg [31:0] data_memory_read_data;			//从内存读出的数据
    reg [31:0] data_memory_write_data;	        //写回内存的数据
    reg [3:0] write_mask;				     	//写掩码

    always @(*) begin
        if (memory_read) begin
			data_memory_write_data = 32'b0;
			write_mask = 4'b0;
			
			case (funct3)
				// ───────────── LOAD ─────────────
				`LOAD_LB , `LOAD_LBU : begin
					case (address[1:0])
						2'b00: byte_sel = data_memory_read_data[ 7: 0];//第0字节
						2'b01: byte_sel = data_memory_read_data[15: 8];//第1字节
						2'b10: byte_sel = data_memory_read_data[23:16];//第2字节
						2'b11: byte_sel = data_memory_read_data[31:24];//第3字节
					endcase

					if (funct3 == `LOAD_LBU)
						register_file_write_data = {24'b0, byte_sel};               //无符号拓展
					else
						register_file_write_data = {{24{byte_sel[7]}}, byte_sel};   //有符号拓展
				end

				`LOAD_LH , `LOAD_LHU : begin
					case (address[1])
						1'b0 : half_sel = data_memory_read_data[15:0]; //低半字
						1'b1 : half_sel = data_memory_read_data[31:16];//高半字
					endcase

					if (funct3 == `LOAD_LHU)
						register_file_write_data = {16'b0, half_sel};                //无符号拓展
					else
						register_file_write_data = {{16{half_sel[15]}}, half_sel};   //有符号拓展
				end

				`LOAD_LW : begin
					register_file_write_data = data_memory_read_data;//一个字
				end

				default: begin
					register_file_write_data = 32'b0;
				end
			endcase
		end
		else if (memory_write) begin
			register_file_write_data = 32'b0;
						
			case (funct3)
				// ───────────── STORE ─────────────
				`STORE_SB: begin
					data_memory_write_data = {4{register_file_read_data[7:0]}};//要存的字节复制为32位
					
					case (address[1:0])
						2'b00: write_mask = 4'b0001;//写道第0字节
						2'b01: write_mask = 4'b0010;//写道第1字节
						2'b10: write_mask = 4'b0100;//写道第2字节
						2'b11: write_mask = 4'b1000;//写道第3字节
					endcase
				end
				`STORE_SH: begin
					data_memory_write_data = {2{register_file_read_data[15:0]}};//要存的半字复制为32位
					
					case (address[1:0])
						2'b00: write_mask = 4'b0011;//写到低半字
						2'b10: write_mask = 4'b1100;//写到高半字
						default: write_mask = 4'b0000;
					endcase
				end
				`STORE_SW: begin
					data_memory_write_data = register_file_read_data;
					
					if (address[1:0] == 2'b00)
						write_mask = 4'b1111;//写一个字
					else
						write_mask = 4'b0000;
				end
				default: begin
					data_memory_write_data = 32'b0;
					write_mask = 4'b0;
				end
			endcase
		end
		else begin
			register_file_write_data = 32'b0;
			data_memory_write_data = 32'b0;
			write_mask = 4'b0;
		end
    end
//————————————————————数据存储器读写————————————————————//
    reg [31:0] memory [0:8191];       //容量=32*8192=8*4*8192=8*32768=32kb
    reg [31:0] new_word;

    //地址解码= 0x10000000~0x10007FFF → 0~8191
    wire [31:0] extended_mask = {{8{write_mask[3]}}, {8{write_mask[2]}}, {8{write_mask[1]}}, {8{write_mask[0]}}};
    wire ram_access = (address[31:16] == 16'h1000);//ram访问
    wire rom_access = (address[31:16] == 16'h0000);//rom访问
    wire [12:0] ram_address = address[14:2];  //ram地址

    assign rom_address = address;

    integer i;
    initial begin    //初始化，将文件数据加载到内存中（文件路径需要更改）
        for (i=0; i<8192; i=i+1) memory[i] = 32'b0;
        $readmemh("C:/Users/KHWL2025/Desktop/RISC-KC/FPGA_Verification/Clean_RV32I46F5SP/Clean_RV32I46F5SP.srcs/sim_1/imports/basic_rv32s-31344d35dd9090e10fd692f257ae98d7bf7702a7/data_init.mem", memory, 13'h1424);
        written_data = 32'b0;
        written_address = 32'b0;
    end

    always @(*) begin    //读操作
        if (ram_access) begin
            data_memory_read_data = memory[ram_address];
        end else if (rom_access) begin
            data_memory_read_data = rom_read_data;
        end else begin
            data_memory_read_data = 32'b0; 
        end
    end

    always @(posedge clk) begin    //写操作
        if (clk_enable && memory_write && ram_access) begin
            new_word = ((memory[ram_address] & ~extended_mask) | (data_memory_write_data & extended_mask)); //按掩码写入：保留未掩码的位
            memory[ram_address] <= new_word;
            written_data <= new_word;
            written_address <= ram_address;
        end
    end
endmodule