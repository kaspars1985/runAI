#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Kompilē testus…"
mkdir -p .buildtmp

swiftc -O -target arm64-apple-macosx14.0 -framework AppKit -framework ApplicationServices -o .buildtmp/test_runner Tests/TestRunner.swift Sources/Models.swift Sources/KeyLabel.swift Sources/AudioGuard.swift Sources/UpdateChecker.swift Sources/AppLogger.swift Sources/HotkeyMonitor.swift Sources/TextInserter.swift Sources/PreferencesManager.swift

echo "==> Palaidž testus…"
.buildtmp/test_runner
