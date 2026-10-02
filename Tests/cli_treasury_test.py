#!/usr/bin/env python3
"""treasury 命令行的回归门：起一个**隔离的本地服务端**（临时数据目录 + 空闲端口），
用真实入口 `cli/treasury` 走一遍读、写、失败退出码。不碰线上、不碰任何真实账号。
另验随 Mac 版打包：project.yml 只在 macOS build 把命令拷进 Contents/Resources/bin，
cli/install.sh 按 bundle id 在（临时的）Applications 目录找宿主 .app，没有才链本仓入口。

服务端源码取 $EDU_SERVER_PY，缺省是同一工作区的 ~/Apps/edu/web/points/server.py
（公开仓单独克隆时没有它：本测试直接失败并说明原因，不假装通过）。

    python3 Tests/cli_treasury_test.py
"""
from __future__ import annotations

import json
import os
import plistlib
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from http.cookiejar import CookieJar
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CLI = REPO / "cli" / "treasury"
SERVER = Path(os.environ.get("EDU_SERVER_PY") or REPO.parents[2] / "web" / "points" / "server.py")
KID_PW, PARENT_PW = "kidpass1", "parentpass1"
FAILS: list[str] = []


def ck(name: str, cond: bool, detail: str = "") -> None:
    print(("  ✅ " if cond else "  ❌ ") + name + ("" if cond else f"　{detail}"))
    if not cond:
        FAILS.append(name)


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def old_server_gate() -> None:
    """服务端响应不带 scope（旧版）时：管理写入一律不发出去。
    用一个只会回旧形状的桩服务端验，记下它收到过哪些写请求。"""
    hits: list[str] = []

    class Old(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):                                    # noqa: N802  /api/me、/api/state
            self.do_POST()

        def do_POST(self):                                   # noqa: N802
            self.rfile.read(int(self.headers.get("Content-Length") or 0))
            hits.append(self.path)
            body = {"/api/login": {"ok": True, "u": "atk"},
                    "/api/config": {"ok": True, "subjects": [], "rules": [], "shop": [], "tiers": [], "eras": {}},
                    "/api/me": {"ok": True, "u": "atk", "nick": "atk", "email": "atk@example.test"},
                    "/api/state": {"ok": True, "u": "atk", "total": 500, "entries": [
                        {"id": f"e{i}", "ts": f"2026-09-2{i}T10:00:00", "day": f"2026-09-2{i}", "kind": "earn",
                         "cat": "study", "label": "x", "pts": 5, "bal": 5 * i} for i in (1, 2)]},
                    "/api/users": {"ok": True, "account_deletions": {"pending": 2},
                                   "users": [{"u": u, "nick": u, "balance": 7, "created": "2026-09-01"}
                                             for u in ("atk", "jingbao", "other")]}}.get(self.path, {"ok": True})
            data = json.dumps(body).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    srv = ThreadingHTTPServer(("127.0.0.1", 0), Old)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        env = {k: v for k, v in os.environ.items() if not k.startswith("EDU_")}
        env.update(EDU_API_BASE=f"http://127.0.0.1:{srv.server_port}", EDU_USER="atk@example.test",
                   EDU_PASSWORD="x", EDU_PARENT_PW="p")
        items = Path(tempfile.mkdtemp(prefix="treasury-old-")) / "shop.json"
        items.write_text("[]", encoding="utf-8")

        def run(args, stdin=""):
            p = subprocess.run([str(CLI), *args, "--json"], env=env, input=stdin, capture_output=True, text=True, timeout=30)
            return p.returncode, json.loads(p.stdout or "{}")

        code, out = run(["config", "put", "shop", "--file", str(items)])
        ck("旧服务端：config put 拒绝且没发 config_put", code == 1 and "scope" in out.get("err", "")
           and "/api/config_put" not in hits, str(out))
        code, out = run(["users", "delete", "jingbao", "--yes"])
        ck("旧服务端：users delete 拒绝且没发 user_del", code == 1 and "/api/user_del" not in hits, str(out))
        code, out = run(["users", "reset-password", "jingbao", "--new-stdin"], stdin="newpass1\n")
        ck("旧服务端：reset-password 拒绝且没发 passwd_reset", code == 1 and "/api/passwd_reset" not in hits, str(out))
        code, out = run(["config", "get"])
        ck("旧服务端：config get 照读，标 server_scoped=false、scope=unknown（不猜成 site）",
           code == 0 and out.get("server_scoped") is False and out.get("scope") == "unknown", str(out))
        code, out = run(["users", "list"])
        ck("旧服务端：users list 只列本账号，别人的账号与注销汇总不带出来",
           code == 0 and [u["u"] for u in out.get("users", [])] == ["atk"] and out.get("hidden") == 2
           and out.get("scope") == "unknown" and out.get("account_deletions") == {}, str(out))
        p = subprocess.run([str(CLI), "users", "list"], env=env, capture_output=True, text=True, timeout=30)
        ck("旧服务端：users list 文字输出也只有本账号并说明另有 2 个未显示",
           p.returncode == 0 and "jingbao" not in p.stdout and "另有 2 个" in p.stdout, p.stdout)
        p = subprocess.run([str(CLI), "entries"], env=env, capture_output=True, text=True, timeout=30)
        ck("entries 文字输出有流水时也带「服务端只下发最近 N 笔」", p.returncode == 0 and "#e2" in p.stdout
           and "服务端只下发最近 2 笔" in p.stdout, p.stdout)
        shutil.rmtree(items.parent, ignore_errors=True)
    finally:
        srv.shutdown()


