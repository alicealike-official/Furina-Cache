class mshr_monitor extends uvm_monitor;
    virtual mshr_interface vif;
    uvm_analysis_port #(mshr_sample) monitor_port;

    `uvm_component_utils(mshr_monitor)

    function new(string name = "mshr_monitor",
        uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        monitor_port = new("monitor_port", this);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
endclass

function void mshr_monitor::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(virtual mshr_interface)::get(this, "", "mshr_vif", vif) || vif == null) begin
        `fatal("mshr_interface not found", "MSHR_CONFIG")
    end
endfunction

task mshr_monitor::run_phase(uvm_phase phase);
    forever begin
        mshr_sample sample;

        @(vif.mon_cb);
        sample = mshr_sample::type_id::create("tr");
        // TB复位状态：predictor用它复位C++ MSHR，其他组件据此处理启动采样。
        sample.rst_n = vif.mon_cb.rst_n;

        // 分配一个新Entry并保存首个Slot。
        // 上游alloc输入：predictor送入C++ MSHR；scoreboard登记Entry及首Slot、原始字段和锁归属。
        sample.alloc_en = vif.mon_cb.alloc_en;
        sample.alloc_tag = vif.mon_cb.alloc_tag;
        sample.alloc_index = vif.mon_cb.alloc_index;
        sample.alloc_way = vif.mon_cb.alloc_way;
        sample.alloc_isWrite = vif.mon_cb.alloc_isWrite;
        sample.alloc_wData = vif.mon_cb.alloc_wData;
        sample.alloc_wordOff = vif.mon_cb.alloc_wordOff;
        sample.alloc_respId = vif.mon_cb.alloc_respId;
        sample.alloc_wbSlot = vif.mon_cb.alloc_wbSlot;
        sample.alloc_hasWb = vif.mon_cb.alloc_hasWb;

        // 向已有Entry追加一个Slot。
        // 上游merge输入：predictor更新C++ MSHR中对应Entry；scoreboard保存追加Slot的接受顺序。
        sample.merge_en = vif.mon_cb.merge_en;
        sample.merge_entry = vif.mon_cb.merge_entry;
        sample.merge_isWrite = vif.mon_cb.merge_isWrite;
        sample.merge_wData = vif.mon_cb.merge_wData;
        sample.merge_wordOff = vif.mon_cb.merge_wordOff;
        sample.merge_respId = vif.mon_cb.merge_respId;

        // 两路独立查询及可用资源。
        // q0/q1由上游驱动；m0/m1、hasFree/freeEntry由DUT输出，scoreboard按字段有效条件比较预测。
        sample.q0_tag = vif.mon_cb.q0_tag;
        sample.q0_index = vif.mon_cb.q0_index;
        sample.q1_tag = vif.mon_cb.q1_tag;
        sample.q1_index = vif.mon_cb.q1_index;
        sample.m0_hit = vif.mon_cb.m0_hit;
        sample.m0_entry = vif.mon_cb.m0_entry;
        sample.m0_mergeable = vif.mon_cb.m0_mergeable;
        sample.m0_slotFree = vif.mon_cb.m0_slotFree;
        sample.m0_freeSlot = vif.mon_cb.m0_freeSlot;
        sample.m1_hit = vif.mon_cb.m1_hit;
        sample.m1_entry = vif.mon_cb.m1_entry;
        sample.m1_mergeable = vif.mon_cb.m1_mergeable;
        sample.m1_slotFree = vif.mon_cb.m1_slotFree;
        sample.m1_freeSlot = vif.mon_cb.m1_freeSlot;
        sample.hasFree = vif.mon_cb.hasFree;
        sample.freeEntry = vif.mon_cb.freeEntry;

        // DUT发出的整行内存读请求。
        // valid/addr/id由DUT输出，ready由memory driver驱动；实际握手时内存代理保存C++稀疏内存行快照。
        sample.memReadReq_valid = vif.mon_cb.memReadReq_valid;
        sample.memReadReq_ready = vif.mon_cb.memReadReq_ready;
        sample.memReadReq_payload_addr = vif.mon_cb.memReadReq_payload_addr;
        sample.memReadReq_payload_id = vif.mon_cb.memReadReq_payload_id;

        // 内存代理返回的整行读响应。
        // valid/rData/id来自memory driver，ready来自DUT；predictor只将实际响应握手送入C++ MSHR。
        sample.memReadResp_valid = vif.mon_cb.memReadResp_valid;
        sample.memReadResp_ready = vif.mon_cb.memReadResp_ready;
        sample.memReadResp_payload_rData = vif.mon_cb.memReadResp_payload_rData;
        sample.memReadResp_payload_id = vif.mon_cb.memReadResp_payload_id;

        // 填充目标和合并后的整行数据。
        // fill字段来自DUT，fillReady来自接收代理；scoreboard检查目标、合并行、dirty及只接受一次。
        sample.fill_en = vif.mon_cb.fill_en;
        sample.fill_index = vif.mon_cb.fill_index;
        sample.fill_way = vif.mon_cb.fill_way;
        sample.fill_tag = vif.mon_cb.fill_tag;
        sample.fill_dirty = vif.mon_cb.fill_dirty;
        sample.fill_line = vif.mon_cb.fill_line;
        sample.fillReady = vif.mon_cb.fillReady;

        // 逐Slot重放及CPU响应身份。
        // replay字段来自DUT，ready来自接收代理；scoreboard按CPU ID及类型比较Slot历史读值与完成顺序。
        sample.replay_valid = vif.mon_cb.replay_valid;
        sample.replay_ready = vif.mon_cb.replay_ready;
        sample.replay_payload_rData = vif.mon_cb.replay_payload_rData;
        sample.replay_payload_id = vif.mon_cb.replay_payload_id;
        sample.replay_payload_isWrite = vif.mon_cb.replay_payload_isWrite;

        // 所有set与way的占用锁。
        // lockMask由DUT输出；scoreboard用已接受alloc到最后replay的IO历史检查每个set/way锁位。
        sample.lockMask = vif.mon_cb.lockMask;

        // 每拍发布一个独立对象，同一快照交给内存代理、predictor和检查器，不在发布后改写。
        monitor_port.write(sample);
    end
endtask
