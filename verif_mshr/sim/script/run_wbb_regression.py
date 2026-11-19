#!/usr/bin/env python3
"""按验证计划顺序运行 WBB case，保留所有失败；不运行 pipeline case，也不修改 DUT。"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


SIM_DIR = Path(__file__).resolve().parents[1]
REGRESSION_DIR = SIM_DIR / "work" / "regression"
DUT_FILE = SIM_DIR.parent / "generated" / "WriteBackBuffer.v"
COVERAGE = "line+cond+fsm+branch+tgl+assert"
TEST_ORDER = (
    "wbb_base_test",
    "wbb_data_pattern_test",
    "wbb_capacity_test",
    "wbb_query_test",
    "wbb_reuse_test",
    "wbb_send_backpressure_test",
    "wbb_arbitration_test",
    "wbb_response_order_test",
    "wbb_event_collision_test",
    "wbb_delayed_push_test",
    "wbb_random_test",
)
COUNTER_PATTERN = re.compile(
    r"\bcycles=(\d+) reserve=(\d+) push=(\d+) send=(\d+) "
    r"response=(\d+) full_cycles=(\d+) stalled_cycles=(\d+)"
)
COUNTER_NAMES = ("cycles", "reserve", "push", "send", "response", "full_cycles", "stalled_cycles")


def result_status(result):
    """将已运行的通过/失败与因编译失败等原因未运行的组合分开显示。"""
    if result.get("status") == "NOT_RUN":
        return "NOT RUN"
    return "PASS" if result.get("pass") else "FAIL"


class TerminalReport:
    """只为终端添加颜色和表格，不把ANSI字符写入日志、JSON或Markdown。"""

    STYLES = {"PASS": "1;32", "FAIL": "1;31", "NOT RUN": "1;33",
              "INCOMPLETE": "1;33", "BUILD": "1;36", "WARN": "1;33",
              "title": "1;36", "dim": "2", "bold": "1"}

    def __init__(self, color="auto", stream=None):
        self.stream = sys.stdout if stream is None else stream
        self.color = color == "always" or (
            color == "auto" and self.stream.isatty() and
            os.environ.get("TERM") != "dumb" and "NO_COLOR" not in os.environ
        )
        self.width = shutil.get_terminal_size(fallback=(110, 24)).columns
        self.unicode = True
        try:
            "┌─┬┐│├┼┤└┴┘".encode(getattr(self.stream, "encoding", None) or "utf-8")
        except (LookupError, UnicodeEncodeError):
            self.unicode = False

    def paint(self, value, style):
        """先得到普通文本，再按语义着色；每段结束都恢复终端原色。"""
        text = str(value)
        return f"\033[{self.STYLES[style]}m{text}\033[0m" if self.color else text

    def emit(self, text=""):
        """及时刷新输出，长时间编译或回归过程中也能看到进度。"""
        print(text, file=self.stream, flush=True)

    def progress(self, status, message):
        """逐项输出彩色状态；失败原因和完整日志路径放到最终报告中集中列出。"""
        self.emit(f"{self.paint(f'[{status}]', status)} {message}")

    def table(self, results):
        """按普通文本计算列宽后再着色；较窄终端省略事件数和profile列。"""
        columns = [("result", "Result"), ("test", "Test"), ("profile", "Mode"),
                   ("period", "ns"), ("seed", "Seed"), ("events", "R/P/S/A"), ("uvm", "W/E/F")]
        rows = []
        styles = []
        for result in results:
            counts = result.get("counts", {})
            severity = result.get("severity_counts", {})
            status = result_status(result)
            rows.append({"result": status, "test": str(result.get("test", "-")),
                         "profile": str(result.get("profile", "-")),
                         "period": period_text(result["period_ns"]) if "period_ns" in result else "-",
                         "seed": str(result.get("seed", "-")),
                         "events": "/".join(str(counts.get(name, "-")) for name in
                                            ("reserve", "push", "send", "response")),
                         "uvm": "/".join(str(severity.get(name)) if severity.get(name) is not None else "-"
                                          for name in ("WARNING", "ERROR", "FATAL"))})
            styles.append("FAIL" if (severity.get("ERROR") or severity.get("FATAL")) else
                          "WARN" if severity.get("WARNING") else "dim")
        widths = {key: max([len(title)] + [len(row[key]) for row in rows]) for key, title in columns}
        for optional in ("profile", "events"):
            if sum(widths[key] + 3 for key, _ in columns) + 1 > self.width:
                columns = [(key, title) for key, title in columns if key != optional]
        if self.unicode:
            top, middle, bottom, vertical = ("┌", "┬", "┐"), ("├", "┼", "┤"), ("└", "┴", "┘"), "│"
            horizontal = "─"
        else:
            top = middle = bottom = ("+", "+", "+")
            vertical, horizontal = "|", "-"

        def border(parts):
            """生成表格边框，不受单元格中的颜色转义长度影响。"""
            return parts[0] + parts[1].join(horizontal * (widths[key] + 2) for key, _ in columns) + parts[2]

        self.emit(self.paint(border(top), "dim"))
        self.emit(vertical + vertical.join(" " + self.paint(title.ljust(widths[key]), "bold") + " "
                                           for key, title in columns) + vertical)
        self.emit(self.paint(border(middle), "dim"))
        for row, uvm_style in zip(rows, styles):
            cells = []
            for key, _ in columns:
                value = row[key].rjust(widths[key]) if key in ("period", "seed", "events", "uvm") else row[key].ljust(widths[key])
                if key == "result":
                    value = self.paint(value, row[key])
                elif key == "uvm":
                    value = self.paint(value, uvm_style)
                cells.append(" " + value + " ")
            self.emit(vertical + vertical.join(cells) + vertical)
        self.emit(self.paint(border(bottom), "dim"))

    def summary(self, summary, report_path):
        """打印最终结果、失败详情和报告位置；未完成或未运行的组合不会被当成通过。"""
        results = summary.get("results", [])
        total = max(summary.get("planned_runs", len(results)), len(results))
        passed = sum(result_status(row) == "PASS" for row in results)
        failed = sum(result_status(row) == "FAIL" for row in results)
        not_run = sum(result_status(row) == "NOT RUN" for row in results)
        pending = total - len(results)
        warning_runs = sum(bool(row.get("severity_counts", {}).get("WARNING")) for row in results)
        complete = summary.get("complete", False)
        status = "INCOMPLETE" if not complete else "FAIL" if failed or not_run or pending or not total else "PASS"
        self.emit()
        self.emit(self.paint("  WBB REGRESSION REPORT", "title"))
        self.emit(f"  Run: {summary.get('run_id', '-')}  |  DUT: {summary.get('dut_sha256', '-')[:16]}")
        self.emit()
        self.table(results)
        self.emit("  " + "   ".join([
            self.paint(f"TOTAL {total}", "bold"), self.paint(f"PASS {passed}", "PASS"),
            self.paint(f"FAIL {failed}", "FAIL" if failed else "dim"),
            self.paint(f"NOT RUN {not_run}", "NOT RUN" if not_run else "dim"),
            self.paint(f"PENDING {pending}", "INCOMPLETE" if pending else "dim"),
        ]))
        if warning_runs:
            self.emit("  " + self.paint(f"WARNING in {warning_runs} run(s)", "WARN"))
        elapsed = summary.get("elapsed_seconds")
        duration = f"  |  elapsed {elapsed:.1f}s" if elapsed is not None else ""
        self.emit("  " + self.paint(f"OVERALL {status}", status) + duration)
        self.emit(self.paint("  R/P/S/A = reserve/push/send/response; W/E/F = UVM warning/error/fatal", "dim"))
        failures = [row for row in results if result_status(row) != "PASS"]
        if failures:
            self.emit()
            self.emit(self.paint("  FAILURE DETAILS", "FAIL"))
            for row in failures:
                label = f"{row.get('test', '-')}  ns={row.get('period_ns', '-')}  seed={row.get('seed', '-')}"
                self.emit("  " + self.paint(result_status(row), result_status(row)) + "  " + label)
                errors = ", ".join(f"{name} x{count}" for name, count in row.get("error_ids", {}).items())
                reason = errors or "; ".join(row.get("failure_reasons", [])) or "No failure details recorded"
                self.emit("        " + reason)
                self.emit("        Log: " + str(row.get("log", "-")))
        self.emit()
        self.emit("  Report: " + str(report_path))
        self.emit("  Detail: " + str(report_path.with_suffix(".md")))
        self.emit()
        return status == "PASS"


def positive_period(value):
    """读取有限的正时钟周期；实际时钟只由 TB 顶层的 CLOCK_PERIOD_NS 参数改变。"""
    try:
        period = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("period must be a number") from error
    if not math.isfinite(period) or period <= 0:
        raise argparse.ArgumentTypeError("period must be finite and positive")
    return period


def seed_value(value):
    """限制为 VCS 可接受的32位非负 seed，避免输入被截断或按负数解释。"""
    try:
        seed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("seed must be an integer") from error
    if seed < 0 or seed > 0xFFFFFFFF:
        raise argparse.ArgumentTypeError("seed must be in 0..4294967295")
    return seed


def parse_args(argv=None):
    """选择 case、时钟和随机种子；不接受 pipeline，执行顺序始终以计划清单为准。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tests", nargs="+", choices=TEST_ORDER, default=list(TEST_ORDER),
                        help="待运行的 test；省略时运行全部11个，顺序按验证计划排列")
    parser.add_argument("--periods", nargs="+", type=positive_period, default=[10.0, 4.0],
                        help="时钟周期，单位ns，默认10和4")
    parser.add_argument("--random-seeds", nargs="+", type=seed_value, default=[1, 2, 3],
                        help="仅用于 wbb_random_test；其他 case 固定使用 seed=1")
    parser.add_argument("--skip-compile", action="store_true",
                        help="复用两个 profile 目录下已有的 simv，由调用方保证与当前源码一致")
    parser.add_argument("--color", choices=("auto", "always", "never"), default="auto",
                        help="终端配色：auto自动识别终端，always强制，never关闭；auto遵循NO_COLOR")
    parser.add_argument("--report", type=Path,
                        help="只在终端重新展示已有summary.json，不编译、不运行、不覆盖报告")
    args = parser.parse_args(argv)
    args.tests = [name for name in TEST_ORDER if name in set(args.tests)]
    args.periods = list(dict.fromkeys(args.periods))
    args.random_seeds = list(dict.fromkeys(args.random_seeds))
    return args


