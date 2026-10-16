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
import re
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
from unittest.mock import patch

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
    sys.path.insert(0, str(SERVER.parent))
    from test_treasury_prd import TreasuryPRD
    fixture = TreasuryPRD("runTest")
    fixture.setUp()
    try:
        env = {k:v for k,v in os.environ.items() if not k.startswith("EDU_")}
        env.update(EDU_API_BASE=fixture.base, EDU_USER="family", EDU_PASSWORD="old-short")
        def run(args, stdin="", account=None):
            custom=dict(env)
            if account: custom.update(EDU_USER=account[0], EDU_PASSWORD=account[1])
            r=subprocess.run([str(CLI), *args, "--json"],input=stdin,env=custom,text=True,capture_output=True,timeout=20)
            return r.returncode,json.loads(r.stdout or "{}")
        def ok(args, **kw):
            code,j=run(args,**kw)
            ck(' '.join(args[:2]),code==0,str(j));return j
        before=ok(["state"])["balance"]
        ea=ok(["earn","tr-show","--request-id","cli-stable-request-01"])
        again=ok(["earn","tr-show","--request-id","cli-stable-request-01"])
        ck("无家长密码且同标识只记一笔",ea["entry"]["id"]==again["entry"]["id"] and ok(["state"])["balance"]==before+100)
        ok(["request-result","cli-stable-request-01"])
        ok(["undo",ea["entry"]["id"]]);ok(["undo",ea["entry"]["id"]])
        ck("重复撤销恢复余额",ok(["state"])["balance"]==before)
        cfg=ok(["config","get"]);ck("旧账号家庭覆盖层",cfg["scope"]=="account" and cfg.get("revision"))
        file=Path(fixture.temp.name)/"shop-edit.json"
        items=cfg["shop"]+[{"id":"cli-reward","label":"家庭活动","pts":2,"requires_tier":False}]
        file.write_text(json.dumps(items))
        ok(["config","put","shop","--file",str(file),"--revision",cfg["revision"]])
        ck("旧版本配置冲突",run(["config","put","shop","--file",str(file),"--revision",cfg["revision"]])[1].get("status")==409)
        ok(["spend","cli-reward","--expected-pts","2","--request-id","cli-reward-request-01"])
        ok(["trend","--span","0"])
        # ── 给 Agent 的约定：顶层帮助四样、version 读回、失败形状、界面对照里新补的读命令 ──
        def bare(args, creds=False):
            custom = dict(env)
            if not creds: custom.pop("EDU_USER"); custom.pop("EDU_PASSWORD")
            r = subprocess.run([str(CLI), *args], env=custom, text=True, capture_output=True, timeout=20, stdin=subprocess.DEVNULL)
            return r.returncode, r.stdout, r.stderr
        code, top, _ = bare(["--help"])
        ck("顶层帮助退出 0", code == 0)
        tail = top[top.index("暂无命令"):] if "暂无命令" in top else ""
        window = top[top.index("仅在窗口中"):top.index("暂无命令")] if tail else ""
        ck("帮助区分 App 设置与 CLI 沙盒边界，不把现有偏好迁移说成没有",
           all(w in tail for w in ("检查更新", "升级到新版", "退出登录")) and "配置的 iCloud 同步" not in tail
           and "退出登录" not in window and "偏好迁移" in tail and "本 App 没有可迁移" not in tail, tail)
        for word in ("读命令", "写命令", "--json 输出形状", "退出码", "仅在窗口中", "暂无命令"):
            ck(f"顶层帮助有「{word}」", word in top)
        ck("顶层帮助的退出码表列了 0 / 1 / 2 / 130", all(re.search(rf"(?m)^\s+{n}\s", top) for n in (0, 1, 2, 130)), top[-900:])
        for name in ("version", "state", "entries", "trend", "export", "shop", "tiers", "rules", "me", "request-result",
                     "preview", "earn", "adjust", "undo", "spend", "config", "profile", "account", "users"):
            ck(f"顶层帮助把 {name} 列为命令", re.search(rf"(?m)^\s+(?:treasury\s+)?{name}(?![\w-])", top) is not None)
        code, out, _ = bare(["version", "--json"])
        ver = json.loads(out)
        ck("version 不登录 → 0，报版本、服务端可达、凭据未给", code == 0 and ver["ok"] is True and ver["cli"]
           and ver["server"]["reachable"] is True and ver["credentials"] == {"user": False, "password": False}, out)
        ck("version 给了凭据只报「已给」", ok(["version"])["credentials"] == {"user": True, "password": True})
        code, j = run(["entries", "--no-such-flag"])
        ck("参数写错带 --json → 2，ok:false 与 error.code=usage", code == 2 and j.get("ok") is False and j["error"]["code"] == "usage", str(j))
        code, _, err = bare(["entries", "--no-such-flag"], creds=True)
        ck("参数写错不带 --json → 2，照 argparse 原样写 stderr", code == 2 and "unrecognized arguments" in err, err[-200:])
        code, j = run(["spend", "no-such-reward"])
        ck("服务端拒绝 → 1，error.code=rejected，原有 err / status 不变",
           code == 1 and j["error"] == {"code": "rejected", "message": j["err"]} and j.get("status"), str(j))
        redeem = ok(["entries", "--filter", "redeem", "--limit", "0"])["entries"]
        ck("entries --filter redeem 只有兑换", len(redeem) >= 1 and all(e["kind"] == "spend" for e in redeem), str(redeem)[:200])
        earned = ok(["entries", "--filter", "earn", "--limit", "0"])["entries"]
        ck("entries --filter earn 只有加分", all(e["pts"] > 0 for e in earned), str(earned)[:200])
        deducted = ok(["entries", "--filter", "deduct", "--limit", "0"])["entries"]
        ck("entries --filter deduct 只有非兑换的减分", all(e["pts"] < 0 and e["kind"] != "spend" for e in deducted), str(deducted)[:200])
        recent, full = ok(["entries", "--limit", "0"]), ok(["entries", "--all", "--limit", "0"])
        ck("entries --all 取到全部流水（不少于默认窗口）", full["window"] >= recent["window"] and full["window"] == full["total"], f"{recent['window']} {full['window']} {full['total']}")
        ledger = Path(fixture.temp.name) / "ledger-export.json"
        exported = ok(["export", "--out", str(ledger)])
        dumped = json.loads(ledger.read_text(encoding="utf-8"))
        ck("export 写出整本账（同 App 导出账本）", exported["out"] == str(ledger.resolve()) and exported["bytes"] == ledger.stat().st_size
           and len(dumped["entries"]) == exported["entries"] == full["window"] and dumped["balance"] == ok(["state"])["balance"], str(exported))
        ck("export 不覆盖已有文件 → 2", run(["export", "--out", str(ledger)])[0] == 2)
        ok(["export", "--out", str(ledger), "--force"])
        me = ok(["me"])
        ck("me 带账号安全页的邮箱、手机与近期安全记录", isinstance(me.get("security_events"), list) and "email" in me and "phone" in me, str(me))
        ck("当前账号没有在办的注销申请", ok(["account", "delete-status"]).get("receipt_id") is None)
        email="cli-new@example.test"
        # Deterministic valid edge: change only the random identifier, not the
        # production challenge verification or registration implementation.
        import account_security
        token_urlsafe = account_security.secrets.token_urlsafe
        with patch.object(account_security.secrets, "token_urlsafe",
                          side_effect=lambda n=32: "-" + token_urlsafe(n)[1:] if n == 24 else token_urlsafe(n)):
            challenge=ok(["account","code-send","--purpose","register","--email",email])["challenge"]
        ck("实际服务生成以连字符开头的有效挑战", challenge.startswith("-") and len(challenge) == 32)
        code=re.search(r"验证码：(\d{6})",fixture.mail[-1][2]).group(1)
        grant=ok(["account","code-verify","--challenge",challenge],stdin=code+"\n")["grant"]
        password="a unique long passphrase"
        reg=ok(["account","register","--email",email,"--new-stdin"],stdin=password+"\n"+grant+"\n")
        account=(email,password)
        ck("验证码注册新户从零起步",ok(["state"],account=account)["balance"]==0)
        ck("普通户不能重置其他账号",run(["users","reset-password","family","--parent-stdin","--new-stdin"],stdin="site-management-only\nnew long unique phrase\n",account=account)[0]==1)
        ck("无确认不注销",run(["account","delete"],account=account)[0]==2)
        ok(["account","delete","--yes"],account=account)
        ck("注销后不可登录",run(["me"],account=account)[0]==1)
        # 注销申请与进度（同 App 注销页：即时注销 409 时改递申请，凭回执不登录也能查）
        email2 = "cli-request@example.test"
        challenge = ok(["account", "code-send", "--purpose", "register", "--email", email2])["challenge"]
        code = re.search(r"验证码：(\d{6})", fixture.mail[-1][2]).group(1)
        grant = ok(["account", "code-verify", "--challenge=" + challenge], stdin=code + "\n")["grant"]
        ok(["account", "register", "--email", email2, "--new-stdin"], stdin=password + "\n" + grant + "\n")
        second = (email2, password)
        ck("无确认不递注销申请", run(["account", "delete-request"], account=second)[0] == 2)
        ck("无确认时没有产生申请", ok(["account", "delete-status"], account=second).get("receipt_id") is None)
        asked = ok(["account", "delete-request", "--yes"], account=second)
        ck("注销申请受理并给回执", bool(asked.get("receipt_id")) and asked.get("status") not in (None, "completed"), str(asked))
        ck("登录后读到同一份申请", ok(["account", "delete-status"], account=second).get("receipt_id") == asked["receipt_id"])
        code, out, _ = bare(["account", "delete-status", "--receipt", asked["receipt_id"], "--json"])
        ck("凭回执不登录也能查进度", code == 0 and json.loads(out).get("status") == asked["status"], out)
        code, out, _ = bare(["account", "delete-status", "--receipt", "no-such-receipt", "--json"])
        ck("回执不存在 → 1 且 404", code == 1 and json.loads(out).get("status") == 404, out)
        code, j = run(["account", "delete", "--yes"], account=second)
        ck("申请在办时即时注销被拒（409）", code == 1 and j.get("status") == 409, str(j))
        # 仅传输为替身；CLI 子进程仍访问正在运行的同一个产品 HTTP 服务。
        import account_phone
        from test_phone_account import FakePNVS
        from contextlib import closing
        gateway = FakePNVS()
        service = account_phone.PhoneChallenges(fixture.server.HOME, fixture.server.load_cfg()["secret"])
        number = "13800000000"
        def sms_grant(purpose, login_grant=None):
            with closing(service.connect()) as db, db:
                db.execute("DELETE FROM hits WHERE bucket=?", ("sms-resend:" + service.digest(account_phone.phone(number)),))
            args = (["--phone-grant-stdin"] if login_grant else []) + ["account", "phone-send", "--purpose", purpose, "--phone", number]
            challenge = ok(args, stdin=(login_grant + "\n") if login_grant else "")["challenge"]
            return ok(["account", "phone-verify", "--challenge", challenge], stdin="246810\n")["grant"]
        with patch.object(account_phone, "gateway", return_value=gateway):
            registered = ok(["account", "phone-register", "--agree"], stdin=sms_grant("register") + "\n")
            ck("CLI 手机注册未强迫设密码",registered["has_password"] is False)
            identity = sms_grant("phone_identity", sms_grant("login"))
            login = sms_grant("login")
            phone_password = "a separate CLI phone phrase"
            ok(["--phone-grant-stdin", "account", "password-set", "--identity-grant-stdin", "--new-stdin"], stdin=login+"\n"+identity+"\n"+phone_password+"\n")
            ck("CLI 手机密码登录仍读原零分账本",ok(["state"],account=(number,phone_password))["balance"]==0)
            ck("CLI 手机密码设置后沿原ID",ok(["me"],account=(number,phone_password))["user"]==registered["u"])
    finally:
        fixture.tearDown()
    print(f"CLI 回归：{len(FAILS)} 项失败")
    return 2 if FAILS else 0

if __name__ == "__main__":
    raise SystemExit(main())
