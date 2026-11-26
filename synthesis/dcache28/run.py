#!/usr/bin/env python3
"""Map generated DCache RTL into local TSMC 28 HPC+ cells and run pre-layout STA."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path('/tmp/furina-synth-tools/root/usr/bin')


def fingerprint(path):
    """Record the actual input without copying foundry libraries into the project."""
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def execute(command, log, cwd):
    """Preserve full tool output and reject process failures."""
    with log.open('w') as stream:
        code = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT).returncode
    if code:
        raise RuntimeError(f'Tool exit {code}; see {log}')


def find_library(suffix):
    """Select one standard-Vt family and explicit voltage/temperature corner."""
    matches = sorted(Path('/home/alicealike/local/tsmc28/TSMC28/logic').rglob('*bwp40p140' + suffix + '.lib'))
    if len(matches) != 1:
        raise RuntimeError(f'Expected exactly one library for {suffix}, found {len(matches)}')
    return matches[0]


def write_synthesis(run, library, delay_ps):
    """Use real cell mapping for all storage; no SRAM blackboxes or area substitution."""
    (run / 'abc.constr').write_text('set_driving_cell BUFFD1BWP40P140\nset_load 10\n')
    script = f'''read_verilog DCache.rtl.v
hierarchy -check -top DCache
proc
opt
memory -nomap
tee -o memory.rpt stat
write_json memory.json
synth -top DCache -flatten -noabc
read_liberty -lib -ignore_miss_func {library}
dfflibmap -liberty {library}
abc -liberty {library} -constr abc.constr -D {delay_ps}
clean
delete t:$scopeinfo
check -assert
tee -o area.rpt stat -liberty {library}
tee -o area.json stat -json -liberty {library}
write_verilog -noattr -noexpr -simple-lhs DCache.mapped.v
write_json DCache.mapped.json
'''
    (run / 'synth.ys').write_text(script)


def write_sta(run, library, corner, period):
    """Constrain all ordinary IO and functional clock paths; reset is explicitly excluded."""
    script = f'''read_liberty {library}
read_verilog DCache.mapped.v
link_design DCache
create_clock -name core_clk -period {period:.9f} [get_ports clk]
set_clock_uncertainty 0.05 [get_clocks core_clk]
set_clock_transition 0.05 [get_clocks core_clk]
set inputs [get_ports {{cpu_valid cpu_payload_* cpuReadResp_ready cpuWriteResp_ready memReadReq_ready memWriteReq_ready memReadResp_valid memReadResp_payload_* memWriteResp_valid memWriteResp_payload_id}}]
set_input_delay 0.2 -clock core_clk $inputs
set_input_transition 0.05 $inputs
set_input_delay 0.0 -clock core_clk [get_ports resetn]
set_input_transition 0.05 [get_ports resetn]
set_output_delay 0.2 -clock core_clk [all_outputs]
set_load 0.01 [all_outputs]
set_false_path -from [get_ports resetn]
puts "CONSTRAINED_INPUT_BITS [llength $inputs]"
puts "OUTPUT_BITS [llength [all_outputs]]"
report_clock_properties
check_setup -verbose
report_checks -path_delay max -group_count 10 -endpoint_count 1 -format full_clock_expanded -digits 4
report_checks -from [all_registers -clock core_clk -clock_pins] -to [all_registers -data_pins] -path_delay max -group_count 5 -endpoint_count 1 -format full_clock_expanded -digits 4
report_worst_slack -digits 4
report_tns -digits 4
report_check_types -max_transition -all_violators
report_check_types -min_period -all_violators
write_sdc constraints_{corner}.sdc
exit
'''
    (run / f'sta_{corner}.tcl').write_text(script)


def main():
    """Save immutable inputs, map for the selected corner, and measure both TT and SS."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--frequency-mhz', type=float, default=700)
    parser.add_argument('--mapping-corner', choices=['tt', 'ss'], default='ss')
    parser.add_argument('--yosys', default=shutil.which('yosys') or str(TOOLS / 'yosys'))
    parser.add_argument('--sta', default=shutil.which('sta') or str(TOOLS / 'sta'))
    parser.add_argument('--resume', type=Path, help='Reuse a mapped run for STA without repeating mapping')
    args = parser.parse_args()
    if args.frequency_mhz <= 0:
        raise RuntimeError('Frequency must be positive')
    libs = {'tt': find_library('tt0p9v25c'), 'ss': find_library('ssg0p81v125c')}
    period = 1000.0 / args.frequency_mhz
    run = args.resume.resolve() if args.resume else Path(__file__).resolve().parent / 'work' / datetime.now().strftime('run_%Y%m%d_%H%M%S')
    run.mkdir(parents=True, exist_ok=bool(args.resume))
    source = ROOT / 'Design/DCacheMSHR/rtl/DCache.v'
    manifest = {
        'top': 'DCache', 'frequency_mhz': args.frequency_mhz, 'period_ns': period,
        'mapping_corner': args.mapping_corner, 'abc_delay_target_ps': int(period * 1000),
        'rtl': fingerprint(source), 'libraries': {k: fingerprint(v) for k, v in libs.items()},
        'clock_uncertainty_ns': 0.05, 'input_delay_ns': 0.2, 'output_delay_ns': 0.2,
        'input_transition_ns': 0.05, 'output_load_pf': 0.01,
        'wire_parasitics': 'none; pre-layout', 'clock_network': 'ideal',
        'memories': 'mapped to standard cells; no SRAM macros', 'reset_timing': 'false path from resetn',
        'yosys': args.yosys, 'sta': args.sta,
    }
    if args.resume:
        previous = json.loads((run / 'manifest.json').read_text())
        for key in ['rtl', 'libraries', 'frequency_mhz', 'mapping_corner']:
            if previous[key] != manifest[key]:
                raise RuntimeError(f'Cannot resume: {key} changed')
        if not (run / 'DCache.mapped.v').exists():
            raise RuntimeError('Cannot resume before mapping completed')
    else:
        shutil.copy2(source, run / 'DCache.rtl.v')
        (run / 'manifest.json').write_text(json.dumps(manifest, indent=4) + '\n')
        write_synthesis(run, libs[args.mapping_corner], manifest['abc_delay_target_ps'])
        print(f'SYNTH {args.frequency_mhz:g} MHz at {args.mapping_corner.upper()}: {run}', flush=True)
        execute([args.yosys, '-T', '-l', 'yosys.log', 'synth.ys'], run / 'synth.stdout.log', run)
    results = {}
    for corner, library in libs.items():
        write_sta(run, library, corner, period)
        print(f'STA {corner.upper()}', flush=True)
        execute([args.sta, '-no_init', '-exit', f'sta_{corner}.tcl'], run / f'timing_{corner}.rpt', run)
        report = (run / f'timing_{corner}.rpt').read_text()
        if re.search(r'^Error:', report, re.M):
            raise RuntimeError(f'STA reported errors; see timing_{corner}.rpt')
        slack = float(re.search(r'worst slack ([-\d.]+)', report).group(1))
        tns = float(re.search(r'^tns ([-\d.]+)', report, re.M).group(1))
        results[corner] = {'worst_setup_slack_ns': slack, 'tns_ns': tns, 'setup_met': slack >= 0}
        color = '32' if slack >= 0 else '31'
        status = 'SETUP MET' if slack >= 0 else 'SETUP VIOLATED'
        print(f'\033[1;{color}m{corner.upper()} {status}\033[0m WNS={slack:+.4f} ns TNS={tns:.4f} ns', flush=True)
    area = json.loads((run / 'area.json').read_text())['modules']['\\DCache']
    if any(k.startswith('$') for k in area['num_cells_by_type']):
        raise RuntimeError('Internal cells remain after technology mapping')
    summary = {'status': 'COMPLETE', 'frequency_mhz': args.frequency_mhz, 'period_ns': period,
               'mapping_corner': args.mapping_corner, 'area_library_units': area['area'],
               'cells': area['num_cells'], 'corners': results}
    (run / 'summary.json').write_text(json.dumps(summary, indent=4) + '\n')
    if fingerprint(source) != manifest['rtl']:
        raise RuntimeError('Source RTL changed during the run')
    print(f'Cell area: {area["area"]:.3f}; report: {run}', flush=True)
    return 0 if all(r['setup_met'] for r in results.values()) else 2


if __name__ == '__main__':
    raise SystemExit(main())
