#!/usr/bin/env python3
"""编译并检查MSHR空态/基础读写框架；结果以UVM、计数和波形共同判定。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from datetime import datetime

SIM = Path(__file__).resolve().parents[1]
ROOT = SIM.parents[1]


def execute(command, output, timeout):
    """保存完整命令输出，超时也返回失败，避免把不完整日志判成通过。"""
    with output.open("w") as stream:
        try:
            return subprocess.run(command, cwd=SIM, stdout=stream, stderr=subprocess.STDOUT,
                                  timeout=timeout, check=False).returncode
        except subprocess.TimeoutExpired:
            stream.write("\nMSHR_FRAMEWORK_PROCESS_TIMEOUT\n")
            return 124


def assess(text, test, returncode):
    """忽略simv可能返回0的习惯，核对实际UVM错误、结束标记和精确事件数量。"""
    reasons = []
    if returncode != 0:
        reasons.append(f"process exit {returncode}")
    for severity in ("WARNING", "ERROR", "FATAL"):
        values = re.findall(rf"^UVM_{severity}\s*:\s*(\d+)\s*$", text, re.M)
        if len(values) != 1 or int(values[0]) != 0:
            reasons.append(f"UVM_{severity} summary missing or nonzero")
    if re.search(r"^UVM_(?:ERROR|FATAL)\b(?!\s*:)", text, re.M):
        reasons.append("actual UVM error/fatal line")
    if re.search(r"^Error(?:-|:)", text, re.M):
        reasons.append("simulator error")
    if "[MSHR_TEST_PASS] MSHR framework checks passed" not in text or "[MSHR_TEST_FAIL]" in text:
        reasons.append("missing success marker or present failure marker")
    match = re.search(r"\[MSHR_COUNTS\] cycles=(\d+) alloc=(\d+) merge=(\d+) send=(\d+) "
                      r"response=(\d+) fill=(\d+) replay=(\d+) release=(\d+)", text)
    counts = dict(zip(("cycles", "alloc", "merge", "send", "response", "fill", "replay", "release"),
                      map(int, match.groups()))) if match else {}
    n = 2 if test == "mshr_smoke_test" else 0
    if not counts or counts["cycles"] <= 0 or counts.get("merge") != 0 or any(
            counts.get(k) != n for k in ("alloc", "send", "response", "fill", "replay", "release")):
        reasons.append("event counts did not meet this test's requirements")
    if n and "[MSHR_SMOKE_COVERAGE] read=1 write=1 fills_checked=2 external_memory_unchanged=2" not in text:
        reasons.append("missing smoke data coverage")
    return reasons, counts


def input_hashes():
    """记录真实RTL、SV、DPI和原有C++模型源码版本，便于重现本次结果。"""
    paths = list((ROOT / "verif_mshr/src/mshr").rglob("*.sv"))
    paths += list((ROOT / "verif_mshr/src/mshr").rglob("*.svh"))
    paths += list((ROOT / "verif_mshr/src/common").rglob("*.sv*"))
    paths += list((ROOT / "verif_mshr/test/mshr").glob("*.sv"))
    paths += [ROOT / p for p in (
        "verif_mshr/tb/mshr_tb_top.sv", "verif_mshr/generated/mshr/Mshr.v",
        "verif_mshr/generated/mshr/mshr_params_pkg.sv", "verif_mshr/dpi/mshr_dpi.cpp",
        "verif_mshr/dpi/mshr_dpi.h", "RefModel/Cache/MSHR.hpp", "RefModel/Cache/params.hpp",
        "RefModel/MEM/SparseMemory.hpp", "verif_mshr/sim_mshr/Makefile",
        "verif_mshr/sim_mshr/dut.f", "verif_mshr/sim_mshr/tb.f")]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(paths))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--color", choices=("auto", "always", "never"), default="auto")
    args = parser.parse_args()
    colored = args.color == "always" or (args.color == "auto" and sys.stdout.isatty()
                                        and "NO_COLOR" not in os.environ and os.environ.get("TERM") != "dumb")

    def paint(value, color):
        return f"\033[{color}m{value}\033[0m" if colored else value

    run_id = "run_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    directory = SIM / "work/framework" / run_id
    directory.mkdir(parents=True)
    hashes = input_hashes()
    (directory / "inputs.json").write_text(json.dumps(hashes, indent=4) + "\n")
    print(paint("MSHR framework verification", "36;1"), flush=True)
    print("Compiling default MSHR configuration ...", flush=True)
    compile_command = ["make", "vcs_compile", f"VCS_COMP_LOG={directory / 'compile.log'}"]
    compile_code = execute(compile_command, directory / "compile.stdout.log", 300)
    rows = []
    started = time.monotonic()
    if compile_code == 0:
        for test in ("mshr_base_test", "mshr_smoke_test"):
            for period in (10, 4):
                tag = f"{test}_p{period}_s1"
                log = directory / f"{tag}.log"
                wave = directory / f"{tag}.fsdb"
                tcl = directory / f"{tag}.tcl"
                # base故意不传UVM_TESTNAME，验证无testname的默认启动入口。
                command = ["make", "vcs_simulate", f"TEST_NAME={'' if test == 'mshr_base_test' else test}",
                           f"SIM_ARGS=+CLOCK_PERIOD_NS={period} +ntb_random_seed=1",
                           f"VCS_SIM_LOG={log}", f"WAVEFORM={wave}", f"DUMP_TCL={tcl}"]
                code = execute(command, directory / f"{tag}.stdout.log", 120)
                text = log.read_text(errors="replace") if log.exists() else ""
                reasons, counts = assess(text, test, code)
                if not wave.exists() or wave.stat().st_size == 0:
                    reasons.append("missing or empty FSDB")
                if f"period_ns={period:.3f}" not in text or "reset=ASYNC_LOW" not in text:
                    reasons.append("clock/reset configuration marker mismatch")
                if input_hashes() != hashes:
                    reasons.append("input source changed during this run")
                rows.append(dict(test=test, period_ns=period, seed=1, passed=not reasons,
                                 exit_code=code, reasons=reasons, counts=counts, command=command,
                                 log=str(log), wave=str(wave)))
    passed = compile_code == 0 and len(rows) == 4 and all(r["passed"] for r in rows)
    summary = dict(run_id=run_id, passed=passed, compile_exit_code=compile_code,
                   compile_command=compile_command, results=rows,
                   elapsed_seconds=round(time.monotonic() - started, 2))
    (directory / "summary.json").write_text(json.dumps(summary, indent=4) + "\n")
    md = ["# MSHR framework verification", "", f"Run: `{run_id}`", "",
          "| Test | Period (ns) | Result | Events alloc/merge/send/response/fill/replay/release | Log |",
          "| --- | --- | --- | --- | --- |"]
    print("\n  Test                       Clock   Result   Events (A/M/S/R/F/P/E)")
    print("  " + "─" * 72)
    for row in rows:
        status = "PASS" if row["passed"] else "FAIL"
        counts = row["counts"]
        events = "/".join(str(counts.get(k, "?")) for k in ("alloc", "merge", "send", "response", "fill", "replay", "release"))
        print(f"  {row['test']:<26} {row['period_ns']:>2} ns   {paint(status, '32;1' if row['passed'] else '31;1')}     {events}")
        if row["reasons"]:
            print("    " + "; ".join(row["reasons"]))
        md.append(f"| {row['test']} | {row['period_ns']} | {status} | {events} | [{Path(row['log']).name}]({Path(row['log']).name}) |")
    if compile_code != 0:
        print(paint("  FAIL: compilation did not complete", "31;1"))
    count = sum(r["passed"] for r in rows)
    print(paint(f"\n  {'PASS' if passed else 'FAIL'}  {count}/4 runs passed", "32;1" if passed else "31;1"))
    print(f"  Report: {directory / 'summary.md'}")
    md += ["", f"Result: {'PASS' if passed else 'FAIL'}, {count}/4 runs passed.", "",
           "Default base performs idle startup checks; smoke performs one read and one write lifecycle.",
           "This report does not close the complete MSHR IP verification plan."]
    (directory / "summary.md").write_text("\n".join(md) + "\n")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
