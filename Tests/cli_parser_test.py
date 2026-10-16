"""Opaque identifiers must survive parsing; no network or account fixtures."""
from pathlib import Path
import runpy
import pytest

CLI = runpy.run_path(str(Path(__file__).resolve().parents[1] / "cli/treasury"))


@pytest.mark.parametrize("command", ["code-verify", "phone-verify"])
@pytest.mark.parametrize("challenge", ["-" + "a" * 31, "--" + "b" * 30, "_" + "c" * 31])
@pytest.mark.parametrize("equals", [False, True])
def test_server_challenge_bytes_survive_parser(command, challenge, equals):
    args = ["--challenge=" + challenge] if equals else ["--challenge", challenge]
    parsed = CLI["build"]().parse_args(["account", command, *args])
    assert parsed.challenge == challenge


def test_real_options_are_not_consumed_as_challenge():
    with pytest.raises(SystemExit) as error:
        CLI["build"]().parse_args(["account", "code-verify", "--challenge", "--json"])
    assert error.value.code == 2
