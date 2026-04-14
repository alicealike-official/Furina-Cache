// filename: d_cache_model.sv
`ifndef D_CACHE_MODEL__SV
`define D_CACHE_MODEL__SV

class d_cache_model extends uvm_component;
    
    // 配置参数
    parameter int Num_Cache_Set = 32;
    parameter int Cache_Block_Size = 64;  // 字节
    parameter int Num_Cache_Way = 4;
    parameter int DataWidth = 32;   // 位
    parameter int DataAddrBus = 32;
    
    // 计算派生参数
    localparam int Offset_Width = $clog2(Cache_Block_Size);     // 块内偏移位数 (6 bits for 64B)
    localparam int Index_Width = $clog2(Num_Cache_Set);        // 组索引位数 (5 bits for 32 sets)
    localparam int Tag_Width = DataAddrBus - Index_Width - Offset_Width; // 标签位数 (21 bits)
    localparam int Way_Width = $clog2(Num_Cache_Way);
    localparam int Words_Per_Block = Cache_Block_Size / (DataWidth/8); // 每块字数 (64B/4B=16 words)
    localparam int Bytes_Per_Word = DataWidth / 8;       // 每字字节数 (4)
    
    // 缓存存储结构
    typedef struct {
        logic valid;                    // 有效位
        logic dirty;                    // 脏位
        logic [Tag_Width-1:0] tag;       // 标签
        logic [DataWidth-1:0] data [Words_Per_Block-1:0]; // 数据数组
    } cache_line_t;

    typedef struct {
        logic [Way_Width-1  : 0] way_hit;
        logic hit_sign;
        logic [Way_Width-1 : 0] alloc_way;
    } cache_hit_status;
    
    cache_line_t cache[Num_Cache_Set][Num_Cache_Way];
    cache_hit_status status;
    
    // LRU 跟踪（简化版，用于替换策略）
    int lru_counter[Num_Cache_Set][Num_Cache_Way];
    int lru_global;
    
    // 统计信息
    int hit_count;
    int miss_count;
    int writeback_count;
    
    // UVM 端口
    uvm_blocking_get_port #(cpu_transaction) cpu_req_port;
    uvm_analysis_port #(cpu_transaction) cpu_resp_port;
    uvm_blocking_get_port #(mem_transaction) mem_resp_port;
    uvm_analysis_port #(mem_transaction) mem_req_port;
    
    // // 内部事务队列
    // typedef struct {
    //     cpu_transaction req;
    //     int set_index;
    //     int way_index;
    //     int word_offset;
    //     bit hit;
    //     cache_line_t original_line;
    // } pending_req_t;
    
    // pending_req_t pending_req;
    // bit has_pending_req;
    
    // 函数声明
    extern function new(string name, uvm_component parent);
    extern function void build_phase(uvm_phase phase);
    extern function void start_of_simulation_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern function void reset_cache();
    extern function void parse_address(bit [DataAddrBus-1:0] addr, 
                                        output logic [Tag_Width-1:0] tag,
                                        output logic [Index_Width-1:0] index,
                                        output logic [Offset_Width-1:0] offset);
    extern function int check_hit(logic [Tag_Width-1:0] tag, 
                                  logic [Index_Width-1:0] index,
                                  output int way_hit);
    extern function int select_victim(logic [Index_Width-1:0] index);
    extern function void update_lru(logic [Index_Width-1:0] index, int way_accessed);
    extern task write_back_line(logic [Index_Width-1:0] index, int way);
    extern task fetch_line(logic [Index_Width-1:0] index, int way, 
                           logic [Tag_Width-1:0] tag);
    extern function logic [DataWidth-1:0] read_word_from_cache(
        logic [Index_Width-1:0] index, int way, int word_offset);
    extern function void write_word_to_cache(
        logic [Index_Width-1:0] index, int way, int word_offset,
        logic [DataWidth-1:0] data, logic [Bytes_Per_Word-1:0] byte_enable);
    extern task process_cpu_request(cpu_transaction req);
    extern function void report_stats();
    extern function void report_phase(uvm_phase phase);
    
    `uvm_component_utils(d_cache_model)
    
endclass

// 构造函数
function d_cache_model::new(string name = "d_cache_model",
                            uvm_component parent = null
    );
    super.new(name, parent);
    if (parent == null) begin
        `fatal("This component's parent can not be null!!")
    end
    hit_count = 0;
    miss_count = 0;
    writeback_count = 0;
    //has_pending_req = 0;
    lru_global = 0;
endfunction

// Build Phase
function void d_cache_model::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cpu_req_port = new("cpu_req_port", this);
    cpu_resp_port = new("cpu_resp_port", this);
    mem_resp_port = new("mem_resp_port", this);
    mem_req_port = new("mem_req_port", this);
endfunction

