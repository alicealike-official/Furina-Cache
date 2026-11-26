#!/usr/bin/env python3
"""Collect fresh DUT-only code coverage; merge only clean, clock-verified passing runs."""
import argparse
from datetime import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ENV = Path(__file__).resolve().parents[1]
METRICS = ['line', 'cond', 'branch', 'fsm', 'tgl']
METRIC_NAMES = {'LINE':'line', 'COND':'cond', 'BRANCH':'branch', 'FSM':'fsm', 'TOGGLE':'tgl'}
TOPS = {'wbb':'tb_top', 'mshr':'mshr_tb_top', 'dcache':'dcache_tb_top'}
EXPECTED_MODULES = {'wbb':{'WriteBackBuffer'}, 'mshr':{'Mshr'}, 'dcache':{'DCache','CacheMem','Mshr','WriteBackBuffer','StreamFifo','StreamFifo_1'}}


def load_script(label, path):
    """Reuse trusted existing case inventories without copying stimulus or expected behavior."""
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location(label, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def inventory(periods, seeds, include_long):
    """Keep legal profiles and input modes from the existing functional regressions."""
    wbb = load_script('coverage_wbb_cases', ENV/'sim_wbb/script/run_wbb_regression.py')
    mshr = load_script('coverage_mshr_cases', ENV/'sim_mshr/script/run_mshr_regression.py')
    dcache = json.loads((ENV/'sim_dcache/script/external_cases.json').read_text())
    plans = []
    for module in TOPS:
        tests = list(wbb.TEST_ORDER) if module == 'wbb' else list(mshr.TESTS) if module == 'mshr' else ['dcache_base_test','dcache_smoke_test'] + dcache
        tests += [f'{module}_reset_test', f'{module}_reset_active_test']
        for test in dict.fromkeys(tests):
            if not include_long and 'long_run' in test:
                continue
            profile = wbb.profile_for(test) if module == 'wbb' else 'default'
            modes = wbb.input_modes_for(test, ['serial','pipeline']) if module == 'wbb' else ['cpu' if module == 'dcache' else 'slot']
            randomized = ('random' in test or 'long_run' in test or test in ['dcache_memory_combinations_test','dcache_read_during_write_test'])
            for mode in modes:
                for period in periods:
                    for seed in seeds if randomized else [1]:
                        tag = f'{module}_{profile}_{test}_{mode}_p{period:g}_s{seed}'
                        plans.append(dict(module=module, profile=profile, test=test, input_mode=mode, period_ns=period, seed=seed, tag=tag))
    return plans


def source_hashes():
    """Read bytes only to pin RTL, verification and original model versions."""
    files = list((ENV/'src').rglob('*.sv*')) + list((ENV/'test').rglob('*.sv'))
    files += list((ENV/'tb').glob('*.sv')) + list((ENV/'dpi').glob('*.*'))
    files += list((ENV/'generated').rglob('*.v')) + list((ENV/'generated').rglob('*params_pkg.sv'))
    files += list((ENV.parent/'RefModel').rglob('*.hpp'))
    files += [ENV/f'sim_{module}/Makefile' for module in TOPS]
    return {str(p.relative_to(ENV.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(files)) if p.is_file()}


def execute(command, cwd, log, timeout=600):
    """Preserve diagnostics and terminate timed-out process groups, including child simulators."""
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('w') as output:
        try:
            process = subprocess.Popen(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                return process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                import signal
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=10)
                return 124
        except OSError as error:
            output.write(str(error)+'\n')
            return 127


def save(folder, summary):
    """Keep a partial machine report throughout a long collection; do not replace prior runs."""
    (folder/'summary.json').write_text(json.dumps(summary, indent=4, ensure_ascii=False)+'\n')


def fsm_objects(database):
    """Count actual extracted FSM objects; an empty XML file does not mean FSM data exists."""
    path = Path(database)/'snps/coverage/db/shape/fsm.verilog.shape.xml'
    if not path.exists():
        return 0
    data = path.read_bytes()
    if data.startswith(b'\x1f\x8b'):
        import gzip
        data = gzip.decompress(data)
    return len(re.findall(rb'<fsmfsm\b', data))


def compile_profile(folder, module, profile):
    """Compile the original Makefile into an isolated directory with explicit code-only metrics."""
    root = folder/module/profile
    root.mkdir(parents=True)
    hier = root/'dut.cm'
    scope = f'+tree {TOPS[module]}.dut\n'
    if module == 'dcache':
        scope += '-tree dcache_tb_top.dut.u_dcache_probe\n-tree dcache_tb_top.dut.u_dcache_ip_checks\n'
    hier.write_text(scope)
    build = root/'build'
    database = build/'simv.vdb'
    options = f'-cm_hier {hier} -cm_line contassign -cm_cond allops+anywidth+tf -cm_tgl mda -cm_fsmopt allowTmp+report2StateFsms'
    command = ['make','vcs_compile',f'WORK_DIR={build}/', f'COVERAGE_DATABASE={database}',
               'COVERAGE_METRICS='+'+'.join(METRICS), f'COVERAGE_OPTIONS={options}', f'VCS_COMP_LOG={root / "compile.log"}']
    if profile == 'delayed':
        command += ['SVA_DEFINES=+define+WBB_ALLOW_DELAYED_PUSH']
    code = execute(command, ENV/f'sim_{module}', root/'compile.stdout.log')
    binary = build/'run/simv'
    text = (root/'compile.log').read_text(errors='replace') if (root/'compile.log').exists() else ''
    okay = code == 0 and binary.is_file() and database.is_dir() and not re.search(r'^\s*(?:Error|Fatal)-\[', text, re.M)
    return dict(pass_build=okay, exit_code=code, binary=str(binary), database=str(database), command=command,
                log=str(root/'compile.log'), has_fsm=fsm_objects(database)>0, fsm_object_count=fsm_objects(database))


def assess_simulation(text, code, plan):
    """A coverage-producing run must still pass real DUT/model/SVA checks and the actual clock check."""
    reasons = []
    if code: reasons.append(f'exit={code}')
    errors = re.findall(r'^UVM_(?:ERROR|FATAL)\b(?!\s*:).*', text, re.M)
    if errors or re.search(r'^\s*(?:Error|Fatal)-\[', text, re.M): reasons.append('simulator/UVM errors')
    for severity in ['WARNING','ERROR','FATAL']:
        if not re.search(rf'^UVM_{severity}\s*:\s*0\s*$', text, re.M): reasons.append(f'{severity} missing/nonzero')
    if not re.search(r'\[(?:WBB|MSHR|DCACHE)_TEST_PASS\]', text) or re.search(r'\[\w+_TEST_FAIL\]', text): reasons.append('completion not PASS')
    clock = re.search(r'\[CLK_RESET_CONFIG\] configured_ns=([\d.]+) measured_ns=([\d.]+)', text)
    actual = float(clock[2]) if clock else None
    if not clock or any(abs(float(value)-plan['period_ns'])>0.001 for value in clock.groups()): reasons.append('actual clock missing/mismatch')
    if plan['module']=='wbb':
        if f'input_mode={plan["input_mode"]}' not in text: reasons.append('input mode mismatch')
    if '_reset_' in plan['test']:
        reset = re.search(r'\[RESET_COVERAGE\].*resets=(\d+) checks=(\d+) failures=(\d+)',text)
        if not reset or int(reset[1])<1 or int(reset[2])<1 or int(reset[3])!=0: reasons.append('reset completion missing')
    return reasons, errors[:10], actual


def simulate(folder, build, plan, waves, timeout):
    """One database per unique case/mode/clock/seed; failed data is retained but never merged."""
    root = folder/plan['module']/plan['profile']/'tests'/plan['tag']
    root.mkdir(parents=True)
    database = root/'coverage.vdb'
    row = dict(plan, status='NOT RUN', reasons=['build failed'], database=str(database), log=str(root/'simulation.log'))
    if not build['pass_build']: return row
    shutil.copytree(build['database'], database)
    tcl = root/'run.tcl'
    text = ''
    if waves:
        text += f'fsdbDumpfile "{root / "wave.fsdb"}"\nfsdbDumpvars 0 "{TOPS[plan["module"]]}"\n'
    tcl.write_text(text+'run\n')
    command = [build['binary'], f'+UVM_TESTNAME={plan["test"]}', f'+CLOCK_PERIOD_NS={plan["period_ns"]:g}',
               f'+ntb_random_seed={plan["seed"]}', '+UVM_MAX_QUIT_COUNT=10,NO', '-cm','+'.join(METRICS),
               '-cm_dir',str(database),'-cm_name',plan['tag'],'-ucli','-do',str(tcl),'-l',row['log']]
    if plan['module']=='wbb': command.insert(1, f'+WBB_INPUT_MODE={plan["input_mode"]}')
    code = execute(command, ENV/f'sim_{plan["module"]}', root/'simulation.stdout.log', timeout)
    text = Path(row['log']).read_text(errors='replace') if Path(row['log']).exists() else ''
    reasons, errors, actual = assess_simulation(text,code,plan)
    testdata = database/'snps/coverage/db/testdata'
    records = [p.name for p in testdata.iterdir() if p.is_dir()] if testdata.exists() else []
    if records != [plan['tag']]: reasons.append('coverage record missing or contaminated')
    row.update(status='FAIL' if reasons else 'PASS', reasons=reasons, errors=errors, actual_period_ns=actual,
               command=command, exit_code=code, coverage_records=records)
    return row


def parse_summary(report):
    """Read each percentage with its covered/coverable denominator; N/A is never treated as 100%."""
    text = (report/'dashboard.txt').read_text()
    block = text.split('Total Coverage Summary',1)[1].strip().splitlines()
    headers = block[0].split()[1:]
    values = re.findall(r'([\d.]+|--)\s+(\d+)/(\d+)',block[1])
    if len(headers)!=len(values): raise RuntimeError(f'Unexpected URG summary format: {report}')
    metrics = {metric:dict(percent=None,covered=0,total=0) for metric in METRICS}
    for header,(percent,covered,total) in zip(headers,values):
        metrics[METRIC_NAMES[header]] = dict(percent=None if percent=='--' else float(percent),covered=int(covered),total=int(total))
    return metrics


def report_module(folder, module, builds, results):
    """Merge only passing data from this build; keep standalone and integration scopes separate."""
    passed = [row for row in results if row['module']==module and row['status']=='PASS']
    if not passed: return {'status':'NO PASSING DATA'}
    root = folder/'reports'/module
    root.mkdir(parents=True)
    metrics = [metric for metric in METRICS if metric!='fsm' or any(build['has_fsm'] for key,build in builds.items() if key.startswith(module+'/'))]
    variants = ['self_rtl','whole_dut'] if module=='dcache' else ['self_rtl']
    reports = {}
    for variant in variants:
        hierarchy = root/(variant+'.hier')
        text = f'+tree {TOPS[module]}.dut\n'
        if module == 'dcache':
            text += '-tree dcache_tb_top.dut.u_dcache_probe\n-tree dcache_tb_top.dut.u_dcache_ip_checks\n'
        if module=='dcache' and variant=='self_rtl': text += '-module StreamFifo\n-module StreamFifo_1\n'
        hierarchy.write_text(text)
        report = root/variant
        command = ['urg','-full64','-dir']+[row['database'] for row in passed]+['-metric','+'.join(metrics),
                   '-hier',str(hierarchy),'-format','both','-show','ratios','-show','tests','-show','testrecords',
                   '-report',str(report),'-dbname',str(root/(variant+'_merged'))]
        code = execute(command, ENV, root/(variant+'.urg.stdout.log'), 900)
        log = (root/(variant+'.urg.stdout.log')).read_text(errors='replace')
        if code or re.search(r'^\s*(?:Error|Fatal)-\[',log,re.M) or not (report/'dashboard.txt').exists():
            reports[variant] = dict(status='URG FAILED',exit_code=code,log=str(root/(variant+'.urg.stdout.log')))
            continue
        numbers = parse_summary(report)
        dashboard = (report/'dashboard.txt').read_text()
        header = dashboard.split('Total Coverage Summary', 1)[1].strip().splitlines()[0]
        if 'ASSERT' in header or 'GROUP' in header:
            raise RuntimeError('Non-code coverage metric appeared in report')
        count = re.search(r'Number of tests:\s*(\d+)', dashboard)
        if not count or int(count[1]) != len(passed):
            raise RuntimeError(f'URG test count mismatch for {module}/{variant}')
        module_metrics = {}
        module_table = (report/'modlist.txt').read_text().split('Total modules in report:', 1)[1]
        for line in module_table.splitlines():
            if not re.match(r'^\s*(?:\d|--)', line):
                continue
            ratios = re.findall(r'([\d.]+|--)\s+(\d+)/(\d+)',line)
            if not ratios:
                continue
            name = line.split()[-1]
            module_metrics[name] = line.strip()
        expected = EXPECTED_MODULES[module]
        if module == 'dcache' and variant == 'self_rtl':
            expected = expected - {'StreamFifo','StreamFifo_1'}
        if set(module_metrics) != expected:
            raise RuntimeError(f'DUT scope mismatch: actual={set(module_metrics)}, expected={expected}')
        reports[variant] = dict(status='COMPLETE',pass_tests=len(passed),metrics=numbers,html=str(report/'dashboard.html'),
                                text=str(report/'dashboard.txt'),command=command,module_rows=module_metrics)
    return reports


def write_overview(folder, summary):
    """Publish module scores plus exact run inventory; a code percentage is not functional closure."""
    lines = ['# DUT code coverage', '', 'Only Line / Condition / Branch / FSM / Toggle. No assertion/group score, no manual line or bin waivers.', '',
             '| Module / scope | Line | Cond | Branch | FSM | Toggle |', '| --- | --- | --- | --- | --- | --- |']
    links = []
    for module,reports in summary.get('reports',{}).items():
        for variant,record in reports.items():
            if not isinstance(record,dict) or record.get('status')!='COMPLETE': continue
            metrics = record['metrics'];values=[]
            for name in METRICS:
                item=metrics[name]
                values.append('N/A (0)' if item['percent'] is None else f"{item['percent']:.2f}% ({item['covered']}/{item['total']})")
            lines.append('| '+module+'/'+variant+' | '+' | '.join(values)+' |')
            links.append(f"{module}/{variant}: [HTML]({Path(record['html']).relative_to(folder)}) · [text]({Path(record['text']).relative_to(folder)})")
    passed=sum(row['status']=='PASS' for row in summary['results'])
    lines += [''] + links
    lines += ['',f"Simulation PASS {passed}/{len(summary['results'])}; complete={summary['complete']}", '',
              'DCache self_rtl includes DCache/CacheMem/MSHR/WBB, excludes official StreamFifo module implementations. whole_dut includes them.',
              'Independent IP results are never used to fill gaps in DCache integration results.', '', '| Test tag | Result | Log |', '| --- | --- | --- |']
    for row in summary['results']:
        lines.append(f"| {row['tag']} | {row['status']} | [log]({Path(row['log']).relative_to(folder)}) |")
    (folder/'summary.md').write_text('\n'.join(lines)+'\n')


def print_scores(summary):
    """Color full/partial/N-A scores without inventing a coverage acceptance threshold."""
    print('\nDUT CODE COVERAGE REPORT')
    print(f"{'Scope':<25} {'Line':>10} {'Condition':>10} {'Branch':>10} {'FSM':>10} {'Toggle':>10}")
    for module, reports in summary.get('reports', {}).items():
        record = reports.get('self_rtl', {})
        if record.get('status') != 'COMPLETE':
            print(f'\033[1;31m{module}: report unavailable\033[0m')
            continue
        fields = []
        for metric in METRICS:
            item = record['metrics'][metric]
            value = 'N/A' if item['percent'] is None else f"{item['percent']:.2f}%"
            color = '90' if item['percent'] is None else '32' if item['covered'] == item['total'] else '33'
            fields.append(f'\033[1;{color}m{value:>10}\033[0m')
        print(f'{module+"/self_rtl":<25} '+ ' '.join(fields))


def main():
    """Generate fresh RTL, instrument only DUT trees, collect all selected cases and report clean data."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--modules',nargs='+',choices=TOPS,default=list(TOPS))
    parser.add_argument('--periods',nargs='+',type=float,default=[10])
    parser.add_argument('--seeds',nargs='+',type=int,default=[1,2,3])
    parser.add_argument('--skip-long',action='store_true')
    parser.add_argument('--tests',nargs='+',help='Optional exact test-name filter')
    parser.add_argument('--waves',action='store_true',help='Dump FSDB per simulation; code coverage itself does not need wave dumping')
    parser.add_argument('--timeout',type=int,default=600)
    args=parser.parse_args()
    if any(period<=0 for period in args.periods): raise RuntimeError('Periods must be positive')
    plans=[p for p in inventory(args.periods,args.seeds,not args.skip_long) if p['module'] in args.modules and (not args.tests or p['test'] in args.tests)]
    if not plans: raise RuntimeError('No tests selected')
    folder=Path(__file__).resolve().parent/'work'/datetime.now().strftime('run_%Y%m%d_%H%M%S')
    folder.mkdir(parents=True)
    summary=dict(complete=False,scope='DUT code only',metrics=METRICS,plans=plans,builds={},results=[],reports={})
    print(f'CODE COVERAGE: {folder}; simulations={len(plans)}',flush=True)
    for module in args.modules:
        if not any(plan['module']==module for plan in plans): continue
        code=execute(['make','generate'],ENV/f'sim_{module}',folder/f'{module}_generate.log')
        if code: raise RuntimeError(f'RTL generation failed for {module}')
    inputs=source_hashes()
    (folder/'inputs.json').write_text(json.dumps(inputs,indent=4)+'\n')
    for module,profile in dict.fromkeys((p['module'],p['profile']) for p in plans):
        print('BUILD',module,profile,flush=True)
        summary['builds'][module+'/'+profile]=compile_profile(folder,module,profile)
        save(folder,summary)
    for index,plan in enumerate(plans,1):
        row=simulate(folder,summary['builds'][plan['module']+'/'+plan['profile']],plan,args.waves,args.timeout)
        if source_hashes()!=inputs:
            row['status']='FAIL';row['reasons'].append('source changed during collection')
        summary['results'].append(row)
        print(f"[{index}/{len(plans)}] \033[1;{'32' if row['status']=='PASS' else '31'}m{row['status']}\033[0m {row['tag']}",flush=True)
        if row.get('errors'):print('  '+row['errors'][0],flush=True)
        save(folder,summary)
    for module in args.modules:
        print('URG MERGE',module,flush=True)
        summary['reports'][module]=report_module(folder,module,summary['builds'],summary['results'])
        save(folder,summary)
    summary['complete']=True
    save(folder,summary);write_overview(folder,summary)
    print_scores(summary)
    passed=sum(row['status']=='PASS' for row in summary['results'])
    print(f'SIMULATION PASS {passed}/{len(plans)} Report: {folder / "summary.md"}',flush=True)
    return 0 if passed==len(plans) and all(summary['reports'][m].get('self_rtl',{}).get('status')=='COMPLETE' for m in args.modules if any(p['module']==m for p in plans)) else 1


if __name__=='__main__':
    raise SystemExit(main())
