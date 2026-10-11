# Verification — 2026-10-11

Environment: Apple silicon macOS, official Claude Desktop 2.31226.1.

- Native Swift release build and Intel cross-compilation succeeded. Generated executables and app bundles are locally ad-hoc signed.
- Twelve management tests passed in disposable roots without changing login handlers or LaunchAgents: repeat setup, email labels and SVG tags, old-config migration, login-mode validation, manager/app collision handling, rename/recolor, remove/restore, stable IDs, data preservation, malformed links, damaged config, and redirected data paths.
- Installed the native Multi Claude manager, persistent Primary/Secondary Dock launchers, and menu helper. Updated the installation while preserving both original Claude main process IDs and account data.
- Inspected the manager visually and through accessibility. The account cards show the Claude vector mark and distinct P1/S2 right-side tags. Verified the Add Account form and canceled it; verified the name/email editor by saving Secondary's existing label. Its launcher restarted while its Claude process stayed running.
- Primary remains the original Claude process. Secondary uses its separate managed desktop directory. Repeated launches focus the intended process.
- `lsof` confirmed Secondary browser storage used its managed folder; no Primary cookie, config, or LevelDB lock files were open in Secondary.
- Direct delivery of a harmless Claude settings deep link to Secondary succeeded through a targeted open-URL Apple Event.
- Doctor verified the official Claude app signature and both configured login handlers. Native mode leaves handlers with Claude; chooser mode registers Multi Claude. Returned the local installation to native mode.
- The native chooser was inspected visually and through accessibility: running profiles have distinct icons, nothing is preselected, and Done stays disabled until a profile is selected.
- Shell syntax checks and `git diff --check` passed.

Sign-in investigation found that this installed Claude build changes its native auth behavior when it is not the default protocol handler. Claude logs showed that branch during the user's attempts. Native mode and the Retry Native Sign-in action avoid that protocol ownership conflict; chooser mode remains available for browser callbacks that reach the wrong instance.

This does **not** establish the precise cause of the user's reported sign-in failure or verify a completed second-account session. Actual second-account authentication, connector OAuth, enterprise/MSAL completion, and all Code/Cowork features require user sign-in and remain unverified. The installed Claude build disables local pairing for relocated data folders; the tool preserves that restriction. Intel runtime behavior is unverified.
