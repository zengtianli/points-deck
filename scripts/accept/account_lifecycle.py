#!/usr/bin/env python3
"""Real native password-flow producer and strict full-account evidence consumer.

The local producer sends no messages. It uses the existing source-verified
Release builder, original UI admission/locks and AccountUITests, against a
temporary production server. Missing email/phone cases always remain pending.
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
import app_sop


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(path)


def current(app):
    return app_sop.monitor_inputs(app, {})["bindings"]["account"]


LOCAL_CHECKS = {"wrong_password_refused_then_native_login", "native_session_survives_relaunch",
                "native_logout_survives_relaunch", "original_ledger_preserved"}
LOCAL_STEPS = ["native-password-login", "native-session-restore", "native-logout-reopen"]


def verified_local(path, binding):
    proof = json.loads(path.read_text())
    if (proof.get("account_input_sha256") != binding or set(proof.get("checks", {})) != LOCAL_CHECKS
            or any(value is not True for value in proof["checks"].values())
            or [step.get("step") for step in proof.get("steps", [])] != LOCAL_STEPS
            or any(step.get("original_ledger_unchanged") is not True for step in proof["steps"])
            or proof.get("messages_sent") != {"sms": 0, "mail": 0}):
        raise ValueError("Native password proof is incomplete or belongs to different inputs")
    native = (ROOT / proof["native_proof"]).resolve(strict=True)
    native.relative_to(path.parent.resolve())
    if sha(native) != proof["native_proof_sha256"] or json.loads(native.read_text()).get("ok") is not True:
        raise ValueError("Native UI original changed or did not pass")
    return proof


def invoke(arguments, log, timeout=245):
    with log.open("w") as stream:
        result = subprocess.run([sys.executable, str(ROOT / "scripts/accept/platform_ui.py"),
            *arguments, "--functional-only", "--budget-min", "4"], cwd=ROOT,
            stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    return result.returncode


def local(app, receipt, directory, binding):
    """Return a real raw proof path, or a deferred/failed observation; never a fabricated pass."""
    target = directory / "native-password.json"
    attempt = directory / "attempt.json"
    if target.exists():
        verified_local(target, binding)
        return target, None
    if attempt.exists() and json.loads(attempt.read_text()).get("exit_code") not in (None, 75):
        return None, "相同客户端、测试和执行脚本已有原生失败；先修原件所示原因，不重复执行"
    directory.mkdir(parents=True, exist_ok=True)
    if receipt is None:
        code = invoke(["--phase", "product", "--platform", "iphone", "--out", str(directory / "build")],
                      directory / "build.log")
        if code:
            write(attempt, {"exit_code": code, "phase": "product", "account_input_sha256": binding})
            return None, "原生产候选构建车道推迟或失败，见 " + str(directory / "build.log")
        records = [json.loads(line) for line in (directory / "build.log").read_text().splitlines()
                   if line.startswith("{") and '"receipt"' in line]
        receipt = Path(records[-1]["receipt"])
    scratch = Path(tempfile.mkdtemp(prefix="points-account-local-"))
    server = control = worker = coordinator = None
    events, steps = [], []
    try:
        created = subprocess.run([sys.executable, str(ROOT / "scripts/demo/ledger.py"), "start",
                                  "--dir", str(scratch), "--json"], cwd=ROOT,
                                 capture_output=True, text=True, timeout=90)
        if created.returncode:
            raise RuntimeError("Original isolated ledger could not start")
        ledger = json.loads(created.stdout)
        subprocess.run([sys.executable, str(ROOT / "scripts/demo/ledger.py"), "stop", "--dir", str(scratch)],
                       cwd=ROOT, check=True, capture_output=True, timeout=30)
        # Observe real production responses. No handler, auth, rate limit, mail
        # or SMS implementation is replaced; only response metadata is recorded.
        os.environ.update(EDU_POINTS_HOME=str(scratch / "home"), EDU_POINTS_STATIC=str(scratch / "static"),
                          EDU_POINTS_PORT=str(ledger["port"]))
        backend = Path.home() / "Apps/edu/web/points"
        sys.path.insert(0, str(backend))
        import server as product
        original_ledger = product.load_ledger(ledger["user"])
        original_signature = hashlib.sha256(json.dumps(original_ledger, sort_keys=True).encode()).hexdigest()

        class Observed(product.H):
            def log_message(self, *args):
                pass

            def _json(self, status, obj, cookie=None):
                events.append({"path": self.path, "status": status})
                return super()._json(status, obj, cookie)

        server = product.ThreadingHTTPServer(("127.0.0.1", ledger["port"]), Observed)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        token = secrets.token_hex(32)

        class Coordinator(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                try:
                    if self.headers.get("X-Points-QA") != token:
                        raise ValueError("Unauthorised coordinator")
                    step = self.path.removeprefix("/mark/")
                    if step not in ("native-password-login", "native-session-restore", "native-logout-reopen"):
                        raise ValueError("Unexpected native checkpoint")
                    signature = hashlib.sha256(json.dumps(product.load_ledger(ledger["user"]), sort_keys=True).encode()).hexdigest()
                    assert signature == original_signature
                    assert ledger["user"] in product.load_users()["users"]
                    if step == "native-password-login":
                        assert [e["status"] for e in events if e["path"] == "/api/login"] == [401, 200]
                    elif step == "native-session-restore":
                        assert events[-1] == {"path": "/api/state", "status": 200}
                    else:
                        assert any(e == {"path": "/api/logout", "status": 200} for e in events)
                        assert events[-1] == {"path": "/api/state", "status": 401}
                    steps.append({"step": step, "original_ledger_unchanged": True, "events": list(events)})
                    reply = {"ok": True}
                except Exception as error:
                    reply = {"ok": False, "error_class": type(error).__name__}
                data = json.dumps(reply).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        control = ThreadingHTTPServer(("127.0.0.1", 0), Coordinator)
        coordinator = threading.Thread(target=control.serve_forever, daemon=True)
        coordinator.start()
        ledger["qa"] = {"COORDINATOR": "http://127.0.0.1:" + str(control.server_port),
                        "COORDINATOR_TOKEN": token, "ACCOUNT_PASSWORD": ledger["pw"], "MODE": "PasswordLogin"}
        connection = scratch / "native-connection.json"
        write(connection, ledger)
        code = invoke(["--phase", "ui", "--platform", "iphone", "--case", "testAccountPasswordLogin",
                       "--receipt", str(receipt), "--connection", str(connection), "--out", str(directory / "native")],
                      directory / "lane.log")
        # XCTest can log typed strings. Retain only redacted text; no xcresult
        # is published or copied into the public raw evidence.
        for log in directory.rglob("*.log"):
            data = log.read_bytes()
            for secret in (ledger["pw"], token):
                data = data.replace(secret.encode(), b"<redacted>")
            log.write_bytes(data)
        write(attempt, {"exit_code": code, "phase": "ui", "account_input_sha256": binding})
        if code:
            return None, "原生密码登录车道推迟或失败，见 " + str(directory / "lane.log")
        native = directory / "native/proof.json"
        assert native.is_file() and json.loads(native.read_text()).get("ok") is True
        assert [s["step"] for s in steps] == LOCAL_STEPS
        assert current(app) == binding
        proof = {"account_input_sha256": binding, "client_environment": "actual Release iPhone simulator App through original XCTest lane",
                 "service_environment": "isolated current production server; synthetic original ledger only",
                 "native_proof": str(native.relative_to(ROOT)), "native_proof_sha256": sha(native),
                 "receipt_sha256": sha(receipt), "steps": steps,
                 "checks": {"wrong_password_refused_then_native_login": True, "native_session_survives_relaunch": True,
                            "native_logout_survives_relaunch": True, "original_ledger_preserved": True},
                 "messages_sent": {"sms": 0, "mail": 0}, "mail_transport": "not_tested", "sms_transport": "not_tested",
                 "limitations": ["Does not certify registration, email/phone flows, password changes, deletion or full abuse protection."]}
        write(target, proof)
        verified_local(target, binding)
        return target, None
    finally:
        for service, thread in ((control, coordinator), (server, worker)):
            if service:
                service.shutdown()
                service.server_close()
                thread.join(5)
        with contextlib.suppress(Exception):
            subprocess.run([sys.executable, str(ROOT / "scripts/demo/ledger.py"), "stop", "--dir", str(scratch)],
                           cwd=ROOT, capture_output=True, timeout=30)
        shutil.rmtree(scratch)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-local", action="store_true", help="produce actual native no-message login/logout evidence if absent")
    parser.add_argument("--receipt", type=Path, help="existing source-verified sim_lane Release iPhone candidate")
    args = parser.parse_args()
    app = app_sop.load_apps("points-deck-ios")[0]
    binding = current(app)
    source = ROOT / "perf/account/account-lifecycle.json"
    detail = json.loads(source.read_text()) if source.exists() else {}
    if detail.get("account_input_sha256") != binding:
        detail["historical_account_cases"] = detail.pop("account_cases", {})
        detail["account_cases"] = {}
    pending = None
    if args.run_local:
        key = hashlib.sha256((binding + sha(__file__) + sha(ROOT / "Tests/AccountUITests.swift")
                              + sha(ROOT / "scripts/accept/platform_ui.py")).encode()).hexdigest()[:20]
        directory = ROOT / "perf/account/native-local" / key
        try:
            proof, pending = local(app, args.receipt, directory, binding)
        except Exception as error:
            proof, pending = None, type(error).__name__ + ": " + str(error)
            write(directory / "attempt.json", {"exit_code": "unknown", "account_input_sha256": binding,
                                               "error_class": type(error).__name__})
        if proof:
            detail.update(client_environment="actual Release iPhone simulator", service_environment="isolated current production server")
            for case in ("login", "logout", "data_preservation"):
                detail.setdefault("account_cases", {})[case] = {"status": "passed", "evidence": str(proof.relative_to(ROOT)),
                                                               "evidence_sha256": sha(proof)}
    detail["account_input_sha256"] = binding
    issues = app_sop.account_evidence_issues(app, detail)
    if pending:
        issues.append(pending)
    detail["issues"] = issues
    detail["summary"] = "账号闭环待实际验收：" + "；".join(issues) if issues else "原生账号逐项流程与真实投递原件通过"
    write(Path(os.environ.get("SOP_OUT_DIR", ROOT / "perf/acceptance")) / "account_lifecycle.detail.json", detail)
    print(detail["summary"])
    return 75 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
