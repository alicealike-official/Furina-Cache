class wbb_memory_store extends uvm_object;
    // Independent instances: actual writes from DUT, expected writes from WBB model.
    protected chandle actual_handle;
    protected chandle expected_handle;
    protected bit touched[int unsigned];

    `uvm_object_utils(wbb_memory_store)

    function new(string name = "wbb_memory_store");
        super.new(name);
    endfunction

    extern function void initialize(int page_size);
    extern function void write_actual(int unsigned addr, bit [LINE_WIDTH-1:0] data);
    extern function void write_expected(int unsigned addr, bit [LINE_WIDTH-1:0] data);
    extern function void compare_contents();
    extern function void close();

endclass

function void wbb_memory_store::initialize(int page_size);
    if (actual_handle != null || expected_handle != null) begin
        `fatal("Memory store already initialized")
    end
    if (!sparse_mem_create(page_size, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, actual_handle)) begin
        `fatal(wbb_dpi_last_error(), "MEM_DPI")
    end
    if (!sparse_mem_create(page_size, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, expected_handle)) begin
        `fatal(wbb_dpi_last_error(), "MEM_DPI")
    end
endfunction

function void wbb_memory_store::write_actual(int unsigned addr, bit [LINE_WIDTH-1:0] data);
    if (!sparse_mem_write_line(actual_handle, addr, data)) begin
        `fatal(wbb_dpi_last_error(), "MEM_DPI")
    end
    touched[addr] = 1;
endfunction

function void wbb_memory_store::write_expected(int unsigned addr, bit [LINE_WIDTH-1:0] data);
    if (!sparse_mem_write_line(expected_handle, addr, data)) begin
        `fatal(wbb_dpi_last_error(), "MEM_DPI")
    end
    touched[addr] = 1;
endfunction

function void wbb_memory_store::compare_contents();
    bit [LINE_WIDTH-1:0] actual;
    bit [LINE_WIDTH-1:0] expected;
    // Union of both write-address sets catches missing and stray writes.
    foreach (touched[addr]) begin
        if (!sparse_mem_read_line(actual_handle, addr, actual) ||
            !sparse_mem_read_line(expected_handle, addr, expected)) begin
            `fatal(wbb_dpi_last_error(), "MEM_DPI")
        end
        if (actual !== expected) begin
            `error($sformatf("Backing memory mismatch at 0x%h: expected=%h actual=%h",
                addr, expected, actual), "MEM_COMPARE")
        end
    end
endfunction

function void wbb_memory_store::close();
    if (actual_handle != null) begin
        if (!sparse_mem_destroy(actual_handle)) begin
            `error(wbb_dpi_last_error(), "MEM_DPI")
        end
        actual_handle = null;
    end
    if (expected_handle != null) begin
        if (!sparse_mem_destroy(expected_handle)) begin
            `error(wbb_dpi_last_error(), "MEM_DPI")
        end
        expected_handle = null;
    end
endfunction
