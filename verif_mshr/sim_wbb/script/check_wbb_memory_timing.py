#!/usr/bin/env python3
"""使用真实 memory driver 自检周期延迟，不编译或实例化 WBB DUT。"""

from pathlib import Path
import re
import subprocess
import sys


SIM_DIR = Path(__file__).resolve().parents[1]
WORK = SIM_DIR / "work" / "memory_timing"
LOG = WORK / "log"
SIMV = WORK / "run" / "simv"


def run_tool(command, name):
    """单独保存工具输出；失败时显示末尾诊断，避免把编译或许可证错误当成通过。"""
    output = LOG / f"{name}.stdout.log"
    with output.open("w") as handle:
        result = subprocess.run(command, cwd=SIM_DIR, stdout=handle,
                                stderr=subprocess.STDOUT, timeout=180)
    if result.returncode != 0:
        raise RuntimeError(f"{name} exited with {result.returncode}:\n" +
                           "\n".join(output.read_text(errors="replace").splitlines()[-35:]))


def compile_harness():
    """编译现有包、monitor、memory driver 和 C++ DPI，使用独立的编译与运行目录。"""
    uvm = SIM_DIR / "../../verif_env/uvm-1.2/src"
    command = [
        "vcs", "-full64", "-sverilog", "-timescale=1ns/1ps",
        f"+incdir+{uvm}", "+incdir+../src/common/pkg",
        "+incdir+../src/common/config", "+incdir+../src/common/component",
        "+incdir+../src/wbb", str(uvm / "uvm.sv"), str(uvm / "dpi/uvm_dpi.cc"),
        "../generated/wbb/wbb_params_pkg.sv", "../src/common/interface/clk_rst_interface.sv",
        "../src/wbb/interface/wbb_interface.sv", "../src/common/pkg/clk_rst_pkg.sv",
        "../src/wbb/pkg/wbb_pkg.sv", "../test/adapter/wbb_memory_timing_check.sv",
        "../dpi/wbb_dpi.cpp", "-CFLAGS", "-DVCS -std=c++17",
        "-top", "wbb_memory_timing_check", f"-Mdir={WORK / 'csrc'}",
        "-o", str(SIMV), "-l", str(LOG / "compile.log"),
    ]
    run_tool(command, "compile")
    if re.search(r"^Error-", (LOG / "compile.log").read_text(errors="replace"), re.MULTILINE):
        raise RuntimeError("VCS reported a compile error; see memory_timing/log/compile.log")


def run_case(period, latency, reject_zero=False):
    """正常场景要求明确成功标记和零错误；零拍负例只接受 driver 的 MEM_CONFIG fatal。"""
    name = f"period_{period}_latency_{latency}"
    path = LOG / f"{name}.log"
    run_tool([str(SIMV), f"+MEM_TIMING_PERIOD_NS={period}",
              f"+MEM_TIMING_LATENCY_CYCLES={latency}", "-l", str(path)], name)
    text = path.read_text(errors="replace")
    if reject_zero:
        if not re.search(r"^UVM_FATAL .*\[MEM_CONFIG\]", text, re.MULTILINE):
            raise RuntimeError(f"{name}: zero-cycle setting was not rejected by MEM_CONFIG")
        if "[MEMORY_TIMING_PASS]" in text or not re.search(r"UVM_ERROR\s*:\s*0\b", text):
            raise RuntimeError(f"{name}: unexpected result in zero-cycle negative test")
        fatal_ids = re.findall(r"^UVM_FATAL .*?\[([^]]+)\]", text, re.MULTILINE)
        if fatal_ids != ["MEM_CONFIG"]:
            raise RuntimeError(f"{name}: unexpected fatal reports: {fatal_ids}")
        print(f"PASS {name}: expected MEM_CONFIG rejection")
        return
    for severity in ["WARNING", "ERROR", "FATAL"]:
        if not re.search(rf"UVM_{severity}\s*:\s*0\b", text):
            raise RuntimeError(f"{name}: UVM_{severity} was not zero; see {path}")
    summary = re.search(r"\[MEMORY_TIMING_PASS\] (.*)", text)
    if not summary or f"latency_cycles={latency} " not in summary.group(1):
        raise RuntimeError(f"{name}: required pass marker is missing")
    if "requests=5 responses=5 exact_matches=3" not in summary.group(1):
        raise RuntimeError(f"{name}: required event counts were not met")
    print("PASS " + summary.group(1))


def main():
    """检查两种时钟周期和三个合法延迟值，再确认零拍延迟被拒绝。"""
    LOG.mkdir(parents=True, exist_ok=True)
    SIMV.parent.mkdir(parents=True, exist_ok=True)
    compile_harness()
    for period in [10, 4]:
        for latency in [1, 2, 32]:
            run_case(period, latency)
    run_case(10, 0, reject_zero=True)
    print("WBB_MEMORY_TIMING_CHECK_PASS: 6 normal runs and 1 expected-fatal run")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
