#!/usr/bin/env python3
"""对账「主 app 与 Widget 落在同一个 keychain 仓」—— 在**构建产物**上验，不看源码。

为什么必须验产物：这条契约的载体是 `.entitlements` 里数组的**第一项**（代码里
故意不传 `kSecAttrAccessGroup`，让 keychain 用 entitlement 的第一个组）。
写错的表现是**编译通过、装机通过、小组件永远空着** —— 没有任何一处报错。
源码 grep 也验不了，因为 `$(AppIdentifierPrefix)` 是构建期才展开的。

fail-closed：找不到产物、解析不出、两边不一致，一律非零退出。
「没找到 .app 所以跳过」不算绿。

    python3 check_shared_group.py [derivedDataPath]     # 默认 .dd-device
"""
from __future__ import annotations

import plistlib
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEY = "keychain-access-groups"
BANNED = "com.apple.security.application-groups"


def entitlements(binary_dir: Path) -> dict:
    """读一个 .app/.appex 已签名的真实 entitlements。"""
    p = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(binary_dir)],
                       capture_output=True)
    if p.returncode != 0 or not p.stdout:
        raise SystemExit(f"❌ 读不出 {binary_dir.name} 的 entitlements（codesign rc="
                         f"{p.returncode}）：{p.stderr.decode()[:200]}")
    try:
        return plistlib.loads(p.stdout)
    except Exception as e:                                   # noqa: BLE001
        raise SystemExit(f"❌ {binary_dir.name} 的 entitlements 解析失败：{e}")


def main() -> int:
    dd = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / ".dd-device"
    prod = dd / "Build" / "Products"
    apps = sorted(prod.glob("*-iphoneos/PointsDeck.app"))
    if not apps:
        print(f"❌ 在 {prod} 下没找到 PointsDeck.app —— 先构建。"
              f"（枚举为空一律判红，不在空集上报绿）")
        return 2
    app = apps[0]
    exts = sorted(app.glob("PlugIns/*.appex"))
    if not exts:
        print(f"❌ {app} 里没有 PlugIns/*.appex —— Widget 根本没被打进包，"
              f"这正是「小组件不出现」的样子")
        return 2

    bad = False
    firsts: dict[str, str] = {}
    for target in [app] + exts:
        ents = entitlements(target)
        groups = ents.get(KEY)
        if not isinstance(groups, list) or not groups:
            print(f"❌ {target.name}: 没有 {KEY} —— 两边就没有共享仓可言")
            bad = True
            continue
        firsts[target.name] = groups[0]
        print(f"   {target.name:28s} 第一个组 = {groups[0]}")
        if BANNED in ents:
            print(f"❌ {target.name}: 还留着 {BANNED} —— "
                  f"这会让描述文件对不上，编译期直接失败，删掉它")
            bad = True
        if not groups[0].endswith(".shared"):
            print(f"❌ {target.name}: 第一个组不是共享仓（{groups[0]}）—— "
                  f"不传 kSecAttrAccessGroup 时会落到它上面，两边就分家了")
            bad = True

    vals = set(firsts.values())
    if len(vals) > 1:
        print(f"❌ 两边的第一个组不一致：{firsts} —— "
              f"app 写进去的，widget 读不到（且不会报错）")
        bad = True
    # ⚠ 这行 ✅ 只在**整轮没有任何一条红**时才打。
    #   否则会出现「红了还印一行绿」——判红的那一轮里出现绿字，
    #   正是最容易被读成通过的那种输出。
    elif len(vals) == 1 and not bad:
        print(f"✅ 主 app 与 {len(exts)} 个扩展落在同一个 keychain 仓：{vals.pop()}")

    return 2 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
