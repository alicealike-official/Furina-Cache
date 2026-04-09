`include "../define/define.vh"
module EX (
    input [6:0] opcode,        		//操作码7位
	input [2:0] funct3,				//功能码3位
    input funct7_5,					//funct7 的第5位，用于区分 R 型指令的变体
    input imm_10,					//立即数的第10位，用于区分 I 型移位指令
	input [31:0] src_A,             //源操作数A
    input [31:0] src_B,             //源操作数B
    input branch,             		//是否有分支指令
	input branch_estimation,        //分支预测结果（1跳，0不跳）
    input [31:0] pc,                //当前pc
	input [31:0] imm,               //分支立即数（偏移量）
  
    output reg [31:0] alu_result,   //ALU结果
    output reg alu_zero,             //0标志位
    output reg branch_taken, 		//分支是否真正跳转
	output reg [31:0] branch_target_actual, //分支跳转目标地址
	output reg branch_prediction_miss //预测是否失误
);

    reg [3:0] alu_op;                 //ALU操作码4位
//————————————————————生成ALU控制信号alu_op————————————————————//
    always @(*) begin
        case (opcode)
			`OPCODE_AUIPC: begin      //跳转指令
				alu_op = `ALU_OP_ADD; //PC+立即数
			end
			`OPCODE_JAL: begin        //跳转指令
				alu_op = `ALU_OP_ADD; //计算跳转目标
			end
			`OPCODE_JALR: begin       //跳转指令
				alu_op = `ALU_OP_ADD; //计算返回地址
			end
			`OPCODE_BRANCH: begin     //分支指令
				case (funct3)
					`BRANCH_BEQ: begin
						alu_op = `ALU_OP_SUB; //相等则相减为0
					end
					`BRANCH_BNE: begin
						alu_op = `ALU_OP_SUB; //不相等则相减不为0
					end
					`BRANCH_BLT: begin
						alu_op = `ALU_OP_SLT; //有符号小于
					end
					`BRANCH_BGE: begin
						alu_op = `ALU_OP_SLT; //有符号大于等于
					end
					`BRANCH_BLTU: begin
						alu_op = `ALU_OP_SLTU; //无符号小于
					end
					`BRANCH_BGEU: begin
						alu_op = `ALU_OP_SLTU; //无符号大于等于
					end
					default: begin
					   alu_op = `ALU_OP_NOP;
					end
				endcase
			end
			`OPCODE_LOAD: begin       //加载指令
				alu_op = `ALU_OP_ADD; //计算内存地址 rs1+立即数
			end
			`OPCODE_STORE: begin      //存储指令
				alu_op = `ALU_OP_ADD; //计算内存地址 rs1+立即数
			end
			`OPCODE_ITYPE: begin      //I型立即数指令
				case (funct3)
					`ITYPE_ADDI: begin
						alu_op = `ALU_OP_ADD; //加立即数
					end
					`ITYPE_SLLI: begin
						alu_op = `ALU_OP_SLL; //逻辑左移
					end
					`ITYPE_SLTI: begin
						alu_op = `ALU_OP_SLT; //有符号比较
					end
					`ITYPE_SLTIU: begin
						alu_op = `ALU_OP_SLTU; //无符号比较
					end
					`ITYPE_XORI: begin
						alu_op = `ALU_OP_XOR;  //异或
					end
					`ITYPE_SRXI: begin         //逻辑右移或算数右移
						if (imm_10) begin
							alu_op = `ALU_OP_SRA; //算数右移:imm[10] = 1
						end
						else begin
							alu_op = `ALU_OP_SRL; //逻辑右移:imm[10] = 0
						end
					end
					`ITYPE_ORI: begin
						alu_op = `ALU_OP_OR;      //立即数或:110
					end
					`ITYPE_ANDI: begin
						alu_op = `ALU_OP_AND;     //立即数与:111
					end
					default: begin
					   alu_op = `ALU_OP_NOP;
					end
				endcase
			end
			`OPCODE_RTYPE: begin      //R型寄存器指令
                case (funct3)
					`RTYPE_ADDSUB: begin          //加或减
						if (funct7_5) begin
							alu_op = `ALU_OP_SUB; //减：funct7 = 0100000
						end
						else begin
							alu_op = `ALU_OP_ADD; //加funct7 = 0000000 
						end
					end
					`RTYPE_SLL: begin 
						alu_op = `ALU_OP_SLL;  //左移
					end
					`RTYPE_SLT: begin 
						alu_op = `ALU_OP_SLT;  //有符号比较
					end
					`RTYPE_SLTU: begin
						alu_op = `ALU_OP_SLTU;  //无符号比较
					end
					`RTYPE_XOR: begin
						alu_op = `ALU_OP_XOR;  //异或
					end
					`RTYPE_SR: begin           //逻辑右移或算数右移
						if (funct7_5) begin
							alu_op = `ALU_OP_SRA; //算数右移：funct7 = 0100000
						end
						else begin
							alu_op = `ALU_OP_SRL; //逻辑右移：funct7 = 0000000
						end
					end
					`RTYPE_OR: begin
						alu_op = `ALU_OP_OR;  //或
					end
					`RTYPE_AND: begin
						alu_op = `ALU_OP_AND;  //与
					end
					default: begin
					   alu_op = `ALU_OP_NOP;
                    end
				endcase
            end
			`OPCODE_ENVIRONMENT: begin  //CSR指令（用于处理器的配置、状态监控和控制）
				case (funct3)
					`CSR_CSRRW: begin   //原子交换：读取CSR的值，同时写入新值
						alu_op = `ALU_OP_BPA;
					end
					`CSR_CSRRS: begin   //原子置位：读取CSR的值，将指定位置 1
						alu_op = `ALU_OP_OR;
					end
					`CSR_CSRRC: begin   //原子清除：读取CSR的值，将指定位清 0
						alu_op = `ALU_OP_ABJ;
					end
					`CSR_CSRRWI: begin   //立即数原子交换
						alu_op = `ALU_OP_BPA;
					end
					`CSR_CSRRSI: begin   //立即数原子置位
						alu_op = `ALU_OP_OR;
					end
					`CSR_CSRRCI: begin   //立即数原子清除
						alu_op = `ALU_OP_ABJ;
					end
					default: begin
						alu_op = `ALU_OP_NOP;
					end
				endcase
			end
			default: begin
				alu_op = `ALU_OP_NOP;
			end
        endcase
    end
//————————————————————ALU运算并输出结果————————————————————//
    always @(*) begin
        case (alu_op)
            `ALU_OP_ADD: begin  //加法
                alu_result = src_A + src_B;
            end

            `ALU_OP_SUB: begin  //减法
                alu_result = src_A - src_B;
            end
            
            `ALU_OP_AND: begin  //与
                alu_result = src_A & src_B;
            end
            
            `ALU_OP_OR: begin  //或
                alu_result = src_A | src_B;
            end
            
            `ALU_OP_XOR: begin  //异或
                alu_result = src_A ^ src_B;
            end
            
            `ALU_OP_SLT: begin  //有符号比较
                alu_result = ($signed(src_A) < $signed(src_B)) ? 32'd1 : 32'd0;
            end

            `ALU_OP_SLTU: begin  //无符号比较
                alu_result = (src_A < src_B) ? 32'd1 : 32'd0;
            end
            
            `ALU_OP_SLL: begin  //逻辑左移
                alu_result = src_A << src_B;
            end
            
            `ALU_OP_SRL: begin  //逻辑右移
                alu_result = src_A >> src_B;
            end
            
            `ALU_OP_SRA: begin  //算数右移
                alu_result = $signed(src_A) >>> src_B;
            end
            
            `ALU_OP_ABJ: begin  //与非（A&~B）
                alu_result = src_B & (~src_A);
            end

            `ALU_OP_BPA: begin  //直接传递（将A直接给结果）
                alu_result = src_A;
            end

            `ALU_OP_NOP: begin  //空操作
                alu_result = 32'd0;
            end

            default: begin
                alu_result = 32'd0;
            end
        endcase

        alu_zero = (alu_result == 32'd0); //0标志位（alu结果为0时才为1）
    end
//————————————————————跳转分支逻辑————————————————————//
    wire branch_prediction;
	assign branch_prediction = branch_estimation;

    always @(*) begin
        if (branch) begin
			case (funct3)
				`BRANCH_BEQ: branch_taken = alu_zero;  //a-b -> alu=0 -> alu_zero=1
				`BRANCH_BNE: branch_taken = ~alu_zero; //a-b -> alu!=0 -> alu_zero=0
				`BRANCH_BLT: branch_taken = ~alu_zero; //a<b -> alu=1 -> alu_zero=0
				`BRANCH_BGE: branch_taken = alu_zero;  //a<b -> alu=0 -> alu_zero=1
				`BRANCH_BLTU: branch_taken = ~alu_zero;//a<b -> alu=1 -> alu_zero=0
				`BRANCH_BGEU: branch_taken = alu_zero; //a<b -> alu=0 -> alu_zero=1
				default: branch_taken = 1'b0;
			endcase
			branch_target_actual = pc + imm;
			branch_prediction_miss = (branch_estimation != branch_taken);
		end
		else begin
			branch_taken = 1'b0;
			branch_target_actual = 32'b0;
			branch_prediction_miss = 1'b0;
		end
    end
endmodule