#!/usr/bin/env python3
"""Isolated demo ledger for store screenshots, platform launch smoke tests and per-platform measurement.

    ~/Dev/.venv/bin/python scripts/demo/ledger.py start --dir <scratch dir> [--json]
    ~/Dev/.venv/bin/python scripts/demo/ledger.py stop  --dir <scratch dir>

start runs the real ~/Apps/edu/web/points/server.py on a random 127.0.0.1 port with its data home inside --dir,
registers a synthetic child account (nickname 小满), and books 30 days of history through the server's own
endpoints (earn / spend / adjust with the synthetic account session), so balances, tier bonuses, unlocks and the
trend are computed by the server exactly as in production. Rule and shop ids come from the server's rules.json
(an unknown id stops the run). Timestamps are then spread over the last 30 days, order preserved, 07:00-21:59,
newest entry a few minutes ago. Prints one JSON object: url, port, pid, user, pw, parent_pw, balance, dir.

Never touches edu.tianli.cyou, the real ledger, ~/.personal_env or any real family data: passwords are random,
the account and nickname are invented, and no rule naming a real third party is used. stop kills the server.
Exit 0 ok, 1 failed, 78 server source or a scrypt-capable Python missing (no fixture).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import random
import secrets
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.request
from http.cookiejar import CookieJar
from pathlib import Path

SERVER_DIR = Path(os.environ.get("POINTS_SERVER_DIR") or Path.home() / "Apps/edu/web/points")
NO_FIXTURE = 78
USER, NICK, AVATAR = "xiaoman", "小满", "🦊"
CST = dt.timezone(dt.timedelta(hours=8))
# Fixed-score rules a parent books day to day (weights = how often). Rules that name a real person are left out.
DAILY = [("cn-dict-all", 4), ("cn-hw-3star", 4), ("cn-hw-2star", 3), ("cn-praise", 3), ("cn-read-ontime", 3),
         ("ma-oral-all", 5), ("ma-quiz85", 2), ("ma-excellent", 2), ("ma-extra-oral", 2),
         ("en-praise", 3), ("en-review-all", 3), ("en-phrase", 1), ("pe-badminton", 2), ("pe-run", 2),
         ("tr-full", 3), ("mo-goodword", 2), ("ch-dish-self", 3), ("ch-desk", 2), ("ch-trash", 2), ("ch-dish-all", 1)]
SLIPS = ["cn-forget", "ch-refuse", "cn-hw-undone", "pe-skip-day"]
# Highlights on fixed days: (day, op). Range rules carry the points a parent would type.
HIGHLIGHTS = {3: [("earn", "cn-unit-all")], 5: [("earn", "mo-activity", 15)], 6: [("earn", "cn-xueba")],
              8: [("spend", "sh-icecream")], 9: [("earn", "mo-rank", 100)], 12: [("earn", "tr-perform")],
              14: [("spend", "sh-anime")], 15: [("earn", "cn-xueba-all")], 17: [("adjust", 30, "帮奶奶把菜拎上楼")],
              19: [("spend", "sh-game30")], 20: [("earn", "ma-exam85")], 21: [("earn", "sp-bonus", 200)],
              22: [("earn", "tr-show")], 23: [("earn", "cn-read-all")], 26: [("earn", "cn-recite", 30)],
              28: [("earn", "cn-xueba")], 29: [("earn", "en-review-all")]}
# Spends and big jumps sit before the last week on purpose: the trend card shows the last 30 bookings (about six
# days), and a month's story reads as a steady climb there, not a cliff. The newest booking is a good one (day 29).
TARGET = (1080, 1160)   # 小木屋 (600+), a short way from 砖瓦房 (1,200): about a month of a pupil's bookings


def scrypt_python() -> str | None:
    for cand in (os.environ.get("POINTS_PYTHON"), sys.executable, str(Path.home() / "Dev/.venv/bin/python"),
                 "/opt/homebrew/bin/python3"):
        if cand and Path(cand).exists() and subprocess.run([cand, "-c", "import hashlib; hashlib.scrypt"],
                                                           capture_output=True).returncode == 0:
            return cand
    return None


def free_port() -> int:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def plan(rules: dict, seed: int) -> list[tuple]:
    """Day-by-day operations; deterministic for a seed."""
    rnd = random.Random(seed)
    ids, weights = zip(*DAILY)
    ops = []
    for day in range(30):
        for _ in range(rnd.randint(3, 6)):
            ops.append(("earn", rnd.choices(ids, weights)[0]))
        if rnd.random() < 0.12:
            ops.append(("earn", rnd.choice(SLIPS)))
        ops += HIGHLIGHTS.get(day, [])
    return ops


def projected(rules: dict, tiers: list[dict], ops: list[tuple]) -> int:
    """Balance the server will reach, tier bonuses included (an estimate to pick the seed; the server decides)."""
    pts = {r["id"]: r.get("pts") for r in rules["rules"]}
    cost = {s["id"]: s["pts"] for s in rules["shop"]}
    unlock_at = {i: t["at"] for t in tiers for i in t.get("unlock") or []}
    bal, paid = 0, 0
    for op in ops:
        if op[0] == "spend" and (bal < cost[op[1]] or bal < unlock_at.get(op[1], 0)):
            return -1      # the server refuses an overdraft or a locked item: this seed's story does not work
        bal += (op[2] if len(op) > 2 else pts[op[1]]) if op[0] == "earn" else -cost[op[1]] if op[0] == "spend" else op[1]
        while paid + 1 < len(tiers) and bal >= tiers[paid + 1]["at"]:
            paid += 1
            bal += int(tiers[paid].get("bonus") or 0)
    return bal


def check_ids(rules: dict, ops: list[tuple]) -> None:
    known = {r["id"]: r for r in rules["rules"]}
    shop = {s["id"] for s in rules["shop"]}
    bad = [op[1] for op in ops if (op[0] == "earn" and op[1] not in known) or (op[0] == "spend" and op[1] not in shop)]
    bad += [op[1] for op in ops if op[0] == "earn" and op[1] in known and
            (known[op[1]].get("cur") == "tv" or (known[op[1]]["kind"] == "fixed") == (len(op) > 2))]
    if bad:
        raise SystemExit(f"rules.json 里没有这些 id，或分值类型对不上：{sorted(set(bad))}")


class Client:
    def __init__(self, base: str):
        self.base = base
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))

    def post(self, path: str, body: dict) -> dict:
        req = urllib.request.Request(self.base + path, method="POST", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with self.op.open(req, timeout=15) as resp:
            out = json.loads(resp.read())
        if not out.get("ok"):
            raise SystemExit(f"{path} 失败：{out}")
        return out


def serve(py: str, env: dict, log: Path) -> subprocess.Popen:
    proc = subprocess.Popen([py, "test_mail_service.py", "serve"], cwd=SERVER_DIR, env=env, stdout=open(log, "a"),
                            stderr=subprocess.STDOUT, start_new_session=True)
    for _ in range(100):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{env['EDU_POINTS_PORT']}/api/health", timeout=1)
            return proc
        except OSError:
            if proc.poll() is not None:
                break
            time.sleep(0.1)
    proc.kill()
    raise SystemExit(f"本地账本服务没起来，见 {log}")


def spread(path: Path) -> None:
    """Spread the booked entries over the last 30 days (order kept, 07-21 h), newest a few minutes ago."""
    led = json.loads(path.read_text(encoding="utf-8"))
    entries, now = led["entries"], dt.datetime.now(CST).replace(microsecond=0)
    n = len(entries)
    for i, e in enumerate(entries):
        t = now - dt.timedelta(minutes=6) if i == n - 1 else now - dt.timedelta(days=30.0 * (1 - i / max(1, n - 1)))
        if i < n - 1:
            t = t.replace(hour=7 + t.hour * 15 // 24)
        e["ts"], e["day"] = t.isoformat(timespec="seconds"), t.strftime("%Y-%m-%d")
    path.write_text(json.dumps(led, ensure_ascii=False, indent=1), encoding="utf-8")


def start(work: Path) -> dict:
    if not (SERVER_DIR / "server.py").is_file():
        print(f"账本服务源码不在 {SERVER_DIR}", file=sys.stderr)
        sys.exit(NO_FIXTURE)
    py = scrypt_python()
    if not py:
        print("找不到带 hashlib.scrypt 的 Python，起不了账本服务", file=sys.stderr)
        sys.exit(NO_FIXTURE)
    stop(work)
    home, static = work / "home", work / "static"
    for d in (home, static):     # every start is a fresh ledger: the same story, never yesterday's leftovers
        shutil.rmtree(d, ignore_errors=True)
        d.mkdir(parents=True)
    rules = json.loads((SERVER_DIR / "rules.json").read_text(encoding="utf-8"))
    tiers = json.loads((SERVER_DIR / "skins/skins.json").read_text(encoding="utf-8"))["tiers"]
    seed = next((s for s in range(20261002, 20261002 + 2000) if TARGET[0] <= projected(rules, tiers, plan(rules, s)) <= TARGET[1]),
                None)
    if seed is None:
        raise SystemExit(f"rules.json 的分值变了，2000 个种子里没有落在 {TARGET} 的演示账本；调 DAILY / HIGHLIGHTS")
    ops = plan(rules, seed)
    check_ids(rules, ops)
    pw, parent = "demo-" + secrets.token_hex(6), "parent-" + secrets.token_hex(6)
    port = free_port()
    env = {**os.environ, "EDU_POINTS_HOME": str(home), "EDU_POINTS_STATIC": str(static), "EDU_POINTS_PORT": str(port),
           # init opens the site-wide account (unused here); its passwords are random too
           "EDU_KID_USER": "siteowner", "EDU_KID_PW": secrets.token_hex(8), "EDU_PARENT_PW": parent}
    for k in ("EDU_POINTS_KID_PW", "EDU_POINTS_PARENT_PW", "EDU_POINTS_KID_USER"):
        env.pop(k, None)
    log = work / "server.log"
    r = subprocess.run([py, "server.py", "init"], cwd=SERVER_DIR, env=env, capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(f"server.py init 失败：{(r.stderr or r.stdout)[-400:]}")
    proc = serve(py, env, log)
    base = f"http://127.0.0.1:{port}"
    try:
        c = Client(base)
        address = USER + "@example.test"
        challenge = c.post("/api/email_send", {"purpose": "register", "email": address})
        message = json.loads((home / "test-outbox.json").read_text())[-1][2]
        code = re.search(r"验证码：(\d{6})", message).group(1)
        grant = c.post("/api/email_verify", {"challenge": challenge["challenge"], "code": code})["grant"]
        c.post("/api/register", {"email": address, "grant": grant, "p": pw, "nick": NICK})
        c.post("/api/profile", {"emoji": AVATAR})
        for op in ops:
            if op[0] == "earn":
                c.post("/api/earn", {"rule": op[1], **({"pts": op[2]} if len(op) > 2 else {})})
            elif op[0] == "spend":
                c.post("/api/spend", {"item": op[1]})
            else:
                c.post("/api/adjust", {"pts": op[1], "label": op[2]})
        spread(home / "ledgers" / f"{USER}.json")
        state = json.loads(c.op.open(base + "/api/state", timeout=15).read())
    except BaseException:
        os.killpg(proc.pid, signal.SIGTERM)
        raise
    balance = state.get("balance", state.get("bal"))
    info = {"ok": True, "url": base, "port": port, "pid": proc.pid, "user": USER, "nick": NICK, "pw": pw,
            "parent_pw": parent, "balance": balance, "seed": seed, "entries": len(ops), "dir": str(work)}
    (work / "ledger.json").write_text(json.dumps(info, ensure_ascii=False), encoding="utf-8")
    os.chmod(work / "ledger.json", 0o600)
    return info


def stop(work: Path) -> bool:
    meta = work / "ledger.json"
    try:
        pid = json.loads(meta.read_text(encoding="utf-8"))["pid"]
    except (OSError, ValueError, KeyError):
        return False
    try:
        os.killpg(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    meta.unlink(missing_ok=True)
    return True


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=("start", "stop"))
    ap.add_argument("--dir", required=True, type=Path, help="scratch directory for the ledger's data home (outside the repo)")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    work = a.dir.expanduser().resolve()
    repo = Path(__file__).resolve().parents[2]
    if work == repo or work.is_relative_to(repo):
        print(f"--dir 必须在仓外（{work}）", file=sys.stderr)
        return 2
    if a.cmd == "stop":
        print(json.dumps({"ok": True, "stopped": stop(work)}))
        return 0
    info = start(work)
    print(json.dumps(info, ensure_ascii=False) if a.json else
          f"demo ledger {info['url']} · {info['nick']} · {info['balance']} 分 · {info['entries']} 笔")
    return 0


if __name__ == "__main__":
    sys.exit(main())
