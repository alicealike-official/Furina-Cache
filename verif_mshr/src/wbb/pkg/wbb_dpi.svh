// C ABI returns 1 on success, 0 on failure. Parameters are checked at creation.
import "DPI-C" function string wbb_dpi_last_error();
import "DPI-C" function int wbb_ref_create(input int aw, dw, block_size, entries,
    slotw, busw, output chandle handle);
import "DPI-C" function int wbb_ref_reset(input chandle handle);
import "DPI-C" function int wbb_ref_destroy(input chandle handle);
import "DPI-C" function int wbb_ref_empty(input chandle handle, output int empty);
import "DPI-C" function int wbb_ref_step(input chandle handle,
    input int reserve_en, input int unsigned reserve_addr,
    input int push_en, input int unsigned push_slot,
    input bit [LINE_WIDTH-1:0] push_line, input int send_ready, resp_valid,
    input int unsigned resp_id, q0, q1,
    output int reserve_ok, reserve_slot, full, q0_same, q1_same, send_valid,
    output int unsigned send_addr, output bit [LINE_WIDTH-1:0] send_data,
    output int unsigned send_id);
import "DPI-C" function int sparse_mem_create(input int page_size, aw, dw, block_size,
    output chandle handle);
import "DPI-C" function int sparse_mem_reset(input chandle handle);
import "DPI-C" function int sparse_mem_destroy(input chandle handle);
import "DPI-C" function int sparse_mem_write_line(input chandle handle,
    input int unsigned addr, input bit [LINE_WIDTH-1:0] line);
import "DPI-C" function int sparse_mem_read_line(input chandle handle,
    input int unsigned addr, output bit [LINE_WIDTH-1:0] line);