def profile_for(test):
    """只有 delayed-push case 使用允许延迟 push 的编译配置。"""
    return "delayed" if test == "wbb_delayed_push_test" else "strict"


def period_text(period):
    """保留命令行周期的有效数值，同时省去整数周期后面的 .0。"""
    return str(period).removesuffix(".0")


def file_hash(path):
    """记录实际生成 Verilog 的 SHA-256，供日志与 DUT 版本核对。"""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def execute(command, stdout_path, timeout_seconds):
    """保存完整工具输出；超时或启动失败返回失败原因，让其他 case 仍能继续。"""
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with stdout_path.open("w") as output:
            result = subprocess.run(command, cwd=SIM_DIR, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=timeout_seconds)
        return result.returncode, None
    except (OSError, subprocess.TimeoutExpired) as error:
        with stdout_path.open("a") as output:
            output.write(f"\nREGRESSION_TOOL_FAILURE: {error}\n")
        return None, str(error)


def compile_profile(profile, run_id, skip_compile, console):
    """调用原有 Makefile 编译独立 profile，不运行 clean，也不复用另一个 profile 的编译产物。"""
    folder = REGRESSION_DIR / profile
    log_dir = folder / "log" / run_id
    log_dir.mkdir(parents=True, exist_ok=True)
    binary = folder / "run" / "simv"
    result = {"profile": profile, "skipped": skip_compile, "binary": str(binary),
              "pass": False, "exit_code": None, "failure_reasons": []}
    if skip_compile:
        result["pass"] = binary.is_file() and os.access(binary, os.X_OK)
        if not result["pass"]:
            result["failure_reasons"].append("--skip-compile requested but executable simv is missing")
        console.progress("PASS" if result["pass"] else "FAIL", f"reuse {profile} build")
        return result

    compile_log = log_dir / "compile.log"
    stdout_log = log_dir / "compile.stdout.log"
    sva_defines = "+define+WBB_ALLOW_DELAYED_PUSH" if profile == "delayed" else ""
    command = ["make", "vcs_compile", f"WORK_DIR=work/regression/{profile}/",
               f"SVA_DEFINES={sva_defines}", f"VCS_COMP_LOG={compile_log}"]
    console.progress("BUILD", f"{profile}  |  log: {stdout_log}")
    code, failure = execute(command, stdout_log, 600)
    text = compile_log.read_text(errors="replace") if compile_log.exists() else ""
    result.update({"command": command, "log": str(compile_log), "console_log": str(stdout_log),
                   "exit_code": code})
    if failure:
        result["failure_reasons"].append(failure)
    if code != 0:
        result["failure_reasons"].append(f"compiler/make exit code: {code}")
    if not compile_log.exists() or re.search(r"^\s*(?:Error|Fatal)-\[", text, re.MULTILINE):
        result["failure_reasons"].append("compile log missing or contains compiler errors")
    if not binary.is_file() or not os.access(binary, os.X_OK):
        result["failure_reasons"].append("compiled simv is missing or not executable")
    result["pass"] = not result["failure_reasons"]
    console.progress("PASS" if result["pass"] else "FAIL", f"compile {profile}")
    return result


