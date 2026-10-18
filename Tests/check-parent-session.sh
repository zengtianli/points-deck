#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d /tmp/points-parent-sop.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
xcrun --sdk macosx swiftc -target "$(uname -m)-apple-macos15.0" \
  Shared/PlatformCompat.swift Shared/RemoteUI.swift Sources/Skin.swift Sources/Api.swift \
  Tests/ParentSessionChecks.swift -o "$scratch/check"
"$scratch/check"

# Keep bilingual UI coverage in the existing Chapter test entry without changing
# its transaction probe or machine-readable output contract.
"$HOME/Dev/.venv/bin/python" -m pytest -n auto Tests/test_l10n.py -q
