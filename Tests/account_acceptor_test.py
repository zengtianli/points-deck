"""Evidence-consumer negative tests; these are not native product acceptance."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("account_acceptor", Path(__file__).resolve().parents[1] / "scripts/accept/account_lifecycle.py")
ACCEPTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ACCEPTOR)


class EvidenceBoundary(unittest.TestCase):
    def test_stale_missing_false_and_changed_raw_never_count_as_native_pass(self):
        with tempfile.TemporaryDirectory() as scratch, patch.object(ACCEPTOR, "ROOT", Path(scratch)):
            root = Path(scratch)
            native = root / "native.json"
            native.write_text('{"ok":true}')
            good = {"account_input_sha256": "current", "checks": dict.fromkeys(ACCEPTOR.LOCAL_CHECKS, True),
                    "steps": [{"step": step, "original_ledger_unchanged": True} for step in ACCEPTOR.LOCAL_STEPS],
                    "messages_sent": {"sms": 0, "mail": 0}, "native_proof": "native.json",
                    "native_proof_sha256": ACCEPTOR.sha(native)}
            target = root / "proof.json"
            target.write_text(json.dumps(good))
            ACCEPTOR.verified_local(target, "current")
            mutations = [lambda p: p.update(account_input_sha256="stale"),
                         lambda p: p["checks"].pop("native_session_survives_relaunch"),
                         lambda p: p["checks"].update(original_ledger_preserved="true"),
                         lambda p: p["steps"].pop(),
                         lambda p: p.update(native_proof_sha256="0" * 64),
                         lambda p: p["messages_sent"].update(sms=1)]
            for mutate in mutations:
                value = copy.deepcopy(good)
                mutate(value)
                target.write_text(json.dumps(value))
                with self.assertRaises(ValueError):
                    ACCEPTOR.verified_local(target, "current")
            target.write_text(json.dumps(good))
            native.write_text('{"ok":false}')
            with self.assertRaises(ValueError):
                ACCEPTOR.verified_local(target, "current")

    def test_full_consumer_rejects_partial_mock_stale_and_changed_native_original(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            native = root / "native/proof.json"
            native.parent.mkdir()
            native.write_text('{"ok":true,"receipt_sha256":"candidate"}')
            service = Path.home() / "Apps/edu/web/points"
            inputs = [service / p for p in ("server.py", "account_security.py", "account_phone.py")]
            inputs += [ACCEPTOR.ROOT / "Tests/AccountUITests.swift"]
            inputs += [ACCEPTOR.ROOT / "scripts/accept" / p for p in ("platform_ui.py", "account_peer.py")]
            good = {"case": "EmailBinding", "exit_code": 0, "offline_diagnostic_only": False,
                    "account_input_sha256": "current", "producer_sha256": ACCEPTOR.sha(ACCEPTOR.ROOT / "scripts/accept/account_native.py"),
                    "source_sha256": {p.name: ACCEPTOR.sha(p) for p in inputs}, "receipt_sha256": "candidate",
                    "native_proof_sha256": ACCEPTOR.sha(native),
                    "steps": [{"step": step, "checks": {"native_observation": True}} for step in ACCEPTOR.FULL_STEPS["EmailBinding"]],
                    "events": [{"transport": "real-mail", "imap_received": True}],
                    "mail_transport": "real", "messages_sent": {"mail": 1, "sms": 0}}
            target = root / "evidence.json"
            target.write_text(json.dumps(good))
            ACCEPTOR.verified_full(target, "current")
            mutations = [lambda p: p.update(offline_diagnostic_only=True),
                         lambda p: p.update(account_input_sha256="stale"),
                         lambda p: p["steps"].pop(), lambda p: p["source_sha256"].clear(),
                         lambda p: p["steps"][0]["checks"].update(native_observation="true"),
                         lambda p: p["events"][0].update(transport="mock-mail"),
                         lambda p: p["events"][0].update(imap_received=False),
                         lambda p: p.update(native_proof_sha256="changed")]
            for mutate in mutations:
                value = copy.deepcopy(good)
                mutate(value)
                target.write_text(json.dumps(value))
                with self.assertRaises(ValueError):
                    ACCEPTOR.verified_full(target, "current")
            target.write_text(json.dumps(good))
            native.write_text('{"ok":false,"receipt_sha256":"candidate"}')
            with self.assertRaises(ValueError):
                ACCEPTOR.verified_full(target, "current")


if __name__ == "__main__":
    unittest.main()
