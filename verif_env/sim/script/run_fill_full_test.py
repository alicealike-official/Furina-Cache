#!/usr/bin/env python3
# run_fill_full_test.py - 专门运行 cache_fill_full_test

import sys
import subprocess
from pathlib import Path

# 固定测试名
TEST_NAME = "cache_fill_full_test"

# 获取当前脚本所在目录
SCRIPT_DIR = Path(__file__).parent.resolve()
RUN_TEST_SCRIPT = SCRIPT_DIR / "run_test.py"

if __name__ == "__main__":
    # 构建调用命令，透传所有额外参数（如 --seed, --no-wave）
    cmd = [sys.executable, str(RUN_TEST_SCRIPT), "--test", TEST_NAME, "--no-wave"] + sys.argv[1:]
    sys.exit(subprocess.call(cmd))