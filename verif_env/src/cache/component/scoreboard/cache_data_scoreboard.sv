`include "uvm_macros.svh"
`include "vutils_macros.svh"
`include "define.svh"
import uvm_pkg::*;
import clk_rst_pkg::*;
import cache_pkg::*;
class cache_data_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(cache_data_scoreboard)

    virtual cache_interface cache_vif;
    virtual cache_debug_interface cache_dbg_vif;    // 根据你的真实参数填
    d_cache_model d_cache_mdl;       


    // 统计计数器
    protected int total_compares = 0;      // 总比较次数（每次触发 compare 计1）
    protected int total_errors = 0;        // 总错误个数（每个mismatch计1）
    
    // 详细错误记录（可选项，防止内存爆炸）
    protected string error_log[$];         // 保存所有错误字符串
    protected int max_errors_to_log = 100; // 最多记录100条详细错误
    
    // 按错误类型分类统计
    protected int valid_errors = 0;
    protected int dirty_errors = 0;
    protected int tag_errors = 0;
    protected int data_errors = 0;
    protected int fifo_ptr_errors = 0;

    function new(string name = "cache_data_scoreboard", 
                    uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern function void compare_cache_state();
    extern virtual function void report_phase(uvm_phase phase);
endclass

function void cache_data_scoreboard::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual cache_debug_interface)::get(this, "", "cache_dbg_vif", cache_dbg_vif))
        `fatal("Debug interface not found")
    if (!uvm_config_db#(virtual cache_interface)::get(this, "", "cache_vif", cache_vif))
        `fatal("cache interface not found")

    // d_cache_mdl = d_cache_model::type_id::create("d_cache_mdl", this);
    if (!uvm_config_db#(d_cache_model)::get(this, "", "d_cache_mdl", d_cache_mdl))
        `fatal("d cache model not found")
endfunction


task cache_data_scoreboard::run_phase(uvm_phase phase);
    forever begin
        @(posedge cache_vif.clk iff cache_vif.cpu_resp_ready && cache_vif.cpu_resp_valid);
        @(negedge cache_vif.clk);
        -> cache_vif.begin_to_compare;
        compare_cache_state();
    end
endtask

// function void cache_data_scoreboard::compare_cache_state();
//     int local_errors = 0;

//     total_compares++;
//     for (int set = 0; set < `NUM_CACHE_SET; set++) begin
//         for (int way = 0; way < `NUM_CACHE_WAY; way++) begin
//             // valid
//             if (cache_dbg_vif.valid[way][set] != d_cache_mdl.cache[set][way].valid) begin
//                 local_errors++;
//                 valid_errors++;
//                 `error($sformatf("valid mismatch set%0d way%0d, cache:%0d vs mdl:%0d", 
//                         set, way, cache_dbg_vif.valid[way][set], d_cache_mdl.cache[set][way].valid))
//             end
//             // dirty
//             if (cache_dbg_vif.dirty[way][set] != d_cache_mdl.cache[set][way].dirty) begin
//                 `error($sformatf("dirty mismatch set%0d way%0d", set, way))
//                 local_errors++;
//                 dirty_errors++;
//             end
//             //tag
//             if (cache_dbg_vif.tag[way][set] != d_cache_mdl.cache[set][way].tag) begin
//                 `error($sformatf("tag mismatch set%0d way%0d", set, way))
//                 local_errors++;
//                 dirty_errors++;
//             end
//             //data
//             for (int w = 0; w < `WORDS_PER_BLOCK; w++) begin
//                 if (cache_dbg_vif.cache_data[way][set][w] != d_cache_mdl.cache[set][way].data[w]) begin
//                     `error($sformatf("data mismatch set%0d way%0d word%0d, cache:%0h vs mdl:%0h", 
//                             set, way, w, cache_dbg_vif.cache_data[way][set][w], d_cache_mdl.cache[set][way].data[w]))
//                 end
//                 local_errors++;
//                 data_errors++;
//             end
//         end
//         // fifo_ptr
//         if (cache_dbg_vif.alloc_way[set] != d_cache_mdl.fifo_ptr[set]) begin
//             `error($sformatf("fifo_ptr mismatch set%0d", set))
//             local_errors++;
//             fifo_ptr_errors++;
//         end
//     end

//     total_errors += local_errors;
// endfunction

function void cache_data_scoreboard::compare_cache_state();
    int local_errors = 0;
    string err_msg;
    
    total_compares++;   // 每次调用代表一次比较周期
    
    for (int set = 0; set < `NUM_CACHE_SET; set++) begin
        for (int way = 0; way < `NUM_CACHE_WAY; way++) begin
            // valid
            if (cache_dbg_vif.valid[way][set] != d_cache_mdl.cache[set][way].valid) begin
                local_errors++;
                valid_errors++;
                err_msg = $sformatf("valid mismatch set%0d way%0d, cache:%0d vs mdl:%0d", 
                        set, way, cache_dbg_vif.valid[way][set], d_cache_mdl.cache[set][way].valid);
                //`error(err_msg)
                if (error_log.size() < max_errors_to_log) error_log.push_back(err_msg);
            end
            // dirty
            if (cache_dbg_vif.dirty[way][set] != d_cache_mdl.cache[set][way].dirty) begin
                local_errors++;
                dirty_errors++;
                err_msg = $sformatf("dirty mismatch set%0d way%0d, cache:%0d vs mdl:%0d", set, way,
                        cache_dbg_vif.dirty[way][set], d_cache_mdl.cache[set][way].dirty);
                //`error(err_msg)
                if (error_log.size() < max_errors_to_log) error_log.push_back(err_msg);
            end
            // tag
            if (cache_dbg_vif.tag[way][set] != d_cache_mdl.cache[set][way].tag) begin
                local_errors++;
                tag_errors++;
                err_msg = $sformatf("tag mismatch set%0d way%0d, cache:%0h vs mdl:%0h", set, way,
                        cache_dbg_vif.tag[way][set], d_cache_mdl.cache[set][way].tag);
                //`error(err_msg)
                if (error_log.size() < max_errors_to_log) error_log.push_back(err_msg);
            end
            // data
            for (int w = 0; w < `WORDS_PER_BLOCK; w++) begin
                if (cache_dbg_vif.cache_data[way][set][w] != d_cache_mdl.cache[set][way].data[w]) begin
                    local_errors++;
                    data_errors++;
                    err_msg = $sformatf("data mismatch set%0d way%0d word%0d, cache:%0h vs mdl:%0h", 
                            set, way, w, cache_dbg_vif.cache_data[way][set][w], d_cache_mdl.cache[set][way].data[w]);
                    //`error(err_msg)
                    if (error_log.size() < max_errors_to_log) error_log.push_back(err_msg);
                end
            end
        end
        // fifo_ptr
        if (cache_dbg_vif.alloc_way[set] != d_cache_mdl.fifo_ptr[set]) begin
            local_errors++;
            fifo_ptr_errors++;
            err_msg = $sformatf("fifo_ptr mismatch set%0d, cache:%0d vs mdl:%0d", set,
                    cache_dbg_vif.alloc_way[set], d_cache_mdl.fifo_ptr[set]);
            `error(err_msg)
            if (error_log.size() < max_errors_to_log) error_log.push_back(err_msg);
        end
    end
    
    total_errors += local_errors;
endfunction

function void cache_data_scoreboard::report_phase(uvm_phase phase);
    super.report_phase(phase);
  
    // uvm_report_server svr = uvm_report_server::get_server();
    // int uvm_total_errors = svr.get_severity_count(UVM_ERROR);
    
    // ========== 1. 详细报告 ==========
    `info( "========== DETAILED SCOREBOARD REPORT ==========")
    if (error_log.size() > 0) begin
        `info($sformatf("First %0d mismatches (of total %0d errors):", 
                  error_log.size(), total_errors))
        foreach (error_log[i]) begin
            `info($sformatf("[%0d] %s", i+1, error_log[i]))
        end
        if (total_errors > error_log.size()) begin
            `info($sformatf("... and %0d more errors not shown (increase max_errors_to_log to see all)", 
                      total_errors - error_log.size()))
        end
    end else begin
        `info("No mismatches recorded.")
    end
    `info( "==================================================")
    
    // ========== 2. 最终报告（汇总统计） ==========
    $display("\n");
    $display("╔════════════════════════════════════════════════╗");
    $display("║  FINAL SUMMARY FOR       %20s ║", get_type_name());
    $display("╠════════════════════════════════════════════════╣");
    $display("║  Total compare cycles  :  %20d ║", total_compares);
    $display("║  Total mismatches      :  %20d ║", total_errors);
    if (total_compares > 0) begin
    $display("║  Mismatch per cycle    :  %20.2f ║", total_errors / (1.0 * total_compares));
    end
    $display("║    - Valid errors      :  %20d ║", valid_errors);
    $display("║    - Dirty errors      :  %20d ║", dirty_errors);
    $display("║    - Tag errors        :  %20d ║", tag_errors);
    $display("║    - Data errors       :  %20d ║", data_errors);
    $display("║    - FIFO ptr errors   :  %20d ║", fifo_ptr_errors);
    $display("╠════════════════════════════════════════════════╣");
    if (total_errors == 0) begin
    $display("║                     PASS                       ║");
    end else begin
    $display("║             FAIL with %0d mismatches           ║", total_errors);
    end
    $display("╚════════════════════════════════════════════════╝");
    $display("\n");
endfunction
