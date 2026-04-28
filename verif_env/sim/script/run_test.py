#!/usr/bin/env python3
"""
run_test.py - 运行单个 UVM 测试用例(基于现有 Makefile)
用法:
    ./run_test.py --test read_hit_test
    ./run_test.py --test read_hit_test --seed 12345 --no-wave
"""

import argparse
import subprocess
import sys
import os
import random
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="Run a single UVM test")
    parser.add_argument("--test", required=True, help="UVM test name (e.g., read_hit_test)")
    parser.add_argument("--seed", type=int, default=random.randint(1, 2**31-1),
                        help="Random seed (default: random)")
    parser.add_argument("--no-wave", action="store_true",
                        help="Disable waveform dumping to speed up simulation")
    parser.add_argument("--makefile-dir", default="..",
                        help="Directory containing Makefile (default: current dir)")
    parser.add_argument("--target", default="vcs_simulate",
                        help="Make target to run (default: vcs_simulate)")
    args = parser.parse_args()

    # 确保 Makefile 存在
    makefile_path = Path(args.makefile_dir) / "Makefile"
    if not makefile_path.exists():
        print(f"Error: Makefile not found in {args.makefile_dir}")
        sys.exit(1)

    # 构建 make 命令
    cmd = [
        "make", "-C", args.makefile_dir, args.target,
        f"TEST_NAME={args.test}",
        f"SEED={args.seed}",
        f"WAVE_ON={'0' if args.no_wave else '1'}"
    ]

    print(f"Running: {' '.join(cmd)}")
    # 执行 make，实时输出到终端
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            universal_newlines=True, bufsize=1)
    # 逐行实时打印输出
    for line in proc.stdout:
        print(line, end='')
    proc.wait()

    if proc.returncode == 0:
        print(f"\nPASS: {args.test} (seed={args.seed})")
        sys.exit(0)
    else:
        print(f"\nFAIL: {args.test} (seed={args.seed})")
        sys.exit(1)

if __name__ == "__main__":
    main()