#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
task_cli="$HOME/.local/bin/multi-claude-app"
if [ ! -x "$task_cli" ] || [ ! -d "$HOME/Applications/Multi Claude.app" ]; then
  sh "$task_root/install.sh" --count 2
fi
if ! "$task_cli" list >/dev/null 2>&1; then
  "$task_cli" setup --count 2
fi
open "$HOME/Applications/Multi Claude.app"
printf '%s\n' 'Opened Multi Claude. Choose an account card to open it, or Add Account to create another.'
