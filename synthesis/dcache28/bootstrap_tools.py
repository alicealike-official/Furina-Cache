#!/usr/bin/env python3
"""Download and locally extract Debian synthesis tools without system installation."""
import argparse
from pathlib import Path
import subprocess


def main():
    """Keep packages and extracted tools under one user-writable temporary directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('/tmp/furina-synth-tools'))
    args = parser.parse_args()
    root = args.root.resolve()
    packages = root / 'debs'
    packages.mkdir(parents=True, exist_ok=True)
    subprocess.run(['apt-get', 'download', 'yosys', 'yosys-abc', 'opensta'], cwd=packages, check=True)
    for package in sorted(packages.glob('*.deb')):
        subprocess.run(['dpkg-deb', '-x', str(package), str(root / 'root')], check=True)
    subprocess.run([str(root / 'root/usr/bin/yosys'), '-V'], check=True)
    subprocess.run([str(root / 'root/usr/bin/sta'), '-version'], check=True)


if __name__ == '__main__':
    main()
