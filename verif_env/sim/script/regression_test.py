#!/usr/bin/env python3
"""
run_regression.py - 并行运行多个测试脚本（如 run_*_test.py）
用法:
    ./run_regression.py run_basic_test.py run_read_hit_test.py run_read_miss_test.py
    ./run_regression.py --jobs 4 run_*.py                     (shell 通配符展开)
    ./run_regression.py --command "python run_basic_test.py --seed 42" --command "python run_read_hit_test.py --no-wave"
"""

import argparse
import subprocess
import sys
import os
from pathlib import Path
from datetime import datetime
from concurrent.futures import ProcessPoolExecutor, as_completed
import random

def run_single_script(script_path, log_dir):
    """执行单个脚本，捕获输出到日志文件，返回 (script_name, returncode, log_file_path)"""
    script_name = Path(script_path).name
    log_file = log_dir / f"{script_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{random.randint(1000,9999)}.log"
    
    with open(log_file, 'w') as f:
        f.write(f"Running: {script_path}\n")
        f.write(f"Started at: {datetime.now()}\n")
        f.write("-" * 80 + "\n")
        # 执行脚本，捕获输出
        proc = subprocess.run([sys.executable, script_path], stdout=f, stderr=subprocess.STDOUT)
        f.write("-" * 80 + "\n")
        f.write(f"Finished at: {datetime.now()}\n")
        f.write(f"Return code: {proc.returncode}\n")
    
    return script_name, proc.returncode, log_file

def main():
    parser = argparse.ArgumentParser(description="Run multiple test scripts in parallel")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--scripts", nargs="+", help="List of script files to run (e.g., run_*.py)")
    group.add_argument("--command", action="append", help="Explicit command to run (can be used multiple times)")
    parser.add_argument("--jobs", type=int, default=1, help="Number of parallel jobs (default: 1)")
    parser.add_argument("--log-dir", default="regression_logs", help="Directory to store per-script logs")
    args = parser.parse_args()

    # 收集要运行的命令列表（每个命令是一个字符串或脚本路径）
    commands = []
    if args.scripts:
        # 每个脚本用 "python script.py" 方式执行
        for script in args.scripts:
            if not os.path.exists(script):
                print(f"Warning: script {script} not found, skipping")
                continue
            commands.append((script, sys.executable, script))
    elif args.command:
        for cmd in args.command:
            commands.append((cmd, cmd, None))  # (display_name, full_command, script_path)

    if not commands:
        print("No valid scripts or commands to run.")
        sys.exit(1)

    log_dir = Path(args.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)

    print(f"Regression started at {datetime.now()}")
    print(f"Total tasks: {len(commands)}")
    print(f"Parallel jobs: {args.jobs}")
    print("-" * 60)

    results = {}
    with ProcessPoolExecutor(max_workers=args.jobs) as executor:
        futures = {}
        for name, cmd, script_path in commands:
            # 实际运行函数需要 (script_path, log_dir)
            future = executor.submit(run_single_script, script_path if script_path else cmd, log_dir)
            futures[future] = name

        for future in as_completed(futures):
            name = futures[future]
            try:
                script_name, retcode, log_file = future.result()
                results[name] = (retcode == 0, retcode, log_file)
                status = "PASS" if retcode == 0 else "FAIL"
                print(f"{status:4} {name} (exit={retcode}) -> {log_file.name}")
            except Exception as e:
                results[name] = (False, -1, None)
                print(f"FAIL  {name} (exception: {e})")

    print("-" * 60)
    passed = sum(1 for p, _, _ in results.values() if p)
    failed = len(results) - passed
    print(f"Summary: PASS={passed}  FAIL={failed}  Total={len(results)}")
    if failed > 0:
        sys.exit(1)

if __name__ == "__main__":
    main()