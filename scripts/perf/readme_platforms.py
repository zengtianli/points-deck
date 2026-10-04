#!/usr/bin/env python3
"""Render the per-platform resource table of README.md / README_EN.md from perf/platforms/<lane>.json.

    python3 scripts/perf/readme_platforms.py [--check]

Rewrites only the block between <!-- platforms:start --> and <!-- platforms:end --> in both READMEs (the lightweight
block below it belongs to Chapter). Every number comes from the evidence file and is labelled with its environment
(simulator, or native for the Mac lane); a lane without evidence shows "not measured" instead of a number.
The host load each lane was measured under (1/5/15-minute load average right before the timed launches, from the
lane's measure-*.json) is printed per row, and the note says so plainly when the host was busier than its core count:
launch times measured that way are likely pessimistic.
--check exits 1 when a README is out of date and changes nothing.
"""
from __future__ import annotations

import json
import os
import re
import sys
from functools import lru_cache
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
import app_sop
LANES = ("iphone", "ipad", "mac", "watch", "vision")
NAME = {"zh": {"iphone": "iPhone", "ipad": "iPad", "mac": "Mac", "watch": "Apple Watch", "vision": "Apple Vision Pro"},
        "en": {"iphone": "iPhone", "ipad": "iPad", "mac": "Mac", "watch": "Apple Watch", "vision": "Apple Vision Pro"}}
START, END = "<!-- platforms:start -->", "<!-- platforms:end -->"
# The lanes are measured on this Mac; a load average above its core count means the CPUs were oversubscribed.
HOST_CORES = os.cpu_count() or 1


@lru_cache
def product():
    return app_sop.load_apps("points-deck-ios")[0]


@lru_cache
def current_evidence(lane):
    try:
        data = json.loads((REPO / f"perf/platforms/{lane}.json").read_text())
        if data["input_sha256"] != app_sop.lane_inputs(product(), lane)["input_sha256"]:
            return None
        return data
    except (OSError, ValueError, KeyError):
        return None


def target(lane, lang):
    sop = product()["sop"]
    limits = {**app_sop.PLATFORM_BUDGETS[lane], **(sop.get("budget") or {}),
              **(sop["platforms"][lane].get("budget") or {})}
    size = "安装" if lane == "mac" else "包"
    if lang == "en": size = "installed" if lane == "mac" else "package"
    return (f"≤ {limits['memory_mb']:g} MiB · ≤ {limits['cpu']:g}% · "
            f"≤ {limits['size_mb']:g} MB {size} · ≤ {limits['cold_launch_ms']/1000:g} s")


def lane_loads(lane: str) -> list[float] | None:
    """1/5/15-minute load average just before the timed launches, from the lane's evidence file (None if absent)."""
    try:
        d = current_evidence(lane)
        if d is None: return None
        ev = json.loads((REPO / d["runtime_measurement"]["evidence"]).read_text(encoding="utf-8"))
        loads = ev["measurement"]["loads"]["before_launches"]
        return [float(x) for x in loads[:3]] if len(loads) >= 3 else None
    except (OSError, ValueError, KeyError, TypeError):
        return None


def load_note(lang: str) -> str:
    loads = [x for x in (lane_loads(l) for l in LANES) if x]
    if not loads:
        return ""
    span = [f"{min(x[i] for x in loads):.1f}–{max(x[i] for x in loads):.1f}" for i in range(3)]
    heavy = max(x[0] for x in loads) > HOST_CORES or max(x[1] for x in loads) > HOST_CORES
    if lang == "zh":
        if heavy:
            return (f"**这些数字是在本机重负载下测的**：各线开始计时启动前，宿主（{HOST_CORES} 核）1 分钟负载 {span[0]}、"
                    f"5 分钟 {span[1]}、15 分钟 {span[2]}（每行的「测量时负载」），部分负载高于核数；测量门要求 1 分钟负载低于核数的 1.5 倍。"
                    "冷启动最受宿主负载影响，表里的启动时间很可能偏悲观（偏慢），空闲时重测会更低。")
        return f"各线开始计时启动前，宿主（{HOST_CORES} 核）1 分钟负载 {span[0]}、5 分钟 {span[1]}、15 分钟 {span[2]}。"
    if heavy:
        return (f"**These numbers were measured on a heavily loaded host**: right before each lane's timed launches the "
                f"{HOST_CORES}-core host's load average was {span[0]} (1 min), {span[1]} (5 min) and {span[2]} (15 min) "
                "(the \"Host load\" column); some exceed its core count. The measurement gate requires the 1-minute load "
                "to be under 1.5× the cores. Cold launch is the number most sensitive to host load, so the launch times "
                "here are likely pessimistic (slow) and should come out lower when re-measured on an idle machine.")
    return (f"Right before each lane's timed launches the {HOST_CORES}-core host's load average was {span[0]} (1 min), "
            f"{span[1]} (5 min) and {span[2]} (15 min).")


