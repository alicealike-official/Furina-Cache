#!/usr/bin/env python3
"""Audit mapped artifacts and resolve critical register names from the exported netlist."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re


def timing_paths(text):
    """Extract actual STA paths, preserving cell increments and setup slack."""
    paths = []
    for block in re.findall(r'^Startpoint: (.*?)(?=^Startpoint:|^worst slack|\Z)', text, re.M | re.S):
        endpoint = re.search(r'^Endpoint: (\S+)', block, re.M)
        slack = re.search(r'^\s+([-\d.]+)\s+slack \((MET|VIOLATED)\)', block, re.M)
        arrival = re.search(r'^\s+([\d.]+)\s+data arrival time', block, re.M)
        required = re.search(r'^\s+([\d.]+)\s+data required time', block, re.M)
        if not all([endpoint, slack, arrival, required]):
            raise RuntimeError('Incomplete STA path')
        cells = []
        for match in re.finditer(r'^\s+([-\d.]+)\s+([-\d.]+)\s+[\^v]\s+(\S+)/(\S+)\s+\((\S+)\)', block, re.M):
            cells.append({'increment_ns': float(match[1]), 'arrival_ns': float(match[2]),
                          'instance': match[3], 'pin': match[4], 'cell': match[5]})
        paths.append({'startpoint': block.split()[0], 'endpoint': endpoint[1],
                      'slack_ns': float(slack[1]), 'data_arrival_ns': float(arrival[1]),
                      'data_required_ns': float(required[1]), 'cells': cells})
    return paths


def register_aliases(netlist, names):
    """Read instance pin connections from tool-generated netlist, not original RTL logic."""
    result = {}
    if not names:
        return result
    alternatives = '|'.join(re.escape(name) for name in names)
    pattern = r'^\s*(\w+) (' + alternatives + r')\s*\((.*?)\n  \);'
    for match in re.finditer(pattern, netlist, re.M | re.S):
        pins = dict(re.findall(r'\.(\w+)\((.*?)\)', match[3]))
        result[match[2]] = {'cell': match[1], 'pins': {k: v.strip().lstrip('\\') for k, v in pins.items()}}
    return result


def main():
    """Verify provenance and unconstrained constants, then save a reviewable path audit."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    args = parser.parse_args()
    run = args.run.resolve()
    manifest = json.loads((run / 'manifest.json').read_text())
    summary = json.loads((run / 'summary.json').read_text())
    source = Path(manifest['rtl']['path'])
    assert hashlib.sha256(source.read_bytes()).hexdigest() == manifest['rtl']['sha256']
    assert hashlib.sha256((run / 'DCache.rtl.v').read_bytes()).hexdigest() == manifest['rtl']['sha256']
    corners = {}
    all_names = set()
    for corner in ['tt', 'ss']:
        text = (run / f'timing_{corner}.rpt').read_text()
        assert not re.search(r'^Error:', text, re.M)
        paths = timing_paths(text)
        if not paths:
            raise RuntimeError('No timed paths reported')
        paths.sort(key=lambda path: path['slack_ns'])
        seen = set()
        unique = []
        for path in paths:
            pair = (path['startpoint'], path['endpoint'])
            if pair not in seen:
                seen.add(pair)
                unique.append(path)
                all_names.update(pair)
        corners[corner] = {'warnings': re.findall(r'^Warning:.*$', text, re.M), 'paths': unique}
    netlist = (run / 'DCache.mapped.v').read_text()
    aliases = register_aliases(netlist, all_names)
    del netlist
    for result in corners.values():
        for path in result['paths']:
            for key in ['startpoint', 'endpoint']:
                path[key + '_connection'] = aliases.get(path[key], {})
    mapped = json.loads((run / 'DCache.mapped.json').read_text())['modules']['DCache']
    constants = {}
    for name, port in mapped['ports'].items():
        if port['direction'] == 'output':
            for index, bit in enumerate(port['bits']):
                if isinstance(bit, str):
                    constants[name if len(port['bits']) == 1 else f'{name}[{index}]'] = bit
    for corner in ['tt', 'ss']:
        text = (run / f'timing_{corner}.rpt').read_text()
        match = re.search(r'Warning: There are \d+ unconstrained endpoints\.\n(.*?)(?=^Startpoint:|^Warning:|\Z)', text, re.M | re.S)
        endpoints = set(line.strip() for line in match[1].splitlines() if line.strip()) if match else set()
        if endpoints - set(constants):
            raise RuntimeError(f'Unconstrained nonconstant endpoints: {endpoints - set(constants)}')
        corners[corner]['unconstrained_endpoints_are_constants'] = True
        corners[corner]['unconstrained_endpoint_count'] = len(endpoints)
    types = collections.Counter(cell['type'] for cell in mapped['cells'].values())
    del mapped
    assert not any(name.startswith('$') for name in types)
    memory = json.loads((run / 'memory.json').read_text())
    arrays = collections.Counter()
    for module in memory['modules'].values():
        for cell in module['cells'].values():
            if cell['type'] == '$mem_v2':
                p = cell['parameters']
                arrays[(int(p['SIZE'], 2), int(p['WIDTH'], 2))] += 1
    audit = {'corner_paths': corners, 'constant_outputs': constants,
             'memory_arrays': [{'depth': k[0], 'width': k[1], 'count': v} for k, v in arrays.items()],
             'inferred_memory_bits': sum(depth * width * count for (depth, width), count in arrays.items()),
             'flip_flops': sum(count for name, count in types.items() if name.startswith(('DF', 'SDF'))),
             'standard_cell_count': sum(types.values())}
    (run / 'path_audit.json').write_text(json.dumps(audit, indent=4) + '\n')
    names = ['DCache.rtl.v', 'DCache.mapped.v', 'synth.ys', 'sta_tt.tcl', 'sta_ss.tcl',
             'constraints_tt.sdc', 'constraints_ss.sdc']
    (run / 'artifact_hashes.json').write_text(json.dumps({name: hashlib.sha256((run/name).read_bytes()).hexdigest() for name in names}, indent=4) + '\n')
    for corner, result in corners.items():
        path = result['paths'][0]
        print(corner.upper(), 'WNS', summary['corners'][corner]['worst_setup_slack_ns'],
              path['startpoint_connection'].get('pins', {}).get('Q', path['startpoint']), '->',
              path['endpoint_connection'].get('pins', {}).get('Q', path['endpoint']))
    print('Audit:', run / 'path_audit.json')


if __name__ == '__main__':
    main()
