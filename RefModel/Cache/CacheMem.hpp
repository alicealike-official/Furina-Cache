// cachemem.hpp
#pragma once
#include "params.hpp"
#include <array>
#include <cstdint>
#include <iostream>
#include <iomanip>

namespace dcache {

// =============================================================
// Layer 1 : CacheMem 存储主体（2R2W + clear）
//
// 对应文档 5.2 - 5.6。
//
// 时序约定（松散时序）：
//   - 每拍分两步：
//       (1) 外部写各端口的 *_req 字段
//       (2) 调用 tick()，表示本拍时钟沿
//   - tick() 内：写端口在沿上生效；读端口采样地址并锁存到 *_resp
//   - tick() 返回后，r1_resp / r2_resp 即为本次采样的结果
//
// 端口模型（文档 5.5）：
//   物理上每个 bank 为 TDP，2R2W+clear 互不冲突。
//   本模型为确定性，tick() 内按
//      W2 -> W1 -> Clear -> R1 -> R2
//   串行化。若同拍同 bank 发生读写，读端口看到新值，
//   与文档 6.6 CPU 旁路后的语义一致。
//
// 本层明确不做（属于 Layer 2 / Layer 3）：
//   命中判断、Way Lock、victim 选择、端口冲突仲裁、
//   Stage2 冻结、"W1 被 W2 顶掉后保持请求" 等控制流。
// =============================================================
class CacheMem {
public:
    // ---------- 端口请求 / 响应 ----------

    // ----- R1端口，单word读 -----
    struct R1Req  {
        bool en      = false;
        int  index   = 0;   // 0 .. NUM_SETS-1
        int  wordOff = 0;   // 0 .. WORDS_PER_BLOCK-1
    };

    struct R1Resp {
        std::array<Tag,  NUM_WAYS> tag{};
        std::array<bool, NUM_WAYS> valid{};
        std::array<bool, NUM_WAYS> dirty{};
        std::array<Word, NUM_WAYS> data{};   // 各路上 wordOff 处的字
    };

    // ----- R2端口，整行读 -----
    struct R2Req  {
        bool en    = false;
        int  index = 0;
        int  way   = 0;
    };
    struct R2Resp {
        Line line{};
    };

    // ----- W1端口，word写 -----
    struct W1Req {
        bool en      = false;
        int  index   = 0;
        int  way     = 0;
        int  wordOff = 0;
        Word data    = 0;
    };

    // ----- W2端口，整行写 -----
    struct W2Req {
        bool en    = false;
        int  index = 0;
        int  way   = 0;
        Tag  tag   = 0;
        bool dirty = false;   // 由外部按 hasWriteSlot 决定
        Line line{};
    };

    // Clear : victim 清 valid（文档 5.4）
    struct ClearReq {
        bool en    = false;
        int  index = 0;
        int  way   = 0;
    };

    // ---------- 端口输入（由驱动方每拍布置） ----------
    R1Req    r1_req;
    R2Req    r2_req;
    W1Req    w1_req;
    W2Req    w2_req;
    ClearReq clr_req;

    // ---------- 端口输出（tick 后有效） ----------
    R1Resp   r1_resp;
    R2Resp   r2_resp;

    // ---------- 构造 / 复位（文档 5.6） ----------
    CacheMem() { reset(); }

    void reset() {
        for (int w = 0; w < NUM_WAYS; ++w)
            for (int o = 0; o < WORDS_PER_BLOCK; ++o)
                data_[w][o].fill(0);
        for (int w = 0; w < NUM_WAYS; ++w)
            for (int s = 0; s < NUM_SETS; ++s) {
                valid_[w][s] = false;
                dirty_[w][s] = false;
                tag_  [w][s] = 0;
            }
        r1_req  = R1Req{};
        r2_req  = R2Req{};
        w1_req  = W1Req{};
        w2_req  = W2Req{};
        clr_req = ClearReq{};
        r1_resp = R1Resp{};
        r2_resp = R2Resp{};
    }

