#!/usr/bin/env python3
"""统一回归：每个profile编译一次，framework先验收，再并行运行独立case。"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

ENV = Path(__file__).resolve().parents[1]
for module_name in ('wbb', 'mshr', 'dcache'):
    sys.path.insert(0, str(ENV / f'sim_{module_name}/script'))

import run_wbb_regression as wbb
import run_mshr_regression as mshr
import run_mshr_framework as mshr_framework
import run_dcache_regression as dcache
import run_dcache_framework as dcache_framework
import run_dcache_perf as perf
import run_reset_regression as reset

METRICS = 'line+cond+fsm+branch+tgl+assert'
PROFILES = {'wbb_strict': 'wbb', 'wbb_delayed': 'wbb', 'mshr': 'mshr', 'dcache': 'dcache'}
TOPS = {'wbb': 'tb_top', 'mshr': 'mshr_tb_top', 'dcache': 'dcache_tb_top'}
process_lock = threading.Lock()
active_processes = set()
stopping = threading.Event()


def positive_int(value):
    """并发与超时必须是正整数，错误参数在启动工具前报告。"""
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError('must be a positive integer')
    return number


def arguments():
    """默认运行全部；筛选参数用于局部重放，framework仍强制前置。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-j', '--jobs', type=positive_int, default=4, help='同时运行的simv数，默认4')
    parser.add_argument('--compile-jobs', type=positive_int, default=10, help='每次VCS编译线程数，默认10')
    parser.add_argument('--tests', nargs='+', help='仅运行指定test；默认全部，包括长跑/复位/perf')
    parser.add_argument('--dry-run', action='store_true', help='只打印计划，不生成/编译/仿真')
    parser.add_argument('--no-waves', action='store_true', help='关闭FSDB导出，仍保留日志和检查')
    parser.add_argument('--timeout', type=positive_int, default=600, help='每个工具进程超时秒数，默认600')
    parser.add_argument('--color', choices=('auto', 'always', 'never'), default='auto')
    return parser.parse_args()


def plan_cases(selected=None):
    """复用原入口清单与模式规则，显式纳入长跑、复位、性能，避免复制case名单。"""
    cases = []

    def add(module, test, kind, period, seed=1, mode='serial', profile=None, **extra):
        profile = profile or ('wbb_delayed' if test == 'wbb_delayed_push_test' else
                              'wbb_strict' if module == 'wbb' else module)
        tag = f'{kind}_{test}_{profile}_{mode}_p{period}_s{seed}'
        if 'perf_plan' in extra:
            config = extra['perf_plan']
            tag += '_{scenario}_{submission}_r{read}_w{write}_g{group}'.format(**config)
        cases.append(dict(module=module, test=test, kind=kind, period=period, seed=seed,
                          mode=mode, profile=profile, tag=tag, **extra))

    for test in wbb.TEST_ORDER:
        for mode in wbb.input_modes_for(test, ['serial', 'pipeline']):
            for period in (10, 4):
                for seed in ((1, 2, 3) if test in ('wbb_random_test', 'wbb_long_run_test') else (1,)):
                    add('wbb', test, 'functional', period, seed, mode)
    for test in mshr.TESTS:
        for period in (10, 4):
            for seed in ((1, 2, 3) if test in ('mshr_random_test', 'mshr_long_run_test') else (1,)):
                add('mshr', test, 'functional', period, seed)
    for test in dcache.TESTS:
        randomized = test in ('dcache_random_test', 'dcache_long_run_test',
                             'dcache_memory_combinations_test', 'dcache_read_during_write_test') or test.startswith('dcache_random_')
        for period in (10, 4):
            for seed in ((1, 2, 3) if randomized else (1,)):
                add('dcache', test, 'functional', period, seed)
    for module, tests in reset.CASES.items():
        for test in tests:
            if test not in reset.PULSES:
                continue  # 原复位入口附带的普通功能case已经在上面纳入，不重复跑。
            for period in (10, 4):
                add(module, test, 'reset', period)
    for config in perf.profiles():
        add('dcache', 'dcache_perf_test', 'perf', config['period'], perf_plan=config)

    available = {case['test'] for case in cases} | {'mshr_base_test', 'dcache_base_test', 'dcache_smoke_test'}
    if selected and set(selected) - available:
        raise ValueError('Unknown tests: ' + ', '.join(sorted(set(selected) - available)))
    chosen = [case for case in cases if not selected or case['test'] in selected]
    needed = {case['profile'] for case in chosen}
    for test in selected or []:
        if test in ('mshr_base_test', 'dcache_base_test', 'dcache_smoke_test'):
            needed.add('mshr' if test.startswith('mshr') else 'dcache')

    framework = []
    for profile in PROFILES:
        if profile not in needed:
            continue
        module = PROFILES[profile]
        tests = [f'{module}_base_test']
        if module != 'wbb':
            tests.append(f'{module}_smoke_test')
        for test in tests:
            for period in (10, 4):
                add(module, test, 'framework', period, profile=profile)
                framework.append(cases[-1])
    return framework, chosen


