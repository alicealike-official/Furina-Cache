// test_cachemem.cpp
#include "CacheMem.hpp"
#include <cassert>
#include <iostream>

using namespace dcache;

int main() {
    CacheMem mem;

    const int SET = 5, WAY = 2;
    const Tag TAG = 0x12345;

    // ---- T1: W2 填充整行（纯读未命中 → dirty=false） ----
    mem.w2_req.en    = true;
    mem.w2_req.index = SET;
    mem.w2_req.way   = WAY;
    mem.w2_req.tag   = TAG;
    mem.w2_req.dirty = false;
    for (int i = 0; i < WORDS_PER_BLOCK; ++i)
        mem.w2_req.line[i] = 0xAA000000u | static_cast<unsigned>(i);
    mem.tick();
    mem.w2_req = CacheMem::W2Req{};
    assert(mem.getValid(SET, WAY) == true);
    assert(mem.getDirty(SET, WAY) == false);
    assert(mem.getTag  (SET, WAY) == TAG);

    // ---- T2: R1 读 set=5 wordOff=3 ----
    mem.r1_req.en      = true;
    mem.r1_req.index   = SET;
    mem.r1_req.wordOff = 3;
    mem.tick();
    mem.r1_req = CacheMem::R1Req{};
    assert(mem.r1_resp.valid[WAY] == true);
    assert(mem.r1_resp.dirty[WAY] == false);
    assert(mem.r1_resp.tag  [WAY] == TAG);
    assert(mem.r1_resp.data [WAY] == 0xAA000003u);

    // ---- T3: W1 命中单字写 ----
    mem.w1_req.en      = true;
    mem.w1_req.index   = SET;
    mem.w1_req.way     = WAY;
    mem.w1_req.wordOff = 3;
    mem.w1_req.data    = 0xDEADBEEFu;
    mem.tick();
    mem.w1_req = CacheMem::W1Req{};
    assert(mem.getDirty(SET, WAY) == true);
    assert(mem.getWord (SET, WAY, 3) == 0xDEADBEEFu);
    // 同行其余字不变
    assert(mem.getWord (SET, WAY, 2) == 0xAA000002u);

    // ---- T4: R1 再读，应见新值 ----
    mem.r1_req.en      = true;
    mem.r1_req.index   = SET;
    mem.r1_req.wordOff = 3;
    mem.tick();
    mem.r1_req = CacheMem::R1Req{};
    assert(mem.r1_resp.data[WAY] == 0xDEADBEEFu);
    assert(mem.r1_resp.dirty[WAY] == true);

    // ---- T5: R2 victim 整行读 ----
    mem.r2_req.en    = true;
    mem.r2_req.index = SET;
    mem.r2_req.way   = WAY;
    mem.tick();
    mem.r2_req = CacheMem::R2Req{};
    assert(mem.r2_resp.line[3] == 0xDEADBEEFu);
    assert(mem.r2_resp.line[2] == 0xAA000002u);

    // ---- T6: Clear 清 valid ----
    mem.clr_req.en    = true;
    mem.clr_req.index = SET;
    mem.clr_req.way   = WAY;
    mem.tick();
    mem.clr_req = CacheMem::ClearReq{};
    assert(mem.getValid(SET, WAY) == false);
    assert(mem.getDirty(SET, WAY) == true);          // dirty 保留
    assert(mem.getWord (SET, WAY, 3) == 0xDEADBEEFu); // data 保留

    // ---- T7: R1 再读，valid 应为 0 ----
    mem.r1_req.en      = true;
    mem.r1_req.index   = SET;
    mem.r1_req.wordOff = 3;
    mem.tick();
    mem.r1_req = CacheMem::R1Req{};
    assert(mem.r1_resp.valid[WAY] == false);
    assert(mem.r1_resp.dirty[WAY] == true);

    std::cout << "[test_cachemem] all assertions passed\n";
    return 0;
}