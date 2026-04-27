`include "uvm_macros.svh"
`include "vutils_macros.svh"
`include "define.svh"
import uvm_pkg::*;
import clk_rst_pkg::*;
import cache_pkg::*;
class mem_req_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(mem_req_scoreboard)
    
    `uvm_analysis_imp_decl(_ref_model)
    `uvm_analysis_imp_decl(_monitor)
    // 分析端口：接收来自 driver 的驱动数据
    uvm_analysis_imp_ref_model #(mem_req_transaction, mem_req_scoreboard) ref_model_export;
    // 分析端口：接收来自 monitor 的实际数据
    uvm_analysis_imp_monitor #(mem_req_transaction, mem_req_scoreboard) monitor_export;
    
    // // 使用队列存储期望数据
    uvm_tlm_analysis_fifo #(mem_req_transaction) expected_fifo;
    uvm_tlm_analysis_fifo #(mem_req_transaction) actual_fifo;
    // 统计信息
    int match_count = 0;
    int mismatch_count = 0;

    int expected_count = 0;
    int actual_count = 0;
    
    function new(string name = "mem_req_scoreboard", 
                    uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        ref_model_export = new("ref_model_export", this);
        monitor_export = new("monitor_export", this);
        expected_fifo = new("expected_fifo", this);
        actual_fifo = new("actual_fifo",this);
    endfunction
    
    extern function void write_ref_model(mem_req_transaction tr);
    extern function void write_monitor(mem_req_transaction tr);
    extern virtual task run_phase(uvm_phase phase);
    extern function void compare_transactions(
        mem_req_transaction expected_tr, 
        mem_req_transaction actual_tr
    );

    extern virtual function void report_phase(uvm_phase phase);
endclass


// 接收期望数据（来自 driver）
function void mem_req_scoreboard::write_ref_model(mem_req_transaction tr);
    if (!expected_fifo.try_put(tr)) begin
        `warn("Expected FIFO full")
    end
    else begin
        expected_count++;
        `info_high($sformatf("Expected transaction received: %s", 
                tr.convert2string()))
    end
endfunction
    

// 接收实际数据（来自 monitor）
function void mem_req_scoreboard::write_monitor(mem_req_transaction tr);
    if(!actual_fifo.try_put(tr)) begin
        `warn("Actual FIFO full")
    end

    else begin
        actual_count++;
        `info_high($sformatf("Actual transaction received: %s", 
                tr.convert2string()))
    end
endfunction
    
task mem_req_scoreboard::run_phase(uvm_phase phase);
    mem_req_transaction expected_tr;
    mem_req_transaction actual_tr;

    forever begin
        fork
            expected_fifo.get(expected_tr);
            actual_fifo.get(actual_tr);
        join

        compare_transactions(expected_tr, actual_tr);
    end
endtask


// 比对函数
function void mem_req_scoreboard::compare_transactions(
    mem_req_transaction expected_tr, 
    mem_req_transaction actual_tr);

    if (expected_tr.compare(actual_tr)) begin
        match_count++;
        `info_high($sformatf("MATCH: Expected vs Actual matches! (Total matches: %0d)", 
                  match_count))
    end 
    else begin
        mismatch_count++;
        `error($sformatf("MISMATCH: Expected:\n%s\nActual:\n%s", 
                   expected_tr.sprint(), actual_tr.sprint()))
    end
endfunction
    


// 报告阶段
function void mem_req_scoreboard::report_phase(uvm_phase phase);
    super.report_phase(phase);
    // `info($sformatf("Final Report:\n  Expected: %0d\n  Actual: %0d\n  Matches: %0d\n  Mismatches: %0d", 
    //           expected_count, actual_count, match_count, mismatch_count))

    $display("\n");
    $display("╔════════════════════════════════════════════════╗");
    $display("║  FINAL SUMMARY FOR        %20s ║", get_type_name());
    $display("╠════════════════════════════════════════════════╣");
    $display("║  Expected mem request  :  %20d ║", expected_count);
    $display("║   Actual mem request   :  %20d ║", actual_count);
    $display("║         Matches        :  %20d ║", match_count);
    $display("║        Mismatches      :  %20d ║", mismatch_count);
    $display("╠════════════════════════════════════════════════╣");
    if (mismatch_count == 0) begin
    $display("║                     PASS                       ║");
    end else begin
    $display("║             FAIL with %0d mismatches           ║", mismatch_count);
    end
    $display("╚════════════════════════════════════════════════╝");
    $display("\n");
endfunction