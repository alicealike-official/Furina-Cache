module ahb_master #(
    parameter addr_width = 32,
    parameter data_width = 32
)(
    input HCLK,
    input HRESETn,
    //用户接口（usr）
    input usr_en,                      //用户使能
    input usr_write,                   //写使能
    input [2:0] usr_burst,             //用户设置的突出传输类型
    input [addr_width-1:0] usr_addr,   //传输地址
    input [data_width-1:0] usr_wdata,  //写数据
    output reg [data_width-1:0] usr_rdata, //读数据
    output reg done,                   //完成信号
    output reg error,                  //报错信号
    //AHB接口（H）
    input HREADY,                      //从机准备信号
    input HRESP,                       //从机响应信号
    input [data_width-1:0] HRDATA,     //读数据
    output reg HWRITE,                 //写使能
    output wire [2:0] HSIZE,           //写数据或读数据类型
    output wire [2:0] HBURST,          //突发传输
    output reg [1:0] HTRANS,           //传输状态
    output reg [addr_width-1:0] HADDR, //传输地址
    output reg [data_width-1:0] HWDATA //写数据
);
//FSM状态(理解这里的状态可以把它当成从机的状态更好理解)
localparam [2:0] M_STA_IDLE = 2'b001;
localparam [2:0] M_STA_NONSEQ = 2'b010;
localparam [2:0] M_STA_SEQ = 2'b100;
//HTRANS传输状态
localparam [1:0] TR_IDLE = 2'b00;
localparam [1:0] TR_BUSY = 2'b01;
localparam [1:0] TR_NONSEQ = 2'b10;
localparam [1:0] TR_SEQ = 2'b11;
//内部寄存器配置
reg [2:0] state,next_state;            //当前状态与下一个状态
reg [3:0] burst_len;                   //突发传输的长度
reg [3:0] beat_count;                  //突发传输时拍计数
reg [addr_width-1:0] reg_addr;         //内部地址寄存器，用于计算下一拍地址
reg data_phase_last; //由于AHB的数据阶段比地址阶段晚一拍，所以完成标志应该在“最后一个地址阶段结束后的那个周期”拉高

//计算当前突增传输长度
always @(*)begin
    case (usr_burst)//只设置突增传输（INCR），不设计回环传输（WARP）
        3'b000: burst_len = 4'd1;      // SINGLE
        3'b010: burst_len = 4'd4;      // INCR4
        3'b011: burst_len = 4'd8;      // INCR8
        3'b100: burst_len = 4'd16;     // INCR16
        default: burst_len = 4'd1;     // 默认防错
    endcase
end

//内部地址寄存器与计数器更新
always @(posedge HCLK or negedge HRESETn) begin
    if(!HRESETn) begin
        beat_count <= 4'd0;
        reg_addr <= 32'd0;
    end
    else if(HREADY) begin //HREADY为1时才更新计数和下一拍地址
        if((state==M_STA_IDLE) && usr_en) begin
            beat_count <= 4'd1;
            reg_addr <= usr_addr + 32'd4; //提前计算好下一拍地址
        end
        else if((state == M_STA_NONSEQ) || (state == M_STA_SEQ)) begin
            if(beat_count < burst_len) begin
                beat_count <= beat_count + 4'd1;
                reg_addr <= reg_addr + 32'd4;
            end
            else begin
                beat_count <= 4'd0;
                reg_addr <= 32'd0;
            end
        end
    end
    else begin  //HREADY为0时，保持计数和下一拍地址不变
        beat_count <= beat_count;
        reg_addr <= reg_addr;
    end
end

//状态机更新
always @(posedge HCLK or negedge HRESETn) begin
    if(!HRESETn) begin
        state <= M_STA_IDLE;
    end
    else begin
        if(HREADY&&HRESP) state <= M_STA_IDLE;
        else state <= next_state;
    end
end

always @(*) begin
    case(state)
        M_STA_IDLE:begin
            next_state = usr_en? M_STA_NONSEQ : M_STA_IDLE;
        end
        M_STA_NONSEQ:begin
            if(HREADY)begin
                if(burst_len>1) next_state = M_STA_SEQ;
                else if((burst_len==1)&&usr_en) next_state = M_STA_NONSEQ;
                else next_state = M_STA_IDLE
            end
        end
        M_STA_SEQ:begin
            if(HREADY)begin
                if(beat_count<burst_len) next_state = M_STA_SEQ;
                else if((beat_count==burst_len)&&usr_en) next_state = M_STA_NONSEQ;
                else next_state = M_STA_IDLE;
            end
         end
        default:next_state = state;
    endcase
end

//输出逻辑更新
always @(*) begin
    case(next_state)
        M_STA_IDLE: begin
            HTRANS = TR_IDLE;
            HWRITE = 1'b0;
            HADDR = 32'd0;
            HWDATA = 32'd0;
        end
        M_STA_NONSEQ:begin
            HTRANS = TR_NONSEQ;
            HWRITE = usr_write;
            HADDR = usr_addr;
            HWDATA = usr_wdata;
        end
        M_STA_SEQ:begin
            HTRANS = TR_SEQ;
            HWRITE = usr_write;
            HADDR = reg_addr;
            HWDATA = usr_wdata;
        end
    endcase
end

assign HSIZE = 3'b010;                 //默认字传输（32bit）
assign HBURST = usr_burst;             //用户定义突发传输类型

//用户响应逻辑更新
always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) 
        data_phase_last <= 1'b0;
    else if (HREADY) begin
        // 判断当前是不是处于“发出最后一个地址”的周期
        if ((state == M_STA_NONSEQ && burst_len == 1) || 
            (state == M_STA_SEQ    && beat_count == burst_len)) begin
            data_phase_last <= 1'b1; // 下一个周期就是最后的数据阶段
        end else begin
            data_phase_last <= 1'b0;
        end
    end
end

assign done = data_phase_last & HREADY;//当处于最后一个数据阶段，并且 HREADY 为 1，说明所有数据都写进/读出从机了，Burst真正结束
assign error = HRSEP;

always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            usr_rdata <= {data_width{1'b0}};
        end
        else begin
            if(HREADY) usr_data <= HRDATA;
        end
    end

endmodule
