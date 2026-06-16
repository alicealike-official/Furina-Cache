CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -g

INCLUDES = -I$(SYSTEMC_HOME)/include \
			-ICache \
			-IMEM \
			-Itest

LIBS = -L$(SYSTEMC_HOME)/lib-linux64 \
		-lsystemc

SRCS = Cache/cache_tlm.cpp \
		MEM/sparse_memory.cpp \
		test/testbench.cpp

# build目录
BUILD_DIR = build
# 目标文件（放在build目录）
OBJS = $(patsubst %.cpp,$(BUILD_DIR)/%.o,$(SRCS))
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
	rm -rf $(BUILD_DIR)
# 运行测试
run: $(TARGET)
	./$(TARGET)
.PHONY: all clean run