#!/usr/bin/env python3
"""独立性能矩阵：新仿真重放确定性请求，保留完整正确性检查和原始结果。"""
import csv
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

from run_dcache_framework import capture_inputs

SIM = Path(__file__).resolve().parents[1]


def execute(command, output):
    """每次输出到独立文件；超时也保留现场，不读取历史成功结果。"""
    with output.open('w') as stream:
        try:
            return subprocess.run(command, cwd=SIM, stdout=stream,
                                  stderr=subprocess.STDOUT, timeout=600).returncode
        except subprocess.TimeoutExpired:
            return 124


def profiles():
    """27组主测量，另用两组4ns重放检查统计是否依赖写死的时间单位。"""
    plans = []

    def add(scenario, submission='stream', read=8, write=8, group=1, count=256, period=10):
        plans.append(dict(scenario=scenario, submission=submission, read=read, write=write,
                          group=group, count=count, period=period))

    for scenario in ('hit_read', 'hit_write', 'hit_mixed'):
        add(scenario, count=1024)
    for latency in (1, 8, 32, 128):
        for submission in ('serial', 'stream'):
            add('independent', submission, read=latency)
        for group in (1, 2, 4):
            add('merge', read=latency, group=group, count=512)
        add('dirty', write=latency)
    add('hit_mixed', count=1024, period=4)
    add('independent', read=32, period=4)
    return plans


def validate(log, code, plan, metrics):
    """检查运行完整性、真实时钟和计数；场景路径由sequence另行逐项检查。"""
    reasons = []
    if code != 0:
        reasons.append(f'exit={code}')
    for severity in ('WARNING', 'ERROR', 'FATAL'):
        if not re.search(rf'^UVM_{severity}\s*:\s*0\s*$', log, re.M):
            reasons.append(f'UVM {severity} nonzero/missing')
    for marker in ('DCACHE_TEST_PASS', 'DCACHE_SCENARIO_COVERAGE', 'DCACHE_PERF_RESULT'):
        if not re.search(rf'^UVM_INFO .*\[{marker}\]', log, re.M):
            reasons.append(f'{marker} missing')
    if re.search(r'^\s*(?:Error|Fatal)-\[|^UVM_(?:ERROR|FATAL)\b(?!\s*:)', log, re.M):
        reasons.append('simulator/UVM error')
    clock = re.search(r'configured_ns=([\d.]+) measured_ns=([\d.]+)', log)
    if not clock or any(abs(float(value)-plan['period']) > 0.001 for value in clock.groups()):
        reasons.append('measured clock mismatch')
    if metrics is None:
        reasons.append('metrics JSON missing/invalid')
        return reasons
    if metrics['requests'] != plan['count'] or metrics['responses'] != plan['count']:
        reasons.append('CPU count mismatch')
    if metrics['requests'] != metrics['hit_count']+metrics['alloc_count']+metrics['merge_count']:
        reasons.append('commit count mismatch')
    if metrics['presentation_cycles'] != metrics['requests']+metrics['cpu_stall_cycles']+metrics['source_idle_cycles']:
        reasons.append('presentation accounting mismatch')
    for direction in ('read', 'write'):
        if metrics[f'memory_{direction}_requests'] != metrics[f'memory_{direction}_acks']:
            reasons.append(f'memory {direction} not drained')
    return reasons


def write_reports(folder, rows, hashes):
    """保存逐组配置、命令和原始指标，并输出可直接阅读的彩色终端表。"""
    report = dict(inputs=hashes, results=rows)
    (folder / 'summary.json').write_text(json.dumps(report, indent=4)+'\n')
    fields = ['tag', 'status', 'scenario', 'submission', 'read', 'write', 'group', 'count', 'period',
              'cpu_cycles', 'settled_cycles', 'completion_throughput', 'acceptance_throughput',
              'cpu_stall_cycles', 'source_idle_cycles', 'hit_count', 'alloc_count', 'merge_count',
              'memory_read_requests', 'memory_write_requests', 'peak_mshr', 'peak_wbb', 'mean_mshr', 'mean_wbb']
    with (folder / 'summary.csv').open('w') as output:
        writer = csv.DictWriter(output, fields, extrasaction='ignore')
        writer.writeheader()
        for row in rows:
            writer.writerow(dict(row, **(row.get('metrics') or {})))
    lines = ['# DCache性能测量原始汇总', '',
             '| 场景 | 结果 | R/W延迟 | 同行笔数 | 时钟ns | CPU周期 | 全部完成周期 | 笔/拍 | CPU反压拍 | MSHR/WBB峰值 |',
             '|---|---|---|---|---|---|---|---|---|---|']
    print('\nDCache PERFORMANCE REPORT', flush=True)
    for row in rows:
        metrics = row.get('metrics') or {}
        rate = metrics.get('completion_throughput', 0)
        color = '32' if row['status'] == 'PASS' else '31'
        print(f"{row['tag']:<44} \033[1;{color}m{row['status']:<4}\033[0m  {rate:.5f} req/cycle", flush=True)
        lines.append(f"| [{row['tag']}]({row['tag']}.log) | {row['status']} | {row['read']}/{row['write']} | "
                     f"{row['group']} | {row['period']} | {metrics.get('cpu_cycles', '-')} | "
                     f"{metrics.get('settled_cycles', '-')} | {rate:.6f} | {metrics.get('cpu_stall_cycles', '-')} | "
                     f"{metrics.get('peak_mshr', '-')}/{metrics.get('peak_wbb', '-')} |")
        if row['reasons']:
            print('  '+ '; '.join(row['reasons']), flush=True)
    passed = sum(row['status'] == 'PASS' for row in rows)
    print(f'TOTAL {len(rows)}  PASS {passed}  FAIL {len(rows)-passed}', flush=True)
    (folder / 'summary.md').write_text('\n'.join(lines)+'\n')
    print('Report:', folder / 'summary.md', flush=True)


