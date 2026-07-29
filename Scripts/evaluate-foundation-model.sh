#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE="$ROOT/Scripts/evaluate-foundation-model.swift"
BINARY="${TMPDIR:-/tmp}/writesense-foundation-model-evaluation"

if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]; then
    echo "Apple Foundation Models evaluation requires macOS 26 or later." >&2
    exit 2
fi

xcrun swiftc -parse-as-library "$SOURCE" -o "$BINARY"
"$BINARY"
