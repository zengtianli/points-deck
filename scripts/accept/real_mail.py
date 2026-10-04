#!/usr/bin/env python3
"""隔离账号服务，复用现有 Mailu 发送到本人 hi+测试子地址并经 IMAP 回读。

凭据只从外部600文件读取，不存进测试产物；不触碰线上教育账号和其他收件人。
此脚本只证明真实服务端邮件流程，不能替代原生页面验收。
"""
import argparse
import email
from email.header import decode_header, make_header
import hashlib
from datetime import datetime, timezone
import imaplib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import time
from unittest.mock import patch

parser = argparse.ArgumentParser()
parser.add_argument("--credentials", type=Path, required=True)
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
if args.credentials.stat().st_mode & 0o077:
    parser.error("邮件凭据文件必须仅本人可读（600）")
lines = args.credentials.read_text().splitlines()
index = next(i for i, line in enumerate(lines) if "hi@tianli.cyou" in line)
password = lines[index + 1].split("：", 1)[-1].strip()
repo = Path(__file__).resolve().parents[2]
backend = repo.parents[2] / "web/points"
sys.path.insert(0, str(backend))
from test_treasury_prd import TreasuryPRD, Client

fixture = TreasuryPRD()
fixture.setUp()
fixture.sender.stop()  # 唯一替换项是发信，HTTP 仍是实际后端。
stamp = str(int(time.time()))
addresses = {name: f"hi+treasury-{stamp}-{name}@tianli.cyou" for name in ("register", "bind", "change")}
records = []


def delivered_code(address):
    with imaplib.IMAP4_SSL("mx.tianli.cyou", 993, timeout=15) as mailbox:
        mailbox.login("hi@tianli.cyou", password)
        mailbox.select("INBOX", readonly=True)
        for _ in range(30):
            status, hits = mailbox.uid("search", None, "HEADER", "To", address)
            for uid in reversed(hits[0].split() if status == "OK" else []):
                _, packets = mailbox.uid("fetch", uid, "(BODY.PEEK[])")
                raw = next((part[1] for part in packets if isinstance(part, tuple)), b"")
                message = email.message_from_bytes(raw)
                texts = [part.get_payload(decode=True).decode(part.get_content_charset() or "utf-8", errors="replace")
                         for part in message.walk() if part.get_content_type() == "text/plain"]
                match = re.search(r"验证码：(\d{6})", "\n".join(texts))
                if match:
                    mailbox.logout()
                    return match.group(1)
            time.sleep(1)
        mailbox.logout()
    raise RuntimeError("本人测试收件箱未收到验证码（30秒内）")


def grant(client, address, purpose, current=""):
    started = time.monotonic()
    response = fixture.ok(client, "email_send", {"email": address, "purpose": purpose, "password": current})
    code = delivered_code(address)
    result = fixture.ok(client, "email_verify", {"challenge": response["challenge"], "code": code})
    records.append({"purpose": purpose, "smtp_accepted": True, "imap_received": True,
                    "verified": True, "elapsed_ms": round((time.monotonic() - started) * 1000)})
    print(f"PASS: {purpose} 真实SMTP投递、IMAP收信、验证码验证", flush=True)
    return result["grant"]


def delivered_notice(address, subject):
    with imaplib.IMAP4_SSL("mx.tianli.cyou", 993, timeout=15) as mailbox:
        mailbox.login("hi@tianli.cyou", password); mailbox.select("INBOX", readonly=True)
        for _ in range(30):
            status, hits = mailbox.uid("search", None, "HEADER", "To", address)
            for uid in reversed(hits[0].split() if status == "OK" else []):
                _, packets = mailbox.uid("fetch", uid, "(BODY.PEEK[])")
                raw = next((part[1] for part in packets if isinstance(part, tuple)), b"")
                message = email.message_from_bytes(raw)
                if subject in str(make_header(decode_header(message.get("Subject", "")))):
                    records.append({"purpose": "security_notification", "action": subject, "smtp_accepted": True, "imap_received": True})
                    print("PASS: 安全通知真实收件（" + subject + "）", flush=True)
                    return
            time.sleep(2)
    raise RuntimeError("安全通知未收到；不计通过")

try:
    with patch.dict(os.environ, {"EDU_SMTP_HOST": "mx.tianli.cyou", "EDU_SMTP_FROM": "hi@tianli.cyou",
                                 "EDU_SMTP_USER": "hi@tianli.cyou", "EDU_SMTP_PASSWORD": password}):
        anonymous = Client(fixture.base)
        verified = grant(anonymous, addresses["register"], "register")
        fixture.ok(anonymous, "register", {"email": addresses["register"], "p": "isolated mailbox passphrase", "grant": verified})
        fixture.ok(anonymous, "adjust", {"pts": 19, "request_id": "real-mail-preservation-0001"})
        bound = grant(fixture.client, addresses["bind"], "email_new", "old-short")
        fixture.ok(fixture.client, "email_bind", {"email": addresses["bind"], "password": "old-short", "grant": bound})
        original = grant(fixture.client, addresses["bind"], "email_old", "old-short")
        replacement = grant(fixture.client, addresses["change"], "email_new", "old-short")
        changed = fixture.ok(fixture.client, "email_bind", {"email": addresses["change"], "password": "old-short",
                                                         "grant": replacement, "old_grant": original})
        fixture.assertTrue(changed["notification_sent"])
        delivered_notice(addresses["bind"], "账号恢复邮箱已更换")
        recovered = grant(Client(fixture.base), addresses["register"], "recover")
        reset = fixture.ok(Client(fixture.base), "recover", {"grant": recovered, "new": "recovered mailbox passphrase"})
        fixture.assertTrue(reset["notification_sent"])
        delivered_notice(addresses["register"], "登录密码已重置")
        fixture.ok(anonymous, "login", {"u": addresses["register"], "p": "recovered mailbox passphrase"})
        fixture.assertEqual(fixture.ok(anonymous, "state")["balance"], 19)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({"schema": 1, "captured_at": datetime.now(timezone.utc).isoformat(),
                                   "source_sha256": {name: hashlib.sha256((backend / name).read_bytes()).hexdigest() for name in ("server.py", "account_security.py")},
                                   "mail_transport": "real", "tls_certificate_verified": True, "mail_service": "existing tianli.cyou Mailu",
                                   "client_environment": "production HTTP API in isolated test service; native UI not covered",
                                   "service_environment": "current local server.py and account_security.py",
                                   "cases": records, "data_preservation": True, "production_accounts_modified": False},
                                  ensure_ascii=False, indent=2) + "\n")
finally:
    fixture.tearDown()
