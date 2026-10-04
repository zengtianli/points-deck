#!/usr/bin/env python3
"""Execute production cache/journal/Snapshot storage across four fresh Mac processes.

Only a unique synthetic HTTPS account and .lane Snapshot service are written.
No server requests use the synthetic HTTPS URL; no installed App's entries change.
"""
from pathlib import Path
import fcntl
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import uuid
import urllib.request
from http.cookiejar import CookieJar

REPO = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(Path.home() / "Apps/chapter/engine"),
                 str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios")]
import app_sop
import sim_lane


def main():
    connection = Path(sys.argv[1])
    output = Path(sys.argv[2])
    ledger = json.loads(connection.read_text())
    if not ledger["url"].startswith("http://127.0.0.1:"):
        raise ValueError("only isolated ledger allowed")
    output.mkdir(parents=True, exist_ok=True)
    locks = []
    try:
        with (app_sop.STATE_DIR / "lock").open("a+") as global_lock:
            fcntl.flock(global_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            gate = app_sop.steady(False, allow_owner_now=False)
            if not gate[0] or not app_sop.on_ac_power():
                raise sim_lane.Busy(gate[1])
            locks = sim_lane.lock_chain("Points production storage cross-process check")
            sim_lane.acquire(locks, None, 0, 0, sim_lane.max_load_default())
            with tempfile.TemporaryDirectory(prefix="points-storage.", dir="/private/tmp") as scratch:
                root = Path(scratch)
                app = root / "Storage.app/Contents"
                (app / "MacOS").mkdir(parents=True)
                identifier = "cyou.tianli.points.storage." + uuid.uuid4().hex + ".lane"
                (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier,
                    "CFBundleExecutable": "check", "CFBundlePackageType": "APPL", "LSUIElement": True}))
                sources = [REPO / name for name in ("Shared/PlatformCompat.swift", "Sources/Skin.swift",
                    "Sources/Api.swift", "Sources/Snapshot.swift", "scripts/accept/storage.swift")]
                fingerprints = {str(p.relative_to(REPO)): sim_lane.sha256(p) for p in sources}
                executable = app / "MacOS/check"
                with (output / "build.log").open("w") as log:
                    subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                        "-target", os.uname().machine + "-apple-macos15.0", *map(str, sources), "-o", str(executable)],
                        stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
                subprocess.run(["codesign", "--force", "--sign", "-", str(app.parent)], check=True,
                               capture_output=True, timeout=30)
                opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
                data = json.dumps({"u": ledger["user"], "p": ledger["pw"]}).encode()
                opener.open(urllib.request.Request(ledger["url"] + "/api/login", data=data,
                    headers={"Content-Type": "application/json"}), timeout=10).read()
                state = json.loads(opener.open(ledger["url"] + "/api/state", timeout=10).read())
                user = uuid.uuid4().hex
                state["u"] = user
                fixture = root / "state.json"
                fixture.write_text(json.dumps(state, ensure_ascii=False)); fixture.chmod(0o600)
                env = {**os.environ, "CFFIXED_USER_HOME": str(root / "home"),
                    "POINTS_STORAGE_BASE": "https://" + user + ".invalid", "POINTS_STORAGE_USER": user,
                    "POINTS_STORAGE_STATE": str(fixture)}
                lines = []
                try:
                    for mode in ("save", "restore", "clear", "verify-clear"):
                        reply = subprocess.run([str(executable)], env={**env, "POINTS_STORAGE_MODE": mode},
                            capture_output=True, text=True, timeout=30)
                        lines.extend(reply.stdout.splitlines())
                        if reply.returncode:
                            raise RuntimeError((reply.stderr or reply.stdout)[-600:])
                finally:
                    subprocess.run([str(executable)], env={**env, "POINTS_STORAGE_MODE": "clear"},
                                   capture_output=True, timeout=30)
                if any(sim_lane.sha256(REPO / p) != digest for p, digest in fingerprints.items()):
                    raise RuntimeError("production storage changed during execution")
                proof = {"ok": True, "environment": "native", "scope": "actual Keychain storage, independent processes",
                    "production_sources": fingerprints, "assertions": lines, "processes": 4,
                    "installed_product_entries_changed": False, "limitations": "Mac Keychain execution; simulator Keychain/Widget groups are separate scopes"}
                (output / "proof.json").write_text(json.dumps(proof, ensure_ascii=False, indent=1) + "\n")
                print(json.dumps(proof, ensure_ascii=False))
    except (BlockingIOError, sim_lane.Busy) as error:
        print(json.dumps({"ok": False, "deferred": True, "reason": str(error)}, ensure_ascii=False))
        return 75
    finally:
        for lock in reversed(locks): lock.release()
    return 0


if __name__ == "__main__":
    sys.exit(main())
