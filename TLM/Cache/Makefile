# 编译器
CXX = g++
CXXFLAGS = -std=c++17 -Wall
# SystemC 路径（根据你的安装位置修改）
SYSTEMC_HOME = /opt/systemc
SYSTEMC_INC = $(SYSTEMC_HOME)/include
SYSTEMC_LIB = $(SYSTEMC_HOME)/lib-linux64
# 目标
TARGET = cache_tlm_test
# 源文件
SRCS = cache_tlm.cpp cache_tlm_test.cpp simplememory.cpp
# 编译规则
$(TARGET): $(SRCS) cache_tlm.h
	$(CXX) $(CXXFLAGS) -I$(SYSTEMC_INC) -c cache_tlm.cpp -o build/cache_tlm.o
	$(CXX) $(CXXFLAGS) -I$(SYSTEMC_INC) -c simplememory.cpp -o build/simplememory.o
	$(CXX) $(CXXFLAGS) -I$(SYSTEMC_INC) -c cache_tlm_test.cpp -o build/cache_tlm_test.o
	$(CXX) $(CXXFLAGS) build/cache_tlm.o build/cache_tlm_test.o -L$(SYSTEMC_LIB) -lsystemc -o $(TARGET)
run: $(TARGET)
	./$(TARGET)
clean:
	rm -f build/*.o $(TARGET)
.PHONY: run clean