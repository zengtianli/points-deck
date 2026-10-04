#!/usr/bin/env python3
"""A separate XCTest UI runner for source-verified production Apps, plus real paired WC.

The tiny test host follows the shared LaneRotator pattern. It never replaces the
product: XCUIApplication explicitly drives the installed actual Points bundle.
All SDK/runtime work uses the canonical Chapter and native locks; no Simulator UI.
"""
import time
ENTRY_STARTED = time.monotonic()
from pathlib import Path
import argparse
import contextlib
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import urllib.request
from http.cookiejar import CookieJar

REPO = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(Path.home() / "Apps/chapter/engine"),
                 str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios")]
import app_sop
import sim_lane
import yaml
from bounded import Budget, BudgetExpired, current as run_budget


def command(args, cwd, log, timeout=600, env=None):
    with log.open("w") as stream:
        result = run_budget().run(["/bin/bash", "-c", 'source "$1"; shift; scrub_env_run "$@"',
            "points-platform-ui", str(sim_lane.MACAPP / "scrub_env.sh"), *args], cwd=cwd,
            env=env or os.environ, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        code = result.returncode
    if code:
        raise RuntimeError(f"command exited {code}: {log}")


@contextlib.contextmanager
def ownership(label, functional_only=False):
    if os.environ.get("SOP_OWNER_NOW") == "1" or os.environ.get("SIM_LANE_EXTRA_LOCK"):
        raise ValueError("original admission cannot be overridden")
    with (app_sop.STATE_DIR / "lock").open("a+") as global_lock:
        run_budget().lock(global_lock, wait=not functional_only)
        gate = app_sop.steady(False, allow_owner_now=False)
        deadline = time.monotonic() + 600
        while not functional_only and not gate[0] and time.monotonic() < deadline:
            time.sleep(10)
            gate = app_sop.steady(False, allow_owner_now=False)
        if not gate[0] or not app_sop.on_ac_power():
            raise sim_lane.Busy(gate[1])
        locks = sim_lane.lock_chain(label)
        sim_lane.acquire(locks, None, 0, 0, sim_lane.max_load_default())
        try:
            yield
        finally:
            for lock in reversed(locks):
                lock.release()


def build_runner(platform, root):
    test = REPO / "Tests/PlatformUITests.swift"
    sdk = "iphonesimulator" if platform == "ipad" else "xrsimulator"
    key = hashlib.sha256(test.read_bytes() + sim_lane.developer_dir(sdk).encode() + platform.encode()).hexdigest()[:16]
    out = root / (platform + "-ui-" + key)
    ready = out / "runner.json"
    if ready.exists():
        doc = json.loads(ready.read_text())
        if sim_lane.sha256(test) != doc["test_sha256"] or not Path(doc["xctestrun"]).is_file():
            raise ValueError("test-only runner changed")
        return doc
    out.mkdir(parents=True, exist_ok=True)
    source = out / "source"
    (source / "Host").mkdir(parents=True, exist_ok=True)
    (source / "Tests").mkdir(exist_ok=True)
    shutil.copytree(sim_lane.ROTATOR_SRC / "Host", source / "Host", dirs_exist_ok=True)
    shutil.copy2(test, source / "Tests/PlatformUITests.swift")
    native_platform = "iOS" if platform == "ipad" else "visionOS"
    base = {"GENERATE_INFOPLIST_FILE": "YES", "SWIFT_VERSION": "5.0", "PRODUCT_BUNDLE_IDENTIFIER": "cyou.tianli.points.qa.host"}
    if platform == "ipad":
        base.update(TARGETED_DEVICE_FAMILY="1,2", INFOPLIST_KEY_UILaunchScreen_Generation="YES")
    spec = {"name": "PointsUIAcceptance", "options": {"deploymentTarget": {native_platform: "26.0"}}, "targets": {
        "PointsQAHost": {"type": "application", "platform": native_platform, "sources": ["Host"],
            "settings": {"base": base}, "scheme": {"testTargets": ["PointsQAUITests"]}},
        "PointsQAUITests": {"type": "bundle.ui-testing", "platform": native_platform, "sources": ["Tests"],
            "dependencies": [{"target": "PointsQAHost"}], "settings": {"base": {
                **base, "TEST_TARGET_NAME": "PointsQAHost", "PRODUCT_BUNDLE_IDENTIFIER": "cyou.tianli.points.qa.uitests"}}}}}
    (source / "project.yml").write_text(yaml.safe_dump(spec, allow_unicode=True))
    run_budget().run(["/opt/homebrew/bin/xcodegen", "generate", "--spec", "project.yml"], cwd=source,
                   check=True, stdout=subprocess.DEVNULL)
    command(["xcodebuild", "-project", "PointsUIAcceptance.xcodeproj", "-scheme", "PointsQAHost",
             "-configuration", "Debug", "-destination", "generic/platform=" + ("iOS Simulator" if platform == "ipad" else "visionOS Simulator"),
             "-derivedDataPath", str(out / "dd"), "CODE_SIGNING_ALLOWED=NO", "build-for-testing"],
             source, out / "build.log", env={**os.environ, "DEVELOPER_DIR": sim_lane.developer_dir(sdk)})
    runs = list((out / "dd/Build/Products").glob("*.xctestrun"))
    if len(runs) != 1:
        raise ValueError("test-only build did not produce one xctestrun")
    doc = {"test_sha256": sim_lane.sha256(test), "xctestrun": str(runs[0]), "source": str(source),
           "platform": platform, "product_rebuilt": False, "sdk": sdk}
    ready.write_text(json.dumps(doc, indent=1))
    return doc


def run_tests(runner, device, ledger, out, case):
    env = {**os.environ, "DEVELOPER_DIR": sim_lane.developer_dir(runner["sdk"]),
           **{"TEST_RUNNER_POINTS_QA_" + key: ledger[value] for key, value in
              (("BASE", "url"), ("USER", "user"), ("PASSWORD", "pw"))}}
    command(["xcodebuild", "test-without-building", "-xctestrun", runner["xctestrun"],
        "-destination", "id=" + device, "-destination-timeout", "120", "-parallel-testing-enabled", "NO",
        "-collect-test-diagnostics", "never", "-only-testing:PointsQAUITests/PlatformUITests/" + case,
        "-resultBundlePath", str(out / "ui.xcresult")], Path(runner["source"]), out / "ui.log", env=env)
    if "TEST EXECUTE SUCCEEDED" not in (out / "ui.log").read_text(errors="replace"):
        raise RuntimeError("real UI tests did not report success")


def saved_configuration(ledger):
    client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
    request = urllib.request.Request(ledger["url"] + "/api/login",
        data=json.dumps({"u": ledger["user"], "p": ledger["pw"]}).encode(),
        headers={"Content-Type": "application/json"})
    client.open(request, timeout=10).read()
    request = urllib.request.Request(ledger["url"] + "/api/config", data=b"{}",
        headers={"Content-Type": "application/json"})
    config = json.loads(client.open(request, timeout=10).read())
    saved = {}
    for key, label, points in (("rules", "QA-Points-Project", 7), ("shop", "QA-Points-Reward", 4)):
        matches = [row for row in config[key] if row.get("label") == label and row.get("pts") == points]
        if not matches:
            raise RuntimeError("actual native save absent from server configuration: " + label)
        saved[key] = {"label": label, "points": points, "count": len(matches)}
    return saved


def mac_hosted(receipt, connection, out):
    built = sim_lane.reuse_build(receipt, "points-deck-ios", REPO, "mac", "PointsDeck", "Release", False)
    ledger = json.loads(connection.read_text())
    if not ledger["url"].startswith("http://127.0.0.1:"):
        raise ValueError("only isolated ledger allowed")
    test = REPO / "Tests/MacHostedTests.swift"
    root = out / "hosted"
    root.mkdir(parents=True, exist_ok=True)
    clone = sim_lane.uielement_copy(Path(built["app_path"]), root)
    info = sim_lane.bundle_info(clone)
    if not info["bundle_id"].endswith(".lane"):
        raise ValueError("hosted Mac test must use the original isolated lane clone")
    source = root / "source"; source.mkdir(exist_ok=True)
    shutil.copy2(test, source / test.name)
    target = "PointsMacHostedTests"
    spec = {"name": target, "options": {"deploymentTarget": {"macOS": "26.0"}}, "targets": {
        target: {"type": "bundle.unit-test", "platform": "macOS", "sources": [test.name], "settings": {"base": {
            "GENERATE_INFOPLIST_FILE": "YES", "SWIFT_VERSION": "5.0", "PRODUCT_BUNDLE_IDENTIFIER": "cyou.tianli.points.qa.machosted",
            }}, "scheme": {"testTargets": [target]}}}}
    (source / "project.yml").write_text(yaml.safe_dump(spec))
    run_budget().run(["/opt/homebrew/bin/xcodegen", "generate", "--spec", "project.yml"], cwd=source,
                   check=True, stdout=subprocess.DEVNULL)
    command(["xcodebuild", "-project", target + ".xcodeproj", "-scheme", target,
             "-configuration", "Debug", "-destination", "platform=macOS", "-derivedDataPath", str(root / "dd"),
             "CODE_SIGNING_ALLOWED=NO", "build-for-testing"], source, out / "build.log",
             env={**os.environ, "DEVELOPER_DIR": sim_lane.developer_dir("macosx")})
    runs = list((root / "dd/Build/Products").glob("*.xctestrun"))
    if len(runs) != 1: raise ValueError("Mac test-only build lacks one actual xctestrun")
    document = plistlib.loads(runs[0].read_bytes())
    found = False
    def arguments(value):
        nonlocal found
        if isinstance(value, dict):
            if "TestHostPath" in value:
                value["TestHostPath"] = str(clone)
                value["TestHostBundleIdentifier"] = info["bundle_id"]
                value["IsAppHostedTestBundle"] = True
                value.setdefault("TestingEnvironmentVariables", {})["DYLD_INSERT_LIBRARIES"] = "__PLATFORMS__/MacOSX.platform/Developer/usr/lib/libXCTestBundleInject.dylib"
                value["CommandLineArguments"] = ["-lane_quiet", "YES", "-api_base", ledger["url"],
                    "-dev_user", ledger["user"], "-dev_pw", ledger["pw"], "-tab", "2"]
                found = True
            for child in value.values(): arguments(child)
        elif isinstance(value, list):
            for child in value: arguments(child)
    arguments(document)
    if not found: raise ValueError("actual Mac test host metadata absent")
    private_run = runs[0].with_name("private.xctestrun")
    private_run.write_bytes(plistlib.dumps(document)); private_run.chmod(0o600)
    front = sim_lane.front_app()
    try:
        command(["xcodebuild", "test-without-building", "-xctestrun", str(private_run), "-destination", "platform=macOS",
            "-collect-test-diagnostics", "never", "-parallel-testing-enabled", "NO", "-resultBundlePath", str(out / "ui.xcresult")],
            source, out / "ui.log", env={**os.environ, "DEVELOPER_DIR": sim_lane.developer_dir("macosx")})
        if "TEST EXECUTE SUCCEEDED" not in (out / "ui.log").read_text(errors="replace"):
            raise RuntimeError("Mac actual hosted test did not succeed")
        if sim_lane.front_bundle(sim_lane.front_app()) == info["bundle_id"]:
            raise RuntimeError("hosted Mac test took focus")
        sim_lane.reuse_build(receipt, "points-deck-ios", REPO, "mac", "PointsDeck", "Release", False)
        proof = {"ok": True, "platform": "mac", "environment": "native", "scope": "actual offscreen Mac window, native Cmd-W menu mapping and its window close selector",
            "receipt_sha256": sim_lane.sha256(receipt), "test_sha256": sim_lane.sha256(test), "product_rebuilt": False,
            "original_executable_sha256": built["executable_sha256"], "clone_bundle_id": info["bundle_id"],
            "front_changed": sim_lane.front_app() != front, "focus_taken": False}
        (out / "proof.json").write_text(json.dumps(proof, indent=1) + "\n")
        print(json.dumps(proof))
    finally:
        with run_budget().cleanup():
            for pid in sim_lane.pids_of(info["executable"]):
                sim_lane.mac_terminate(pid, clone)
            private_run.unlink(missing_ok=True)


def main(argv=None):
    entered = ENTRY_STARTED
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--phase", choices=("product", "build", "ui", "watch"), required=True)
    ap.add_argument("--platform", choices=("ipad", "vision", "mac"), default="ipad")
    ap.add_argument("--receipt", type=Path)
    ap.add_argument("--connection", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--budget-min", type=float, default=30, help="total time including admission and cleanup")
    ap.add_argument("--functional-only", action="store_true", help="one admission check; defer immediately if busy, without a performance wait")
    a = ap.parse_args(argv)
    try:
        with Budget(a.budget_min * 60, entered):
            result = run(a)
            run_budget().timeout(1, cleanup=True)
            return result
    except (BudgetExpired, subprocess.TimeoutExpired, BlockingIOError, sim_lane.Busy):
        print(json.dumps({"ok": False, "deferred": True, "reason": "time budget exhausted or original lane busy",
                          "elapsed_seconds": round(time.monotonic() - entered, 3)}))
        return 75
    except ValueError as error:
        ap.error(str(error))


def run(a):
    a.out.mkdir(parents=True, exist_ok=True)
    started = run_budget().started
    try:
        with ownership("Points real native UI / paired WC", a.functional_only):
            if a.phase == "product":
                sys.path.insert(0, str(Path.home() / "Apps/.claude/skills/app-lightweight/scripts"))
                import platform_measure
                with contextlib.ExitStack() as leases:
                    built = platform_measure.cached_build("points-deck-ios", REPO, a.platform,
                                                         "PointsDeck", False, leases)
                    receipt = Path(built["work_dir"]) / "build.json"
                    sim_lane.reuse_build(receipt, "points-deck-ios", REPO, a.platform, "PointsDeck", "Release", False)
                    print(json.dumps({"ok": True, "receipt": str(receipt), "receipt_sha256": sim_lane.sha256(receipt)}))
                return 0
            if a.platform == "mac":
                if a.phase != "ui": raise ValueError("Mac hosted acceptance uses ui phase with the actual Release receipt")
                mac_hosted(a.receipt, a.connection, a.out)
                return 0
            runner = build_runner(a.platform, a.out / "runners")
            if a.phase == "build":
                print(json.dumps({"ok": True, "runner": runner}))
                return 0
            built = sim_lane.reuse_build(a.receipt, "points-deck-ios", REPO, a.platform if a.phase == "ui" else "iphone", "PointsDeck", "Release", False)
            ledger = json.loads(a.connection.read_text())
            if not ledger["url"].startswith("http://127.0.0.1:"):
                raise ValueError("only isolated server allowed")
            phone = None; watch = None
            before = sim_lane.simulator_app_pids()
            app = app_sop.load_apps("points-deck-ios")[0]
            digest = app_sop.lane_inputs(app, a.platform if a.phase == "ui" else "watch")["input_sha256"]
            try:
                if a.phase == "ui":
                    cfg = app["sop"]["platforms"][a.platform]["simulator"]
                    phone = sim_lane.ensure_device(a.platform, cfg["device_type"])["udid"]
                    sim_lane.boot(phone, 420)
                    sim_lane.simctl("install", phone, built["app_path"])
                    run_tests(runner, phone, ledger, a.out, "testCoreEditingAndReopen")
                    (a.out / "saved-config.json").write_text(json.dumps(saved_configuration(ledger), indent=1))
                else:
                    phone = sim_lane.ensure_device("iphone", "iPhone-17-Pro", "Points Pair Phone")["udid"]
                    watch = sim_lane.ensure_device("watch", "Apple-Watch-Series-12-46mm", "Points Pair Watch")["udid"]
                    pairs = json.loads(sim_lane.simctl("list", "pairs", "--json").stdout)["pairs"]
                    existing = [row for row in pairs.values() if row["phone"]["udid"] == phone or row["watch"]["udid"] == watch]
                    if not existing:
                        sim_lane.simctl("pair", watch, phone)
                    elif len(existing) != 1 or existing[0]["phone"]["udid"] != phone or existing[0]["watch"]["udid"] != watch:
                        raise ValueError("dedicated pair associated elsewhere")
                    # simctl pair returns before device_set.plist is flushed.
                    # Activate only our dedicated pair, then await both native records.
                    pairs = json.loads(sim_lane.simctl("list", "pairs", "--json").stdout)["pairs"]
                    pair_ids = [key for key, row in pairs.items()
                                if row["phone"]["udid"] == phone and row["watch"]["udid"] == watch]
                    if len(pair_ids) != 1:
                        raise ValueError("dedicated native pair absent or ambiguous")
                    if not pairs[pair_ids[0]]["state"].startswith("(active,"):
                        sim_lane.simctl("pair_activate", pair_ids[0])
                    deadline = time.monotonic() + 20
                    while True:
                        active = plistlib.loads((Path.home() / "Library/Developer/CoreSimulator/Devices/device_set.plist").read_bytes())["DevicePairs"]
                        peers = [(key, value) for key, value in active.items() if value.get("companion") == phone or value.get("gizmo") == watch]
                        if (len(peers) == 1 and peers[0][0] == pair_ids[0] and
                            peers[0][1].get("companion") == phone and
                            peers[0][1].get("gizmo") == watch and peers[0][1].get("active") is True):
                            break
                        if time.monotonic() >= deadline:
                            raise ValueError("actual CoreSimulator pair is not the active peer")
                        time.sleep(.5)
                    (a.out / "actual-pair.json").write_text(json.dumps({"pair_id": peers[0][0], "phone": phone, "watch": watch, "active": True}, indent=1))
                    for udid in (phone, watch):
                        sim_lane.boot(udid, 420)
                    watch_app = sim_lane.find_product(Path(built["app_path"]) / "Watch", "PointsDeckWatch")
                    sim_lane.simctl("install", phone, built["app_path"])
                    sim_lane.simctl("install", watch, str(watch_app))
                    # No Watch login arguments or cookie/context injection anywhere in this path.
                    stream = sim_lane.ReadyStream("cyou.tianli.pointsdeck.watchkitapp", watch)
                    import threading
                    observed = {}
                    def observe():
                        observed["watch_home_ready_at"] = stream.ready_at(150)
                        if observed["watch_home_ready_at"]:
                            stream.settled_at(15)
                            sim_lane.simctl("io", watch, "screenshot", str(a.out / "watch-signed-in.png"))
                    waiter = threading.Thread(target=observe); waiter.start()
                    try:
                        sim_lane.simctl("launch", "--terminate-running-process", watch, "cyou.tianli.pointsdeck.watchkitapp", "-api_base", ledger["url"])
                        run_tests(runner, phone, ledger, a.out, "testPhoneWatchLogout")
                        waiter.join(160)
                        if not observed.get("watch_home_ready_at"):
                            raise RuntimeError("real WC never entered WatchHome; no injected login fallback")
                        sim_lane.simctl("io", watch, "screenshot", str(a.out / "watch-signed-out.png"))
                        (a.out / "watch-receive.json").write_text(json.dumps(observed, indent=1))
                    finally:
                        stream.close()
                        waiter.join(5)
                if sim_lane.simulator_app_pids() - before:
                    raise RuntimeError("UI tests unexpectedly opened Simulator.app")
                if app_sop.lane_inputs(app, a.platform if a.phase == "ui" else "watch")["input_sha256"] != digest:
                    raise RuntimeError("production input changed during tests")
            finally:
                with run_budget().cleanup():
                    for device in (watch, phone):
                        if device:
                            sim_lane.shutdown(device)
            proof = {"ok": True, "phase": a.phase, "platform": a.platform if a.phase == "ui" else "watch",
                     "input_sha256": digest, "receipt_sha256": sim_lane.sha256(a.receipt),
                     "test_sha256": runner["test_sha256"], "seconds": round(time.monotonic() - started, 1),
                     "environment": "simulator", "product_rebuilt": False,
                     "watch_credentials_injected": False if a.phase == "watch" else None,
                     "cleanup": "owned devices shutdown; canonical locks released on exit"}
            (a.out / "proof.json").write_text(json.dumps(proof, indent=1) + "\n")
            print(json.dumps(proof))
    except (BlockingIOError, sim_lane.Busy) as error:
        print(json.dumps({"ok": False, "deferred": True, "reason": str(error)}, ensure_ascii=False))
        return 75
    return 0


if __name__ == "__main__":
    sys.exit(main())