def tcl_string(value):
    """转义 Tcl 字符串，避免路径中的特殊字符被当作变量或命令执行。"""
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    escaped = escaped.replace("$", "\\$").replace("[", "\\[").replace("]", "\\]")
    escaped = escaped.replace("\n", "\\n").replace("\r", "\\r")
    return '"' + escaped + '"'


def parse_log(text):
    """分别统计真实 UVM 报错行与汇总值，保留错误ID；cover的0 match不会被当作错误。"""
    error_events = re.findall(r"^\s*UVM_(ERROR|FATAL)\b(?!\s*:).*?\[([^]]+)\]", text, re.MULTILINE)
    severity_counts = {}
    for severity in ("WARNING", "ERROR", "FATAL"):
        summaries = re.findall(rf"^\s*UVM_{severity}\s*:\s*(\d+)\s*$", text, re.MULTILINE)
        severity_counts[severity] = max(map(int, summaries)) if summaries else None
    counts = COUNTER_PATTERN.findall(text)
    coverage = [{"id": match.group(1), "text": match.group(2).strip()}
                for match in re.finditer(r"^UVM_INFO .*?\[(WBB_[^]]*COVERAGE)\]\s*(.*)$", text, re.MULTILINE)]
    return {
        "severity_counts": severity_counts,
        "error_ids": dict(Counter(identifier for _, identifier in error_events)),
        "error_events": len(error_events),
        "counts": dict(zip(COUNTER_NAMES, map(int, counts[-1]))) if counts else {},
        "coverage": coverage,
        "pass_marker": bool(re.search(r"^UVM_INFO .*?\[WBB_TEST_PASS\]", text, re.MULTILINE)),
        "fail_marker": bool(re.search(r"^UVM_INFO .*?\[WBB_TEST_FAIL\]", text, re.MULTILINE)),
        "simulator_errors": re.findall(r"^\s*(?:Error|Fatal)-\[.*$", text, re.MULTILINE),
    }


