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
import time

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


def invoke(arguments, log, timeout=555):
    with log.open("w") as stream:
        result = subprocess.run([sys.executable, str(ROOT / "scripts/accept/platform_ui.py"),
            *arguments, "--functional-only", "--budget-min", "9"], cwd=ROOT,
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
        # A resource refusal before XCTest started may resume when admission
        # changes. Once a native result exists, an interrupted run must first
        # be diagnosed; never overwrite or rerun that result on the same input.
        partial_native = code == 75 and (directory / "native/ui.xcresult").exists()
        write(attempt, {"exit_code": "partial_native_run" if partial_native else code,
                        "actual_exit_code": code, "phase": "ui", "account_input_sha256": binding})
        if code:
            if partial_native:
                return None, "原生测试已产生中断原件，先定位执行预算或车道原因，不重复相同输入：" + str(directory / "native")
            return None, "原生密码登录车道推迟或失败，见 " + str(directory / "lane.log")
        native = directory / "native/proof.json"
        assert native.is_file() and json.loads(native.read_text()).get("ok") is True
        assert [s["step"] for s in steps] == LOCAL_STEPS
        assert current(app) == binding
        proof = {"account_input_sha256": binding, "client_environment": "actual Release iPhone simulator App through original XCTest lane",
                 "service_environment": "isolated current production server; synthetic original ledger only",
                 "native_proof": str(native.relative_to(ROOT)), "native_proof_sha256": sha(native),
                 "receipt": str(receipt), "receipt_sha256": sha(receipt), "steps": steps,
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


FULL_STEPS = {
    "EmailLifecycle": {"native-policies-read-and-closed", "email-registration", "business-use", "email-change",
                       "password-change", "logout", "email-recovery-and-data", "email-account-deletion"},
    "EmailBinding": {"email-wrong-code-then-correct", "email-binding-preserved", "email-binding-login"},
    "PhoneLifecycle": {"phone-wrong-code-then-correct", "phone-registration", "business-use", "phone-password-set", "phone-login",
                       "phone-recovery-and-data", "phone-account-deletion"},
    "PhoneBinding": {"phone-binding-peer-start", "phone-binding-preserved", "phone-change-peer-start", "phone-change-preserved"},
    "PasswordlessDeletion": {"phone-registration", "passwordless-account-deletion"},
}
FULL_CASES = {
    "EmailLifecycle": ("registration", "password_change", "password_recovery", "account_deletion", "data_preservation",
                       "email_verification", "email_change", "email_delivery"),
    "EmailBinding": ("email_binding",),
    "PhoneLifecycle": ("phone_verification", "phone_login", "sms_delivery"),
    "PhoneBinding": ("phone_binding", "phone_change"),
    "PasswordlessDeletion": (),
}


def verified_full(path, binding):
    """Validate current original UI, service and native peer proofs, not a result label."""
    proof = json.loads(path.read_text())
    case = proof["case"]
    if (case not in FULL_STEPS or proof.get("exit_code") != 0 or proof.get("offline_diagnostic_only") is not False
            or proof.get("account_input_sha256") != binding
            or proof.get("producer_sha256") != sha(ROOT / "scripts/accept/account_native.py")):
        raise ValueError("Current real native account proof missing or changed")
    if {s["step"] for s in proof["steps"]} != FULL_STEPS[case]:
        raise ValueError("A required actual native checkpoint is absent")
    if set(proof["source_sha256"]) != {"server.py", "account_security.py", "account_phone.py",
                                      "AccountUITests.swift", "platform_ui.py", "account_peer.py"}:
        raise ValueError("The complete observed service/test input map is required")
    for name, digest in proof["source_sha256"].items():
        candidate = (Path.home() / "Apps/edu/web/points" / name if name in
                     ("server.py", "account_security.py", "account_phone.py") else
                     ROOT / ("Tests" if name.endswith("Tests.swift") else "scripts/accept") / name)
        if sha(candidate) != digest:
            raise ValueError("Observed service or native test changed: " + name)
    native_path = path.parent / "native/proof.json"
    native = json.loads(native_path.read_text())
    if (sha(native_path) != proof.get("native_proof_sha256") or native.get("ok") is not True
            or native.get("receipt_sha256") != proof["receipt_sha256"]):
        raise ValueError("Native product receipt differs from observed account proof")
    checks = [value for step in proof["steps"] for value in step["checks"].values()]
    if (any(not step["checks"] for step in proof["steps"]) or not checks
            or any(type(value) not in (bool, int) or value < 1 for value in checks)):
        raise ValueError("An actual account assertion was false")
    for event in proof["events"]:
        if event.get("coordinator_failure") or str(event.get("transport", "")).startswith("mock"):
            raise ValueError("An actual checkpoint failed or used a mock")
        if event.get("native_peer"):
            peer_path = path.parent.parent / event["proof"]
            peer = json.loads(peer_path.read_text())
            if (sha(peer_path) != event.get("proof_sha256") or peer.get("ok") is not True or peer.get("cookie_injected") is not False
                    or peer.get("receipt_sha256") != proof["receipt_sha256"]):
                raise ValueError("Independent native session proof missing")
    channel = "mail" if case.startswith("Email") else "sms"
    if (proof.get(channel + "_transport") != "real" or type(proof["messages_sent"][channel]) is not int
            or proof["messages_sent"][channel] < 1):
        raise ValueError("Real delivery is required")
    received_key = "imap_received" if channel == "mail" else "actual_device_forward_received"
    if not any(event.get(received_key) is True for event in proof["events"]):
        raise ValueError("Provider acceptance alone is not actual receipt")
    return proof


def interrupted_native_original(path):
    """A 75 after native execution or message dispatch is not a clean admission refusal."""
    record = json.loads(path.read_text())
    return record.get("exit_code") == 75 and bool(
        record.get("steps") or (path.parent / "native/ui.log").exists()
        or any(record.get("messages_attempted", {}).values())
        or any(record.get("messages_sent", {}).values()))


def full(app, local_path, detail, binding):
    """One bounded pass of the original real-transport coordinator; never retry failed inputs."""
    producers = [ROOT / "scripts/accept" / name for name in
                 ("account_native.py", "account_peer.py", "platform_ui.py")]
    key = hashlib.sha256((binding + "".join(sha(p) for p in producers)
                          + sha(ROOT / "Tests/AccountUITests.swift")).encode()).hexdigest()[:20]
    directory = ROOT / "perf/account/native-current" / key
    directory.mkdir(parents=True, exist_ok=True)
    directory.chmod(0o700)
    contract = directory / "contract.json"
    if not contract.exists():
        verified_local(local_path, binding)
        write(contract, {"execution_state": "authorized_20261016_continuation", "allow_real_transports": True,
                         "authorization": "Chapter 2026-10-16 complete native account acceptance and release",
                         "resumption_deadline_epoch": time.time() + 3600,
                         "limits": {"sms": 12, "mail": 20}, "historical_contracts_unchanged": True})
    receipt = Path(json.loads(local_path.read_text())["receipt"])
    product_log = directory / "product.jsonl"
    product_log.write_text(json.dumps({"receipt": str(receipt)}) + "\n")
    pending = []
    completed = {}
    executed = False
    for case in FULL_STEPS:
        records = sorted(directory.glob("account-" + case + "-*/evidence.json"))
        successful = next((p for p in records if json.loads(p.read_text()).get("exit_code") == 0), None)
        if not successful:
            attempt = directory / (case + "-attempt.json")
            if attempt.exists() and json.loads(attempt.read_text()).get("exit_code") != 75:
                pending.append(case + "已有当前输入的失败，先回读原件，不重复发信：" + str(attempt))
                break
            if any(json.loads(p.read_text()).get("exit_code") != 75 or interrupted_native_original(p) for p in records):
                pending.append(case + "已有当前输入的原生失败或中断原件，先定位，不重复发信：" + str(records[-1]))
                break
            if executed:
                pending.append("已保存一个完整原生流程，剩余流程交原队列有界接续")
                break
            log = directory / (case + ".log")
            with log.open("w") as stream:
                result = subprocess.run(["/opt/homebrew/bin/uv", "run", "--script", str(producers[0]), case,
                    "--platform", "iphone", "--product-log", str(product_log)], cwd=ROOT,
                    env={**os.environ, "POINTS_ACCOUNT_RUN_ROOT": str(directory), "POINTS_ACCOUNT_INPUT_SHA256": binding},
                    stdout=stream, stderr=subprocess.STDOUT, timeout=1980)
            write(attempt, {"case": case, "exit_code": result.returncode, "account_input_sha256": binding})
            executed = True
            records = sorted(directory.glob("account-" + case + "-*/evidence.json"))
            if result.returncode:
                pending.append(case + "原车道推迟或原生失败：" + str(log))
                break
            successful = records[-1] if records else None
        if not successful:
            raise ValueError("Real coordinator did not retain an original")
        observed = verified_full(successful, binding)
        completed[case] = (successful, observed)
        detail.update(client_environment="source-verified actual Release iPhone simulator; original XCTest UI",
                      service_environment="isolated current production server; actual Mailu/Aliyun transports; no production accounts")
        detail["mail_transport" if case.startswith("Email") else "sms_transport"] = "real"
        for name in FULL_CASES[case]:
            detail.setdefault("account_cases", {})[name] = {"status": "passed", "evidence": str(successful.relative_to(ROOT)),
                                                           "evidence_sha256": sha(successful)}
    if "EmailBinding" in completed and "PhoneLifecycle" in completed:
        guard = next((e for e in completed["PhoneLifecycle"][1]["events"] if e.get("actual_http_abuse_guards")), {})
        checks = {"email_wrong_code_refused_before_same_challenge_success": True,
                  "phone_wrong_code_refused_before_same_challenge_success": True,
                  "same_sms_request_does_not_send_twice": guard.get("same_request_replayed_without_send") is True,
                  "new_sms_request_inside_resend_window_refused": guard.get("resend_refused_status") == 429,
                  "resend_limit_preserves_provider_send_count": guard.get("provider_send_count_unchanged") is True}
        if all(checks.values()):
            raw = directory / "abuse-protection.json"
            write(raw, {"account_input_sha256": binding, "checks": checks,
                        "native_originals": [{"path": str(p.relative_to(ROOT)), "sha256": sha(p)}
                                             for p, _ in completed.values()],
                        "scope": "actual native wrong-code recovery in both channels plus original HTTP SMS idempotency and resend throttle"})
            detail.setdefault("account_cases", {})["abuse_protection"] = {"status": "passed", "evidence": str(raw.relative_to(ROOT)),
                                                                         "evidence_sha256": sha(raw)}
    return pending


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-local", action="store_true", help="produce actual native no-message login/logout evidence if absent")
    parser.add_argument("--run-full", action="store_true", help="after local native pass, continue bounded real authorized mail/phone flows")
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
    if args.run_local or args.run_full:
        key = hashlib.sha256((binding + sha(__file__) + sha(ROOT / "Tests/AccountUITests.swift")
                              + sha(ROOT / "scripts/accept/platform_ui.py")).encode()).hexdigest()[:20]
        directory = ROOT / "perf/account/native-local" / key
        local_was_ready = (directory / "native-password.json").exists()
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
            if args.run_full:
                if not local_was_ready:
                    pending = "无发信原生流程已保存，真实通道流程交原队列下一步接续"
                else:
                    try:
                        pending = "；".join(full(app, proof, detail, binding)) or None
                    except Exception as error:
                        pending = type(error).__name__ + ": " + str(error)
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
