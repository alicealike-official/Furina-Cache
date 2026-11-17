#include "SparseMemory.hpp"
#include <cassert>
#include <iostream>
#include <limits>

using namespace dcache;

template<class F> static void mustThrow(F action) {
    bool threw = false;
    try { action(); } catch (const std::exception&) { threw = true; }
    assert(threw);
}

int main() {
    mustThrow([] { SparseMemory bad(0); });
    mustThrow([] { SparseMemory bad(3); });
    SparseMemory mem(16), other(16);
    std::vector<uint8_t> data(70), result(70, 0xff);
    mem.read(13, result.data(), result.size());
    assert(result == std::vector<uint8_t>(70, 0));
    assert(mem.allocatedPages() == 0);
    for (std::size_t i = 0; i < data.size(); ++i) data[i] = uint8_t(i + 1);
    mem.write(13, data.data(), data.size());
    mem.read(13, result.data(), result.size());
    assert(result == data && mem.allocatedPages() == 6);
    other.read(13, result.data(), result.size());
    assert(result == std::vector<uint8_t>(70, 0));
    const uint8_t replacement[] = {0xa1, 0xb2, 0xc3};
    mem.write(15, replacement, 3);
    mem.read(13, result.data(), result.size());
    data[2] = 0xa1; data[3] = 0xb2; data[4] = 0xc3;
    assert(result == data);
    Line line{};
    for (int i = 0; i < WORDS_PER_BLOCK; ++i) line[i] = 0x01020304u + i;
    mem.writeLine(0x1000, line); // one line spans several small pages
    assert(mem.readLine(0x1000) == line);
    uint8_t bytes[4];
    mem.read(0x1000, bytes, 4);
    assert(bytes[0] == 4 && bytes[1] == 3 && bytes[2] == 2 && bytes[3] == 1);
    assert(other.readLine(0x1000) == Line{});
    mem.writeLine(0x1000, Line{});
    assert(mem.readLine(0x1000) == Line{});
    const uint64_t last = std::numeric_limits<uint64_t>::max();
    mem.write(last, replacement, 1);
    mem.read(last, bytes, 1);
    assert(bytes[0] == 0xa1);
    mustThrow([&] { mem.write(last, replacement, 2); });
    mustThrow([&] { mem.read(last, bytes, 2); });
    mustThrow([&] { mem.write(0, nullptr, 1); });
    mustThrow([&] { mem.readLine(1); });
    mem.write(0, nullptr, 0);
    mem.read(0, nullptr, 0);
    mem.reset();
    assert(mem.allocatedPages() == 0 && mem.readLine(0x1000) == Line{});
    std::cout << "SparseMemory checks passed\n";
}