def run_case(test, period, seed, build, run_id, dut_sha256):
    """单独运行一项组合，任何真实 DUT/SVA/UVM 失败都保留为 FAIL，不设置错误白名单。"""
    profile = profile_for(test)
    folder = REGRESSION_DIR / profile
    label = period_text(period).replace(".", "p").replace("+", "p").replace("-", "m")
    tag = f"{test}_p{label}_s{seed}"
    result = {"test": test, "profile": profile, "period_ns": period, "seed": seed,
              "pass": False, "exit_code": None, "dut_sha256": dut_sha256,
              "failure_reasons": [], "error_ids": {}, "counts": {}, "coverage": []}
    if not build["pass"]:
        result.update({"log": build.get("log", build["binary"]), "waveform": None,
                       "failure_reasons": ["profile compilation/executable check failed"], "status": "NOT_RUN"})
        return result

    log = folder / "log" / run_id / f"{tag}.log"
    stdout_log = log.with_suffix(".stdout.log")
    wave = folder / "wave" / run_id / f"{tag}.fsdb"
    tcl = folder / "script" / run_id / f"{tag}.tcl"
    for directory in (log.parent, wave.parent, tcl.parent):
        directory.mkdir(parents=True, exist_ok=True)
    tcl.write_text(f"fsdbDumpfile {tcl_string(wave)}\nfsdbDumpvars 0 \"tb_top\"\nrun\n")
    command = [build["binary"], f"+UVM_TESTNAME={test}", f"+CLOCK_PERIOD_NS={period_text(period)}",
               f"+ntb_random_seed={seed}", "+fsdb+autoflush", f"+wave={wave}",
               "-cm", COVERAGE, "-cm_dir", str(folder / "simv.vdb"),
               "-cm_name", f"{run_id}_{tag}", "-ucli", "-do", str(tcl), "-l", str(log)]
    code, failure = execute(command, stdout_log, 180)
    result.update({"command": command, "log": str(log), "console_log": str(stdout_log),
                   "waveform": str(wave), "tcl": str(tcl), "exit_code": code, "status": "RUN"})
    data = parse_log(log.read_text(errors="replace") if log.exists() else "")
    result.update(data)
    if failure:
        result["failure_reasons"].append(failure)
    if code != 0:
        result["failure_reasons"].append(f"simulator exit code: {code}")
    for severity in ("ERROR", "FATAL"):
        if data["severity_counts"][severity] != 0:
            result["failure_reasons"].append(f"UVM_{severity} count is {data['severity_counts'][severity]}")
    if data["error_events"] or data["simulator_errors"]:
        result["failure_reasons"].append("error/fatal report lines found")
    if not data["pass_marker"] or data["fail_marker"]:
        result["failure_reasons"].append("WBB_TEST_PASS missing or WBB_TEST_FAIL present")
    if not data["counts"]:
        result["failure_reasons"].append("scoreboard count summary missing")
    if not wave.is_file():
        result["failure_reasons"].append("requested FSDB waveform missing")
    if file_hash(DUT_FILE) != dut_sha256:
        result["failure_reasons"].append("generated DUT changed during regression")
    result["pass"] = not result["failure_reasons"]
    return result