def lane_row(lane: str, lang: str) -> str:
    path = REPO / f"perf/platforms/{lane}.json"
    budget = target(lane, lang)
    d = current_evidence(lane)
    if d is None:
        miss = "当前版本未测（旧原件保留）" if lang == "zh" else "Current version not measured (history retained)"
        return f"| {NAME[lang][lane]} | {miss} | — | — | — | — | — | {budget} |"
    rm, size, idle, speed = d["runtime_measurement"], d["size"], d["idle"], d["speed"]
    env = rm["environment"]
    if lang == "zh":
        where = f"{'模拟器' if env == 'simulator' else '本机原生'} · {rm['device'].split(' (')[0]} · {rm['os']}"
    else:
        where = f"{'Simulator' if env == 'simulator' else 'Native'} · {rm['device'].split(' (')[0]} · {rm['os']}"
    launch = speed.get("cold_launch_ms")
    loads = lane_loads(lane)
    load = " / ".join(f"{x:.1f}" for x in loads) if loads else "—"
    package = size["installed_mb"] if lane == "mac" else size["download_mb"]
    kind = ("安装" if lang == "zh" else "installed") if lane == "mac" else "zip"
    return (f"| {NAME[lang][lane]} | {where} | {package:.1f} MB {kind} | {idle['memory_mb']:.1f} MiB | "
            f"{idle['cpu_pct']:g}% | {launch / 1000:.2f} s | {load} | {budget} |")


def block(lang: str) -> str:
    dates = sorted({d["measured_at"][:10] for l in LANES if (d := current_evidence(l)) is not None})
    when = "、".join(dates) if lang == "zh" else ", ".join(dates)
    if lang == "zh":
        head = ("| 平台 | 测量环境 | 包体／安装 | 空闲内存 | 空闲 CPU | 冷启动到首屏有数据 | 测量时负载（1 / 5 / 15 分钟） | 目标 |\n"
                "|---|---|---|---|---|---|---|---|")
        note = (f"<sub>{load_note(lang)}{when} 实测，数据来自 `perf/platforms/<平台>.json`。iPhone / iPad / Watch / Vision 是 Xcode 模拟器上的 Release 构建，"
                "Mac 是本机原生的本地 Release 构建；**移动平台不是实机数值，包体不是 App Store 切片**。"
                "本表仅统计 App 宿主，不含 WebKit/XPC 与系统进程合计。内存为 App 进程 phys_footprint（MiB），CPU 为启动静置 45 秒后 60 秒窗口内的 CPU 时间 ÷ 墙钟，冷启动是发出启动到 App 打出"
                "「第一屏有数据」日志的中位数（隔离的本地演示账本，5 次，丢弃装机后第一次）。"
                "模拟器的启动时间随宿主负载浮动很大：2026-10-02 本机内存吃紧时，同一份代码的 iPhone 线在不同时段测出 1.8–4.1 秒；"
                "Vision Pro 的冷启动里模拟器自己的开销（进程拉起后到 App 打出第一行日志、visionOS 场景与 RealityKit 初始化）占大头，"
                "宿主忙时会拉长到十几秒，App 自己从取账本到画出第一屏约 2 秒。</sub>")
    else:
        head = ("| Platform | Measured on | Package / installed | Idle memory | Idle CPU | Cold launch to first data screen | Host load (1 / 5 / 15 min) | Target |\n"
                "|---|---|---|---|---|---|---|---|")
        lead = load_note(lang)
        note = (f"<sub>{lead + ' ' if lead else ''}Measured {when}; data in `perf/platforms/<platform>.json`. iPhone, iPad, Watch and Vision are Release builds on "
                "Xcode simulators; the Mac is a native local Release build. **Mobile results are not physical-device measurements, and package "
                "sizes are not App Store slices**. This is host-only, excluding WebKit/XPC and system totals. Memory is the app "
                "process's phys_footprint in MiB; CPU is CPU time ÷ wall time over 60 s after a 45 s settle; cold launch is the median time "
                "from the launch request to the app's \"first data-bearing screen\" log (isolated local demo ledger, 5 runs, the "
                "first run after install discarded). Simulator launch times swing widely with host load: with memory tight on "
                "2026-10-02, the same code on the iPhone lane measured 1.8–4.1 s at different times. Most of a Vision Pro cold launch "
                "is the simulator's own overhead (from process spawn to the app's first log line, plus visionOS scene and RealityKit "
                "setup), which stretches past ten seconds on a busy host; the app itself takes about 2 s from fetching the ledger to "
                "drawing its first screen.</sub>")
    rows = "\n".join(lane_row(l, lang) for l in LANES)
    return f"{START}\n{head}\n{rows}\n\n{note}\n{END}"


def main(argv=None) -> int:
    check = "--check" in (argv if argv is not None else sys.argv[1:])
    stale = []
    for name, lang in (("README.md", "zh"), ("README_EN.md", "en")):
        path = REPO / name
        text = path.read_text(encoding="utf-8")
        if START not in text or END not in text:
            print(f"{name}: 没有 {START} … {END} 区块", file=sys.stderr)
            return 1
        new = re.sub(re.escape(START) + r".*?" + re.escape(END), lambda _: block(lang), text, flags=re.S)
        if new != text:
            stale.append(name)
            if not check:
                path.write_text(new, encoding="utf-8")
    print(("过期：" if check else "已更新：") + "、".join(stale) if stale else "两份 README 的平台表已是最新")
    return 1 if check and stale else 0


if __name__ == "__main__":
    sys.exit(main())
