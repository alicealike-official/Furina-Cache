// SparseMemory.hpp -- byte-addressed sparse backing storage, no simulation kernel.
#pragma once
#include "../Cache/params.hpp"
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <unordered_map>
#include <vector>

namespace dcache {

class SparseMemory {
public:
    explicit SparseMemory(std::size_t pageSize = 4096) : pageSize_(pageSize) {
        if (pageSize == 0 || (pageSize & (pageSize - 1)) != 0)
            throw std::invalid_argument("SparseMemory page size must be a positive power of two");
    }

    // Reset discards storage. This is not a cache flush operation.
    void reset() { pages_.clear(); }
    std::size_t allocatedPages() const { return pages_.size(); }
    std::size_t pageSize() const { return pageSize_; }

    void read(uint64_t addr, uint8_t* bytes, std::size_t size) const {
        checkRange(addr, bytes, size);
        while (size != 0) {
            const uint64_t base = addr & ~uint64_t(pageSize_ - 1);
            const std::size_t offset = static_cast<std::size_t>(addr - base);
            const std::size_t count = std::min(size, pageSize_ - offset);
            const auto page = pages_.find(base);
            if (page == pages_.end()) {
                std::fill_n(bytes, count, uint8_t(0));
            } else {
                std::copy_n(page->second.data() + offset, count, bytes);
            }
            bytes += count;
            size -= count;
            if (size != 0) addr += count;
        }
    }

    void write(uint64_t addr, const uint8_t* bytes, std::size_t size) {
        checkRange(addr, bytes, size);
        while (size != 0) {
            const uint64_t base = addr & ~uint64_t(pageSize_ - 1);
            const std::size_t offset = static_cast<std::size_t>(addr - base);
            const std::size_t count = std::min(size, pageSize_ - offset);
            auto result = pages_.try_emplace(base, pageSize_, uint8_t(0));
            std::copy_n(bytes, count, result.first->second.data() + offset);
            bytes += count;
            size -= count;
            if (size != 0) addr += count;
        }
    }

    // Lowest byte address corresponds to bits [7:0] of Line[0].
    Line readLine(Addr addr) const {
        checkLine(addr);
        std::array<uint8_t, BLOCK_SIZE> bytes{};
        read(addr, bytes.data(), bytes.size());
        Line line{};
        for (int w = 0; w < WORDS_PER_BLOCK; ++w)
            for (int b = 0; b < BYTE_WIDTH; ++b)
                line[w] |= Word(bytes[w * BYTE_WIDTH + b]) << (8 * b);
        return line;
    }

    void writeLine(Addr addr, const Line& line) {
        checkLine(addr);
        std::array<uint8_t, BLOCK_SIZE> bytes{};
        for (int w = 0; w < WORDS_PER_BLOCK; ++w)
            for (int b = 0; b < BYTE_WIDTH; ++b)
                bytes[w * BYTE_WIDTH + b] = uint8_t(line[w] >> (8 * b));
        write(addr, bytes.data(), bytes.size());
    }

private:
    static_assert(DATA_WIDTH == sizeof(Word) * 8, "Line word width must match Word");
    std::size_t pageSize_;
    std::unordered_map<uint64_t, std::vector<uint8_t>> pages_;

    static void checkRange(uint64_t addr, const void* bytes, std::size_t size) {
        if (size == 0) return;
        if (bytes == nullptr) throw std::invalid_argument("Null byte buffer");
        if (size - 1 > std::numeric_limits<uint64_t>::max() - addr)
            throw std::out_of_range("Memory address range overflows");
    }

    static void checkLine(Addr addr) {
        if ((addr % BLOCK_SIZE) != 0)
            throw std::invalid_argument("Line access must be block aligned");
        if (uint64_t(addr) + BLOCK_SIZE - 1 > std::numeric_limits<Addr>::max())
            throw std::out_of_range("Line exceeds Addr range");
    }
};

} // namespace dcache
