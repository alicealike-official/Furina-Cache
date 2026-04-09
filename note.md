控制信号(no register)
alloc_enable
    读状态下：IDLE && ~hit_sign
    写状态下：IDLE && ~hit_sign
mem_req
    读状态下：replace_dirty || wb_done || (MISS_WAIT)
    写状态下：IDLE && ~hit_sign
mem_wr_en
    读状态下: replace_dirty
    写状态下：IDLE && ~hit_sign
mem_addr
    读状态下：
        replace_dirty           --> mem_addr = {index[alloc_way][index_in], tag[alloc_way][index_in], Offset_Width{1'b0}};
        wb_done                 --> mem_addr = cpu_req_addr;
        (MISS_WAIT)             --> mem_addr = cpu_req_addr;
    写状态下：
        IDLE && ~hit_sign       --> mem_addr = cpu_req_addr;
mem_wdata
    读状态下：-->0;
    写状态下：
        IDLE && ~hit_sign       --> mem_wdata = cpu_wdata;
hit_sign
hit_way


ready
    读状态下：(IDLE && hit_sign) || miss_done
    写状态下：(IDLE && hit_sign) || miss_done
wb_done
    读状态下:(WB && mem_resp)
    写状态下: 0
miss_done
    读状态下：(MISS_WAIT && mem_resp)
    写状态下：(MISS_WAIT && mem_resp)
replace_dirty
    读状态下: (DIRTY_CHECK && dirty)
    写状态下: 0

状态跳转
IDLE --> IDLE
    读状态下
        hit_sign
    写状态下
        hit_sign

IDLE --> DIRTY_CHECK
    读状态下
        ~hit_sign
IDLE --> MISS_WAIT
    读状态下
        无
    写状态下
        ~hit_sign
DIRTY_CHECK --> WB
    dirty = 1
DIRTY_CHECK --> MISS_WAIT
    dirty = 0
WB --> MISS_WAIT
    mem_resp
WB --> WB
    ~mem_resp
MISS_WAIT --> MISS_WAIT
    ~mem_resp
MISS_WAIT --> IDLE
    mem_resp



数据时序

写命中：
    IDLE下一个上升沿：写入加更改dirty
读未命中：
    MISS_WAIT下一个上升沿： 写入mem_rdata
写未命中：
    MISS_WAIT下一个上升沿： 写入mem_rdata   