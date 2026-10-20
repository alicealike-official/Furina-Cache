// test_wbb.cpp
// =============================================================
// WriteBackBuffer 黑盒测试
//
// 只依据《Cache 架构设计文档 v2》第 8 章（8.1 - 8.8）、12.5、13
// 以及 WriteBackBuffer 的公开接口编写，不依赖其内部实现。
//
// 覆盖点：
//   T1 基本生命周期：预留 -> push -> 发送 -> 释放
//   T2 满 / 预留失败（reserved 计入占用）
//   T3 同地址检查覆盖 reserved 与 valid
//   T4 发送轮询仲裁（文档 8.6）
//   T5 reserve(en) 的语义（en 与"有空槽"分离）
//   T6 释放与再次预留相差一拍（拍初状态语义）
//
// 编译（在 RefModel 目录下）：
//   make run-wbb
// 或：
//   g++ -std=c++17 -Wall -Wextra -ICache test/test_wbb.cpp -o build/test_wbb
// =============================================================

#include "WriteBackBuffer.hpp"

#include <cassert>
#include <iostream>

using namespace dcache;

// -------------------------------------------------------------
// 小工具
// -------------------------------------------------------------

// 造一行数据：base, base+1, ..., base+15
static Line makeLine(Word base) {
    Line l{};
    for (int i = 0; i < WORDS_PER_BLOCK; ++i)
        l[i] = base + static_cast<Word>(i);
    return l;
}

// 走一拍（所有状态更新都在 tick 的沿上），并做不变量自检
static void tick(WriteBackBuffer& w) {
    w.tick();
    assert(w.checkInvariants());   // 文档 §13 第三、六条
}

// 预留 + push 一个完整条目，返回槽位下标
static int reserve_and_push(WriteBackBuffer& w, Addr addr, Word base) {
    // 预留（文档 8.3 / 8.4）
    w.rsv_req = WriteBackBuffer::RsvReq{ true, addr };
    auto r = w.reserve(w.rsv_req.en);      // 带 en：ok 即"本次预留成功"
    assert(r.ok && r.slot >= 0);
    tick(w);
    w.rsv_req = WriteBackBuffer::RsvReq{};

    // push 整行（文档 8.3）
    w.push_req = WriteBackBuffer::PushReq{ true, r.slot, makeLine(base) };
    tick(w);
    w.push_req = WriteBackBuffer::PushReq{};

    return r.slot;
}

