# Verification — 2026-10-11

Environment: Apple silicon macOS, Claude Desktop 2.31226.1.

- Native Swift release build succeeded; generated CLI and launcher bundles are locally ad-hoc signed.
- Nine management tests passed in disposable roots with login routing and LaunchAgents disabled: repeat setup, rename/recolor, remove/restore, stable IDs, collision handling, data preservation, malformed links, damaged config, and redirected data paths.
- Installed Primary and Secondary launchers in the user's Applications directory and started the menu helper through a user LaunchAgent.
- Primary continued as the original running process. Secondary launched through its installed app bundle into a separate data directory. Repeated launch commands focused that process rather than creating another main process.
- `lsof` confirmed Secondary's browser storage used its managed folder; no Primary cookie, config, or LevelDB lock files were open in Secondary.
- Direct delivery of a harmless Claude settings deep link to Secondary's process succeeded through a targeted open-URL Apple Event.
- Doctor verified the official Claude app signature and both configured login-handler registrations.
- The native chooser was inspected visually and through accessibility: both running profiles were listed with distinct colors, no initial selection, and a disabled Done button. Selecting Secondary enabled Done.

Actual second-account authentication, live connector OAuth, enterprise/MSAL completion, and all Code/Cowork features require user sign-in and remain unverified. The installed build explicitly disables local pairing for relocated data folders; the tool preserves that restriction.
