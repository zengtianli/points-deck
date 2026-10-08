#!/usr/bin/env python3
"""Production Cookie persistence across immediate process exits; no UI input.

python3 Tests/account_session_persistence.py --out /private/tmp/points-session --platform mac|ipad
The iPad diagnostic uses the original lane admission and a private test bundle,
not the complete product UI. It never sends real mail/SMS or edits production users.
"""
from pathlib import Path
import argparse, hashlib, json, os, platform, plistlib, re, subprocess, sys, uuid

ROOT = Path(__file__).resolve().parents[1]
ENV = {"PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(Path.home()),
       "LANG": "en_US.UTF-8", "PYTHONDONTWRITEBYTECODE": "1"}

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--platform", choices=("mac", "ipad"), default="mac")
    a = ap.parse_args(); a.out.mkdir(parents=True, exist_ok=False); a.out.chmod(0o700)
    os.environ.clear(); os.environ.update(ENV)
    secret_values = []
    def command(args, name, env=None, timeout=120):
        r = subprocess.run(args, cwd=ROOT, env=env or ENV, capture_output=True, timeout=timeout)
        data = r.stdout + r.stderr
        for value in secret_values: data = data.replace(value.encode(), b"<redacted>")
        data = re.sub(rb"gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{30,}", b"<redacted>", data)
        log = a.out/(name+".log"); log.write_bytes(data); log.chmod(0o600)
        if r.returncode: raise RuntimeError(name+" failed; see redacted log")
        return r
    py = Path.home()/"Dev/.venv/bin/python"
    fixture = a.out/"fixture"; device = None
    sdk = "macosx" if a.platform == "mac" else "iphonesimulator"
    sys.path[:0] = [str(ROOT/"scripts/accept"), str(Path.home()/"Dev/tools/dev/lib/tools/macapp/ios")]
    import sim_lane
    from bounded import Budget
    from platform_ui import ownership
    # Mac Foundation probe has no GUI or simulator resource. iPad follows the
    # same locks and load checks as the project's original native lane.
    import contextlib
    gate = contextlib.nullcontext() if a.platform == "mac" else ownership("Points immediate Cookie persistence", True)
    with Budget(600), gate:
        r = subprocess.run([str(py), "scripts/demo/ledger.py", "start", "--dir", str(fixture), "--json"],
                           cwd=ROOT, env=ENV, capture_output=True, timeout=90)
        if r.returncode: raise RuntimeError("isolated fixture failed")
        ledger = json.loads((fixture/"ledger.json").read_text())
        secret_values.extend([ledger["pw"], ledger["parent_pw"]])
        try:
            if a.platform == "mac":
                app = a.out/"SessionProbe.app"; contents = app/"Contents"; binary = contents/"MacOS/probe"
                info = contents/"Info.plist"; target = platform.machine()+"-apple-macos15.0"
            else:
                app = a.out/"SessionProbe.app"; binary = app/"probe"; info = app/"Info.plist"
                target = platform.machine()+"-apple-ios26.0-simulator"
            binary.parent.mkdir(parents=True)
            identifier = "cyou.tianli.points.session-probe."+uuid.uuid4().hex+".lane"
            properties = {"CFBundleIdentifier": identifier, "CFBundleExecutable": "probe", "CFBundlePackageType": "APPL",
                          "CFBundleName": "SessionProbe", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0"}
            if a.platform == "mac": properties["LSUIElement"] = True
            else: properties.update(MinimumOSVersion="26.0", UIDeviceFamily=[1, 2], UILaunchScreen={},
                                    UIApplicationSceneManifest={"UIApplicationSupportsMultipleScenes":False,
                                    "UISceneConfigurations":{"UIWindowSceneSessionRoleApplication":[{"UISceneConfigurationName":"Probe"}]}})
            info.write_bytes(plistlib.dumps(properties))
            resources = app/"Contents/Resources" if a.platform == "mac" else app
            resources.mkdir(parents=True, exist_ok=True)
            private = resources/"fixture.json"; private.write_text(json.dumps({k:ledger[k] for k in ("url", "user", "pw")})); private.chmod(0o600)
            sources = [ROOT/p for p in ("Shared/PlatformCompat.swift", "Shared/RemoteUI.swift", "Sources/Skin.swift",
                                       "Sources/Api.swift", "Tests/account_session_persistence.swift")]
            fingerprints = {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
            env = {**ENV, "DEVELOPER_DIR":sim_lane.developer_dir(sdk)}
            sdkpath = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], env=env).decode().strip()
            command(["xcrun", "--sdk", sdk, "swiftc", "-parse-as-library", "-target", target, "-sdk", sdkpath,
                     *map(str, sources), "-o", str(binary)], "build", env)
            command(["codesign", "--force", "--sign", "-", str(app)], "sign", env)
            before = sim_lane.simulator_app_pids()
            if a.platform == "ipad":
                device = sim_lane.ensure_device("ipad", "iPad-Pro-13-inch-M5-12GB", "Points Cookie Probe")["udid"]
                sim_lane.boot(device, 180)
                command(["xcrun", "simctl", "install", device, str(app)], "install", env)
            for mode in ("login", "restore", "logout", "signedout"):
                if a.platform == "mac":
                    r = command([str(binary), mode], mode, {**env,"CFFIXED_USER_HOME":str(a.out/"home")}, 30)
                else:
                    r = command(["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device, identifier, mode], mode, env, 45)
                if ("SESSION-PASS: "+mode).encode() not in r.stdout: raise RuntimeError(mode+" pass missing")
                print("SESSION-PASS: "+a.platform+" "+mode, flush=True)
            if sim_lane.simulator_app_pids() - before: raise RuntimeError("unexpected Simulator.app")
            if any(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h for p,h in fingerprints.items()):
                raise RuntimeError("source changed during regression")
            proof = {"passed":True,"platform":a.platform,"processes":4,"immediate_exit":True,
                     "production_sources":fingerprints,"assertions":["wrong password 401", "login original account",
                     "Cookie survives immediate exit and new process", "logout Cookie removal survives immediate exit"],
                     "scope":"same production Api and real isolated server; diagnostic bundle, not complete native UI", "real_messages_sent":0}
            (a.out/"proof.json").write_text(json.dumps(proof, ensure_ascii=False, indent=2)+"\n")
            print(json.dumps({"passed":True,"proof":str(a.out/"proof.json")}))
        finally:
            if device: sim_lane.simctl("shutdown", device, check=False)
            subprocess.run([str(py),"scripts/demo/ledger.py","stop","--dir",str(fixture)],cwd=ROOT,env=ENV,capture_output=True,timeout=30)

if __name__ == "__main__":
    try: main()
    except Exception as error:
        print("session regression stopped: "+type(error).__name__, file=sys.stderr); sys.exit(1)