    // ---------- 一拍 ----------
    void tick() {
        // ===== 1) 写端口在时钟沿生效 =====

        // W2：填充整行。tag / valid / dirty / 整行 data 一次写入。
        if (w2_req.en) {
            const int s = w2_req.index;
            const int w = w2_req.way;
            tag_  [w][s] = w2_req.tag;
            valid_[w][s] = true;
            dirty_[w][s] = w2_req.dirty;   // 文档 7.10：dirty 由外部按 hasWriteSlot 决定
            for (int o = 0; o < WORDS_PER_BLOCK; ++o)
                data_[w][o][s] = w2_req.line[o];
        }

        // W1：命中单字写。只写目标字 + 置 dirty（文档 5.4）。
        if (w1_req.en) {
            data_[w1_req.way][w1_req.wordOff][w1_req.index] = w1_req.data;
            dirty_[w1_req.way][w1_req.index] = true;
        }

        // Clear：只清 valid；不清 dirty、不清 data（文档 5.4）。
        if (clr_req.en) {
            valid_[clr_req.way][clr_req.index] = false;
        }

        // ===== 2) 读端口采样并锁存输出（同步读、一拍延迟） =====

        // R1：并行读同组所有路的 tag / valid / dirty 与指定 wordOff 的字。
        if (r1_req.en) {
            const int s = r1_req.index;
            const int o = r1_req.wordOff;
            for (int w = 0; w < NUM_WAYS; ++w) {
                r1_resp.tag  [w] = tag_  [w][s];
                r1_resp.valid[w] = valid_[w][s];
                r1_resp.dirty[w] = dirty_[w][s];
                r1_resp.data [w] = data_ [w][o][s];
            }
        }

        // R2：整行读指定路。
        if (r2_req.en) {
            const int s = r2_req.index;
            const int w = r2_req.way;
            for (int o = 0; o < WORDS_PER_BLOCK; ++o)
                r2_resp.line[o] = data_[w][o][s];
        }
    }

    // ---------- 观测 / 预置（调试、单测用；绕过端口） ----------
    bool getValid(int s, int w)         const { return valid_[w][s]; }
    bool getDirty(int s, int w)         const { return dirty_[w][s]; }
    Tag  getTag  (int s, int w)         const { return tag_  [w][s]; }
    Word getWord (int s, int w, int o)  const { return data_ [w][o][s]; }

    void pokeValid(int s, int w, bool v)         { valid_[w][s]    = v; }
    void pokeDirty(int s, int w, bool v)         { dirty_[w][s]    = v; }
    void pokeTag  (int s, int w, Tag t)          { tag_  [w][s]    = t; }
    void pokeWord (int s, int w, int o, Word d)  { data_ [w][o][s] = d; }

    void dump(std::ostream& os = std::cout) const {
        os << "=== CacheMem dump ===\n";
        for (int s = 0; s < NUM_SETS; ++s) {
            bool any = false;
            for (int w = 0; w < NUM_WAYS; ++w) if (valid_[w][s]) any = true;
            if (!any) continue;
            os << "set " << s << ":\n";
            for (int w = 0; w < NUM_WAYS; ++w) {
                if (!valid_[w][s]) continue;
                os << "  way" << w
                   << " tag=0x" << std::hex << tag_[w][s] << std::dec
                   << (dirty_[w][s] ? " D" : "  ") << " : ";
                for (int o = 0; o < WORDS_PER_BLOCK; ++o)
                    os << std::hex << std::setw(8) << std::setfill('0')
                       << data_[w][o][s] << " ";
                os << std::dec << "\n";
            }
        }
    }

private:
    bool     valid_[NUM_WAYS][NUM_SETS];
    bool     dirty_[NUM_WAYS][NUM_SETS];
    Tag      tag_  [NUM_WAYS][NUM_SETS];
    DataBank data_ [NUM_WAYS][WORDS_PER_BLOCK];
};

}