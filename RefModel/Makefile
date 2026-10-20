CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -g

INCLUDES = -I$(SYSTEMC_HOME)/include \
			-ICache \
			-IMEM \
			-Iutils \
			-Itest

LIBS = -L$(SYSTEMC_HOME)/lib-linux64 

SRCS = Cache/CacheMem.hpp \
		test/test_cachemem.cpp 

# build目录
BUILD_DIR = build
# 目标文件（放在build目录）
OBJS = $(patsubst %.cpp,$(BUILD_DIR)/%.o,$(filter %.cpp,$(SRCS)))
# 可执行文件（放在build目录）
TARGET = $(BUILD_DIR)/cache_test
# 默认目标
all: $(TARGET)
# 链接
$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LIBS)
# 编译规则（生成到build目录）
$(BUILD_DIR)/%.o: %.cpp
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@
# 清理
clean:
	rm -rf $(BUILD_DIR)/*
# 运行测试
run: $(TARGET)
	./$(TARGET)

# ---- WriteBackBuffer 单元测试（黑盒，不依赖 SystemC）----
WBB_TARGET = $(BUILD_DIR)/test_wbb
wbb: $(WBB_TARGET)
$(WBB_TARGET): $(BUILD_DIR)/test/test_wbb.o
	$(CXX) $(CXXFLAGS) -o $@ $^
run-wbb: wbb
	./$(WBB_TARGET)

# ---- MSHR 单元测试（黑盒，不依赖 SystemC）----
MSHR_TARGET = $(BUILD_DIR)/test_mshr
mshr: $(MSHR_TARGET)
$(MSHR_TARGET): $(BUILD_DIR)/test/test_mshr.o
	$(CXX) $(CXXFLAGS) -o $@ $^
run-mshr: mshr
	./$(MSHR_TARGET)

# ---- CacheTop 集成测试（黑盒，不依赖 SystemC）----
TOP_TARGET = $(BUILD_DIR)/test_cachetop
cachetop: $(TOP_TARGET)
$(TOP_TARGET): $(BUILD_DIR)/test/test_cachetop.o
	$(CXX) $(CXXFLAGS) -o $@ $^
run-cachetop: cachetop
	./$(TOP_TARGET)

# ---- CacheTop 完整测试（内部数据 + 状态）----
TOP_FULL_TARGET = $(BUILD_DIR)/test_cachetop_full
cachetop-full: $(TOP_FULL_TARGET)
$(TOP_FULL_TARGET): $(BUILD_DIR)/test/test_cachetop_full.o
	$(CXX) $(CXXFLAGS) -o $@ $^
run-cachetop-full: cachetop-full
	./$(TOP_FULL_TARGET)
.PHONY: all clean run wbb run-wbb mshr run-mshr cachetop run-cachetop cachetop-full run-cachetop-full