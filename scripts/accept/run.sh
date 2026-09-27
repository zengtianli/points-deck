#!/bin/bash
# Fixed acceptance runner for Chapter app_sop: `scripts/accept/run.sh <functionality|recovery|privacy>`.
# Compiles the production client (Sources/Api.swift, ParentSession.swift, Skin.swift + Shared/PlatformCompat.swift)
# with scripts/accept/<check>.swift and drives it against a throwaway local ledger started from the real
# ~/Apps/edu/web/points/server.py (scratch EDU_POINTS_HOME, synthetic passwords, random localhost port).
# Never touches edu.tianli.cyou, the user's keychain, cookies, preferences, mouse, keyboard or clipboard.
# Idempotent and non-interactive; exit 0 = passed, 78 = server source missing (no acceptor).
set -euo pipefail
check="${1:?usage: run.sh <functionality|recovery|privacy>}"
case "$check" in functionality|recovery|privacy) ;; *) echo "unknown check $check"; exit 2;; esac
cd "$(dirname "$0")/../.."
repo="$PWD"
out="${SOP_OUT_DIR:-$repo/perf/acceptance}"
server_dir="${POINTS_SERVER_DIR:-$HOME/Apps/edu/web/points}"
mkdir -p "$out"
[ -f "$server_dir/server.py" ] || { echo "账本服务源码不在 $server_dir，无法验收"; exit 78; }

# server.py hashes with hashlib.scrypt, which the macOS system python3 lacks; pick an interpreter that has it.
py=""
for cand in "${POINTS_PYTHON:-}" "$HOME/Dev/.venv/bin/python" /opt/homebrew/bin/python3 python3; do
  [ -n "$cand" ] && "$cand" -c 'import hashlib; hashlib.scrypt' 2>/dev/null && { py="$cand"; break; }
done
[ -n "$py" ] || { echo "找不到带 hashlib.scrypt 的 Python，无法启动账本服务"; exit 78; }

scratch="$(mktemp -d /tmp/points-accept-$check.XXXXXX)"
server_pid=""
cleanup() {
  kill "$server_pid" "$(cat "$scratch/server.pid" 2>/dev/null)" 2>/dev/null || true
  wait 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/ledger" "$scratch/home" "$scratch/static"

static_note="" static_code=0
if [ "$check" = privacy ]; then
  static_note="$(python3 scripts/accept/privacy_static.py)" || static_code=$?
  echo "$static_note"
fi

port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')"
export EDU_POINTS_HOME="$scratch/ledger" EDU_POINTS_PORT="$port" EDU_POINTS_STATIC="$scratch/static"
export EDU_KID_USER=acceptkid EDU_KID_PW="kid-$RANDOM-$RANDOM" EDU_PARENT_PW="parent-$RANDOM-$RANDOM"
( cd "$server_dir" && "$py" server.py init >/dev/null && "$py" server.py seed 30 --force >/dev/null )

start_server() {
  ( cd "$server_dir" && exec "$py" server.py serve ) >"$scratch/server.log" 2>&1 &
  server_pid=$!
  for _ in $(seq 1 50); do
    curl -fsS "http://127.0.0.1:$port/api/health" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  echo "本地账本服务未启动"; cat "$scratch/server.log"; return 1
}
stop_server() { kill "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null || true; server_pid=""; }
start_server

xcrun --sdk macosx swiftc -target "$(uname -m)-apple-macos15.0" -parse-as-library \
  Shared/PlatformCompat.swift Sources/Skin.swift Sources/Api.swift Sources/ParentSession.swift \
  scripts/accept/Common.swift "scripts/accept/$check.swift" -o "$scratch/accept"

# The recovery check stops and restarts the server itself; it reports any new pid through this file.
echo "$server_pid" >"$scratch/server.pid"

log="$scratch/accept.log"
set +e
CFFIXED_USER_HOME="$scratch/home" ACCEPT_SERVER_DIR="$server_dir" ACCEPT_PYTHON="$py" ACCEPT_PID_FILE="$scratch/server.pid" \
  ACCEPT_PORT="$port" ACCEPT_KID_USER="$EDU_KID_USER" \
  ACCEPT_KID_PW="$EDU_KID_PW" ACCEPT_PARENT_PW="$EDU_PARENT_PW" ACCEPT_HOME="$scratch/home" \
  "$scratch/accept" -api_base "http://127.0.0.1:$port" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
set -e

# Leak probe: neither synthetic password may be written anywhere under the client's sandboxed home.
leak=$( (grep -rlaF -e "$EDU_PARENT_PW" -e "$EDU_KID_PW" "$scratch/home" 2>/dev/null || true) | wc -l | tr -d ' ')
written=$(find "$scratch/home" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "ACCEPT: 客户端隔离 HOME 写入 $written 个文件，其中含密码明文 $leak 个" | tee -a "$log"
[ "$leak" = 0 ] || code=3
[ "$static_code" = 0 ] || code=4

steps=$(grep -oE "ACCEPT: .*" "$log" | sed 's/^ACCEPT: //' || true)
python3 - "$out/$check.detail.json" "$check" "$code" "$static_note" "$steps" <<'PY'
import json, sys
path, check, code, static, steps = sys.argv[1:]
steps = [s for s in steps.splitlines() if s]
ok = code == "0" and len(steps) > 1
label = {"functionality": "功能", "recovery": "故障与恢复", "privacy": "隐私边界"}[check]
summary = (f"{label}：生产 Swift 客户端对本地真实账本服务 {len(steps)} 项通过" if ok
           else f"{label}：失败（退出码 {code}）；末步：{steps[-1] if steps else '无'}")
if static:
    summary += "；" + static.strip().splitlines()[-1]
json.dump({"summary": summary, "passed": ok, "steps": steps,
           "scope": "macOS 编译同一份 Sources/Api.swift + ParentSession.swift，驱动 ~/Apps/edu/web/points/server.py "
                    "的隔离临时账本（合成账号/密码、随机本地端口）；不含 SwiftUI 界面、Widget、真机与线上 edu.tianli.cyou"},
          open(path, "w"), ensure_ascii=False, indent=2)
print(summary)
PY
exit "$code"
