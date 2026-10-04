#!/usr/bin/env python3
"""Select the actual embedded Watch from a Chapter-built iOS Release receipt.

No SDK build or simulator operation. Producer facts remain unchanged;
sim_lane independently validates both receipts and all current sources.
"""
from pathlib import Path
import argparse
import json
import sys

REPO = Path(__file__).resolve().parents[2]
APP = "points-deck-ios"
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import sim_lane


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--parent-receipt", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    parent = args.parent_receipt.resolve()
    built = json.loads(parent.read_text())
    producer = built["platform"]
    if producer not in ("iphone", "ipad"):
        raise ValueError("producer must be the original iOS Simulator build")
    sim_lane.reuse_build(parent, APP, REPO, producer, "PointsDeck", "Release", False)
    args.out.mkdir(parents=True, exist_ok=True)
    phone = Path(built["app_path"])
    watch = sim_lane.find_product(phone / "Watch", "PointsDeckWatch")
    info = sim_lane.bundle_info(watch)
    child = dict(built)
    child.update(platform="watch", target_scheme="PointsDeckWatch", app_path=str(watch),
                 bundle_id=info["bundle_id"], version=info["version"], build=info["build"],
                 sdk=info["sdk"], executable_sha256=sim_lane.sha256(Path(info["executable"])),
                 embedded_watch_origin={"receipt": str(parent), "receipt_sha256": sim_lane.sha256(parent),
                                        "iphone_app": str(phone), "watch_app": str(watch)})
    child_path = args.out.resolve() / "watch-Release.json"
    child_path.write_text(json.dumps(child, ensure_ascii=False, indent=1) + "\n")
    sim_lane.reuse_build(parent, APP, REPO, "ipad", "PointsDeck", "Release", False)
    sim_lane.reuse_build(child_path, APP, REPO, "watch", "PointsDeckWatch", "Release", False)
    manifest = {"schema_version": 1, "app_id": APP, "platforms": {
        lane: {"size_receipt": str(path), "runtime_receipt": str(path)}
        for lane, path in (("ipad", parent), ("watch", child_path))}}
    target = args.out.resolve() / "release-manifest.json"
    target.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n")
    print(json.dumps({"ok": True, "manifest": str(target), "sha256": sim_lane.sha256(target),
                      "parent_receipt": str(parent), "watch_receipt": str(child_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
