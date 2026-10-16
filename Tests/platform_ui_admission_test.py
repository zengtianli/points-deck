"""Regression checks for build/simulator scheduling; no product verdicts are mocked."""
import contextlib
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/accept"))
spec = importlib.util.spec_from_file_location("points_platform_ui", ROOT / "scripts/accept/platform_ui.py")
lane = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lane)


def test_product_build_does_not_acquire_simulator(monkeypatch, tmp_path):
    receipt = tmp_path / "build.json"
    receipt.write_text("{}")
    calls = []
    monkeypatch.setitem(sys.modules, "platform_measure", SimpleNamespace(
        cached_build=lambda *args: calls.append("build") or {"work_dir": str(tmp_path)}))
    monkeypatch.setattr(lane.sim_lane, "reuse_build", lambda *args: calls.append("verify"))
    monkeypatch.setattr(lane, "ownership", lambda *args: (_ for _ in ()).throw(AssertionError("simulator lease around build")))
    with lane.Budget(20):
        assert lane.run(SimpleNamespace(phase="product", platform="iphone", out=tmp_path)) == 0
    assert calls == ["build", "verify"]


def test_runtime_admission_names_device_and_preserves_canonical_gate(monkeypatch):
    calls = []
    lock = SimpleNamespace(release=lambda: calls.append("release"))
    monkeypatch.setattr(lane.sim_lane, "lock_chain", lambda label: [lock])
    monkeypatch.setattr(lane.sim_lane, "max_load_default", lambda: 12)
    monkeypatch.setattr(lane.sim_lane, "_chapter_sim_admission", lambda: None)
    monkeypatch.setattr(lane.sim_lane, "acquire", lambda *args: calls.append(args[1:]))
    monkeypatch.delenv("SOP_OWNER_NOW", raising=False)
    monkeypatch.delenv("SIM_LANE_EXTRA_LOCK", raising=False)
    with lane.ownership("test", "owned-device", functional_only=True):
        calls.append("runtime")
    assert calls == [("owned-device", 0, 0, 12), "runtime", "release"]


def test_runner_compile_holds_build_slot_without_simulator(monkeypatch, tmp_path):
    active = []
    @contextlib.contextmanager
    def slot(*args, **kwargs):
        active.append(True)
        try:
            yield
        finally:
            active.pop()
    monkeypatch.setattr(lane.sim_lane, "BuildSlot", slot)
    monkeypatch.setattr(lane.sim_lane, "developer_dir", lambda sdk: "/test/Xcode")
    def compile(args, cwd, log, **kwargs):
        assert active == [True]
        products = log.parent / "dd/Build/Products"
        products.mkdir(parents=True)
        (products / "runner.xctestrun").write_text("actual metadata placeholder for scheduler test")
    monkeypatch.setattr(lane, "command", compile)
    with lane.Budget(20):
        monkeypatch.setattr(lane.run_budget(), "run", lambda *args, **kwargs: None)
        runner = lane.build_runner("iphone", tmp_path)
    assert Path(runner["xctestrun"]).is_file()
    assert not active
