#!/usr/bin/env python3
"""调用现有RTL生成入口，只核对公开端口；生成失败或复位接口不符时拒绝复制旧产物。"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT.parent / 'Design/DCacheMSHR'
OUTPUT = ROOT / 'generated/dcache'


def main():
    """生成成功后才同步RTL；不读取模块体、不修改设计，也不运行Spinal测试。"""
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with (OUTPUT / 'generate.log').open('w') as log:
        code = subprocess.run(['sbt', 'runMain furina.dcache.DCacheVerilog'], cwd=PROJECT,
                              stdout=log, stderr=subprocess.STDOUT).returncode
    if code != 0:
        print('FAIL: DCache RTL generation failed; see generated/dcache/generate.log')
        return 1
    source = PROJECT / 'rtl/DCache.v'
    # 仅解析模块端口声明；其余字节只用于复制和哈希。
    data = source.read_bytes()
    header = re.search(rb'module\s+DCache\s*\((.*?)\);', data, re.S)
    if not header:
        raise ValueError('DCache public port declaration missing')
    ports = [(direction.decode(), int(high or b'0') + 1, name.decode()) for direction, high, name in
             re.findall(rb'(input|output)\s+wire\s*(?:\[(\d+):0\])?\s*(\w+)', header[1])]
    expected = [tuple(port) for port in json.loads(Path(__file__).with_name('ports.json').read_text())]
    expected += [('input', 1, 'clk'), ('input', 1, 'resetn')]
    if set(ports) != set(expected):
        raise ValueError(f'Public IO mismatch: missing={sorted(set(expected) - set(ports))}; unexpected={sorted(set(ports) - set(expected))}. Reset polarity cannot be inferred from its port name.')
    (OUTPUT / 'DCache.v').write_bytes(data)
    (OUTPUT / 'manifest.json').write_text(json.dumps({'source': str(source),
        'sha256': hashlib.sha256(data).hexdigest(), 'ports': ports,
        'scope': 'fixed 32-bit CPU, 64-byte line, FIFO reference; parameter/policy contract must match'}, indent=4) + '\n')
    print('PASS: Generated RTL public IO matches DCache framework contract')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        raise SystemExit(1)
