#!/usr/bin/env python3
"""Record the current five tabs and settings from the actual headless iPhone App.

Uses the original admitted SDK cache and XCTest lane. Continuous simctl video,
actual native taps, and source-bound timestamps are retained. No desktop capture,
fake pointer, screenshot slideshow, personal account or physical installation.
"""
import argparse
import datetime as dt
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

PAGES = [("ledger", "账本"), ("trend", "走势"), ("score", "加分"),
         ("shop", "兑换"), ("account", "账户"), ("settings", "设置")]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def run(args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, timeout=kwargs.pop("timeout", 240), **kwargs)


def lane(args, log):
    with log.open("w") as stream:
        return subprocess.run([sys.executable, str(ROOT / "scripts/accept/platform_ui.py"), *args,
            "--functional-only", "--budget-min", "5"], cwd=ROOT,
            stdout=stream, stderr=subprocess.STDOUT, timeout=310).returncode


def stamp(seconds):
    ms = round(seconds * 1000)
    return f"{ms // 3600000:02}:{ms // 60000 % 60:02}:{ms // 1000 % 60:02}.{ms % 1000:03}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--device-type", choices=("iPhone-17-Pro", "iPhone-17-Pro-Max"), default="iPhone-17-Pro-Max",
                        help="capture the product's registered APP_IPHONE_67 store size with the same verified SDK candidate")
    args = parser.parse_args()
    app = app_sop.load_apps("points-deck-ios")[0]
    source = app_sop.app_source_snapshot(app, app["sop"]["ui"])["sha256"]
    inputs = {str(path.relative_to(ROOT)): sha(path) for path in
              (Path(__file__), ROOT / "Tests/PlatformUITests.swift", ROOT / "scripts/accept/platform_ui.py")}
    key = source[:16] + "-" + hashlib.sha256(json.dumps([inputs, args.device_type], sort_keys=True).encode()).hexdigest()[:12]
    base = ROOT / "perf/media/current"
    out = base / key
    out.mkdir(parents=True, exist_ok=True)
    meta = base / "provenance.json"
    if meta.exists():
        previous = json.loads(meta.read_text())
        if (previous.get("ui_source_sha256") == source and previous.get("producer_inputs") == inputs
                and previous.get("device_type") == args.device_type):
            for relative, digest in previous["artifacts"].items():
                if sha(ROOT / relative) != digest:
                    raise ValueError("Existing actual capture artifact changed; not re-recording blindly")
            print("当前源码的真实连续录像与截图原件仍有效，跳过录制")
            return 0
    if (out / "native/ui.xcresult").exists():
        raise ValueError("This capture has a native test result; read it and fix the cause before retrying unchanged inputs")
    receipt = args.receipt
    if receipt is None:
        code = lane(["--phase", "product", "--platform", "iphone", "--out", str(out / "build")], out / "build.log")
        if code:
            print("当前素材候选准备推迟或失败：" + (out / "build.log").read_text()[-1200:])
            return code
        records = [json.loads(line) for line in (out / "build.log").read_text().splitlines()
                   if line.startswith("{") and '"receipt"' in line]
        receipt = Path(records[-1]["receipt"])
    scratch = Path(tempfile.mkdtemp(prefix="points-current-media-"))
    coordinator = thread = None
    checkpoints = []
    token = secrets.token_hex(32)
    ledger = {}
    try:
        created = run([sys.executable, str(ROOT / "scripts/demo/ledger.py"), "start", "--dir", str(scratch), "--json"],
                      capture_output=True, text=True, timeout=90)
        ledger = json.loads(created.stdout)

        class Coordinator(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                event = self.path.strip("/")
                allowed = [name + "/" + action for name, _ in PAGES for action in ("start", "still", "end")]
                accepted = self.headers.get("X-Points-QA") == token and event in allowed
                if accepted:
                    checkpoints.append({"event": event, "epoch": time.time()})
                self.send_response(200 if accepted else 403)
                self.send_header("Content-Length", "0")
                self.end_headers()

        coordinator = ThreadingHTTPServer(("127.0.0.1", 0), Coordinator)
        thread = threading.Thread(target=coordinator.serve_forever, daemon=True)
        thread.start()
        ledger["qa"] = {"COORDINATOR": "http://127.0.0.1:" + str(coordinator.server_port), "COORDINATOR_TOKEN": token}
        connection = scratch / "native.json"
        write(connection, ledger)
        connection.chmod(0o600)
        code = lane(["--phase", "ui", "--platform", "iphone", "--case", "testCurrentProductTour", "--record-video",
                     "--device-type", args.device_type,
                     "--receipt", str(receipt), "--connection", str(connection), "--out", str(out / "native")], out / "lane.log")
        if code:
            print("当前素材原生车道推迟或失败：" + str(out / "lane.log"))
            return code
    finally:
        if coordinator:
            coordinator.shutdown(); coordinator.server_close(); thread.join(5)
        subprocess.run([sys.executable, str(ROOT / "scripts/demo/ledger.py"), "stop", "--dir", str(scratch)],
                       cwd=ROOT, capture_output=True, timeout=30)
        shutil.rmtree(scratch)
        for log in out.rglob("*.log"):
            data = log.read_bytes()
            for secret in (ledger.get("pw", ""), token):
                if secret:
                    data = data.replace(secret.encode(), b"<redacted>")
            log.write_bytes(data)
    expected = [name + "/" + action for name, _ in PAGES for action in ("start", "still", "end")]
    assert [point["event"] for point in checkpoints] == expected
    assert app_sop.app_source_snapshot(app, app["sop"]["ui"])["sha256"] == source
    assert all(sha(ROOT / relative) == digest for relative, digest in inputs.items())
    native = out / "native"
    assert json.loads((native / "proof.json").read_text())["ok"] is True
    recording = json.loads((native / "recording.json").read_text())
    origin = recording["requested_at_epoch"]
    start = max(0, checkpoints[0]["epoch"] - origin - 1)
    duration = checkpoints[-1]["epoch"] - origin - start + .3
    source_video = native / "continuous.mp4"
    sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
    import store_shots
    probe = json.loads(run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(source_video)],
                           capture_output=True, text=True).stdout)
    stream = next(item for item in probe["streams"] if item["codec_type"] == "video")
    if (stream["width"], stream["height"]) not in store_shots.TYPE_SIZES["APP_IPHONE_67"]:
        raise ValueError("Actual capture does not match the registered APP_IPHONE_67 store dimensions")
    video = out / "tour.mp4"
    run(["ffmpeg", "-v", "error", "-nostdin", "-y", "-ss", str(start), "-i", str(source_video),
         "-t", str(duration), "-an", "-c:v", "libx264", "-threads", "2", "-crf", "20", "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", str(video)])
    shots = ROOT / "shots/current-iphone"
    shots.mkdir(parents=True, exist_ok=True)
    captions = ["WEBVTT", ""]
    actions = []
    for index, (name, label) in enumerate(PAGES):
        first, still, last = checkpoints[index * 3:index * 3 + 3]
        a, b = first["epoch"] - origin - start, last["epoch"] - origin - start
        captions += [f"{stamp(max(0, a))} --> {stamp(min(duration, b))}", f"{label}：当前源码的真实 iPhone 模拟器界面", ""]
        image = out / (name + ".png")
        run(["ffmpeg", "-v", "error", "-nostdin", "-y", "-ss", str(max(0, still["epoch"] - origin - start - .3)),
             "-i", str(video), "-frames:v", "1", "-threads", "2", str(image)])
        shutil.copy2(image, shots / f"{index + 1:02}-{name}.png")
        actions.append({"page": name, "start": a, "end": b, "action": "actual native tab tap" if name != "settings" else "actual native settings open and close"})
    (out / "tour.vtt").write_text("\n".join(captions))
    shutil.copy2(out / "ledger.png", out / "poster.png")
    run(["ffmpeg", "-v", "error", "-nostdin", "-threads", "2", "-i", str(video), "-f", "null", "-"], timeout=120)
    artifacts = {str(path.relative_to(ROOT)): sha(path) for path in
                 [video, out / "tour.vtt", out / "poster.png", *out.glob("*.png"), source_video, native / "proof.json", native / "recording.json"]}
    write(out / "checkpoints.json", checkpoints)
    artifacts[str((out / "checkpoints.json").relative_to(ROOT))] = sha(out / "checkpoints.json")
    write(meta, {"schema_version": 1, "recorded_at": dt.datetime.fromtimestamp(checkpoints[-1]["epoch"], dt.timezone(dt.timedelta(hours=8))).isoformat(),
                 "ui_source_sha256": source, "producer_inputs": inputs, "capture_kind": "continuous",
                 "device_type": args.device_type, "store_display_type": "APP_IPHONE_67",
                 "environment": "headless iPhone simulator, actual production Release App and original XCTest lane",
                 "receipt_sha256": sha(receipt), "actions": actions, "artifacts": artifacts,
                 "video": str(video.relative_to(ROOT)), "captions": str((out / "tour.vtt").relative_to(ROOT)),
                 "limitations": ["Silent current-interface preview; historical narrated clips retained separately.",
                                 "No physical-device, account transport or cross-device iCloud validation is claimed."]})
    print("当前六屏真实连续录像、截图、字幕与原始SHA已保存：" + str(meta))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
