#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Kompilē testus…"
mkdir -p .buildtmp

swiftc \
    -O \
    -o .buildtmp/test_runner \
    Tests/TestRunner.swift \
    Sources/Models.swift \
    Sources/KeyLabel.swift \
    Sources/AudioGuard.swift \
    Sources/UpdateChecker.swift

echo "==> Palaidž testus…"
.buildtmp/test_runner
