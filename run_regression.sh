#!/usr/bin/env bash
# Shell启动入口；统一调度器负责一次编译、framework前置和case并行。
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -B -u "$project_root/verif_mshr/script/run_all_regression.py" "$@"