// -------------------------------------------------------------
// T1：基本生命周期
// -------------------------------------------------------------
static void test_basic_lifecycle() {
    std::cout << "[T1] 基本生命周期 预留->push->发送->释放 ... ";

    WriteBackBuffer w;
    const Addr A = 0x1000;                    // 块对齐
    const Line L = makeLine(0xCAFE0000u);

    // --- 预留 ---
    w.rsv_req = WriteBackBuffer::RsvReq{ true, A };
    auto r = w.reserve(w.rsv_req.en);
    assert(r.ok && r.slot == 0);
    tick(w);
    w.rsv_req = WriteBackBuffer::RsvReq{};

    // reserved 已可见；数据尚未 push，不能发送
    assert(w.hasSameAddr(A));
    assert(!w.full());
    assert(!w.sendReq().en);

    // --- push ---
    w.push_req = WriteBackBuffer::PushReq{ true, r.slot, L };
    tick(w);
    w.push_req = WriteBackBuffer::PushReq{};

    // 组合发送：id=槽位，addr/data 正确
    auto s = w.sendReq();
    assert(s.en);
    assert(s.id == 0);
    assert(s.addr == A);
    assert(s.data == L);

    // --- 握手发出 ---
    w.mem_wr_ready = true;
    tick(w);
    w.mem_wr_ready = false;
    assert(!w.sendReq().en);                  // 已 issued，不再被选中

    // --- 释放 ---
    w.mem_wr_resp = WriteBackBuffer::MemWrResp{ true, 0 };
    tick(w);
    w.mem_wr_resp = WriteBackBuffer::MemWrResp{};

    assert(!w.hasSameAddr(A));
    assert(!w.sendReq().en);
    assert(!w.full());

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T2：满与预留失败（reserved 计入占用）
// -------------------------------------------------------------
static void test_full_and_reserve_fail() {
    std::cout << "[T2] 满 / 预留失败 ... ";

    WriteBackBuffer w;

    // 把 4 个槽全部"预留但未 push"，验证 reserved 也计入满
    for (int i = 0; i < WBB_ENTRIES; ++i) {
        w.rsv_req = WriteBackBuffer::RsvReq{
            true, static_cast<Addr>(0x1000u * (i + 1)) };
        auto r = w.reserve(w.rsv_req.en);
        assert(r.ok);
        tick(w);
        w.rsv_req = WriteBackBuffer::RsvReq{};
    }

    assert(w.full());                         // 全 reserved，也算满
    assert(!w.reserve(true).ok);              // 预留失败
    assert(w.reserve(true).slot == -1);
    assert(!w.reserve(false).ok);             // en=false 永远不成功

    // 失败时不应改变状态
    w.rsv_req = WriteBackBuffer::RsvReq{ true, 0x9000 };
    tick(w);
    w.rsv_req = WriteBackBuffer::RsvReq{};
    assert(w.full());

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T3：同地址检查覆盖 reserved 与 valid
// -------------------------------------------------------------
static void test_same_addr() {
    std::cout << "[T3] 同地址检查 ... ";

    WriteBackBuffer w;
    const Addr A = 0x2000;

    assert(!w.hasSameAddr(A));

    // 预留后即可见（reserved）
    w.rsv_req = WriteBackBuffer::RsvReq{ true, A };
    auto r = w.reserve(true);
    assert(r.ok);
    tick(w);
    w.rsv_req = WriteBackBuffer::RsvReq{};

    assert(w.hasSameAddr(A));
    assert(w.hasSameAddr(toBlockAddr(A + 4)));   // 同一行的字地址，归一后仍命中
    assert(!w.hasSameAddr(A + BLOCK_SIZE));      // 下一行不算

    // push 后仍可见（valid）
    w.push_req = WriteBackBuffer::PushReq{ true, r.slot, makeLine(0xAB) };
    tick(w);
    w.push_req = WriteBackBuffer::PushReq{};
    assert(w.hasSameAddr(A));

    // 发出并释放后消失
    w.mem_wr_ready = true;
    tick(w);
    w.mem_wr_ready = false;

    w.mem_wr_resp = WriteBackBuffer::MemWrResp{ true, static_cast<BusId>(r.slot) };
    tick(w);
    w.mem_wr_resp = WriteBackBuffer::MemWrResp{};
    assert(!w.hasSameAddr(A));

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T4：发送轮询仲裁（文档 8.6）
// -------------------------------------------------------------
static void test_round_robin() {
    std::cout << "[T4] 发送轮询 ... ";

    WriteBackBuffer w;
    for (int i = 0; i < 3; ++i)
        reserve_and_push(w, static_cast<Addr>(0x3000u + BLOCK_SIZE * i),
                         0x300u + static_cast<Word>(i));

    // 轮询指针从 0 开始，应依次选中 0、1、2
    for (int expect = 0; expect < 3; ++expect) {
        auto s = w.sendReq();
        assert(s.en);
        assert(static_cast<int>(s.id) == expect);

        w.mem_wr_ready = true;
        tick(w);
        w.mem_wr_ready = false;
    }
    assert(!w.sendReq().en);                  // 全部已发出

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T5：reserve(en) 语义
// -------------------------------------------------------------
static void test_reserve_en_overload() {
    std::cout << "[T5] reserve(en) 语义 ... ";

    WriteBackBuffer w;

    // en=false：不探测、不成功
    auto r0 = w.reserve(false);
    assert(!r0.ok && r0.slot == -1);

    // 无参版本只反映"有空槽"，与 en 无关
    auto r1 = w.reserve();
    assert(r1.ok && r1.slot == 0);

    // 带 en 的版本：en=true 才表示本次预留成功
    auto r2 = w.reserve(true);
    assert(r2.ok && r2.slot == 0);

    // 没有布置 rsv_req，tick 不产生任何预留
    tick(w);
    assert(!w.hasSameAddr(0x1000));
    assert(w.reserve(true).ok);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T6：释放与再次预留相差一拍
// -------------------------------------------------------------
static void test_release_latency() {
    std::cout << "[T6] 释放/再预留差一拍 ... ";

    WriteBackBuffer w;
    for (int i = 0; i < WBB_ENTRIES; ++i)
        reserve_and_push(w, static_cast<Addr>(0x1000u * (i + 1)),
                         static_cast<Word>(i));
    assert(w.full());

    // 发出 slot0
    w.mem_wr_ready = true;
    tick(w);
    w.mem_wr_ready = false;

    // 释放发生在"本拍沿"，本拍组合探测仍看不到该槽
    w.mem_wr_resp = WriteBackBuffer::MemWrResp{ true, 0 };
    assert(!w.reserve(true).ok);
    tick(w);
    w.mem_wr_resp = WriteBackBuffer::MemWrResp{};

    // 下一拍才可见
    auto r = w.reserve(true);
    assert(r.ok && r.slot == 0);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
int main() {
    std::cout << "=== WriteBackBuffer black-box test ===\n";

    test_basic_lifecycle();
    test_full_and_reserve_fail();
    test_same_addr();
    test_round_robin();
    test_reserve_en_overload();
    test_release_latency();

    std::cout << "=== all WBB tests passed ===\n";
    return 0;
}
