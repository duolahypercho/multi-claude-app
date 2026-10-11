#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_arch=${ARCH:-$(uname -m)}
case "$task_arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $task_arch" >&2; exit 1 ;; esac
mkdir -p "$task_root/build"
xcrun swiftc -O -target "$task_arch-apple-macosx13.0" \
  "$task_root/native/macos/Models.swift" \
  "$task_root/native/macos/Icons.swift" \
  "$task_root/native/macos/CLI.swift" \
  "$task_root/native/macos/Helper.swift" \
  "$task_root/native/macos/main.swift" \
  -o "$task_root/build/multi-claude-app"
codesign --force --sign - "$task_root/build/multi-claude-app"
echo "Built $task_root/build/multi-claude-app"
