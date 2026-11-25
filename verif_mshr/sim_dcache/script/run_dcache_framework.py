#!/usr/bin/env python3
"""先生成当前DUT再运行UVM框架；生成失败的组合明确记为NOT RUN。"""
from datetime import datetime
import json
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys

SIM = Path(__file__).resolve().parents[1]


def execute(command, path):
    """保存完整进程输出；超时记为失败，不把已有旧日志当作本轮结果。"""
    with path.open('w') as output:
        try:
            return subprocess.run(command, cwd=SIM, stdout=output, stderr=subprocess.STDOUT, timeout=600).returncode
        except subprocess.TimeoutExpired:
            return 124


def capture_inputs():
    """保存本轮实际使用的RTL、UVM与原C++模型版本，仅计算哈希不解析DUT实现。"""
    base = SIM.parent
    files = list((base / 'src/dcache').rglob('*.sv*'))
    files += list((base / 'src/common').rglob('*.sv*'))
    for module in ('mshr', 'wbb'):
        files += list((base / f'src/{module}').rglob('*.sv*'))
        files += [base / f'generated/{module}/{module}_params_pkg.sv', base / f'dpi/{module}_dpi.cpp', base / f'dpi/{module}_dpi.h']
    files += list((base / 'test/dcache').glob('*.sv'))
    files += list((base.parent / 'RefModel/Cache').rglob('*.hpp'))
    files += list((base.parent / 'RefModel/MEM').glob('*.hpp'))
    files += [base / 'dpi/dcache_dpi.cpp', base / 'tb/dcache_tb_top.sv',
              base / 'generated/dcache/DCache.v', SIM / 'Makefile', SIM / 'tb.f', SIM / 'dut.f']
    return {str(path.relative_to(base.parent)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(set(files)) if path.is_file()}


def main():
    """生成、编译通过才执行默认空态和smoke，两时钟结果分别留档并打印彩色汇总。"""
    folder = SIM / 'work/framework' / datetime.now().strftime('run_%Y%m%d_%H%M%S')
    folder.mkdir(parents=True)
    generate_code = execute(['make', 'generate'], folder / 'generate.stdout.log')
    (folder / 'generate.log').write_bytes((SIM.parent / 'generated/dcache/generate.log').read_bytes())
    compile_code = None
    if generate_code == 0:
        compile_code = execute(['make', 'vcs_compile', f'VCS_COMP_LOG={folder / "compile.log"}'], folder / 'compile.stdout.log')
    hashes = capture_inputs()
    (folder / 'inputs.json').write_text(json.dumps(hashes, indent=4) + '\n')
    results = []
    for test in ['dcache_base_test', 'dcache_smoke_test']:
        for period in [10, 4]:
            row = dict(test=test, period_ns=period, status='NOT RUN', reasons=['generation or compilation failed'])
            if generate_code == 0 and compile_code == 0:
                tag = f'{test}_p{period}'
                log = folder / f'{tag}.log'
                command = ['make', 'run', f'TEST_NAME={"" if test == "dcache_base_test" else test}',
                           f'SIM_ARGS=+CLOCK_PERIOD_NS={period} +ntb_random_seed=1', f'VCS_SIM_LOG={log}',
                           f'WAVEFORM={folder / (tag + ".fsdb")}', f'DUMP_TCL={folder / (tag + ".tcl")}']
                code = execute(command, folder / f'{tag}.stdout.log')
                text = log.read_text() if log.exists() else ''
                reasons = []
                if code != 0 or '[DCACHE_TEST_PASS]' not in text or '[DCACHE_TEST_FAIL]' in text:
                    reasons.append('process failed or success marker missing')
                if re.search(r'^UVM_(?:ERROR|FATAL)\b(?!\s*:)', text, re.M):
                    reasons.append('actual UVM error/fatal')
                for severity in ['WARNING', 'ERROR', 'FATAL']:
                    if not re.search(rf'^UVM_{severity}\s*:\s*0\s*$', text, re.M):
                        reasons.append(f'{severity} summary missing or nonzero')
                wave = folder / (tag + '.fsdb')
                if not wave.exists() or wave.stat().st_size == 0:
                    reasons.append('waveform missing or empty')
                if capture_inputs() != hashes:
                    reasons.append('input files changed during run')
                if re.search(r'^\s*(?:Error|Fatal)-\[', text, re.M):
                    reasons.append('simulator error')
                expected = (3, 2, 1) if test == 'dcache_smoke_test' else (0, 0, 0)
                counts = re.search(r'\[DCACHE_COUNTS\] cycles=(\d+) requests=(\d+) read_responses=(\d+) write_responses=(\d+)', text)
                if not counts or int(counts[1]) == 0 or tuple(map(int, counts.groups()[1:])) != expected:
                    reasons.append('event count mismatch')
                row.update(status='PASS' if not reasons else 'FAIL', reasons=reasons, command=command, log=str(log), wave=str(wave), exit_code=code)
            results.append(row)
    report = dict(generate_exit=generate_code, compile_exit=compile_code, results=results)
    (folder / 'summary.json').write_text(json.dumps(report, indent=4) + '\n')
    lines = ['# DCache framework', '', '| Test | Clock ns | Result | Log | Wave |', '| --- | --- | --- | --- | --- |']
    print('\nDCache UVM FRAMEWORK REPORT')
    for row in results:
        color = '32' if row['status'] == 'PASS' else '33' if row['status'] == 'NOT RUN' else '31'
        print(f"{row['test']:<24} {row['period_ns']:>2}ns  \033[1;{color}m{row['status']}\033[0m")
        log_link = f"[log]({Path(row['log']).name})" if row.get('log') else '-'
        wave_link = f"[FSDB]({Path(row['wave']).name})" if row.get('wave') else '-'
        lines.append(f"| {row['test']} | {row['period_ns']} | {row['status']} | {log_link} | {wave_link} |")
    (folder / 'summary.md').write_text('\n'.join(lines) + '\n')
    for row in results:
        if row['reasons']:
            print('  ' + '; '.join(row['reasons']))
            if row.get('log'):
                print('  Log:', row['log'])
    passed = sum(row['status'] == 'PASS' for row in results)
    print(f"TOTAL 4  PASS {passed}  FAIL {sum(row['status'] == 'FAIL' for row in results)}  NOT RUN {sum(row['status'] == 'NOT RUN' for row in results)}")
    print('Report:', folder / 'summary.md')
    return 0 if all(row['status'] == 'PASS' for row in results) else 1


if __name__ == '__main__':
    sys.exit(main())
