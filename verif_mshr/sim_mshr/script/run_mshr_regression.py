#!/usr/bin/env python3
"""运行MSHR独立IP功能回归，保留失败，不修改DUT或为失败设置豁免。"""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import sys
import time

from run_mshr_framework import execute, input_hashes

SIM = Path(__file__).resolve().parents[1]
CASE_NAMES = (
    "smoke", "query", "entry_capacity", "slot_capacity", "merge_matrix", "data_pattern",
    "read_view", "entry_slot_sweep", "send_backpressure", "send_arbitration", "response_order",
    "response_latency", "fill_backpressure", "fill_arbitration", "replay_backpressure",
    "replay_arbitration", "lock", "reuse", "event_collision", "idle_payload", "random", "long_run",
)
TESTS = tuple(f"mshr_{name}_test" for name in CASE_NAMES)
COUNT_NAMES = ("cycles", "alloc", "merge", "send", "response", "fill", "replay", "release")


def assess(text, code, test):
    """检查真实错误行、结束标记和事件守恒；失败不会因simv退出码为0而被忽略。"""
    reasons = []
    if code != 0:
        reasons.append(f"process exit {code}")
    severities = {}
    for severity in ("WARNING", "ERROR", "FATAL"):
        values = re.findall(rf"^UVM_{severity}\s*:\s*(\d+)\s*$", text, re.M)
        severities[severity] = int(values[-1]) if values else None
        if severities[severity] != 0:
            reasons.append(f"UVM_{severity} missing or nonzero")
    errors = re.findall(r"^UVM_(?:ERROR|FATAL)\b(?!\s*:).*", text, re.M)
    if errors or re.search(r"^\s*(?:Error|Fatal)-\[", text, re.M):
        reasons.append("actual error/fatal lines")
    if "[MSHR_TEST_PASS]" not in text or "[MSHR_TEST_FAIL]" in text:
        reasons.append("missing PASS or present FAIL marker")
    matches = re.findall(r"\[MSHR_COUNTS\] cycles=(\d+) alloc=(\d+) merge=(\d+) send=(\d+) "
                         r"response=(\d+) fill=(\d+) replay=(\d+) release=(\d+)", text)
    counts = dict(zip(COUNT_NAMES, map(int, matches[-1]))) if matches else {}
    if not counts or counts["alloc"] == 0 or any(counts.get(key) != counts["alloc"]
            for key in ("send", "response", "fill", "release")) or counts["alloc"] + counts["merge"] != counts["replay"]:
        reasons.append("missing or inconsistent event counts")
    coverage = re.findall(r"^UVM_INFO .*?\[(MSHR_[^]]*COVERAGE)\]\s*(.*)$", text, re.M)
    marker = "MSHR_SMOKE_COVERAGE" if test == "mshr_smoke_test" else "MSHR_SCENARIO_COVERAGE"
    if not any(identifier == marker for identifier, _ in coverage):
        reasons.append("case completion evidence missing")
    return dict(reasons=reasons, counts=counts, severities=severities, errors=errors[:10], coverage=coverage)


