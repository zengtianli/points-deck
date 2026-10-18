#!/usr/bin/env python3
"""Build and run the production localization behavior probe without a GUI.

Run from the repository with the shared Python environment:
  /Users/tianli/Dev/.venv/bin/python scripts/accept/localization_probe.py

Only swiftc/catalog compilation occupies a shared BuildSlot. A busy slot exits 75
immediately so the original Chapter queue can schedule a bounded continuation.
No simulator, device installation, window, Dock item, or network account is used.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shlex
import sys
import tempfile
import uuid

from bounded import Budget


ROOT = Path(__file__).resolve().parents[2]
SIM_LANE = Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"
SOURCE_PATHS = (
    "Shared/PlatformCompat.swift",
    "Shared/RemoteUI.swift",
    "Sources/Skin.swift",
    "Sources/Api.swift",
    "Tests/LocalizationChecks.swift",
)
CATALOG = "Resources/Localizable.xcstrings"
LANGUAGES = ("en", "zh-Hans")


def fingerprints():
    return {
        relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
        for relative in (*SOURCE_PATHS, CATALOG)
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "perf/acceptance/l10n")
    parser.add_argument("--budget-seconds", type=float, default=360)
    args = parser.parse_args()
    out = args.out.expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)
    log_path = out / "probe-build.log"
    log = ["Started: " + datetime.now(timezone.utc).isoformat()]

    def append_log(value):
        log.append(value)
        log_path.write_text("\n".join(log) + "\n")

    sys.path.insert(0, str(SIM_LANE))
    import sim_lane

    bundle = None
    try:
        inputs = fingerprints()
        append_log("Source SHA-256: " + json.dumps(inputs, sort_keys=True))
        env = {**os.environ, "DEVELOPER_DIR": sim_lane.developer_dir("macosx")}
        append_log("DEVELOPER_DIR: " + env["DEVELOPER_DIR"])
        with Budget(args.budget_seconds) as budget:
            def run(command, timeout=180):
                command = list(map(str, command))
                append_log("COMMAND " + shlex.join(command))
                result = budget.run(command, cwd=ROOT, env=env, capture_output=True, timeout=timeout)
                append_log((result.stdout or "") + (result.stderr or "") + "\nEXIT " + str(result.returncode))
                if result.returncode:
                    raise RuntimeError("Probe command failed; see " + str(log_path))
                return result.stdout

            with sim_lane.BuildSlot("Growth Treasury l10n Foundation probe", wait=0):
                bundle = Path(tempfile.mkdtemp(prefix="points-l10n-probe-")) / "LocalizationProbe.app"
                contents = bundle / "Contents"
                binary = contents / "MacOS/LocalizationProbe"
                resources = contents / "Resources"
                binary.parent.mkdir(parents=True)
                resources.mkdir(parents=True)
                (contents / "Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleIdentifier": "cyou.tianli.points.localization-probe." + uuid.uuid4().hex + ".lane",
                    "CFBundleExecutable": "LocalizationProbe",
                    "CFBundlePackageType": "APPL",
                    "CFBundleName": "LocalizationProbe",
                    "CFBundleVersion": "1",
                    "CFBundleShortVersionString": "1.0",
                    "CFBundleDevelopmentRegion": "en",
                    "CFBundleLocalizations": list(LANGUAGES),
                    "LSUIElement": True,
                }))
                append_log("Offscreen probe bundle: " + str(bundle))
                sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).strip()
                run(["xcrun", "xcstringstool", "compile", ROOT / CATALOG,
                     "--output-directory", resources])
                run(["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                     "-target", platform.machine() + "-apple-macos15.0", "-sdk", sdk,
                     *(ROOT / relative for relative in SOURCE_PATHS), "-o", binary], timeout=240)

            for language in LANGUAGES:
                output = run([binary, "-AppleLanguages", "(" + language + ")",
                              "--expect-language", language], timeout=30)
                result = json.loads(output)
                if result.get("passed") is not True or result.get("language") != language:
                    raise RuntimeError("Probe did not confirm language " + language)
                result.update(
                    production_sources=inputs,
                    bundle_path=str(bundle),
                    scope="Production Api.localizedText, AccountHints and shared RemoteUI behavior; direct macOS CLI binary, no GUI or simulator.",
                )
                path = out / ("probe-" + language + ".json")
                path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
                print(json.dumps({"language": language, "passed": True,
                                  "checks": len(result["checks"]), "result": str(path)}), flush=True)

            if fingerprints() != inputs:
                raise RuntimeError("Probe source changed during verification; rerun for current source")
        print(json.dumps({"passed": True, "bundle": str(bundle), "log": str(log_path)}), flush=True)
        return 0
    except sim_lane.Busy as error:
        append_log("RESOURCE WAIT (75): " + str(error))
        print(json.dumps({"blocked": True, "auto": True, "resource": "sim_lane.build",
                          "state": "waiting_resource", "detail": str(error), "exit_code": 75,
                          "log": str(log_path)}), flush=True)
        return 75
    except Exception as error:
        append_log(type(error).__name__ + ": " + str(error))
        print(json.dumps({"passed": False, "detail": str(error),
                          "bundle": str(bundle) if bundle else None, "log": str(log_path)}), flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
