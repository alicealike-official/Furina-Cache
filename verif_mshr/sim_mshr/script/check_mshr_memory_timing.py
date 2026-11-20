#!/usr/bin/env python3
"""运行MSHR内存代理自检；不实例化DUT，不使用主仿真的编译目录。"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


SIM_DIR = Path(__file__).resolve().parents[1]
WORK = SIM_DIR / "work" / "memory_timing"
LOG = WORK / "log"
SIMV = WORK / "run" / "simv"


def run_tool(command, name):
    """保存每次工具调用的独立输出，返回退出码，结果判断另检查UVM日志。"""
    path = LOG / f"{name}.stdout.log"
    with path.open("w") as handle:
        result = subprocess.run(command, cwd=SIM_DIR, stdout=handle,
                                stderr=subprocess.STDOUT, timeout=240)
    return result.returncode


def compile_harness():
    """只编译接口、真实UVM组件及C++适配，用独立顶层模拟内存读请求。"""
    uvm = SIM_DIR / "../../verif_env/uvm-1.2/src"
    command = [
        "vcs", "-full64", "-sverilog", "-timescale=1ns/1ps",
        f"+incdir+{uvm}", "+incdir+../src/common/pkg",
        "+incdir+../src/common/config", "+incdir+../src/common/component",
        "+incdir+../src/mshr", str(uvm / "uvm.sv"), str(uvm / "dpi/uvm_dpi.cc"),
        "../generated/mshr/mshr_params_pkg.sv", "../src/common/interface/clk_rst_interface.sv",
        "../src/mshr/interface/mshr_interface.sv", "../src/common/pkg/clk_rst_pkg.sv",
        "../src/mshr/pkg/mshr_pkg.sv", "../test/adapter/mshr_memory_timing_check.sv",
        "../dpi/mshr_dpi.cpp", "-CFLAGS", "-DVCS -std=c++17",
        "-top", "mshr_memory_timing_check", f"-Mdir={WORK / 'csrc'}",
        "-o", str(SIMV), "-l", str(LOG / "compile.log"),
    ]
    code = run_tool(command, "compile")
    text = (LOG / "compile.log").read_text(errors="replace") if (LOG / "compile.log").exists() else ""
    if code != 0 or re.search(r"^Error-", text, re.MULTILINE) or not SIMV.exists():
        tail = "\n".join((LOG / "compile.stdout.log").read_text(errors="replace").splitlines()[-40:])
        raise RuntimeError(f"VCS compile failed ({code}); see {LOG / 'compile.log'}\n{tail}")


def run_case(period, latency):
    """正常组要求5次响应及快照检查通过；零拍负例只接受配置错误fatal。"""
    name = f"period_{period}_latency_{latency}"
    path = LOG / f"{name}.log"
    # 防止工具启动失败时误读上一轮同名日志，尤其是预期fatal的负例。
    path.unlink(missing_ok=True)
    command = [str(SIMV), f"+MEM_TIMING_PERIOD_NS={period}",
               f"+MEM_TIMING_LATENCY_CYCLES={latency}", "-l", str(path)]
    code = run_tool(command, name)
    text = path.read_text(errors="replace") if path.exists() else ""
    expected_fatal = latency == 0
    failures = []
    summary = re.search(r"\[MSHR_MEMORY_TIMING_PASS\] (.*)", text)
    if expected_fatal:
        fatal_ids = re.findall(r"^UVM_FATAL .*?\[([^]]+)\]", text, re.MULTILINE)
        if fatal_ids != ["MSHR_MEM_CONFIG"] or summary:
            failures.append("zero-cycle configuration did not produce only the expected MSHR_MEM_CONFIG fatal")
        if not re.search(r"UVM_ERROR\s*:\s*0\b", text):
            failures.append("unexpected UVM_ERROR in the negative test")
    else:
        if code != 0:
            failures.append(f"simulator exited with {code}")
        for severity in ("WARNING", "ERROR", "FATAL"):
            if not re.search(rf"UVM_{severity}\s*:\s*0\b", text):
                failures.append(f"UVM_{severity} was not zero")
        if not summary or f"latency_cycles={latency} " not in summary.group(1):
            failures.append("required timing pass marker is missing")
        elif "requests=5 responses=5 exact_matches=3 snapshot_matches=5" not in summary.group(1):
            failures.append("required request, response, latency or snapshot counts were not met")
    return {
        "period_ns": period, "latency_cycles": latency, "expected_fatal": expected_fatal,
        "pass": not failures, "exit_code": code, "failure_reasons": failures,
        "summary": summary.group(1) if summary else "expected MSHR_MEM_CONFIG rejection" if not failures else "",
        "log": str(path), "command": command,
    }


def print_report(results, color):
    """在全部运行完成后显示彩色结果表，失败项附带原因和日志位置。"""
    enabled = color == "always" or color == "auto" and sys.stdout.isatty()

    def status_word(passed):
        value = "PASS" if passed else "FAIL"
        return f"\033[{32 if passed else 31}m{value}\033[0m" if enabled else value

    print("\nMSHR memory timing self-check")
    print("Period(ns)  Latency(cycles)  Kind             Result")
    print("----------------------------------------------------")
    for result in results:
        kind = "expected fatal" if result["expected_fatal"] else "normal"
        print(f"{result['period_ns']:>10}  {result['latency_cycles']:>15}  {kind:<15}  {status_word(result['pass'])}")
        if not result["pass"]:
            print("  " + "; ".join(result["failure_reasons"]))
            print("  " + result["log"])
    passed = sum(result["pass"] for result in results)
    print(f"\n{status_word(passed == len(results))}: {passed}/{len(results)}; summary: {WORK / 'summary.json'}")


def main():
    """编译后依次检查两种周期和三个合法延迟，再检查零拍配置被拒绝。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--color", choices=("auto", "always", "never"), default="auto")
    args = parser.parse_args()
    LOG.mkdir(parents=True, exist_ok=True)
    SIMV.parent.mkdir(parents=True, exist_ok=True)
    compile_harness()
    results = [run_case(period, latency) for period in (10, 4) for latency in (1, 2, 32)]
    results.append(run_case(10, 0))
    summary = {"normal_runs": 6, "negative_runs": 1, "pass": all(r["pass"] for r in results), "results": results}
    (WORK / "summary.json").write_text(json.dumps(summary, indent=4) + "\n")
    print_report(results, args.color)
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
