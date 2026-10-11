# Multi Claude App

Run several accounts in the **official Claude desktop app** at the same time on macOS. Each extra profile has separate browser storage, sign-in, desktop settings, and a colored launcher. Primary continues using your existing Claude data.

Inspired by [am-will/multi-codex-app](https://github.com/am-will/multi-codex-app). The native profile chooser is adapted from that project's MIT-licensed helper. This version is a small Swift program with no third-party runtime dependencies.

## Start using an installed copy

1. Open Finder and choose **Go → Home → Applications**. This is your personal Applications folder.
2. Double-click **Claude Primary** for your existing account.
3. Double-click **Claude Secondary** and sign in to another account. Both can stay open.
4. Use the **stack icon in the menu bar** to open either profile later.

If a profile chooser appears during browser sign-in, select the profile where you started the sign-in and click **Continue**. The chooser's **Preview** mode sends no login link and doesn't open an account; launch accounts using their app icons or the menu-bar entries.

You can also double-click **Start Claude Profiles.command** in this project folder to open Primary and Secondary together. On the first run it builds and installs them if needed, so Apple's Swift command-line tools are required for that first build.

## Install

Requires macOS 13 or newer and the official `/Applications/Claude.app`. Building the source requires Apple's Swift command-line tools. A built binary runs without Swift, Go, Node, or Python installed.

```sh
sh scripts/build.sh
sh install.sh --count 2
```

Open **Claude Primary** and **Claude Secondary** from `~/Applications`, Spotlight, or the stack icon in the menu bar. Sign in to the second account in Secondary. No existing credentials are copied. You can drag the launchers into the Dock yourself.

The CLI is installed at `~/.local/bin/multi-claude-app`. If that directory isn't on your PATH, use the full path:

```sh
~/.local/bin/multi-claude-app wizard
~/.local/bin/multi-claude-app list
~/.local/bin/multi-claude-app launch 2
```

## Manage profiles

```sh
multi-claude-app add --name Work --color teal
multi-claude-app add --count 2
multi-claude-app rename 2 Personal
multi-claude-app icon 2 purple
multi-claude-app icons
multi-claude-app remove 2
multi-claude-app list --removed
multi-claude-app restore 2
multi-claude-app doctor
```

Colors: orange, blue, purple, teal, yellow. Up to 100 active profiles. Names and colors can change without changing data folders. Profile numbers are never reused. `setup --count N` only adds profiles when necessary; it never reduces the active count or overwrites sign-ins. Remove/restore only changes launchers. A running Claude window stays open when its launcher is removed.

For **ten accounts total**, run this once, then open each new launcher and sign in separately:

```sh
~/.local/bin/multi-claude-app setup --count 10
```

You can keep unused profiles closed. Each running Claude instance uses additional memory and CPU.

## Login links

The menu helper registers for the `claude://` and Microsoft sign-in schemes declared by the installed app. When a browser sends a link, choose the **running profile where you started sign-in or Connect**, then Continue. Nothing is preselected. Closed profiles are disabled. Cancel discards the link; restart the sign-in flow to try again.

The helper delivers a link directly to the chosen process through a macOS open-URL Apple Event. Links remain in memory and are never written to logs, a file, or a subprocess command line. It refreshes link ownership every five seconds because Claude registers itself at startup. Browser login is shared: pick the intended account in your browser too. Some native authentication flows return directly to their originating window and don't show a chooser.

## What is isolated

| Profile | Desktop data | Claude Code config environment |
| --- | --- | --- |
| Primary | Existing `~/Library/Application Support/Claude` | Existing default |
| Extra profiles | `~/Library/Application Support/Multi Claude/profiles/ID/desktop` | `…/profiles/ID/claude-code` |

The launcher passes `--user-data-dir` to the original signed app. Extra profiles also receive `CLAUDE_CONFIG_DIR` for child tools that honor it. Claude may choose its own internal Code/Cowork directories; isolation of every spawned tool, OS Keychain item, and native service has not been verified. Usage and billing remain attached to each account.

**Claude-specific limits:**

- Tested with Claude Desktop **2.31226.1** on Apple silicon. Current signed builds ignore `CLAUDE_USER_DATA_DIR`; this tool uses the Chromium profile flag instead.
- This Claude build marks relocated data folders as ineligible for **local pairing**. That restriction is preserved. Other Code/Cowork features may have additional constraints; verify the features you need after signing in.
- The official Claude app is never copied, patched, or re-signed. Running windows can group under the original Claude Dock icon. Launchers have distinct names and colors.
- Claude chats and memories are managed by the account/service. This tool does **not** implement Codex-style local chat or memory sharing.
- Successful second-account login and real connector/enterprise OAuth completion require the user's account and have not been automated. The router and process delivery are tested separately.
- Only macOS is implemented. Intel compilation is supported by `ARCH=x86_64 sh scripts/build.sh`; Intel runtime behavior is unverified.

## Updates and uninstall

Update Claude normally. Run `multi-claude-app doctor` afterward. Repair the integration with `multi-claude-app setup`. After editing this tool, rebuild and run `sh install.sh`; the new binary replaces the installed helper and launchers while preserving profile data.

```sh
multi-claude-app uninstall
```

This removes managed launchers and the menu helper, stops its LaunchAgent, and restores the prior login handlers if Multi Claude still owns them. All account data, configuration, and the CLI are retained. Run `setup` to reinstall.

Configuration: `~/Library/Application Support/Multi Claude/config.json`. Extra-profile folders are private (mode 700) and config is mode 600. Do not place a real install under `/tmp` or move its root after setup. Use one integrated installation per macOS user.

For development without changing login handlers or login items:

```sh
build/multi-claude-app --root /absolute/dev/root setup --count 2 \
  --no-integration --applications /absolute/dev/Applications
python3 tests/test_cli.py
```

## Credits and license

MIT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). The custom C/card icons are original artwork. Claude and Anthropic are trademarks of their owners; this is an independent project.
