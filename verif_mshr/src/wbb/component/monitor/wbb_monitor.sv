class wbb_monitor extends uvm_monitor;
    virtual wbb_interface vif;
    uvm_analysis_port #(wbb_sample) monitor_port;
    `uvm_component_utils(wbb_monitor)

    function new(string name = "wbb_monitor",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        monitor_port = new("monitor_port", this);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
endclass

function void wbb_monitor::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", vif)) begin
        `fatal("wbb_interface not found")
    end
endfunction

task wbb_monitor::run_phase(uvm_phase phase);
    forever begin
        wbb_sample tr;
        @(vif.mon_cb);
        tr = wbb_sample::type_id::create("tr");
        tr.rst_n = vif.mon_cb.rst_n;
        tr.reserve_en = vif.mon_cb.reserve_en;
        tr.reserve_addr = vif.mon_cb.reserve_addr;
        tr.push_en = vif.mon_cb.push_en;
        tr.push_slot = vif.mon_cb.push_slot;
        tr.push_line = vif.mon_cb.push_line;
        tr.send_ready = vif.mon_cb.send_ready;
        tr.memWriteResp_valid = vif.mon_cb.memWriteResp_valid;
        tr.memWriteResp_payload_id = vif.mon_cb.memWriteResp_payload_id;
        tr.q0Addr = vif.mon_cb.q0Addr;
        tr.q1Addr = vif.mon_cb.q1Addr;
        tr.reserveOk = vif.mon_cb.reserveOk;
        tr.reserveSlot = vif.mon_cb.reserveSlot;
        tr.send_valid = vif.mon_cb.send_valid;
        tr.send_payload_addr = vif.mon_cb.send_payload_addr;
        tr.send_payload_wData = vif.mon_cb.send_payload_wData;
        tr.send_payload_id = vif.mon_cb.send_payload_id;
        tr.memWriteResp_ready = vif.mon_cb.memWriteResp_ready;
        tr.full = vif.mon_cb.full;
        tr.q0Same = vif.mon_cb.q0Same;
        tr.q1Same = vif.mon_cb.q1Same;
        monitor_port.write(tr);
    end
endtask