def source_hashes():
    """仅按字节记录输入版本，不读取DUT行为来制定验证期望。"""
    hashes = dcache_framework.capture_inputs()
    files = list((ENV / 'test').rglob('*.sv')) + list((ENV / 'tb').glob('*.sv'))
    files += list((ENV / 'generated').rglob('*.v'))
    files += [ENV / f'sim_{module}/Makefile' for module in ('wbb', 'mshr', 'dcache')]
    files += list((ENV / 'script').glob('*.py'))
    for module in ('wbb', 'mshr', 'dcache'):
        files += list((ENV / f'sim_{module}/script').glob('*.py'))
    for path in files:
        hashes[str(path.relative_to(ENV.parent))] = hashlib.sha256(path.read_bytes()).hexdigest()
    for path in [Path(__file__), ENV.parent / 'run_regression.sh']:
        hashes[str(path.relative_to(ENV.parent))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def terminate_children(signum=None, frame=None):
    """退出时终止本轮创建的进程组，避免Ctrl-C后遗留后台simv。"""
    stopping.set()
    with process_lock:
        for process in tuple(active_processes):
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass


def execute(command, cwd, output, timeout):
    """每进程独立日志和进程组；超时杀掉整个工具进程树，并保留已产生的现场。"""
    if stopping.is_set():
        return 130
    with output.open('w') as stream:
        with process_lock:
            if stopping.is_set():
                return 130
            process = subprocess.Popen(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            active_processes.add(process)
        try:
            try:
                code = process.wait(timeout=timeout)
                if stopping.is_set():
                    return 130
                return code
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                stream.write('\nREGRESSION_TIMEOUT\n')
                return 124
        finally:
            with process_lock:
                active_processes.discard(process)


def compile_profile(folder, profile, args):
    """同一profile只编译一次，功能、复位和性能统一引用这个只读产物。"""
    module = PROFILES[profile]
    build = folder / 'build' / profile
    build.mkdir(parents=True)
    command = ['make', 'vcs_compile', f'WORK_DIR={build}/', f'THREADS={args.compile_jobs}',
               f'VCS_COMP_LOG={build / "compile.log"}', f'COVERAGE_METRICS={METRICS}']
    if profile == 'wbb_delayed':
        command.append('SVA_DEFINES=+define+WBB_ALLOW_DELAYED_PUSH')
    code = execute(command, ENV / f'sim_{module}', build / 'compile.stdout.log', args.timeout)
    binary = build / 'run/simv'
    database = build / 'simv.vdb'
    log = (build / 'compile.log').read_text(errors='replace') if (build / 'compile.log').exists() else ''
    passed = code == 0 and binary.is_file() and os.access(binary, os.X_OK) and database.is_dir() and bool(log)
    passed = passed and not re.search(r'^\s*(?:Error|Fatal)-\[', log, re.M)
    return dict(profile=profile, status='PASS' if passed else 'FAIL', command=command,
                exit_code=code, binary=str(binary), database=str(database), log=str(build / 'compile.log'))


def tcl_string(value):
    """复用原WBB入口的Tcl转义，路径里的空格、变量符号不改变脚本含义。"""
    return wbb.tcl_string(str(value))


def common_checks(text, code, case):
    """原数据/SVA结果、真实周期及结束标记必须通过，不能只看simv退出码。"""
    reasons = []
    if code != 0:
        reasons.append(f'exit={code}')
    for level in ('WARNING', 'ERROR', 'FATAL'):
        values = re.findall(rf'^UVM_{level}\s*:\s*(\d+)\s*$', text, re.M)
        if not values or any(int(value) != 0 for value in values):
            reasons.append(f'UVM {level} missing/nonzero')
    if re.search(r'^UVM_(?:ERROR|FATAL)\b(?!\s*:)|^\s*(?:Error|Fatal)-\[', text, re.M):
        reasons.append('simulator/UVM error')
    module = case['module'].upper()
    if not re.search(rf'^UVM_INFO .*\[{module}_TEST_PASS\]', text, re.M) or f'[{module}_TEST_FAIL]' in text:
        reasons.append('completion not PASS')
    clock = re.search(r'\[CLK_RESET_CONFIG\] configured_ns=([\d.]+) measured_ns=([\d.]+)', text)
    if not clock or any(abs(float(value)-case['period']) > 0.001 for value in clock.groups()):
        reasons.append('measured clock missing/mismatch')
    return reasons


def case_checks(text, code, case, root):
    """保留原入口的专用结果判定，统一调度只改变运行方式，不放宽检查。"""
    reasons = common_checks(text, code, case)
    detail = {}
    if case['kind'] == 'reset':
        extra, errors, coverage = reset.assess(text, code, case['test'], case['period'])
        reasons += extra
        detail.update(errors=errors, reset_coverage=coverage)
    elif case['kind'] == 'perf':
        try:
            metrics = json.loads((root / 'metrics.json').read_text())
        except (OSError, ValueError):
            metrics = None
        reasons += perf.validate(text, code, case['perf_plan'], metrics)
        detail['metrics'] = metrics
    elif case['module'] == 'wbb':
        observed = wbb.parse_log(text)
        detail['observations'] = observed
        if not observed['counts']:
            reasons.append('WBB counts missing')
        if observed['observed_input_mode'] != case['mode']:
            reasons.append('WBB input mode mismatch')
    elif case['module'] == 'mshr':
        if case['kind'] == 'framework':
            extra, counts = mshr_framework.assess(text, case['test'], code)
            reasons += extra
            detail['counts'] = counts
        else:
            result = mshr.assess(text, code, case['test'])
            reasons += result['reasons']
            detail['observations'] = result
    elif case['kind'] == 'framework':
        expected = (3, 2, 1) if case['test'] == 'dcache_smoke_test' else (0, 0, 0)
        counts = re.search(r'\[DCACHE_COUNTS\] cycles=(\d+) requests=(\d+) read_responses=(\d+) write_responses=(\d+)', text)
        if not counts or int(counts[1]) == 0 or tuple(map(int, counts.groups()[1:])) != expected:
            reasons.append('DCache framework count mismatch')
    else:
        extra, errors, coverage = dcache.assess(text, code)
        reasons += extra
        detail.update(errors=errors, coverage=coverage)
    return sorted(set(reasons)), detail


def simulate(folder, build, case, args):
    """simv共享且只读，cwd、FSDB、UCLI、VDB及DPI输出均逐case隔离。"""
    started = time.monotonic()
    root = folder / 'cases' / case['tag']
    root.mkdir(parents=True)
    database = root / 'coverage.vdb'
    shutil.copytree(build['database'], database)
    control = root / 'run.tcl'
    wave = root / 'wave.fsdb'
    script = ''
    if not args.no_waves:
        script = f'fsdbDumpfile {tcl_string(wave)}\nfsdbDumpvars 0 {tcl_string(TOPS[case["module"]])}\n'
    control.write_text(script + 'run\n')
    log = root / 'simulation.log'
    command = [build['binary'], f'+CLOCK_PERIOD_NS={case["period"]}', f'+ntb_random_seed={case["seed"]}',
               '+UVM_MAX_QUIT_COUNT=10,NO', '-cm', METRICS, '-cm_dir', str(database), '-cm_name', case['tag'],
               '-ucli', '-do', str(control), '-l', str(log)]
    # framework的base故意不传testname，保留无TEST_NAME默认启动检查。
    if not (case['kind'] == 'framework' and case['test'].endswith('_base_test')):
        command.append(f'+UVM_TESTNAME={case["test"]}')
    if case['module'] == 'wbb':
        command.append(f'+WBB_INPUT_MODE={case["mode"]}')
    if not args.no_waves:
        command += ['+fsdb+autoflush', f'+wave={wave}']
    if case['kind'] == 'perf':
        config = case['perf_plan']
        command += [f'+PERF_SCENARIO={config["scenario"]}', f'+PERF_SUBMISSION={config["submission"]}',
                    f'+PERF_REQUESTS={config["count"]}', f'+PERF_GROUP_SIZE={config["group"]}',
                    f'+PERF_READ_LATENCY={config["read"]}', f'+PERF_WRITE_LATENCY={config["write"]}',
                    f'+PERF_RESULT_FILE={root / "metrics.json"}']
    (root / 'command.json').write_text(json.dumps(command, indent=4)+'\n')
    code = execute(command, root, root / 'stdout.log', args.timeout)
    text = log.read_text(errors='replace') if log.exists() else ''
    reasons, detail = case_checks(text, code, case, root)
    if not args.no_waves and (not wave.is_file() or wave.stat().st_size == 0):
        reasons.append('FSDB missing/empty')
    records_path = database / 'snps/coverage/db/testdata'
    records = sorted(path.name for path in records_path.iterdir() if path.is_dir()) if records_path.is_dir() else []
    if records != [case['tag']]:
        reasons.append('coverage missing or contaminated')
    return dict(case, status='FAIL' if reasons else 'PASS', reasons=reasons, command=command,
                exit_code=code, log=str(log), wave=None if args.no_waves else str(wave), database=str(database),
                coverage_records=records, elapsed_seconds=round(time.monotonic()-started, 3), **detail)


def save_report(folder, report):
    """主线程保存逐项结果与未完成状态；其他进程不写本汇总文件。"""
    temporary = folder / 'summary.json.tmp'
    temporary.write_text(json.dumps(report, indent=4, ensure_ascii=False)+'\n')
    temporary.replace(folder / 'summary.json')
    rows = ['# 全量回归', '', f"Complete: {report['complete']}; jobs: {report['jobs']}; planned: {report['planned_runs']}", '',
            '| Case | 阶段 | 结果 | 秒 | 日志 | 原因 |', '|---|---|---|---:|---|---|']
    for row in report['results']:
        link = f"[log]({Path(row['log']).relative_to(folder)})" if row.get('log') else '-'
        rows.append(f"| {row['tag']} | {row['kind']} | {row['status']} | {row.get('elapsed_seconds', '-')} | {link} | {'; '.join(row['reasons'])} |")
    counts = Counter(row['status'] for row in report['results'])
    rows += ['', f"PASS {counts['PASS']}; FAIL {counts['FAIL']}; NOT RUN {counts['NOT RUN']}."]
    perf_rows = [row for row in report['results'] if row['kind'] == 'perf']
    if perf_rows:
        rows += ['', '## 性能', '', '| 配置 | 结果 | CPU周期 | 笔/拍 |', '|---|---|---:|---:|']
        for row in perf_rows:
            metrics = row.get('metrics') or {}
            rows.append(f"| {row['tag']} | {row['status']} | {metrics.get('cpu_cycles', '-')} | {metrics.get('completion_throughput', '-')} |")
    (folder / 'summary.md').write_text('\n'.join(rows)+'\n')
    with (folder / 'summary.tsv').open('w') as stream:
        stream.write('case\tstage\tstatus\tseconds\tlog\n')
        for row in report['results']:
            stream.write(f"{row['tag']}\t{row['kind']}\t{row['status']}\t{row.get('elapsed_seconds', '-')}\t{row.get('log', '-')}\n")


def paint(status, args):
    """终端状态按PASS/FAIL/未运行着色；文件报告保持纯文本。"""
    enabled = args.color == 'always' or (args.color == 'auto' and sys.stdout.isatty() and 'NO_COLOR' not in os.environ)
    colors = {'PASS': '32', 'FAIL': '31', 'NOT RUN': '33', 'BUILD': '36'}
    return f'\033[1;{colors[status]}m{status}\033[0m' if enabled else status


def run_phase(folder, plans, builds, report, args):
    """固定大小线程池调度simv；只有主线程打印与保存，日志不会交错覆盖。"""
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(simulate, folder, builds[case['profile']], case, args): case for case in plans}
        for future in as_completed(futures):
            case = futures[future]
            try:
                row = future.result()
            except Exception as error:
                row = dict(case, status='FAIL', reasons=[f'runner exception: {type(error).__name__}: {error}'])
            report['results'].append(row)
            save_report(folder, report)
            print(f"[{len(report['results']):3}/{report['planned_runs']}] {paint(row['status'], args):<6} {case['tag']}", flush=True)
            if row['reasons']:
                print('  '+'; '.join(row['reasons']), flush=True)


def skip_cases(plans, report, reason):
    """依赖失败的case登记NOT RUN，不能复用旧产物或把未执行当成通过。"""
    for case in plans:
        report['results'].append(dict(case, status='NOT RUN', reasons=[reason]))


def check_perf_replays(report):
    """并行执行不依赖完成顺序，所有结果齐全后再比较10ns/4ns原始周期指标。"""
    rows = [row for row in report['results'] if row['kind'] == 'perf']
    for row in rows:
        config = row['perf_plan']
        if config['period'] != 4 or row['status'] != 'PASS':
            continue
        reference = next((item for item in rows if item['perf_plan'] == dict(config, period=10)), None)
        if not reference or reference['status'] != 'PASS' or row.get('metrics') != reference.get('metrics'):
            row['status'] = 'FAIL'
            row['reasons'].append('4ns replay differs from 10ns cycle metrics')


def main():
    """先生成/编译，再进行全局framework屏障；通过的profile复用产物并行跑全部case。"""
    args = arguments()
    framework, cases = plan_cases(args.tests)
    needed = [profile for profile in PROFILES if any(case['profile'] == profile for case in framework)]
    print(f'并发simv={args.jobs}; 编译profile={len(needed)}; framework={len(framework)}; 其余case组合={len(cases)}', flush=True)
    if args.dry_run:
        for profile in needed:
            print(f'BUILD ONCE {profile}')
        for stage, plans in [('1 FRAMEWORK', framework), ('2 FUNCTIONAL/RESET/PERF', cases)]:
            print('\n'+stage)
            for case in plans:
                print(case['tag'])
        print('\nDRY RUN: framework全部结束前，不启动第二阶段；同一profile不重复编译。')
        return 0

    for tool in ('make', 'sbt', 'vcs'):
        if not shutil.which(tool):
            raise RuntimeError(f'Missing tool: {tool}; 请先加载工具环境')
    with (ENV / 'sim_dcache/work_all_regression.lock').open('w') as lock_file:
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('已有一个全量回归正在运行') from error
        signal.signal(signal.SIGINT, terminate_children)
        signal.signal(signal.SIGTERM, terminate_children)
        folder = ENV / 'sim_dcache/work/all_regression' / datetime.now().strftime('run_%Y%m%d_%H%M%S_%f')
        folder.mkdir(parents=True)
        print('Artifacts:', folder, flush=True)
        report = dict(complete=False, jobs=args.jobs, planned_runs=len(framework)+len(cases),
                      generations={}, builds={}, results=[])
        save_report(folder, report)

        # sbt生成共用工程，依次生成，所有源码固定后才编译，不能与仿真并发改RTL。
        for module in dict.fromkeys(PROFILES[profile] for profile in needed):
            command = ['make', 'generate']
            code = execute(command, ENV / f'sim_{module}', folder / f'generate_{module}.log', args.timeout)
            report['generations'][module] = dict(exit_code=code, command=command)
            print(f'{paint("PASS" if code == 0 else "FAIL", args)} generate {module}', flush=True)
        inputs = source_hashes()
        (folder / 'inputs.json').write_text(json.dumps(inputs, indent=4)+'\n')
        for profile in needed:
            if report['generations'][PROFILES[profile]]['exit_code'] != 0:
                report['builds'][profile] = dict(status='NOT RUN')
                continue
            print(f'{paint("BUILD", args)} {profile}', flush=True)
            report['builds'][profile] = compile_profile(folder, profile, args)
            save_report(folder, report)

        print('\nPHASE 1: FRAMEWORK', flush=True)
        ready_framework = [case for case in framework if report['builds'][case['profile']]['status'] == 'PASS']
        skip_cases([case for case in framework if case not in ready_framework], report, 'generation/compilation failed')
        run_phase(folder, ready_framework, report['builds'], report, args)
        qualified = {profile for profile in needed if all(row['status'] == 'PASS' for row in report['results'] if row['profile'] == profile)}

        print('\nPHASE 2: FUNCTIONAL / LONG RUN / RESET / PERF', flush=True)
        ready_cases = [case for case in cases if case['profile'] in qualified]
        skip_cases([case for case in cases if case not in ready_cases], report, 'profile framework did not pass')
        run_phase(folder, ready_cases, report['builds'], report, args)
        check_perf_replays(report)
        if source_hashes() != inputs:
            for row in report['results']:
                if row['status'] == 'PASS':
                    row['status'] = 'FAIL'
                    row['reasons'].append('input source changed during run')
        report['complete'] = not stopping.is_set()
        save_report(folder, report)
        print('\n========== ALL REGRESSION SUMMARY ==========', flush=True)
        for stage in ('framework', 'functional', 'reset', 'perf'):
            counts = Counter(row['status'] for row in report['results'] if row['kind'] == stage)
            if counts:
                status = 'PASS' if not counts['FAIL'] and not counts['NOT RUN'] else 'FAIL'
                print(f'{stage:<12} {paint(status, args)}  PASS={counts["PASS"]} FAIL={counts["FAIL"]} NOT RUN={counts["NOT RUN"]}', flush=True)
        counts = Counter(row['status'] for row in report['results'])
        print(f'TOTAL={report["planned_runs"]} PASS={counts["PASS"]} FAIL={counts["FAIL"]} NOT RUN={counts["NOT RUN"]}', flush=True)
        print('Report:', folder / 'summary.md', flush=True)
        if stopping.is_set():
            return 130
        return 0 if len(report['results']) == report['planned_runs'] and all(row['status'] == 'PASS' for row in report['results']) else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError) as error:
        terminate_children()
        print(f'REGRESSION ERROR: {error}', file=sys.stderr)
        sys.exit(1)
