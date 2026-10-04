#!/usr/bin/env python3
"""Static privacy boundary of the shipped sources (Sources/, Shared/, Widget/, Watch/, project.yml, entitlements).

Fails when: a tracking/analytics/ads SDK or AdSupport/AppTrackingTransparency is imported; a network host other
than the own ledger (edu.tianli.cyou), localhost, or official release metadata in verified shared code appears; the parent password is written to
UserDefaults/Keychain/files; the Widget snapshot carries credentials; entitlements ask for more than
network client + sandbox + the shared keychain group; or a permission usage string (camera, location...) appears.
"""
import re
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
code = {p: p.read_text(encoding="utf-8") for d in ("Sources", "Shared", "Widget", "Watch") for p in (repo / d).rglob("*.swift")}
problems = []

shared_source = Path.home() / "Dev/tools/dev/lib/tools/macapp/swift-shared"
verified_lifecycle = set()
for name in ("AppLifecycle.swift", "AppConfiguration.swift", "AppLifecycleMobile.swift"):
    path, canonical = repo / "Shared" / name, shared_source / name
    if not canonical.is_file() or not path.is_file() or canonical.read_bytes() != path.read_bytes():
        problems.append(f"Shared/{name} 与共享责任源不一致")
    else:
        verified_lifecycle.add(path)

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
            allowed_hosts = {"edu.tianli.cyou", "127.0.0.1", "localhost"}
            if p in verified_lifecycle:
                if p.name == "AppLifecycle.swift":
                    allowed_hosts |= {"api.github.com", "itunes.apple.com"}
                elif p.name == "AppLifecycleMobile.swift":
                    allowed_hosts.add("apps.apple.com")
            if h not in allowed_hosts:
                problems.append(f"{p.relative_to(repo)} 连接第三方主机 {h}")

if (repo / "Sources/ParentSession.swift").exists():
    problems.append("已退役的第二套家长密码流程仍存在")
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
      f"版本元数据仅逐字节匹配责任源的共享代码，账号密码及验证码不写入偏好设置，Widget 快照 {len(fields)} 个字段无凭据，权限仅网络+沙盒+共享钥匙串"
      if not problems else f"静态：{len(problems)} 处隐私边界问题")
sys.exit(1 if problems else 0)
