class wbb_sample extends uvm_sequence_item;
    logic rst_n;
    logic reserve_en;
    logic [ADDR_WIDTH-1:0] reserve_addr;
    logic reserveOk;
    logic [SLOT_WIDTH-1:0] reserveSlot;

    logic push_en;
    logic [SLOT_WIDTH-1:0] push_slot;
    logic [LINE_WIDTH-1:0] push_line;

    logic send_valid;
    logic send_ready;
    logic [ADDR_WIDTH-1:0] send_payload_addr;
    logic [LINE_WIDTH-1:0] send_payload_wData;
    logic [BUS_ID_WIDTH-1:0] send_payload_id;

    logic memWriteResp_valid;
    logic memWriteResp_ready;
    logic [BUS_ID_WIDTH-1:0] memWriteResp_payload_id;

    logic [ADDR_WIDTH-1:0] q0Addr;
    logic [ADDR_WIDTH-1:0] q1Addr;
    logic q0Same;
    logic q1Same;

    logic full;


    `uvm_object_utils(wbb_sample)

    function new(string name = "wbb_sample");
        super.new(name);
    endfunction

endclass
