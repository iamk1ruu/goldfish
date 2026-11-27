#!/usr/bin/env bash
# Runs the GoldfishCore tests. Needs only Swift, no simulator or phone.
# Prints a short result; the full output is in build/core-tests.log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
LOG="$ROOT/build/core-tests.log"
cd "$ROOT/Packages/GoldfishCore"

if swift test > "$LOG" 2>&1; then
  grep -E "Executed [0-9]+ tests" "$LOG" | tail -1 || true
  echo "Core tests passed."
else
  grep -E "error:|failed|XCTAssert" "$LOG" | sort -u | head -80 || true
  echo "Core tests FAILED. Full log: build/core-tests.log" >&2
  exit 1
fi