def save_report(directory, summary):
    """每个组合结束就保存报告；Markdown保留独立log和波形链接，终端颜色不写入文件。"""
    (directory / "summary.json").write_text(json.dumps(summary, indent=4, ensure_ascii=False) + "\n")
    rows = ["# MSHR IP regression", "", f"Run: `{summary['run_id']}`", "",
            "| Test | Clock ns | Seed | Result | A/M/S/R/F/P/E | Log | Wave |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for row in summary["results"]:
        counts = "/".join(str(row["counts"].get(key, "-")) for key in COUNT_NAMES[1:])
        rows.append(f"| {row['test']} | {row['period_ns']} | {row['seed']} | {row['status']} | {counts} | "
                    f"[log]({Path(row['log']).name}) | [FSDB]({Path(row['wave']).name}) |")
    passed = sum(row["status"] == "PASS" for row in summary["results"])
    rows += ["", f"PASS={passed}/{summary['planned_runs']}; complete={summary['complete']}.", "",
             "Failures remain failures. This run does not exercise reset or unconfirmed interface extensions."]
    (directory / "summary.md").write_text("\n".join(rows) + "\n")


def main():
    """先编译，再逐个case运行；某个case失败后继续独立组合，最后打印彩色总表与首错。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tests", nargs="+", choices=TESTS, default=list(TESTS[:-1]))
    parser.add_argument("--periods", nargs="+", type=int, choices=(4, 10), default=[10, 4])
    parser.add_argument("--seeds", nargs="+", type=int, default=[1, 2, 3])
    parser.add_argument("--skip-compile", action="store_true")
    parser.add_argument("--max-errors", type=int, default=10, help="UVM错误终止阈值；0保留报错并运行到case结束")
    parser.add_argument("--color", choices=("auto", "always", "never"), default="auto")
    args = parser.parse_args()
    colored = args.color == "always" or (args.color == "auto" and sys.stdout.isatty() and "NO_COLOR" not in os.environ)

    def paint(text, status):
        codes = {"PASS": "1;32", "FAIL": "1;31", "NOT RUN": "1;33", "BUILD": "1;36"}
        return f"\033[{codes[status]}m{text}\033[0m" if colored else text

    started = time.monotonic()
    run_id = "run_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    directory = SIM / "work/regression" / run_id
    directory.mkdir(parents=True)
    hashes = input_hashes()  # 仅计算文件哈希留档，不解析或展示DUT实现。
    (directory / "inputs.json").write_text(json.dumps(hashes, indent=4) + "\n")
    build_dir = SIM / "work/regression/build"
    build_command = ["make", "vcs_compile", f"WORK_DIR={build_dir}", f"VCS_COMP_LOG={directory / 'compile.log'}"]
    print(paint("BUILD MSHR independent IP cases", "BUILD"), flush=True)
    code = 0 if args.skip_compile else execute(build_command, directory / "compile.stdout.log", 600)
    plans = [(test, period, seed) for test in args.tests for period in args.periods
             for seed in (args.seeds if test in ("mshr_random_test", "mshr_long_run_test") else [1])]
    summary = dict(run_id=run_id, planned_runs=len(plans), complete=False, compile_exit_code=code,
                   compile_command=build_command, results=[])
    for test, period, seed in plans:
        tag = f"{test}_p{period}_s{seed}"
        log = directory / f"{tag}.log"
        wave = directory / f"{tag}.fsdb"
        command = ["make", "vcs_simulate", f"WORK_DIR={build_dir}", f"TEST_NAME={test}",
                   f"SIM_ARGS=+CLOCK_PERIOD_NS={period} +ntb_random_seed={seed} +UVM_MAX_QUIT_COUNT={args.max_errors},NO",
                   f"VCS_SIM_LOG={log}", f"WAVEFORM={wave}", f"DUMP_TCL={directory / (tag + '.tcl')}"]
        result = dict(test=test, period_ns=period, seed=seed, command=command, log=str(log), wave=str(wave))
        if code != 0:
            result.update(status="NOT RUN", reasons=["compile failed"], counts={}, errors=[], coverage=[])
        else:
            result_code = execute(command, directory / f"{tag}.stdout.log", 300)
            text = log.read_text(errors="replace") if log.exists() else ""
            result.update(assess(text, result_code, test))
            if not wave.is_file() or wave.stat().st_size == 0:
                result["reasons"].append("missing FSDB")
            if input_hashes() != hashes:
                result["reasons"].append("source changed during run")
            result["status"] = "PASS" if not result["reasons"] else "FAIL"
        summary["results"].append(result)
        save_report(directory, summary)
        print(paint(f"[{result['status']}]", result["status"]), test, f"{period}ns seed={seed}", flush=True)
    summary["complete"] = True
    summary["elapsed_seconds"] = round(time.monotonic() - started, 2)
    save_report(directory, summary)
    print("\n  MSHR REGRESSION REPORT\n  " + "─" * 96)
    for row in summary["results"]:
        events = "/".join(str(row["counts"].get(key, "-")) for key in COUNT_NAMES[1:])
        print(f"  {row['test']:<36} {row['period_ns']:>2}ns  seed={row['seed']:<3} "
              f"{paint(row['status'], row['status'])}  {events}")
    passed = sum(row["status"] == "PASS" for row in summary["results"])
    status = "PASS" if passed == len(plans) else "FAIL"
    print(paint(f"\n  {status}: {passed}/{len(plans)} passed; elapsed {summary['elapsed_seconds']}s", status))
    for row in summary["results"]:
        if row["status"] != "PASS":
            print(paint(f"  {row['test']} {row['period_ns']}ns seed={row['seed']}: " + "; ".join(row["reasons"]), "FAIL"))
            print("    " + (row["errors"][0] if row["errors"] else "See compile/process log"))
            print("    " + row["log"])
    print(f"  Report: {directory / 'summary.md'}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