// Start of Simulation
function void d_cache_model::start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    reset_cache();
//    `uvm_info(get_type_name(), $sformatf("D-Cache Model initialized: %0d sets, %0d ways, %0dB block, %0d-bit data",
//                Num_Cache_Set, Num_Cache_Way, Cache_Block_Size, DataWidth), UVM_MEDIUM)
    `info_med($sformatf("D-Cache Model initialized: %0d sets, %0d ways, %0dB block, %0d-bit data",
                Num_Cache_Set, Num_Cache_Way, Cache_Block_Size, DataWidth))
endfunction

// 复位缓存
function void d_cache_model::reset_cache();
    for (int i = 0; i < Num_Cache_Set; i++) begin
        for (int j = 0; j < Num_Cache_Way; j++) begin
            cache[i][j].valid = 1'b0;
            cache[i][j].dirty = 1'b0;
            cache[i][j].tag = '0;
            for (int k = 0; k < Words_Per_Block; k++) begin
                cache[i][j].data[k] = '0;
            end
            lru_counter[i][j] = 0;
        end
    end
    //has_pending_req = 0;
    //`uvm_info(get_type_name(), "Cache reset completed", UVM_DEBUG)
    `info_debug("Cache reset completed")
endfunction

// 解析地址
function void d_cache_model::parse_address(bit [DataAddrBus-1:0] addr,
                                           output logic [Tag_Width-1:0] tag,
                                           output logic [Index_Width-1:0] index,
                                           output logic [Offset_Width-1:0] offset);
    tag = addr[DataAddrBus-1 -: Tag_Width];
    index = addr[Offset_Width +: Index_Width];
    offset = addr[Offset_Width-1:0];
endfunction

// 检查命中
function void d_cache_model::check_hit(logic [Tag_Width-1:0] tag,
                                      logic [Index_Width-1:0] index,
                                      ref logic [Way_Width-1:0] way_hit,
                                      ref logic hit_sign);
    way_hit = 0;
    hit_sign = 0;
    for (int i = 0; i < Num_Cache_Way; i++) begin
        if (cache[index][i].valid && cache[index][i].tag == tag) begin
            if (hit_sign == 1) begin
                `fatal($sformatf("Cache model fatal error: Address (tag=0x%0h, index=%0d) is found in %0d ways. 
                                    This indicates a duplicate cache line, which violates cache coherency.", 
                                    tag, index, i))
            end
            else begin
                way_hit = i;
                hit_sign = 1;  
            end
        end
    end
endfunction

// 选择牺牲块（LRU策略）
function int d_cache_model::select_victim(logic [Index_Width-1:0] index);
    int victim_way = 0;
    int max_age = -1;
    
    // 优先选择无效块
    for (int i = 0; i < Num_Cache_Way; i++) begin
        if (!cache[index][i].valid) begin
            return i;
        end
    end
    
    // 全满时选择最久未使用的
    for (int i = 0; i < Num_Cache_Way; i++) begin
        if (lru_counter[index][i] > max_age) begin
            max_age = lru_counter[index][i];
            victim_way = i;
        end
    end
    
    return victim_way;
endfunction

// 更新LRU计数
function void d_cache_model::update_lru(logic [Index_Width-1:0] index, int way_accessed);
    lru_global++;
    for (int i = 0; i < Num_Cache_Way; i++) begin
        if (i == way_accessed) begin
            lru_counter[index][i] = lru_global;
        end
    end
endfunction

