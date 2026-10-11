# Multi Claude App

A native macOS account manager with **one Claude app per account**, each with its own account name/email label and **Claude icon with a small colored tag on the right**. The account app is the actual native Claude process; no second launcher stays running. The manager and menu helper have no Dock icons.

Primary uses your existing Claude profile. Extra accounts get fresh desktop storage. Account apps are local copies of your installed Claude app and are locally ad-hoc signed. The original signed Claude app remains unchanged.

Native chat reaches the sign-in screen in local testing. Completed account sign-in, enterprise/MSAL authentication, passkeys, and Code/Cowork compatibility remain unverified. Local copies cannot claim Anthropic’s signing identity or restricted Keychain groups. macOS may ask for Keychain access or other permissions again. Keep the official app available for features that require its identity.

Inspired by [am-will/multi-codex-app](https://github.com/am-will/multi-codex-app). Built in Swift/AppKit, with no third-party runtime dependencies.

## Use the application

1. Open **Multi Claude.app** in your personal Applications folder: Finder → Go → Home → Applications.
2. Click **Open Claude** on Primary or Secondary. Sign in separately in the intended Claude window.
3. Click **Add Account** for more profiles. Enter an account name or email and choose a tag color.
4. On an account card, use **Manage → Rename / Set Email Label** or **Tag Color** to change its identity.

Only the native account apps appear in the Dock. A small startup executable replaces itself with the Claude executable in the same app bundle, keeping the same process ID. There is no persistent proxy launcher.

When upgrading from the old launcher version, existing Claude windows stay open. **Quit each account with Command-Q and reopen it from Multi Claude when ready** to apply its tagged Dock icon. The manager shows a reminder on accounts still running from the original app. Wait for any active work to finish before quitting.

Use the **stack icon in the menu bar → Profile Management** to open the account switcher. It shows the full account name/email and a colored tag, such as **P1**, **S2**, or **W3**. Click **Open Claude** to switch to that account. You can also open Multi Claude from Finder; its window appears without a Dock icon.

Each account card has a **Usage** button, and the menu-bar app has a **5-hour + Weekly Usage** submenu. These open Claude's own Settings → Usage page in the matching account app, where its current session and weekly meters are shown. Anthropic does not document a subscription-usage API for external apps, so Multi Claude opens the authoritative account page instead of estimating or scraping those values. Choose **Chooser Preview** in the manager (or **Preview Login Chooser in Manager** from the menu bar) to see the sign-in chooser inline; it is only a preview and never sends a link.

Labels are yours to set; they do not read or change the authenticated email. Native Claude windows run inside each account app. The same tagged icon identifies the account in the Dock, Finder, manager, and menu bar. Double-clicking an account app selects its saved profile without needing Terminal arguments.

Double-click **Start Claude Profiles.command** in the project folder to build/install on first use and open the manager.

## Install from source

Requires macOS 13+, the official `/Applications/Claude.app`, and Apple's Swift command-line tools to build. Built apps run without Swift, Go, Node, or Python installed.

```sh
sh scripts/build.sh
sh install.sh --count 2
open "$HOME/Applications/Multi Claude.app"
```

The build also creates `build/Multi Claude.app`. It has a native first-run setup screen. It is locally ad-hoc signed; distributed downloads would need Apple signing and notarization for a normal Gatekeeper experience.

## Sign-in troubleshooting

The default mode is **Claude Native Sign-in**. Opening or focusing an account through Multi Claude assigns its authentication links to that native account app. Existing windows from the official app keep the official handler. This lets the intended app handle its native sign-in flow.

If sign-in stalls, choose **Manage → Retry Native Sign-in** on the intended account. This selects native link handling and opens/focuses that profile. Cancel the old sign-in attempt, then retry using Claude's sign-in button. Choose the intended account in the browser or authentication sheet.

If a browser callback opens Primary or another profile, choose **File → Login Links → Choose Profile for Browser Callbacks**, then restart sign-in. A chooser appears for incoming links: select the **running profile where you began sign-in**, then Continue. Nothing is preselected. Closed profiles are disabled. Cancel discards the link; restart sign-in to get a fresh one.

Some native authentication sessions return directly to their originating window, without a chooser. The browser's account session is shared, so select the correct account there too. Switching modes does not clear profile data or sign anyone out. The mode applies to this macOS user's Claude links, not just one profile.

Real second-account, enterprise, and connector OAuth completion still needs verification by the user. The locally signed copies also have different identities from the official app. These controls address protocol ownership conflicts; they cannot resolve service-side account errors, expired login links, or network problems.

## Ten accounts

Use **Add Account** eight more times after the initial two profiles, or run:

```sh
~/.local/bin/multi-claude-app setup --count 10
```

Sign in to each account separately. Keep unused profiles closed to save memory and CPU. There are five tag colors; profile numbers keep tags distinct when colors repeat. Up to 100 active profiles are supported. App copies share unchanged file blocks on APFS. On other filesystems each copy uses roughly the installed Claude app’s full size, in addition to separate account storage.

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

Colors: orange, blue, purple, teal, yellow. Names/colors can change without changing data folders. Numbers are never reused. `setup --count N` only grows the active count. Quit an account before renaming, recoloring, removing, or rebuilding its native app. Remove/restore changes apps and preserves account data. Commands refuse to replace or delete an app while its native Claude process is running.

## How it works

| Profile | Desktop storage | Claude Code configuration environment |
| --- | --- | --- |
| Primary | Existing `~/Library/Application Support/Claude` | Existing default |
| Extra profiles | `~/Library/Application Support/Multi Claude/profiles/ID/desktop` | `…/profiles/ID/claude-code` |

Setup makes a local native copy per account, preserving Electron’s helper naming while assigning a distinct bundle ID, display name, and SVG-derived icon. A bootstrap uses `execv` to become the copied Claude executable and passes Chromium’s `--user-data-dir` flag, including an explicit original data path for Primary. Extra profiles also receive `CLAUDE_CONFIG_DIR` for child tools that honor it. No existing credentials are copied between accounts. Usage and billing stay attached to each account.

In chooser mode, a native menu helper owns the `claude://` and installed Microsoft authentication schemes. It sends incoming links directly to the selected Claude process through a macOS open-URL Apple Event. Links stay in memory and are never stored in logs, files, or process arguments. The helper refreshes ownership every five seconds in chooser mode. In native mode, opening an account selects that account’s native handler.

Editable SVG icons and macOS `.icns` icons are generated inside each native account app’s `Contents/Resources` folder. The vector Claude mark is in [assets/claude-mark.svg](assets/claude-mark.svg).

### Compatibility limits

- Tested locally with Claude Desktop **2.31226.1**, Apple silicon. Signed builds ignore `CLAUDE_USER_DATA_DIR`; this tool uses the Chromium flag.
- This Claude build marks relocated data folders as ineligible for **local pairing**. That protection is preserved.
- Isolation of all Code/Cowork tools, OS Keychain items, native services, and spawned processes is unverified. Claude may choose its own internal directories for some features.
- Claude chats and memories are managed by its service. This app does not provide Codex-style local chat or memory sharing.
- Intel compilation is supported by `ARCH=x86_64 sh scripts/build.sh`; Intel runtime behavior is unverified. Only macOS is implemented.

## Update and uninstall

Update **the official Claude app** normally. Quit the native account copies, then run `multi-claude-app setup` to refresh them from the updated official app. **Use the official app for updates, not the account copies’ in-app updater.** Copies set `DISABLE_AUTOUPDATER=1` and make their bundled Squirrel installer non-executable so an update cannot discard the profile bootstrap. Setup checks the source version/signature identity and bootstrap digest, and keeps current copies in place.

Rebuild and run `sh install.sh` to update this manager. Setup preserves account data. Migrating from old launchers stops those wrapper processes without quitting the real Claude windows. Once native copies are running, updates require quitting the accounts that need rebuilding.

```sh
multi-claude-app uninstall
```

Quit the native account apps before uninstalling. Uninstall removes the manager, local account copies, menu helper, and LaunchAgent. It restores prior login handlers when a managed app or helper owns them. Account data, configuration, and the CLI are retained. Run `setup` to reinstall.

Configuration: `~/Library/Application Support/Multi Claude/config.json`. Profile folders are mode 700; config is mode 600. Use one integrated installation per macOS user and keep its root in a permanent location.

For development without changing protocol handlers or login items:

```sh
build/multi-claude-app --root /absolute/dev/root setup --count 2 \
  --no-integration --applications /absolute/dev/Applications
python3 tests/test_cli.py
```

## Credits and license

Implementation: MIT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). The Claude mark is Anthropic's artwork/trademark and is used to identify Claude account launchers; it is not relicensed as MIT. This is an independent project, not an Anthropic product.