def markdown_summary(summary):
    """输出便于查阅的结果表，日志和波形链接指向本轮独立目录。"""
    rows = ["# WBB regression", "", f"Run: `{summary['run_id']}`", "",
            f"DUT SHA-256: `{summary['dut_sha256']}`", "",
            "| Test | Profile | Period (ns) | Seed | Result | Error IDs / reason | Events | Log | Wave |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for result in summary["results"]:
        errors = ", ".join(f"{name}:{count}" for name, count in result["error_ids"].items())
        if not errors and not result["pass"]:
            errors = "; ".join(result["failure_reasons"])
        errors = errors.replace("|", "\\|").replace("\n", " ")
        counts = result["counts"]
        events = "/".join(str(counts.get(name, "-")) for name in ("reserve", "push", "send", "response"))
        log_link = f"[log](<{result['log']}>)"
        wave_link = f"[fsdb](<{result['waveform']}>)" if result["waveform"] else "-"
        rows.append(f"| {result['test']} | {result['profile']} | {period_text(result['period_ns'])} | "
                    f"{result['seed']} | {'PASS' if result['pass'] else 'FAIL'} | {errors or '-'} | "
                    f"{events} | {log_link} | {wave_link} |")
    passed = sum(result["pass"] for result in summary["results"])
    rows += ["", f"Completed: {len(summary['results'])}/{summary['planned_runs']}; "
             f"PASS={passed}, FAIL={len(summary['results'])-passed}.", "",
             "Events are reserve/push/send/response. A cover with 0 match is not an assertion error.",
             "Known DUT failures remain FAIL; no error ID is waived."]
    return "\n".join(rows) + "\n"


def save_summary(summary):
    """每完成一个组合就更新总表，并保存本轮副本，避免中断时丢失已经得到的结果。"""
    report_dir = REGRESSION_DIR / "reports" / summary["run_id"]
    report_dir.mkdir(parents=True, exist_ok=True)
    json_text = json.dumps(summary, indent=4, ensure_ascii=False) + "\n"
    markdown = markdown_summary(summary)
    for directory in (REGRESSION_DIR, report_dir):
        (directory / "summary.json").write_text(json_text)
        (directory / "summary.md").write_text(markdown)


def main(argv=None):
    """按计划顺序运行全部所选组合；一个组合失败后继续，最终只要有失败就返回1。"""
    args = parse_args(argv)
    console = TerminalReport(args.color)
    if args.report is not None:
        report_path = args.report.resolve()
        try:
            summary = json.loads(report_path.read_text())
            if not isinstance(summary, dict) or not isinstance(summary.get("results"), list):
                raise ValueError("Report must be a regression summary containing a results list")
        except (OSError, ValueError) as error:
            console.progress("FAIL", f"Cannot read report: {error}")
            return 1
        return 0 if console.summary(summary, report_path) else 1
    started = time.monotonic()
    run_id = datetime.now(timezone.utc).strftime("run_%Y%m%d_%H%M%S_%f")
    dut_sha256 = file_hash(DUT_FILE)
    planned = [(test, period, seed) for test in args.tests for period in args.periods
               for seed in (args.random_seeds if test == "wbb_random_test" else [1])]
    summary = {"run_id": run_id, "dut_file": str(DUT_FILE), "dut_sha256": dut_sha256,
               "tests": args.tests, "periods_ns": args.periods, "random_seeds": args.random_seeds,
               "skip_compile": args.skip_compile, "planned_runs": len(planned),
               "builds": {}, "results": [], "complete": False, "pass": False}
    profiles = list(dict.fromkeys(profile_for(test) for test in args.tests))
    for profile in profiles:
        summary["builds"][profile] = compile_profile(profile, run_id, args.skip_compile, console)
        save_summary(summary)
    for test, period, seed in planned:
        result = run_case(test, period, seed, summary["builds"][profile_for(test)], run_id, dut_sha256)
        summary["results"].append(result)
        save_summary(summary)
        console.progress(result_status(result), f"[{len(summary['results']):02d}/{len(planned):02d}] "
                         f"{test}  {period_text(period)}ns  seed={seed}  mode={result['profile']}")
    summary["complete"] = True
    summary["pass"] = all(result["pass"] for result in summary["results"])
    summary["elapsed_seconds"] = time.monotonic() - started
    save_summary(summary)
    console.summary(summary, REGRESSION_DIR / "summary.json")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        TerminalReport(stream=sys.stderr).progress("FAIL", f"REGRESSION_ERROR: {error}")
        sys.exit(1)