BUNDLE_ID = "cyou.tianli.pointsdeck"
INSTALL = REPO / "cli" / "install.sh"


def fake_app(apps: Path, name: str, bundle_id: str, with_cli: bool) -> Path:
    """只有 Info.plist（+ 可选 Resources/bin/treasury）的假 .app：install.sh 只按 bundle id 认宿主。"""
    app = apps / f"{name}.app"
    (app / "Contents").mkdir(parents=True)
    (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": bundle_id}))
    if with_cli:
        b = app / "Contents" / "Resources" / "bin"
        b.mkdir(parents=True)
        shutil.copy2(CLI, b / "treasury")
        (b / "treasury").chmod(0o755)
    return app


def install(bin_dir: Path, apps: Path, *args: str) -> tuple[int, str]:
    env = {**os.environ, "EDU_CLI_BIN_DIR": str(bin_dir), "EDU_APPLICATIONS_DIR": str(apps)}
    r = subprocess.run(["sh", str(INSTALL), *args], env=env, capture_output=True, text=True, timeout=60,
                       stdin=subprocess.DEVNULL)
    return r.returncode, r.stdout + r.stderr


def check_bundle_packaging() -> None:
    print("【随 Mac 版打包】")
    spec = (REPO / "project.yml").read_text(encoding="utf-8")
    block = spec.split("postBuildScripts:", 1)[1].split("    sources:", 1)[0] if "postBuildScripts:" in spec else ""
    ck("project.yml 构建阶段把 cli/treasury 拷进 Resources/bin",
       '"$PROJECT_DIR/cli/treasury"' in block and "$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin" in block, block[:200])
    ck("只在 macOS 的 build 动作拷（iOS 包与归档 ACTION=install 不带）",
       '"$PLATFORM_NAME" != "macosx"' in block and '"$ACTION" = "install"' in block)
    ck("不声明 outputFiles（否则 iOS 包里会多一个空 bin/）",
       not any(ln.strip().startswith("outputFiles:") for ln in block.splitlines()))
    tmp = Path(tempfile.mkdtemp(prefix="treasury-install-"))
    try:
        apps, none, bin_dir = tmp / "Applications", tmp / "empty", tmp / "bin"
        apps.mkdir(); none.mkdir()
        link = bin_dir / "treasury"
        code, out = install(bin_dir, none)
        ck("没装 Mac 版 → 链到本仓入口", code == 0 and os.path.realpath(link) == str(CLI.resolve()), out)
        fake_app(apps, "旧版成长小金库", BUNDLE_ID, with_cli=False)
        code, out = install(bin_dir, apps)
        ck("装了旧 Mac 版（包里没命令）→ 拒绝、退出 1、原链接不动",
           code == 1 and os.path.realpath(link) == str(CLI.resolve()), out)
        shutil.rmtree(apps / "旧版成长小金库.app")
        app = fake_app(apps, "成长小金库", BUNDLE_ID, with_cli=True)
        code, out = install(bin_dir, apps)
        want = os.path.realpath(app / "Contents" / "Resources" / "bin" / "treasury")
        ck("装了带命令的 Mac 版 → 本仓旧链接换成包内命令", code == 0 and os.path.realpath(link) == want, out)
        ck("--check 通过", install(bin_dir, apps, "--check")[0] == 0)
        link.unlink()
        link.symlink_to("/usr/bin/true")
        code, out = install(bin_dir, apps)
        ck("指向别处的同名链接拒绝覆盖", code == 1 and os.readlink(link) == "/usr/bin/true", out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    check_bundle_packaging()
    if not SERVER.is_file():
        print(f"❌ 找不到服务端源码 {SERVER}（设 EDU_SERVER_PY 指向 edu/web/points/server.py）")
        return 2
    home = Path(tempfile.mkdtemp(prefix="treasury-cli-"))
    port = free_port()
    base = f"http://127.0.0.1:{port}"
    env = {**os.environ, "EDU_POINTS_HOME": str(home), "EDU_POINTS_PORT": str(port),
           "EDU_POINTS_STATIC": str(home / "site"), "EDU_KID_PW": KID_PW, "EDU_PARENT_PW": PARENT_PW}
    (home / "site").mkdir()
    srv = None
    try:
        r = subprocess.run([sys.executable, str(SERVER), "init"], env=env, capture_output=True, text=True, timeout=60)
        if r.returncode:
            print(r.stdout, r.stderr)
            return 2
        srv = subprocess.Popen([sys.executable, str(SERVER), "serve"], env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(60):
            time.sleep(0.1)
            try:
                urllib.request.urlopen(base + "/api/health", timeout=2)
                break
            except OSError:
                continue
        else:
            print("❌ 隔离服务端没起来")
            return 2

        clean = {k: v for k, v in os.environ.items() if not k.startswith("EDU_")}

        def run(args, user="jingbao", pw=KID_PW, stdin="", extra=None):
            e = {**clean, "EDU_API_BASE": base, **({"EDU_USER": user} if user else {}),
                 **({"EDU_PASSWORD": pw} if pw else {}), **(extra or {})}
            p = subprocess.run([str(CLI), *args], env=e, input=stdin, capture_output=True, text=True, timeout=60)
            try:
                out = json.loads(p.stdout) if "--json" in args else None
            except ValueError:
                out = None
            return p.returncode, out, p.stdout + p.stderr

        print("【帮助与用法】")
        for sub in ([], ["state"], ["earn"], ["config", "put"], ["users", "delete"], ["account", "passwd"]):
            code, _, _ = run([*sub, "--help"], user=None, pw=None)
            ck(f"treasury {' '.join(sub)} --help → 0", code == 0)
        code, out, _ = run(["state", "--json"], user=None, pw=None)
        ck("缺凭据 → 2 且 ok:false", code == 2 and out["ok"] is False, str(out))
        code, out, _ = run(["state", "--json"], pw="wrong-pass")
        ck("账号密码错 → 1 且带服务端原话", code == 1 and out["ok"] is False and out.get("status") == 401, str(out))
        code, out, _ = run(["state", "--json"], extra={"EDU_API_BASE": "http://127.0.0.1:9"})
        ck("连不上服务端 → 1", code == 1 and out["ok"] is False, str(out))
        code, out, _ = run(["version", "--json"], user=None, pw=None)
        ck("version 不登录：命令行版本 + 服务端可达", code == 0 and out["ok"] and out["cli"]
           and out["server"]["reachable"] is True and out["app"] is None, str(out))
        code, out, _ = run(["version", "--json"], user=None, pw=None, extra={"EDU_API_BASE": "http://127.0.0.1:9"})
        ck("version 连不上服务端 → 仍 0，reachable:false", code == 0 and out["server"]["reachable"] is False, str(out))

        print("【读】首页 / 流水 / 走势 / 兑换 / 阶梯 / 规则")
        code, st, _ = run(["state", "--json"])
        ck("state：开户 1000 分，住第 2 档，下一档还差 200", code == 0 and st["balance"] == 1000
           and st["house"]["next"]["points_to_go"] == 200, str(st))
        code, out, text = run(["state"])
        ck("state 文字版", code == 0 and "余额 1000 分" in text, text)
        code, sh, _ = run(["shop", "--json"])
        ck("shop：12 件，sh-icecream 已解锁、sh-trip 锁着要 40000", code == 0 and len(sh["items"]) == 12
           and next(i for i in sh["items"] if i["id"] == "sh-icecream")["unlocked"]
           and next(i for i in sh["items"] if i["id"] == "sh-trip")["tier_at"] == 40000, str(sh)[:300])
        code, tr, _ = run(["tiers", "--json"])
        ck("tiers：11 档，当前第 2 档（小木屋 600）", code == 0 and len(tr["tiers"]) == 11 and tr["current"] == 2, str(tr)[:200])
        code, rl, _ = run(["rules", "--json"])
        ck("rules：带 tr-show 和科目表", code == 0 and any(r["id"] == "tr-show" for r in rl["rules"]) and rl["subjects"])

        print("【预览 / 记账 / 撤销 / 调账 / 兑换】（隔离服务端）")
        code, pv, _ = run(["preview", "tr-show", "--json"])
        ck("preview tr-show = +100（服务端算）", code == 0 and pv["pts"] == 100, str(pv))
        code, pv, _ = run(["preview", "cn-dict-wrong", "--n", "3", "--json"])
        ck("preview 按个数规则 = -3", code == 0 and pv["pts"] == -3, str(pv))
        code, pv, _ = run(["preview", "no-such-rule", "--json"])
        ck("preview 不存在的规则 → 1 且 ok:false", code == 1 and pv["ok"] is False and "没有这条规则" in pv["err"], str(pv))
        code, out, _ = run(["earn", "tr-show", "--json"])
        ck("earn 没给家长密码 → 2", code == 2 and out["ok"] is False, str(out))
        code, out, _ = run(["earn", "tr-show", "--parent-stdin", "--json"], stdin="wrong-parent\n")
        ck("earn 家长密码错 → 1（403）", code == 1 and out.get("status") == 403, str(out))
        ck("被拒后余额没变", run(["state", "--json"])[1]["balance"] == 1000)
        code, out, _ = run(["earn", "tr-show", "--dry-run", "--json"])
        ck("earn --dry-run 只预览", code == 0 and out["dry_run"] and run(["state", "--json"])[1]["balance"] == 1000)
        code, ea, _ = run(["earn", "tr-show", "--parent-stdin", "--note", "cli", "--json"], stdin=PARENT_PW + "\n")
        ck("earn 记一笔 +100 → 1100", code == 0 and ea["entry"]["pts"] == 100 and ea["balance"] == 1100, str(ea))
        code, es, _ = run(["entries", "--limit", "1", "--json"])
        ck("entries 最新一笔就是它", code == 0 and es["entries"][0]["id"] == ea["entry"]["id"], str(es)[:200])
        code, out, _ = run(["undo", ea["entry"]["id"], "--dry-run", "--json"])
        ck("undo --dry-run 指出要删的那笔", code == 0 and out["entry"]["id"] == ea["entry"]["id"])
        code, out, _ = run(["undo", ea["entry"]["id"], "--json"], extra={"EDU_PARENT_PW": PARENT_PW})
        ck("undo（EDU_PARENT_PW）→ 回到 1000", code == 0 and out["balance"] == 1000, str(out))
        code, out, _ = run(["adjust", "5", "--label", "CLI 调账", "--json"], extra={"EDU_PARENT_PW": PARENT_PW})
        ck("adjust +5 → 1005", code == 0 and out["balance"] == 1005, str(out))
        code, out, _ = run(["spend", "sh-trip", "--dry-run", "--json"])
        ck("spend --dry-run 说清锁着", code == 0 and out["would_succeed"] is False)
        code, out, _ = run(["spend", "sh-trip", "--json"])
        ck("spend 未解锁 → 1 且余额不动", code == 1 and "才能换" in out["err"]
           and run(["state", "--json"])[1]["balance"] == 1005, str(out))
        code, out, _ = run(["spend", "sh-icecream", "--json"])
        ck("spend sh-icecream -200 → 805", code == 0 and out["balance"] == 805, str(out))
        code, out, _ = run(["trend", "--span", "14", "--json"])
        ck("trend：最后一点 = 当前余额", code == 0 and out["points"][-1]["bal"] == 805, str(out)[:200])

        print("【配置】全站（这一家）与公开账号各改各的")
        code, cfg, _ = run(["config", "get", "--json"], extra={"EDU_PARENT_PW": PARENT_PW})
        ck("config get → scope=site", code == 0 and cfg["scope"] == "site" and len(cfg["shop"]) == 12, str(cfg)[:200])
        bad = home / "bad-shop.json"
        bad.write_text(json.dumps([x for x in cfg["shop"] if x["id"] != "sh-trip"]), encoding="utf-8")
        code, out, _ = run(["config", "put", "shop", "--file", str(bad), "--json"], extra={"EDU_PARENT_PW": PARENT_PW})
        ck("config put 删掉档位引用的商品 → 1（服务端整体校验）", code == 1 and "sh-trip" in out["err"], str(out))
        ck("被拒后商品数不变", len(run(["shop", "--json"])[1]["items"]) == 12)

        # 公开账号：同 App 注册页（邮箱 + 自己的家长密码）
        op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
        req = urllib.request.Request(base + "/api/register", data=json.dumps(
            {"email": "cli.owner@example.test", "p": "emailpass1", "parent": "ownparent1"}).encode(),
            headers={"Content-Type": "application/json"})
        op.open(req, timeout=10).read()
        em = dict(user="cli.owner@example.test", pw="emailpass1")
        code, us, _ = run(["users", "list", "--json"], extra={"EDU_PARENT_PW": "ownparent1"}, **em)
        ck("公开账号 users list 只有自己", code == 0 and us["count"] == 1 and us["scope"] == "account", str(us)[:200])
        code, out, _ = run(["users", "delete", "jingbao", "--yes", "--json"], extra={"EDU_PARENT_PW": "ownparent1"}, **em)
        ck("公开账号删这一家的账号 → 1（403）", code == 1 and out.get("status") == 403, str(out))
        mine = home / "mine.json"
        mine.write_text(json.dumps([dict(x, pts=9) if x["id"] == "sh-anime" else x for x in cfg["shop"]]), encoding="utf-8")
        code, out, _ = run(["config", "put", "shop", "--file", str(mine), "--json"], extra={"EDU_PARENT_PW": "ownparent1"}, **em)
        ck("公开账号改价只进本账号", code == 0 and out["scope"] == "account", str(out))
        price = lambda **kw: next(i["pts"] for i in run(["shop", "--json"], **kw)[1]["items"] if i["id"] == "sh-anime")
        ck("本账号看到 9，这一家仍是 150", price(**em) == 9 and price() == 150)

        print("【资料 / 账号 / 用户管理】")
        code, out, _ = run(["profile", "--nick", "CLI昵称", "--json"], **em)
        ck("profile --nick", code == 0 and out["nick"] == "CLI昵称", str(out))
        ck("me 回读昵称", run(["me", "--json"], **em)[1]["nick"] == "CLI昵称")
        code, out, _ = run(["account", "parent-password", "--json"], **em)
        ck("parent-password 缺 --new-stdin → 2", code == 2)
        code, out, _ = run(["account", "parent-password", "--new-stdin", "--json"], stdin="newparent9\n", **em)
        ck("parent-password 改成功", code == 0)
        ck("新家长密码生效", run(["users", "list", "--json"], extra={"EDU_PARENT_PW": "newparent9"}, **em)[0] == 0)
        code, out, _ = run(["users", "reset-password", "cliowner", "--new-stdin", "--parent-stdin", "--json"],
                           stdin=PARENT_PW + "\nresetpass1\n")
        ck("这一家重置公开账号的密码（stdin：家长密码、新密码）", code == 0, str(out))
        ck("新密码能登录", run(["me", "--json"], user="cli.owner@example.test", pw="resetpass1")[0] == 0)
        code, out, _ = run(["account", "delete", "--json"], user="cli.owner@example.test", pw="resetpass1")
        ck("account delete 不带 --yes → 2", code == 2)
        code, out, _ = run(["account", "delete", "--yes", "--json"], user="cli.owner@example.test", pw="resetpass1")
        ck("account delete --yes（隔离服务端里的一次性账号）", code == 0 and out["deleted"], str(out))
        ck("注销后登录不进 → 1", run(["me", "--json"], user="cli.owner@example.test", pw="resetpass1")[0] == 1)
        code, cfg2, _ = run(["config", "get", "--json"], extra={"EDU_PARENT_PW": PARENT_PW})
        ck("当前服务端：config get 标 server_scoped=true", code == 0 and cfg2.get("server_scoped") is True, str(cfg2)[:120])

        print("【旧服务端】响应不带管理范围时，管理写入不发出去")
        old_server_gate()
    finally:
        if srv:
            srv.terminate()
            srv.wait(timeout=10)
        shutil.rmtree(home, ignore_errors=True)

    print()
    if FAILS:
        print(f"❌ treasury 命令行门：{len(FAILS)} 条没过")
        return 2
    print("✅ treasury 命令行门全过（随 Mac 版打包与安装 / 帮助 / 退出码 / 读 / 记账撤销调账兑换 / 配置范围 / 账号）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
