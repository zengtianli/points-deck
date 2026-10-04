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
        email="cli-new@example.test"
        challenge=ok(["account","code-send","--purpose","register","--email",email])["challenge"]
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
        # 仅传输为替身；CLI 子进程仍访问正在运行的同一个产品 HTTP 服务。
        import account_phone
        from test_phone_account import FakePNVS
        from unittest.mock import patch
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