def main():
    """生成当前RTL、独立编译后依次运行；任何失败保留并使整轮返回失败。"""
    folder = SIM / 'work/perf' / datetime.now().strftime('run_%Y%m%d_%H%M%S')
    folder.mkdir(parents=True)
    print('Artifacts:', folder, flush=True)
    if execute(['make', 'generate'], folder / 'generate.stdout.log') != 0:
        print('FAIL: RTL generation; see generate.stdout.log', flush=True)
        return 1
    build = folder / 'build'
    if execute(['make', 'vcs_compile', f'WORK_DIR={build}/',
                f'VCS_COMP_LOG={folder / "compile.log"}',
                'COVERAGE_METRICS=line+cond+branch+fsm+tgl'], folder / 'compile.stdout.log') != 0:
        print('FAIL: compilation; see compile.stdout.log', flush=True)
        return 1
    hashes = capture_inputs()
    hashes['perf_runner'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    (folder / 'runner_snapshot.py').write_bytes(Path(__file__).read_bytes())
    (folder / 'inputs.json').write_text(json.dumps(hashes, indent=4)+'\n')
    control = folder / 'run.tcl'
    control.write_text('run\n')
    rows = []
    for plan in profiles():
        tag = '{scenario}_{submission}_r{read}_w{write}_g{group}_p{period}'.format(**plan)
        path = folder / f'{tag}.json'
        command = [str(build / 'run/simv'), '+UVM_TESTNAME=dcache_perf_test',
                   f'+PERF_SCENARIO={plan["scenario"]}', f'+PERF_SUBMISSION={plan["submission"]}',
                   f'+PERF_REQUESTS={plan["count"]}', f'+PERF_GROUP_SIZE={plan["group"]}',
                   f'+PERF_READ_LATENCY={plan["read"]}', f'+PERF_WRITE_LATENCY={plan["write"]}',
                   f'+PERF_RESULT_FILE={path}', f'+CLOCK_PERIOD_NS={plan["period"]}',
                   '+ntb_random_seed=1', '+UVM_MAX_QUIT_COUNT=10,NO',
                   '-ucli', '-do', str(control), '-l', str(folder / f'{tag}.log')]
        code = execute(command, folder / f'{tag}.stdout.log')
        try:
            metrics = json.loads(path.read_text())
        except (OSError, ValueError):
            metrics = None
        log = (folder / f'{tag}.log').read_text() if (folder / f'{tag}.log').exists() else ''
        reasons = validate(log, code, plan, metrics)
        row = dict(plan, tag=tag, command=command, metrics=metrics, reasons=reasons)
        if plan['period'] == 4 and metrics is not None:
            reference = next(item for item in rows if item['scenario'] == plan['scenario'] and
                             item['submission'] == plan['submission'] and item['read'] == plan['read'] and item['period'] == 10)
            if metrics != reference['metrics'] or reference['status'] != 'PASS':
                reasons.append('4ns replay differs from 10ns cycle metrics')
        row['status'] = 'FAIL' if reasons else 'PASS'
        rows.append(row)
        print(f"[{len(rows):2}/29] {tag}: {row['status']}", flush=True)
    current_hashes = capture_inputs()
    if any(current_hashes.get(key) != value for key, value in hashes.items() if key != 'perf_runner'):
        for row in rows:
            row['reasons'].append('input files changed during matrix')
            row['status'] = 'FAIL'
    write_reports(folder, rows, hashes)
    return 0 if all(row['status'] == 'PASS' for row in rows) else 1


if __name__ == '__main__':
    sys.exit(main())
