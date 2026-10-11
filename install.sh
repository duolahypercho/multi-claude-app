#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$(uname -s)" != Darwin ]; then echo "This version supports macOS 13 or newer." >&2; exit 1; fi
if [ ! -x "$task_root/build/multi-claude-app" ]; then sh "$task_root/scripts/build.sh"; fi
if [ "$#" -eq 0 ]; then set -- setup --count 2; elif [ "$1" != setup ]; then set -- setup "$@"; fi
exec "$task_root/build/multi-claude-app" "$@"
