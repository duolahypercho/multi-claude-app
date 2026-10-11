#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
task_cli="$HOME/.local/bin/multi-claude-app"
if [ ! -x "$task_cli" ]; then
  sh "$task_root/install.sh" --count 2
fi
if ! "$task_cli" list >/dev/null 2>&1; then
  "$task_cli" setup --count 2
fi
"$task_cli" launch 1
"$task_cli" launch 2
printf '%s\n' 'Opened Claude Primary and Claude Secondary. Sign in to your second account in Secondary.'
