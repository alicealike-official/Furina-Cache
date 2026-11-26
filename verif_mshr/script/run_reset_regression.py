#!/usr/bin/env python3
"""Run three-module reset cases and functional checks, preserving all failures and waves."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess

ENV = Path(__file__).resolve().parents[1]
CASES = {
    'wbb': ['wbb_reset_test', 'wbb_reset_active_test', 'wbb_data_pattern_test'],
    'mshr': ['mshr_reset_test', 'mshr_reset_active_test', 'mshr_smoke_test'],
    'dcache': ['dcache_reset_test', 'dcache_reset_active_test', 'dcache_read_during_write_test'],
}
PULSES = {'wbb_reset_test': 4, 'wbb_reset_active_test': 3, 'mshr_reset_test': 4,
          'mshr_reset_active_test': 4, 'dcache_reset_test': 4, 'dcache_reset_active_test': 7}


def hashes():
    """Read exact versions as bytes; do not inspect DUT behavior to define expectations."""
    files = list((ENV/'src').rglob('*.sv*')) + list((ENV/'test').rglob('*.sv'))
    files += list((ENV/'dpi').glob('*.*')) + list((ENV/'tb').glob('*.sv'))
    files += list((ENV/'generated').rglob('*.v')) + list((ENV/'generated').rglob('*params_pkg.sv'))
    files += list((ENV.parent/'RefModel').rglob('*.hpp'))
    return {str(p.relative_to(ENV.parent)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(files)) if p.is_file()}


def execute(command, cwd, log, timeout=180):
    """Keep process output even on timeout; simulation status is additionally checked in its UVM log."""
    with log.open('w') as output:
        try:
            return subprocess.run(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            return 124


def assess(text, code, test, period):
    """Require clean diagnostics, a real completion marker and actual reset-count evidence."""
    reasons = []
    if code:
        reasons.append(f'exit={code}')
    errors = re.findall(r'^UVM_(?:ERROR|FATAL)\b(?!\s*:).*', text, re.M)
    if errors:
        reasons.append('UVM errors')
    for severity in ['WARNING', 'ERROR', 'FATAL']:
        if not re.search(rf'^UVM_{severity}\s*:\s*0\s*$', text, re.M):
            reasons.append(f'{severity} missing/nonzero')
    if not re.search(r'\[(?:WBB|MSHR|DCACHE)_TEST_PASS\]', text) or re.search(r'\[\w+_TEST_FAIL\]', text):
        reasons.append('completion not PASS')
    clock = re.search(r"\[CLK_RESET_CONFIG\] configured_ns=([\d.]+) measured_ns=([\d.]+)", text)
    if not clock or any(abs(float(value)-period)>0.001 for value in clock.groups()):
        reasons.append('actual clock period missing or mismatched')
    coverage = re.findall(r'\[RESET_COVERAGE\]\s+module=(\S+) resets=(\d+) checks=(\d+) failures=(\d+)', text)
    if test in PULSES and (not coverage or int(coverage[-1][1]) != PULSES[test] or int(coverage[-1][2]) < PULSES[test] or int(coverage[-1][3]) != 0):
        reasons.append('reset scenario evidence missing')
    if test in PULSES:
        stage_rows = re.findall(r"\[RESET_STAGE_COVERAGE\]\s+stage=(\S+) count=(\d+)", text)
        if len(stage_rows) != PULSES[test] or any(int(count) != 1 for _, count in stage_rows):
            reasons.append('required reset stage evidence missing')
    return reasons, errors[:10], coverage


def save(folder, data):
    """Write an inspectable partial report after each test; never overwrite historical runs."""
    (folder/'summary.json').write_text(json.dumps(data, indent=4, ensure_ascii=False)+'\n')
    lines = ['# Three-module reset regression', '', '| Module | Case | ns | Status | Log | Wave |', '| --- | --- | --- | --- | --- | --- |']
    for row in data['results']:
        lines.append(f"| {row['module']} | {row['test']} | {row['period_ns']} | {row['status']} | [log]({Path(row['log']).name}) | [FSDB]({Path(row['wave']).name}) |")
    lines += ['', f"PASS {sum(row['status']=='PASS' for row in data['results'])}/{len(data['results'])}; complete={data['complete']}", '',
              'Only local reset is checked. Old-response handling is deferred; physical recovery/removal is outside this UVM/SVA run.']
    (folder/'summary.md').write_text('\n'.join(lines)+'\n')


def main():
    """Regenerate and compile each module, then run every selected period and save colored results."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--modules', nargs='+', choices=CASES, default=list(CASES))
    parser.add_argument('--periods', nargs='+', type=int, default=[10,4])
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    folder = ENV/'sim_dcache/work/reset_regression'/datetime.now().strftime('run_%Y%m%d_%H%M%S')
    folder.mkdir(parents=True)
    data = {'complete':False, 'builds':{}, 'results':[]}
    for module in args.modules:
        sim = ENV/f'sim_{module}'
        code = 0
        if not args.skip_build:
            code = execute(['make','generate'], sim, folder/f'{module}_generate.stdout.log')
            if code == 0:
                code = execute(['make','vcs_compile',f'VCS_COMP_LOG={folder / (module+"_compile.log")}'], sim, folder/f'{module}_compile.stdout.log')
        data['builds'][module] = code
    inputs = hashes()
    (folder/'inputs.json').write_text(json.dumps(inputs,indent=4)+'\n')
    for module in args.modules:
        sim = ENV/f'sim_{module}'
        for test in CASES[module]:
            for period in args.periods:
                tag = f'{test}_p{period}'
                log, wave = folder/(tag+'.log'), folder/(tag+'.fsdb')
                row = {'module':module, 'test':test, 'period_ns':period, 'log':str(log), 'wave':str(wave), 'status':'NOT RUN', 'reasons':['build failed']}
                if data['builds'][module] == 0:
                    top = {'wbb':'tb_top', 'mshr':'mshr_tb_top', 'dcache':'dcache_tb_top'}[module]
                    tcl = folder/(tag+'.tcl')
                    tcl.write_text(f'fsdbDumpfile "{wave}"\nfsdbDumpvars 0 "{top}"\nrun\n')
                    command = [str(sim/'work/run/simv'), '+fsdb+autoflush', f'+wave={wave}',
                               f'+UVM_TESTNAME={test}', f'+CLOCK_PERIOD_NS={period}', '+ntb_random_seed=1',
                               '+UVM_MAX_QUIT_COUNT=10,NO', '-cm', 'line+cond+fsm+branch+tgl+assert',
                               '-cm_dir', str(sim/'work/simv.vdb'), '-cm_name', tag, '-ucli', '-do', str(tcl), '-l', str(log)]
                    code = execute(command, sim, folder/(tag+'.stdout.log'))
                    text = log.read_text(errors='replace') if log.exists() else ''
                    reasons, errors, coverage = assess(text, code, test, period)
                    row['command'] = command
                    measured = re.search(r'\[CLK_RESET_CONFIG\] configured_ns=([\d.]+) measured_ns=([\d.]+)', text)
                    row['actual_period_ns'] = float(measured[2]) if measured else None
                    if not wave.exists() or not wave.stat().st_size: reasons.append('wave missing')
                    if hashes() != inputs: reasons.append('source changed')
                    row.update(status='FAIL' if reasons else 'PASS', reasons=reasons, errors=errors, reset_coverage=coverage)
                data['results'].append(row)
                print(f"\033[1;{'32' if row['status']=='PASS' else '31'}m{row['status']}\033[0m {tag}",flush=True)
                save(folder,data)
    data['complete'] = True
    save(folder,data)
    passed = sum(row['status']=='PASS' for row in data['results'])
    print(f'PASS {passed}/{len(data["results"])} Report: {folder / "summary.md"}',flush=True)
    return 0 if passed == len(data['results']) else 1


if __name__ == '__main__':
    raise SystemExit(main())
