`include "uvm_macros.svh"
`include "vutils_macros.svh"
`include "define.svh"
import uvm_pkg::*;
import clk_rst_pkg::*;
import cache_pkg::*;
class cpu_stimulus_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(cpu_stimulus_scoreboard)
    
    `uvm_analysis_imp_decl(_driver)
    `uvm_analysis_imp_decl(_monitor)
    // 分析端口：接收来自 driver 的驱动数据
    uvm_analysis_imp_driver #(cpu_req_transaction, cpu_stimulus_scoreboard) driver_export;
    // 分析端口：接收来自 monitor 的实际数据
    uvm_analysis_imp_monitor #(cpu_req_transaction, cpu_stimulus_scoreboard) monitor_export;
    
    // // 使用队列存储期望数据
    uvm_tlm_analysis_fifo #(cpu_req_transaction) expected_fifo;
    uvm_tlm_analysis_fifo #(cpu_req_transaction) actual_fifo;
    // 统计信息
    int match_count;
    int mismatch_count;

    int expected_count;
    int actual_count;
    
    function new(string name = "cpu_stimulus_scoreboard", 
                    uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        driver_export = new("driver_export", this);
        monitor_export = new("monitor_export", this);
        expected_fifo = new("expected_fifo", this);
        actual_fifo = new("actual_fifo",this);
    endfunction
    
    extern function void write_driver(cpu_req_transaction tr);
    extern function void write_monitor(cpu_req_transaction tr);
    extern virtual task run_phase(uvm_phase phase);
    extern function void compare_transactions(
        cpu_req_transaction expected_tr, 
        cpu_req_transaction actual_tr
    );

    extern virtual function void extract_phase(uvm_phase phase);
endclass


// 接收期望数据（来自 driver）
function void cpu_stimulus_scoreboard::write_driver(cpu_req_transaction tr);
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
function void cpu_stimulus_scoreboard::write_monitor(cpu_req_transaction tr);
    if(!actual_fifo.try_put(tr)) begin
        `warn("Actual FIFO full")
    end

    else begin
        actual_count++;
        `info_high($sformatf("Actual transaction received: %s", 
                tr.convert2string()))
    end
endfunction
    
task cpu_stimulus_scoreboard::run_phase(uvm_phase phase);
    cpu_req_transaction expected_tr;
    cpu_req_transaction actual_tr;

    forever begin
        fork
            expected_fifo.get(expected_tr);
            actual_fifo.get(actual_tr);
        join

        compare_transactions(expected_tr, actual_tr);
    end
endtask


// 比对函数
function void cpu_stimulus_scoreboard::compare_transactions(
    cpu_req_transaction expected_tr, 
    cpu_req_transaction actual_tr);

    if (expected_tr.compare(actual_tr)) begin
        match_count++;
        `info_med($sformatf("MATCH: Expected vs Actual matches! (Total matches: %0d)", 
                  match_count))
    end 
    else begin
        mismatch_count++;
        `error($sformatf("MISMATCH: Expected:\n%s\nActual:\n%s", 
                   expected_tr.sprint(), actual_tr.sprint()))
    end
endfunction
    


// 报告阶段
function void cpu_stimulus_scoreboard::extract_phase(uvm_phase phase);
    super.extract_phase(phase);
    `info($sformatf("Final Report:\n  Expected: %0d\n  Actual: %0d\n  Matches: %0d\n  Mismatches: %0d", 
              expected_count, actual_count, match_count, mismatch_count))
endfunction