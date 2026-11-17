#!/usr/bin/env python3
"""Self-check IO assertions using synthetic traces; never compile a DUT filelist."""
from pathlib import Path
import os
import subprocess
import sys

sim = Path(__file__).resolve().parents[1]
env = sim.parent
repo = env.parent
uvm = Path(os.environ.get("UVM_HOME", str(repo / "verif_env/uvm-1.2"))).resolve()
checker = env / "src/wbb/bind/wbb_io_assertions.sv"
trace = env / "test/assertions/wbb_io_assertions_test.sv"
work = sim / "work/assertions"


def run(command, log):
    with log.open("w") as output:
        result = subprocess.run(command, cwd=sim, stdout=output, stderr=subprocess.STDOUT)
    text = log.read_text(errors="replace")
    if result.returncode:
        sys.exit(f"Failed: {' '.join(map(str, command))}\n{text[-6000:]}")
    return text


for profile in ("strict", "delayed", "bind"):
    folder = work / profile
    folder.mkdir(parents=True, exist_ok=True)
    binary = folder / "simv"
    command = ["vcs", "-full64", "-sverilog", "-timescale=1ns/1ps", "-Mdir=" + str(folder / "csrc"), "-o", str(binary)]
    if profile == "bind":
        command += ["+incdir+" + str(uvm / "src"), str(uvm / "src/uvm.sv"),
                    str(uvm / "src/dpi/uvm_dpi.cc"), "-CFLAGS", "-DVCS",
                    str(env / "generated/wbb_params_pkg.sv"),
                    str(env / "src/wbb/interface/wbb_interface.sv"), str(checker),
                    str(env / "src/wbb/bind/bind_wbb.sv"),
                    str(env / "test/assertions/wbb_bind_test.sv"), "-top", "tb_top"]
        marker = "WBB_SVA_BIND_PASS"
    else:
        command += ["+define+WBB_SVA_STANDALONE"]
        if profile == "delayed":
            command += ["+define+TEST_DELAYED_PUSH"]
        command += [str(checker), str(trace), "-top", "wbb_io_assertions_test"]
        marker = "WBB_SVA_SELFTEST_PASS"
    run(command, folder / "compile.log")
    text = run([str(binary)], folder / "run.log")
    if marker not in text:
        sys.exit(f"Missing success marker in {folder / 'run.log'}\n{text[-6000:]}")
    print(f"PASS {profile}: {folder / 'run.log'}")
print("SVA self-check complete. Negative traces intentionally emit assertion errors; no DUT was simulated.")
