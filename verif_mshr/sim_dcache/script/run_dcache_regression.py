#!/usr/bin/env python3
"""执行公开IO功能case，所有真实UVM错误保留FAIL，不修改DUT或参考模型。"""
import argparse
from datetime import datetime
import json
from pathlib import Path
import re
from run_dcache_framework import execute, capture_inputs, SIM

TESTS = json.loads(Path(__file__).with_name('external_cases.json').read_text())


def assess(text, code):
    """检查实际报错、严重级别、完成标记和计数；不能仅靠simv退出码判断。"""
    reasons = []
    if code != 0: reasons.append(f'exit={code}')
    errors = re.findall(r'^UVM_(?:ERROR|FATAL)\b(?!\s*:).*', text, re.M)
    if errors: reasons.append('UVM errors')
    for level in ('WARNING', 'ERROR', 'FATAL'):
        if not re.search(rf'^UVM_{level}\s*:\s*0\s*$', text, re.M): reasons.append(f'{level} missing/nonzero')
    if '[DCACHE_TEST_PASS]' not in text or '[DCACHE_TEST_FAIL]' in text: reasons.append('completion not PASS')
    coverage = re.findall(r'^UVM_INFO .*?\[(DCACHE_\w*COVERAGE)\]\s*(.*)$', text, re.M)
    if not any(tag == 'DCACHE_SCENARIO_COVERAGE' for tag, _ in coverage): reasons.append('scenario completion missing')
    return reasons, errors, coverage


def main():
    """先冷编译，独立执行每个case/时钟/seed，即使有失败也继续并保存彩色汇总。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tests', nargs='+', choices=TESTS, default=[t for t in TESTS if t!='dcache_long_run_test'])
    parser.add_argument('--periods', nargs='+', type=int, default=[10,4])
    parser.add_argument('--seeds', nargs='+', type=int, default=[1,2,3])
    args = parser.parse_args()
    folder = SIM / 'work/regression' / datetime.now().strftime('run_%Y%m%d_%H%M%S')
    folder.mkdir(parents=True)
    print('BUILD: DCache public-IO regression', flush=True)
    code = execute(['make','generate'], folder/'generate.stdout.log')
    if code == 0: code = execute(['make','vcs_compile',f'VCS_COMP_LOG={folder / "compile.log"}'], folder/'compile.stdout.log')
    hashes = capture_inputs()
    (folder/'inputs.json').write_text(json.dumps(hashes,indent=4)+'\n')
    results = []
    for test in args.tests:
        for period in args.periods:
            for seed in (args.seeds if (test in ('dcache_random_test','dcache_long_run_test','dcache_memory_combinations_test','dcache_read_during_write_test') or test.startswith('dcache_random_')) else [1]):
                tag = f'{test}_p{period}_s{seed}'
                log = folder/(tag+'.log')
                wave = folder/(tag+'.fsdb')
                row = dict(test=test,period_ns=period,seed=seed,status='NOT RUN',reasons=['build failed'],errors=[],coverage=[],log=str(log),wave=str(wave))
                if code == 0:
                    command=['make','run',f'TEST_NAME={test}',f'SIM_ARGS=+CLOCK_PERIOD_NS={period} +ntb_random_seed={seed} +UVM_MAX_QUIT_COUNT=5,NO',f'VCS_SIM_LOG={log}',f'WAVEFORM={wave}',f'DUMP_TCL={folder / (tag+".tcl")}']
                    ret=execute(command,folder/(tag+'.stdout.log'))
                    reasons,errors,coverage=assess(log.read_text(errors='replace') if log.exists() else '',ret)
                    if not wave.exists() or not wave.stat().st_size: reasons.append('wave missing')
                    if capture_inputs()!=hashes: reasons.append('source changed')
                    row.update(status='FAIL' if reasons else 'PASS',reasons=reasons,errors=errors[:8],coverage=coverage,command=command)
                results.append(row)
                print(f"\033[1;{'32' if row['status']=='PASS' else '31'}m{row['status']}\033[0m {tag}",flush=True)
                (folder/'summary.json').write_text(json.dumps(dict(build_exit=code,results=results,complete=False),indent=4)+'\n')
    lines=['# DCache external IO regression','','| Test | ns | seed | Result | Log | Wave |','| --- | --- | --- | --- | --- | --- |']
    print('\nDCACHE REGRESSION REPORT')
    for row in results:
        lines.append(f"| {row['test']} | {row['period_ns']} | {row['seed']} | {row['status']} | [log]({Path(row['log']).name}) | [FSDB]({Path(row['wave']).name}) |")
        print(f"{row['test']:<38} {row['period_ns']:>2}ns seed={row['seed']} \033[1;{'32' if row['status']=='PASS' else '31'}m{row['status']}\033[0m")
        if row['errors']: print('  '+row['errors'][0])
    passed=sum(row['status']=='PASS' for row in results)
    print(f'PASS {passed}/{len(results)} Report: {folder / "summary.md"}')
    (folder/'summary.md').write_text('\n'.join(lines)+f'\n\nPASS {passed}/{len(results)}\n')
    (folder/'summary.json').write_text(json.dumps(dict(build_exit=code,results=results,complete=True),indent=4)+'\n')
    return 0 if passed==len(results) else 1


if __name__=='__main__':
    raise SystemExit(main())
