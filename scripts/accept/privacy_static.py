#!/usr/bin/env python3
"""Static privacy boundary of the shipped sources (Sources/, Shared/, Widget/, project.yml, entitlements).

Fails when: a tracking/analytics/ads SDK or AdSupport/AppTrackingTransparency is imported; a network host other
than the own ledger (edu.tianli.cyou) or localhost appears in code; the parent password is written to
UserDefaults/Keychain/files; the Widget snapshot carries credentials; entitlements ask for more than
network client + sandbox + the shared keychain group; or a permission usage string (camera, location...) appears.
"""
import re
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
code = {p: p.read_text(encoding="utf-8") for d in ("Sources", "Shared", "Widget") for p in (repo / d).rglob("*.swift")}
problems = []

trackers = re.compile(r"^\s*import\s+(AdSupport|AppTrackingTransparency|Firebase\w*|FBSDK\w*|Adjust\w*|AppsFlyer\w*|"
                      r"Mixpanel|Amplitude\w*|Sentry|Bugsnag|Segment\w*|UMCommon\w*|Bugly)\b", re.M)
for p, text in code.items():
    for m in trackers.finditer(text):
        problems.append(f"{p.relative_to(repo)} 引入跟踪/分析 SDK {m.group(1)}")

hosts = set()
for p, text in code.items():
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///"):
            continue
        for h in re.findall(r"https?://([A-Za-z0-9.\-]+)", line):
            hosts.add(h)
            if h not in {"edu.tianli.cyou", "127.0.0.1", "localhost"}:
                problems.append(f"{p.relative_to(repo)} 连接第三方主机 {h}")

session = (repo / "Sources/ParentSession.swift").read_text(encoding="utf-8")
body = "\n".join(l for l in session.splitlines() if not l.strip().startswith("//"))
if re.search(r"UserDefaults|SecItem|Keychain|\.write\(|FileManager", body):
    problems.append("ParentSession 把家长密码写入持久存储")
for p, text in code.items():
    if re.search(r"UserDefaults[^\n]*\.set\([^\n]*(password|admin|pw)\b", text, re.I):
        problems.append(f"{p.relative_to(repo)} 把密码写入 UserDefaults")

snap = (repo / "Sources/Snapshot.swift").read_text(encoding="utf-8")
fields = re.findall(r"^\s*var (\w+):", snap, re.M)
if any(re.search(r"pass|pw|token|cookie|user|email|admin", f, re.I) for f in fields):
    problems.append(f"Widget 快照含凭据字段 {fields}")

allowed = {"com.apple.security.app-sandbox", "com.apple.security.network.client", "keychain-access-groups"}
for ent in repo.glob("*.entitlements"):
    for key in re.findall(r"<key>([^<]+)</key>", ent.read_text(encoding="utf-8")):
        if key not in allowed:
            problems.append(f"{ent.name} 申请了额外权限 {key}")

spec = (repo / "project.yml").read_text(encoding="utf-8")
for key in re.findall(r"(NS\w+UsageDescription|NSUserTrackingUsageDescription)", spec):
    problems.append(f"project.yml 声明了权限用途 {key}")

for p in problems:
    print("FAIL:", p)
print(f"静态：{len(code)} 个 Swift 源文件无跟踪 SDK，联网主机仅 {sorted(hosts) or ['(无)']}，"
      f"家长密码只在内存，Widget 快照 {len(fields)} 个字段无凭据，权限仅网络+沙盒+共享钥匙串"
      if not problems else f"静态：{len(problems)} 处隐私边界问题")
sys.exit(1 if problems else 0)
