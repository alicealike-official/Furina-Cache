#!/bin/bash
# run_test.sh - 运行单个 cache 测试用例

# 默认值
TEST_NAME=""
SEED=$RANDOM

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)      TEST_NAME="$2"; shift; shift ;;
        --seed)      SEED="$2"; shift; shift ;;
        --no-wave)   WAVE_ON=0; shift ;;
        *)           echo "Unknown option: $1"; exit 1 ;;
    esac
done