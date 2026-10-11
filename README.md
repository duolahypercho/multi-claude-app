# Multi Claude App

A native macOS account manager for the official Claude desktop app. Open multiple profiles, sign in separately, and recognize each one by its account name or email and a **Claude icon with a small colored tag on the right**.

Primary uses your existing Claude profile. Extra accounts get fresh desktop storage. The original signed Claude app remains unchanged.

Inspired by [am-will/multi-codex-app](https://github.com/am-will/multi-codex-app). Built in Swift/AppKit, with no third-party runtime dependencies.

## Use the application

1. Open **Multi Claude.app** in your personal Applications folder: Finder → Go → Home → Applications.
2. Click **Open Claude** on Primary or Secondary. Sign in separately in the intended Claude window.
3. Click **Add Account** for more profiles. Enter an account name or email and choose a tag color.
4. On an account card, use **Manage → Rename / Set Email Label** or **Icon Color** to change its identity.

Each running account keeps a separate colored launcher in the Dock. Its short tag combines the first character of your label with its profile number, such as **P1**, **S2**, or **W3**. Hover over the Dock icon to see the full account label. Click it to bring that profile's Claude windows forward. Drag the launcher into the Dock to keep it there when closed.

Labels are yours to set; they do not read or change the authenticated email. Claude windows still belong to the original Claude application, so macOS may also show its standard Dock icon. The colored icons are persistent account launchers. Quitting a launcher leaves its Claude process running; quitting Claude makes its launcher exit.

The stack icon in the menu bar also opens profiles and the manager. Double-click **Start Claude Profiles.command** in the project folder to build/install on first use and open the manager.

## Install from source

Requires macOS 13+, the official `/Applications/Claude.app`, and Apple's Swift command-line tools to build. Built apps run without Swift, Go, Node, or Python installed.

```sh
sh scripts/build.sh
sh install.sh --count 2
open "$HOME/Applications/Multi Claude.app"
```

The build also creates `build/Multi Claude.app`. It has a native first-run setup screen. It is locally ad-hoc signed; distributed downloads would need Apple signing and notarization for a normal Gatekeeper experience.

## Sign-in troubleshooting

The default mode is **Claude Native Sign-in**. Claude keeps ownership of its authentication links. This avoids changing its native authentication behavior merely because a profile router is installed.

If sign-in stalls, choose **Manage → Retry Native Sign-in** on the intended account. This restores Claude's native link handlers and opens that profile. Cancel the old sign-in attempt, then retry using Claude's sign-in button. Choose the intended account in the browser or authentication sheet.

If a browser callback opens Primary or another profile, choose **File → Login Links → Choose Profile for Browser Callbacks**, then restart sign-in. A chooser appears for incoming links: select the **running profile where you began sign-in**, then Continue. Nothing is preselected. Closed profiles are disabled. Cancel discards the link; restart sign-in to get a fresh one.

Some native authentication sessions return directly to their originating window, without a chooser. The browser's account session is shared, so select the correct account there too. Switching modes does not clear profile data or sign anyone out. The mode applies to this macOS user's Claude links, not just one profile.

Real second-account, enterprise, and connector OAuth completion still needs verification by the user. These controls address protocol ownership conflicts; they cannot resolve service-side account errors, expired login links, or network problems.

## Ten accounts

Use **Add Account** eight more times after the initial two profiles, or run:

```sh
~/.local/bin/multi-claude-app setup --count 10
```

Sign in to each account separately. Keep unused profiles closed to save memory and CPU. There are five tag colors; profile numbers keep tags distinct when colors repeat. Up to 100 active profiles are supported.

## Optional CLI

The CLI is installed at `~/.local/bin/multi-claude-app`. Use its full path if `~/.local/bin` is not on your PATH.

```sh
multi-claude-app list
multi-claude-app launch 2
multi-claude-app add --name 'work@example.com' --color teal
multi-claude-app rename 2 Personal
multi-claude-app icon 2 purple
multi-claude-app remove 2
multi-claude-app list --removed
multi-claude-app restore 2
multi-claude-app login-routing native
multi-claude-app login-routing chooser
multi-claude-app doctor
```

Colors: orange, blue, purple, teal, yellow. Names/colors can change without changing data folders. Numbers are never reused. `setup --count N` only grows the active count. Remove/restore changes launchers and preserves account data; an open Claude window stays open when its launcher is removed.

## How it works

| Profile | Desktop storage | Claude Code configuration environment |
| --- | --- | --- |
| Primary | Existing `~/Library/Application Support/Claude` | Existing default |
| Extra profiles | `~/Library/Application Support/Multi Claude/profiles/ID/desktop` | `…/profiles/ID/claude-code` |

A small persistent launcher starts the original signed Claude app with Chromium's `--user-data-dir` flag. Extra profiles also receive `CLAUDE_CONFIG_DIR` for child tools that honor it. No existing credentials are copied. Usage and billing stay attached to each account.

In chooser mode, a native menu helper owns the `claude://` and installed Microsoft authentication schemes. It sends incoming links directly to the selected Claude process through a macOS open-URL Apple Event. Links stay in memory and are never stored in logs, files, or process arguments. The helper refreshes ownership every five seconds in chooser mode. In native mode, it leaves link ownership with Claude.

Editable SVG icons and macOS `.icns` icons are generated inside each launcher’s `Contents/Resources` folder. The vector Claude mark is in [assets/claude-mark.svg](assets/claude-mark.svg).

### Compatibility limits

- Tested locally with Claude Desktop **2.31226.1**, Apple silicon. Signed builds ignore `CLAUDE_USER_DATA_DIR`; this tool uses the Chromium flag.
- This Claude build marks relocated data folders as ineligible for **local pairing**. That protection is preserved.
- Isolation of all Code/Cowork tools, OS Keychain items, native services, and spawned processes is unverified. Claude may choose its own internal directories for some features.
- Claude chats and memories are managed by its service. This app does not provide Codex-style local chat or memory sharing.
- Intel compilation is supported by `ARCH=x86_64 sh scripts/build.sh`; Intel runtime behavior is unverified. Only macOS is implemented.

## Update and uninstall

Update Claude normally. Use **File → Check Setup** afterward. Rebuild and run `sh install.sh` to update this manager; setup preserves account data and replaces its own apps.

```sh
multi-claude-app uninstall
```

Uninstall removes the manager, launchers, menu helper, and LaunchAgent. It restores prior login handlers when the helper still owns them. Account data, configuration, and the CLI are retained. Run `setup` to reinstall.

Configuration: `~/Library/Application Support/Multi Claude/config.json`. Profile folders are mode 700; config is mode 600. Use one integrated installation per macOS user and keep its root in a permanent location.

For development without changing protocol handlers or login items:

```sh
build/multi-claude-app --root /absolute/dev/root setup --count 2 \
  --no-integration --applications /absolute/dev/Applications
python3 tests/test_cli.py
```

## Credits and license

Implementation: MIT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). The Claude mark is Anthropic's artwork/trademark and is used to identify Claude account launchers; it is not relicensed as MIT. This is an independent project, not an Anthropic product.
