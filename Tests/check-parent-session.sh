#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d /tmp/points-parent-sop.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
xcrun --sdk macosx swiftc -target "$(uname -m)-apple-macos15.0" \
  Shared/PlatformCompat.swift Sources/Skin.swift Sources/Api.swift \
  Sources/ParentSession.swift Tests/ParentSessionChecks.swift -o "$scratch/check"
"$scratch/check"
