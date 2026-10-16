#!/usr/bin/env python3
"""Real iOS app on an isolated headless simulator; no input synthesis or physical installation.

--app/--receipt explicitly select a current sim_lane candidate. With neither flag, verify the
already installed app on --udid and require its recorded receipt; never describe a candidate as installed.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import ssl
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
SHARED = Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"
sys.path.insert(0, str(SHARED))
import sim_lane as lane


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def package_files(app):
    return {str(p.relative_to(app)): sha(p) for p in sorted(app.rglob("*")) if p.is_file() and not p.is_symlink()}


def update_server(scratch):
    key, cert = scratch / "update-key.pem", scratch / "update-cert.pem"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key),
                    "-out", str(cert), "-days", "1", "-subj", "/CN=PointsBasicsFixture", "-addext",
                    "subjectAltName=IP:127.0.0.1", "-addext", "basicConstraints=critical,CA:TRUE"],
                   capture_output=True, check=True, timeout=20)
    requests = []
    payload = json.dumps({"results": [{"trackId": 6806799638, "bundleId": "cyou.tianli.pointsdeck", "version": "9.0.0",
                                       "trackViewUrl": "https://apps.apple.com/app/id6806799638"}]}).encode()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            status = 503 if self.path == "/unavailable" else 200
            data = b"{broken" if self.path == "/broken" else payload
            requests.append({"path": self.path, "status": status, "payload_sha256": hashlib.sha256(data).hexdigest()})
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, cert, requests


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--configuration", choices=("Debug", "Release"), default="Debug")
    parser.add_argument("--prepare-candidate", action="store_true", help="use the original admitted Release SDK cache, then test that candidate")
    parser.add_argument("--udid")
    parser.add_argument("--native-ui", action="store_true")
    args = parser.parse_args()
    spec = json.loads(os.environ["SOP_PRODUCT_BASICS_SPEC"])
    assert spec["app_id"] == os.environ["SOP_APP_ID"] == "points-deck-ios"
    out = Path(os.environ["SOP_OUT_DIR"]).resolve()
    assert out.is_relative_to(ROOT / "perf/acceptance")
    if args.prepare_candidate:
        if args.app or args.receipt or args.udid:
            parser.error("--prepare-candidate cannot be combined with --app, --receipt or --udid")
        # The original platform entry owns admission and all build locks. Its
        # persistent, source-verified SDK cache is shared with other checks.
        log = out / "product-basics-prepare.log"
        with log.open("w") as stream:
            prepared = subprocess.run([sys.executable, str(ROOT / "scripts/accept/platform_ui.py"),
                "--phase", "product", "--platform", "iphone", "--out", str(out / "product-basics-build"),
                "--functional-only", "--budget-min", "4"], cwd=ROOT,
                stdout=stream, stderr=subprocess.STDOUT, timeout=245)
        if prepared.returncode:
            print("候选准备推迟或失败，尚未执行功能检查：" + log.read_text()[-1600:], file=sys.stderr)
            return prepared.returncode
        records = [json.loads(line) for line in log.read_text().splitlines()
                   if line.startswith("{") and '"receipt"' in line]
        args.receipt = Path(records[-1]["receipt"])
        args.configuration = "Release"
    run = out / ("product-basics-" + uuid.uuid4().hex)
    run.mkdir(parents=True)
    checks, error, binding = {}, None, {}
    udid, fixture, receipt_lease = None, None, None
    scratch = Path(tempfile.mkdtemp(prefix="points-basics-ledger-"))
    result = {}
    try:
        if args.app or args.receipt:
            if not args.receipt:
                raise ValueError("Candidate requires --receipt from sim_lane build")
            receipt_path = args.receipt.resolve()
            if (not receipt_path.is_file() or
                    not Path(json.loads(receipt_path.read_text()).get("app_path", "")).is_dir()):
                raise lane.Busy("候选原件已过期；使用 --prepare-candidate 沿原车道准备当前候选后再验收")
            receipt_lease = receipt_path.open("rb")  # protect the cache from its existing lsof-aware pruning
            built = lane.reuse_build(receipt_path, "points-deck-ios", ROOT, "iphone", scheme="PointsDeck", configuration=args.configuration)
            app = args.app.resolve() if args.app else Path(built["app_path"])
            if app != Path(built["app_path"]).resolve():
                raise ValueError("--app does not match receipt")
            candidate = True
        else:
            if not args.udid:
                raise ValueError("Default installed mode needs --udid; for a candidate supply --app/--receipt")
            app = Path(lane.simctl("get_app_container", args.udid, "cyou.tianli.pointsdeck", "app").stdout.strip())
            receipt_path = ROOT / "perf/product-basics-installed-receipt.json"
            built = lane.reuse_build(receipt_path, "points-deck-ios", ROOT, "iphone", scheme="PointsDeck", configuration="Debug")
            if sha(app / "PointsDeck") != built["executable_sha256"]:
                raise ValueError("Installed simulator binary differs from recorded receipt")
            candidate = False
        info = plistlib.loads((app / "Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == "cyou.tianli.pointsdeck"
        engine = lane._chapter_engine()
        current_inputs = engine.lane_inputs(engine.load_apps("points-deck-ios")[0], "iphone")
        binding = {"mode": "candidate" if candidate else "installed_simulator", "receipt": str(receipt_path),
                   "receipt_sha256": sha(receipt_path), "executable_sha256": sha(app / "PointsDeck"),
                   "source_sha256": current_inputs["input_sha256"], "version": info["CFBundleShortVersionString"],
                   "build": info["CFBundleVersion"], "app": str(app)}
        package = package_files(app)
        binding["package_files"] = package
        binding["package_sha256"] = hashlib.sha256(json.dumps(package, sort_keys=True).encode()).hexdigest()
        # A fresh device keeps production accounts, preferences and cloud data out of reach.
        device = lane.ensure_device("iphone", "iPhone-17-Pro", "PointsBasics-" + uuid.uuid4().hex[:12])
        udid = device["udid"]
        demo = subprocess.run([sys.executable, str(ROOT / "scripts/demo/ledger.py"), "start", "--dir", str(scratch), "--json"],
                              cwd=ROOT, capture_output=True, text=True, timeout=90)
        if demo.returncode:
            raise RuntimeError("Isolated demo ledger failed: " + demo.stderr[-1200:])
        ledger = json.loads(demo.stdout)
        fixture, cert, requests = update_server(scratch)
        with lane.Session("iphone", udid, label="points-deck-ios:product_basics", lock_wait=30, load_wait=30) as session:
            session.install(app)
            installed = Path(lane.simctl("get_app_container", udid, "cyou.tianli.pointsdeck", "app").stdout.strip())
            installed_files = package_files(installed)
            # Simulator install may alter signatures; all actual executable payloads must stay byte-for-byte.
            checks["settings.installed_candidate_payload"] = all(installed_files.get(k) == v for k, v in package.items()
                                                                  if k.endswith((".dylib", "PointsDeck")))
            lane.simctl("keychain", udid, "add-root-cert", str(cert))
            container = Path(lane.simctl("get_app_container", udid, "cyou.tianli.pointsdeck", "data").stdout.strip())
            source = container / "Documents/product-basics"
            env = dict(os.environ, SIMCTL_CHILD_POINTS_BASICS_API=ledger["url"], SIMCTL_CHILD_POINTS_BASICS_USER=ledger["user"],
                       SIMCTL_CHILD_POINTS_BASICS_PASSWORD=ledger["pw"],
                       SIMCTL_CHILD_POINTS_BASICS_UPDATE_URL=f"https://127.0.0.1:{fixture.server_port}")
            launch = subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", udid,
                                     "cyou.tianli.pointsdeck", "--ui-self-test"], env=env, capture_output=True, text=True, timeout=30)
            (run / "launch.log").write_text(launch.stdout + launch.stderr)
            if launch.returncode:
                raise RuntimeError("Simulator launch failed")
            deadline = time.monotonic() + 150
            while not (source / "raw.json").is_file() and time.monotonic() < deadline:
                time.sleep(0.5)
            if not (source / "raw.json").is_file():
                raise RuntimeError("Real app did not finish self-test in 150s")
            result = json.loads((source / "raw.json").read_text())
            shutil.copytree(source, run / "app-originals")
            checks.update(result["checks"])
            if result.get("observations", {}).get("error"):
                raise RuntimeError(result["observations"]["error"])
            launch = subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", udid,
                                     "cyou.tianli.pointsdeck", "--basics-readback"], env=env, capture_output=True, text=True, timeout=30)
            deadline = time.monotonic() + 25
            while not (source / "readback.json").is_file() and time.monotonic() < deadline:
                time.sleep(0.2)
            actual = json.loads((source / "readback.json").read_text())
            expected = json.loads((source / "expected-readback.json").read_text())
            checks["settings.persisted_readback"] = launch.returncode == 0 and actual == expected
            checks["shortcuts.fresh_process_enabled"] = actual["shortcut_enabled"] is True
            shutil.copytree(source, run / "app-originals", dirs_exist_ok=True)
            # Reject blank screenshots; actual controls/panel are rendered in process, never from desktop pixels.
            from PIL import Image
            for name in ("settings-controls.png", "settings-panel.png", "sync-update-panel.png"):
                im = Image.open(run / "app-originals" / name).convert("RGB")
                checks["settings." + name + ".nonblank"] = len(im.resize((100, 100)).getcolors(10000) or []) > 20
            binding["device"] = {"udid": udid, "runtime": device["runtime"], "environment": "simulator", "headless": True}
            checks["updates.real_https_fixture_requests"] = [r["path"] for r in requests] == ["/valid", "/unavailable", "/broken", "/valid"]
            write(run / "update-server-requests.json", requests)
            binding["update_server_requests_sha256"] = sha(run / "update-server-requests.json")
    except lane.Busy as exc:
        error = str(exc)
        print(error, file=sys.stderr)
        return 75
    except Exception as exc:
        error = str(exc)
    finally:
        if fixture:
            fixture.shutdown()
            fixture.server_close()
        subprocess.run([sys.executable, str(ROOT / "scripts/demo/ledger.py"), "stop", "--dir", str(scratch)], capture_output=True, timeout=30)
        shutil.rmtree(scratch)
        if udid:
            lane.simctl("delete", udid, check=False)
        if receipt_lease:
            receipt_lease.close()
    # Checks are produced by the app and fresh process, then bound to current policy and immutable originals.
    raw = {"schema_version": 1, "app_id": "points-deck-ios", "spec_digest": spec["digest"], "checks": checks,
           "binding": binding, "app_result": result, "error": error,
           "scope": "Current iOS candidate in fresh headless simulator; in-process real UI actions and shared transport; Apple cross-device delivery untested; no installation to phone or Mac, no publication"}
    for feature in spec["features"]:
        for key in spec["features"][feature]["required_checks"]:
            checks.setdefault(key, False)
    raw_path = run / "raw.json"
    write(raw_path, raw)
    features = {}
    for feature in spec["features"]:
        names = [k for k in checks if k.startswith(feature + ".")]
        features[feature] = {"result": "passed" if error is None and all(checks[k] for k in names) else "failed",
                             "method": "ui_automation" if feature == "settings" else "real_product",
                             "evidence": str(raw_path.relative_to(ROOT)), "evidence_sha256": sha(raw_path), "checks": names}
    passed = all(f["result"] == "passed" for f in features.values())
    detail = {"schema_version": 1, "app_id": "points-deck-ios", "spec_digest": spec["digest"], "features": features,
              "summary": f"iOS候选基本功能{'通过' if passed else '失败'}，{sum(checks.values())}/{len(checks)}项；iCloud为隔离链路，苹果跨设备传输未验", "binding": binding}
    write(out / "product_basics.detail.json", detail)
    print(detail["summary"])
    if error:
        print(error, file=sys.stderr)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