// 写回脏行到内存
task d_cache_model::write_back_line(logic [Index_Width-1:0] index, int way);
    mem_transaction mem_req;
    
    if (cache[index][way].dirty) begin
        mem_req = mem_transaction::type_id::create("mem_req");
        mem_req.addr = {cache[index][way].tag, index, {Offset_Width{1'b0}}};
        mem_req.wr_en = 1'b1;
        mem_req.wdata = new[Words_Per_Block];
        
        // 组装写回数据（连续的字）
        for (int i = 0; i < Words_Per_Block; i++) begin
            mem_req.wdata[i] = cache[index][way].data[i];
        end
        
        mem_req_port.write(mem_req);
        writeback_count++;
        
        `info_debug( $sformatf("Write back: index=%0d, way=%0d, addr=0x%0h",
                    index, way, mem_req.addr))
        
        // 等待内存响应
        mem_transaction mem_resp;
        mem_resp_port.get(mem_resp);
        
        // 写回后清除脏位
        cache[index][way].dirty = 1'b0;
    end
endtask

// 从内存读取缓存行
task d_cache_model::fetch_line(logic [Index_Width-1:0] index, int way,
                               logic [Tag_Width-1:0] tag);
    mem_transaction mem_req;
    
    mem_req = mem_transaction::type_id::create("mem_req");
    mem_req.addr = {tag, index, {Offset_Width{1'b0}}};
    mem_req.wr_en = 1'b0;
    mem_req_port.write(mem_req);
    
    `info_debug($sformatf("Fetch line: index=%0d, way=%0d, tag=0x%0h, addr=0x%0h",
                index, way, tag, mem_req.addr))
    
    // 等待内存响应
    mem_transaction mem_resp;
    mem_resp_port.get(mem_resp);
    
    // 更新缓存行
    cache[index][way].valid = 1'b1;
    cache[index][way].dirty = 1'b0;
    cache[index][way].tag = tag;
    for (int i = 0; i < Words_Per_Block; i++) begin
        cache[index][way].data[i] = mem_resp.rdata[i];
    end
    
    `info_debug(get_type_name(), $sformatf("Fetch completed: %0d words loaded", Words_Per_Block))
endtask

// 从缓存读字
function logic [DataWidth-1:0] d_cache_model::read_word_from_cache(
    logic [Index_Width-1:0] index, int way, int word_offset);
    return cache[index][way].data[word_offset];
endfunction

// 写字到缓存（支持字节掩码）
function void d_cache_model::write_word_to_cache(
    logic [Index_Width-1:0] index, int way, int word_offset,
    logic [DataWidth-1:0] data, logic [Bytes_Per_Word-1:0] byte_enable);
    
    logic [DataWidth-1:0] original_data;
    logic [DataWidth-1:0] new_data;
    
    original_data = cache[index][way].data[word_offset];
    new_data = original_data;
    
    // 按字节使能更新数据
    for (int i = 0; i < Bytes_Per_Word; i++) begin
        if (byte_enable[i]) begin
            new_data[i*8 +: 8] = data[i*8 +: 8];
        end
    end
    
    cache[index][way].data[word_offset] = new_data;
    cache[index][way].dirty = 1'b1;  // 标记为脏
    
    `info_debug($sformatf("Write to cache: index=%0d, way=%0d, offset=%0d, data=0x%0h",
                index, way, word_offset, new_data))
endfunction

// 处理CPU请求
task d_cache_model::process_cpu_request(cpu_transaction req);
    logic [Tag_Width-1:0] tag;
    logic [Index_Width-1:0] index;
    logic [Offset_Width-1:0] offset;
    int word_offset;
    int way_hit;
    bit is_hit;
    cpu_transaction resp;
    
    // 解析地址
    parse_address(req.addr, tag, index, offset);
    word_offset = offset / Bytes_Per_Word;  // 转换为字偏移
    
    // 检查命中
    is_hit = check_hit(tag, index, way_hit);
    
    if (is_hit) begin
        // 缓存命中
        hit_count++;
        `info_debug($sformatf("HIT: addr=0x%0h, tag=0x%0h, index=%0d, way=%0d",
                    req.addr, tag, index, way_hit))
        
        if (req.wr_en) begin
            // 写操作：更新缓存
            write_word_to_cache(index, way_hit, word_offset, req.wdata, req.byte_enable);
        end
        
        // 准备响应数据
        resp = cpu_transaction::type_id::create("resp");
        resp.addr = req.addr;
        resp.wr_en = req.wr_en;
        resp.ready = 1'b1;
        if (!req.wr_en) begin
            resp.rdata = read_word_from_cache(index, way_hit, word_offset);
        end
        
        // 更新LRU
        update_lru(index, way_hit);
    end
    else begin
        // 缓存未命中
        miss_count++;
        `info_med($sformatf("MISS: addr=0x%0h, tag=0x%0h, index=%0d",
                    req.addr, tag, index))
        
        // 选择牺牲块
        int victim_way = select_victim(index);
        
        // 如果牺牲块有效且脏，写回
        if (cache[index][victim_way].valid && cache[index][victim_way].dirty) begin
            write_back_line(index, victim_way);
        end
        
        // 从内存读取新行
        fetch_line(index, victim_way, tag);
        
        // 处理当前请求
        if (req.wr_en) begin
            write_word_to_cache(index, victim_way, word_offset, req.wdata, req.byte_enable);
        end
        
        // 准备响应数据
        resp = cpu_transaction::type_id::create("resp");
        resp.addr = req.addr;
        resp.wr_en = req.wr_en;
        resp.ready = 1'b1;
        if (!req.wr_en) begin
            resp.rdata = read_word_from_cache(index, victim_way, word_offset);
        end
        
        // 更新LRU
        update_lru(index, victim_way);
    end
    
    // 发送响应
    cpu_resp_port.write(resp);
endtask

// 主循环
task d_cache_model::run_phase(uvm_phase phase);
    // 处理CPU请求
    while (1) begin
        cpu_transaction req;
        cpu_req_port.get(req);
        process_cpu_request(req);
    end
endtask

// 报告统计信息
function void d_cache_model::report_stats();
    int total_access = hit_count + miss_count;
    real hit_rate = (total_access > 0) ? (hit_count * 100.0 / total_access) : 0;
    
    `info( 
        $sformatf("\n=== D-Cache Statistics ===\n"
                  "Total accesses: %0d\n"
                  "Hits: %0d\n"
                  "Misses: %0d\n"
                  "Hit rate: %.2f%%\n"
                  "Writebacks: %0d\n"
                  "==========================",
                  total_access, hit_count, miss_count, hit_rate, writeback_count))
endfunction

function void d_cache_model::report_phase(uvm_phase phase);
    super.report_phase(phase);
    report_stats();
endfunction
`endif