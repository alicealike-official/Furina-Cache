class cpu_req_sequence extends uvm_sequence #(cpu_req_transaction);
    `uvm_object_utils(cpu_req_sequence)
    
    int num_transactions = 10;

    function new(string name = "cpu_req_sequence");
        super.new();
    endfunction

    extern virtual task body();
endclass

task cpu_req_sequence::body();
    // localparam ADDR_WR_MISS = 32'h0000_0800;  // tag=1, index=0, offset=0
    // localparam ADDR_RD_MISS = 32'h0000_0840;  // tag=1, index=1, offset=0

    cpu_req_transaction tr;


    //-------------------------------------------------
    // 1. 写未命中（Write Miss）
    //    地址从未被访问过，必然 miss
    //-------------------------------------------------
    // `uvm_do_with(tr, {
    //     cpu_req_addr == ADDR_WR_MISS;
    //     cpu_wr_en    == 1'b1;
    //     cpu_wdata    == 32'hA5A5_A5A5;
    // })

    // //-------------------------------------------------
    // // 2. 写命中（Write Hit）
    // //    同一地址再次写，此时该行已在 Cache 中且有效
    // //-------------------------------------------------
    // `uvm_do_with(tr, {
    //     cpu_req_addr == ADDR_WR_MISS;
    //     cpu_wr_en    == 1'b1;
    //     cpu_wdata    == 32'h5A5A_5A5A;
    // })

    //     //-------------------------------------------------
    // // 2. 写命中（Write Hit）
    // //    同一地址再次写，此时该行已在 Cache 中且有效
    // //-------------------------------------------------
    // `uvm_do_with(tr, {
    //     cpu_req_addr == ADDR_WR_MISS;
    //     cpu_wr_en    == 1'b1;
    //     cpu_wdata    == 32'h5A5A_5A5A;
    // })

    // //-------------------------------------------------
    // // 3. 读命中（Read Hit）
    // //    读同一地址，命中
    // //-------------------------------------------------
    // `uvm_do_with(tr, {
    //     cpu_req_addr == ADDR_WR_MISS;
    //     cpu_wr_en    == 1'b0;
    // })

    // //-------------------------------------------------
    // // 3. 读命中（Read Hit）
    // //    读同一地址，命中
    // //-------------------------------------------------
    // `uvm_do_with(tr, {
    //     cpu_req_addr == ADDR_WR_MISS;
    //     cpu_wr_en    == 1'b0;
    // })

    // //-------------------------------------------------
    // // 4. 读未命中（Read Miss）
    // //    读一个从未访问过的 index，必然 miss
    // //-------------------------------------------------
    // `uvm_do_with(tr, {
    //     cpu_req_addr == ADDR_RD_MISS;
    //     cpu_wr_en    == 1'b0;
    // })

    for (int i = 0; i < num_transactions; i++) begin

        `uvm_do_with(tr, {
            cpu_req_valid == 1;
            cpu_req_addr < 10000;
        })
    end
endtask
