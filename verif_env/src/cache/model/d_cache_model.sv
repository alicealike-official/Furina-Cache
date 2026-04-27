//d_cache_model.sv
`ifndef D_CACHE_MODEL__SV
`define D_CACHE_MODEL__SV
`include "uvm_macros.svh"
`include "vutils_macros.svh"
`include "define.svh"
import uvm_pkg::*;
import clk_rst_pkg::*;
import cache_pkg::*;
class d_cache_model extends uvm_component;
    `uvm_component_utils(d_cache_model)
       
    // 计算派生参数
    localparam int Offset_Width = $clog2(`CACHE_BLOCK_SIZE);     // 块内偏移位数 (6 bits for 64B)
    localparam int Index_Width = $clog2(`NUM_CACHE_SET);        // 组索引位数 (5 bits for 32 sets)
    localparam int Tag_Width = `DATA_ADDR_BUS - Index_Width - Offset_Width; // 标签位数 (21 bits)
    localparam int Way_Width = $clog2(`NUM_CACHE_WAY);
    localparam int Bytes_Per_Word = `DATA_WIDTH / 8;       // 每字字节数 (4)
    
    // 缓存存储结构
    typedef struct {
        logic valid;                    // 有效位
        logic dirty;                    // 脏位
        logic [Tag_Width-1:0] tag;       // 标签
        logic [`DATA_WIDTH-1:0] data [`WORDS_PER_BLOCK-1:0]; // 数据数组
    } cache_line_t;

    typedef struct {
        logic [Way_Width-1  : 0] way_hit;
        logic hit_sign;
        logic [Way_Width-1 : 0] alloc_way;
    } cache_hit_status;
    
    cache_line_t cache[`NUM_CACHE_SET][`NUM_CACHE_WAY];
    cache_hit_status status;

    //FIFO替换
    logic [Way_Width-1:0] fifo_ptr[`NUM_CACHE_SET];

    
    // 统计信息
    int hit_count;
    int miss_count;
    int writeback_count;
    
    // UVM 端口
    uvm_tlm_analysis_fifo #(cpu_req_transaction) cpu_req_fifo;
    uvm_tlm_analysis_fifo #(mem_rsp_transaction) mem_rsp_fifo;

    //给scoreboard进行比对
    uvm_analysis_port #(mem_req_transaction)    mem_req_port;
    uvm_analysis_port #(cache_rsp_transaction)  cache_rsp_port;
    
    mailbox #(mem_rsp_transaction) mem_rsp_mb;
    //内存完成信号
    event mem_done_evt;

    function new(string name = "d_cache_model",
                                uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end

        cpu_req_fifo = new("cpu_req_fifo", this);
        mem_rsp_fifo = new("mem_rsp_fifo", this);
        mem_req_port = new("mem_req_port", this);
        cache_rsp_port = new("cache_rsp_port", this);
        mem_rsp_mb = new();

        hit_count = 0;
        miss_count = 0;
        writeback_count = 0;
    endfunction


    extern function void build_phase(uvm_phase phase);
    extern function void start_of_simulation_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern function void reset_cache();
    extern task cpu_thread();
    extern task mem_thread();
    //extern task access_memory_blocking();
    extern function void parse_address(bit [`DATA_ADDR_BUS-1:0] addr, 
                                        output logic [Tag_Width-1:0] tag,
                                        output logic [Index_Width-1:0] index,
                                        output logic [Offset_Width-1:0] offset);
    extern function void check_hit(logic [Tag_Width-1:0] tag, 
                                  logic [Index_Width-1:0] index,
                                  ref cache_hit_status status);
    extern function logic [Way_Width-1:0] select_alloc_way(logic [Index_Width-1:0] index);
   // extern function void update_lru(logic [Index_Width-1:0] index, int way_accessed);
    extern function void update_fifo_ptr(logic [Index_Width-1:0] index);
    //extern task write_back_line(logic [Index_Width-1:0] index, int way);
    extern task fetch_line(logic [Index_Width-1:0] index, logic [Way_Width-1:0] way, 
                           logic [Tag_Width-1:0] tag,
                           mem_rsp_transaction rsp);
    extern function logic [`DATA_WIDTH-1:0] read_word_from_cache(
        logic [Index_Width-1:0] index, logic[Way_Width-1:0] way, logic [Offset_Width-1:0] word_offset);
    extern function void write_word_to_cache(
        logic [Index_Width-1:0] index, logic[Way_Width-1:0] way, logic [Offset_Width-1:0] word_offset,
        logic [`DATA_WIDTH-1:0] data);
    extern task process_cpu_request(cpu_req_transaction req);
    extern function void report_stats();
    extern function void report_phase(uvm_phase phase);  
endclass



// Build Phase
function void d_cache_model::build_phase(uvm_phase phase);
    super.build_phase(phase);
    //set_report_verbosity_level(UVM_DEBUG);         // 只影响本组件
endfunction


// Start of Simulation
function void d_cache_model::start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    reset_cache();
    `info_med($sformatf("D-Cache Model initialized: %0d sets, %0d ways, %0dB block, %0d-bit data",
                `NUM_CACHE_SET, `NUM_CACHE_WAY, `CACHE_BLOCK_SIZE, `DATA_WIDTH))
endfunction
// 主循环
task d_cache_model::run_phase(uvm_phase phase);
    fork
        cpu_thread();
        mem_thread();
    join
endtask

// 复位缓存
function void d_cache_model::reset_cache();
    for (int i = 0; i < `NUM_CACHE_SET; i++) begin
        for (int j = 0; j < `NUM_CACHE_WAY; j++) begin
            cache[i][j].valid = 1'b0;
            cache[i][j].dirty = 1'b0;
            cache[i][j].tag = '0;
            for (int k = 0; k < `WORDS_PER_BLOCK; k++) begin
                cache[i][j].data[k] = '0;
            end
            fifo_ptr[i] = 0;
        end
    end
    `info_debug("Cache reset completed")
endfunction

task d_cache_model::cpu_thread();
    reset_cache();
    forever begin
        cpu_req_transaction req;
        // if (!cpu_req_fifo.try_put(req)) begin
        //     `warn("Expected FIFO full")
        // end
        cpu_req_fifo.get(req);
        process_cpu_request(req);
    end
endtask

task d_cache_model::mem_thread();
    forever begin
        mem_rsp_transaction rsp;
        mem_rsp_fifo.get(rsp);
        mem_rsp_mb.put(rsp);
    end
endtask


// task d_cache_model::access_memory_blocking();
//     @(mem_done_evt);
// endtask

// 解析地址
function void d_cache_model::parse_address(bit [`DATA_ADDR_BUS-1:0] addr,
                                           output logic [Tag_Width-1:0] tag,
                                           output logic [Index_Width-1:0] index,
                                           output logic [Offset_Width-1:0] offset);
    tag = addr[`DATA_ADDR_BUS-1 -: Tag_Width];
    index = addr[Offset_Width +: Index_Width];
    offset = addr[Offset_Width-1:0];
endfunction

// 检查命中
function void d_cache_model::check_hit(logic [Tag_Width-1:0] tag,
                                      logic [Index_Width-1:0] index,
                                      ref cache_hit_status status);
    status.way_hit = 0;
    status.hit_sign = 0;
    for (int i = 0; i < `NUM_CACHE_WAY; i++) begin
        if (cache[index][i].valid && cache[index][i].tag == tag) begin
            if (status.hit_sign == 1) begin
                `fatal($sformatf("Cache model fatal error: Address (tag=0x%0h, index=%0d) is found in %0d ways.  \
                                    This indicates a duplicate cache line, which violates cache coherency.", 
                                    tag, index, i))
            end
            else begin
                status.way_hit = i;
                status.hit_sign = 1;  
            end
        end
    end
endfunction

// 选择替换行（FIFO策略）
function logic [d_cache_model::Way_Width-1:0] d_cache_model::select_alloc_way(
    logic [Index_Width-1:0] index
);
    int alloc_way;
    
    // 优先选择无效行
    for (int i = 0; i < `NUM_CACHE_WAY; i++) begin
        if (!cache[index][i].valid) begin
            return i;  // 返回无效行，不更新 FIFO 指针
        end
    end
    
    // 所有行都有效，使用 FIFO 指针选择 Victim
    alloc_way = fifo_ptr[index];
    return alloc_way;
endfunction


function void d_cache_model::update_fifo_ptr(logic [Index_Width-1:0] index);
    // 模拟 RTL 中 fifo_counter 的行为：计数器加 1，循环计数
    fifo_ptr[index] = fifo_ptr[index] + 1;
    if (fifo_ptr[index] >= `NUM_CACHE_WAY) begin
        fifo_ptr[index] = 0;
    end
endfunction

// // 写回脏行到内存
// task d_cache_model::write_back_line(logic [Index_Width-1:0] index, logic [Way_Width-1:0] way);
    
//     if (cache[index][way].dirty) begin

//         last_mem_rsp.rdata
        
//         // 等待内存响应
//         mem_transaction mem_resp;
//         mem_resp_port.get(mem_resp);
        
//         // 写回后清除脏位
//         cache[index][way].dirty = 1'b0;
//     end
// endtask

// 从内存读取缓存行
task d_cache_model::fetch_line(logic [Index_Width-1:0] index, logic [Way_Width-1:0] way,
                               logic [Tag_Width-1:0] tag, mem_rsp_transaction rsp);
    
    // 更新缓存行
    cache[index][way].valid = 1'b1;
    cache[index][way].dirty = 1'b0;
    cache[index][way].tag = tag;
    for (int i = 0; i < `WORDS_PER_BLOCK; i++) begin
        cache[index][way].data[i] = rsp.mem_rdata[i];
    end
    
    `info_debug($sformatf("Fetch completed: %0d words loaded", `WORDS_PER_BLOCK))
endtask

// 从缓存读字
function logic [`DATA_WIDTH-1:0] d_cache_model::read_word_from_cache(
    logic [Index_Width-1:0] index, logic [Way_Width-1:0] way, 
    logic [Offset_Width-1:0] word_offset);
    return cache[index][way].data[word_offset];
endfunction

// 写字到缓存
function void d_cache_model::write_word_to_cache(
    logic [Index_Width-1:0] index, logic [Way_Width-1:0] way, 
    logic [Offset_Width-1:0] word_offset,
    logic [`DATA_WIDTH-1:0] data
); 
    cache[index][way].data[word_offset] = data;
    cache[index][way].dirty = 1'b1;  // 标记为脏
    
    `info_debug($sformatf("Write to cache: index=%0d, way=%0d, offset=%0d, data=0x%0h",
                index, way, word_offset, data))
endfunction

// 处理CPU请求
task d_cache_model::process_cpu_request(cpu_req_transaction req);
    logic [Tag_Width-1:0] tag;
    logic [Index_Width-1:0] index;
    logic [Offset_Width-1:0] offset;
    int word_offset;
    //logic [Way_Width-1:0] way_hit;
    bit hit_sign;
    // cpu_req_transaction resp;
    cache_rsp_transaction rsp;
    mem_req_transaction tr_write;
    mem_req_transaction tr_read;
    //mem_rsp_transaction rsp_write;
    mem_rsp_transaction rsp_read;
    
    rsp = new();
    
    // 解析地址
    parse_address(req.cpu_req_addr, tag, index, offset);
    word_offset = offset / Bytes_Per_Word;  // 转换为字偏移
    
    // 检查命中
    check_hit(tag, index, status);
    
    if (status.hit_sign) begin
        // 缓存命中
        hit_count++;
        `info_debug($sformatf("HIT: addr=0x%0h, tag=0x%0h, index=%0d, way=%0d",
                    req.cpu_req_addr, tag, index, status.way_hit))
        
        if (req.cpu_wr_en) begin
            // 写操作：更新缓存
            write_word_to_cache(index, status.way_hit, word_offset, req.cpu_wdata);
        end
        
        // // 准备响应数据
        // resp = cpu_req_transaction::type_id::create("resp");
        // resp.addr = req.cpu_req_addr;
        // resp.wr_en = req.cpu_wr_en;
        // resp.ready = 1'b1;
        rsp.cpu_req_ready = 1;
        rsp.cpu_resp_valid = 1;
        if (!req.cpu_wr_en) begin
            rsp.cache_rdata = read_word_from_cache(index, status.way_hit, word_offset);
        end
    end

    else begin
        // 缓存未命中
        miss_count++;
        `info_high($sformatf("MISS: addr=0x%0h, tag=0x%0h, index=%0d",
                    req.cpu_req_addr, tag, index))
        
        // 选择替换行
        status.alloc_way = select_alloc_way(index);
        //$display("alloc way = %d", status.alloc_way);
        //$display("dirty = %d", cache[index][status.alloc_way].dirty);
        if (cache[index][status.alloc_way].valid && cache[index][status.alloc_way].dirty) begin
            tr_write = new();
            tr_write.mem_addr = {cache[index][status.alloc_way].tag, index, {Offset_Width{1'b0}}};
            //tr_write.mem_addr = {cache[index][status.alloc_way].tag, index, offset};
            tr_write.mem_wr_en = 1'b1;
            //tr_write.mem_wdata = new[`WORDS_PER_BLOCK];
            // 组装写回数据（连续的字）
            for (int i = 0; i < `WORDS_PER_BLOCK; i++) begin
                tr_write.mem_wdata[i] = cache[index][status.alloc_way].data[i];
                //$display("ref model write:%0h", tr_write.mem_wdata[i]);
            end
            mem_req_port.write(tr_write);
            writeback_count++;
            `info_debug($sformatf("Write back: index=%0d, way=%0d, addr=0x%0h",
                    index, status.alloc_way, tr_write.mem_addr))
            //mem_rsp_mb.get(rsp_write);
            //last_mem_rsp = rsp_write;
            cache[index][status.alloc_way].dirty = 1'b0;
        end
        
        // 从内存读取新行
        
        tr_read = new();
        tr_read.mem_addr = {tag, index, {Offset_Width{1'b0}}};
        tr_read.mem_wr_en = 1'b0;
        mem_req_port.write(tr_read);
        `info_debug($sformatf("Fetch line: index=%0d, way=%0d, tag=0x%0h, addr=0x%0h",
                index, status.alloc_way, tag, tr_read.mem_addr))
        mem_rsp_mb.get(rsp_read);
        //last_mem_rsp = rsp_read;
        //$display("read_data : %0h", rsp_read.mem_rdata);
        fetch_line(index, status.alloc_way, tag, rsp_read);
        // 处理当前请求

        if (req.cpu_wr_en) begin
            write_word_to_cache(index, status.alloc_way, word_offset, req.cpu_wdata);
            //$display("cpu_wdata = %0h", req.cpu_wdata);
        end
        

        
        // 准备响应数据
        rsp = cache_rsp_transaction::type_id::create("rsp");
        rsp.cpu_req_ready = 1'b1;
        rsp.cpu_resp_valid = 1'b1;
        if (!req.cpu_wr_en) begin
            rsp.cache_rdata = read_word_from_cache(index, status.alloc_way, word_offset);
        end
        
        // 更新LRU
        update_fifo_ptr(index);
    end
    
    // 发送响应
    cache_rsp_port.write(rsp);
endtask



// 报告统计信息
function void d_cache_model::report_stats();
    int total_access = hit_count + miss_count;
    real hit_rate = (total_access > 0) ? (hit_count * 1.0 / total_access) : 0;
    
    $display("\n");
    $display("╔════════════════════════════════════════════════╗");
    $display("║  FINAL SUMMARY FOR        %20s ║", get_type_name());
    $display("╠════════════════════════════════════════════════╣");
    $display("║     Total accessses    :  %20d ║", total_access);
    $display("║           Hits         :  %20d ║", hit_count);
    $display("║          Missses       :  %20d ║", miss_count);
    $display("║         Hit rate       :  %20.2f ║", hit_rate);
    $display("║        Writebacks      :  %20d ║", writeback_count);
    $display("╚════════════════════════════════════════════════╝");
    $display("\n");

    // `info( 
    //     $sformatf({"\n=== D-Cache Statistics ===\n",
    //               "Total accesses: %0d\n",
    //               "Hits: %0d\n",
    //               "Misses: %0d\n",
    //               "Hit rate: %.2f%%\n",
    //               "Writebacks: %0d\n",
    //               "=========================="},
    //               total_access, hit_count, miss_count, hit_rate, writeback_count))
endfunction

function void d_cache_model::report_phase(uvm_phase phase);
    super.report_phase(phase);
    report_stats();
endfunction
`endif