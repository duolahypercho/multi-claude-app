# Verification — 2026-10-12

Environment: Apple silicon macOS, official Claude Desktop 2.31226.1.

- Native Swift release build succeeded. Fifteen disposable-root tests cover profile management, ten distinct app identities, source-bundle preservation, repeat setup without replacing current apps, name/email labels and SVG tags, data preservation, malformed links, old-config migration, and login modes.
- The native startup fixture confirms that the bootstrap becomes the target executable with the **same PID**. Each account receives its exact data path, account-specific Code configuration, and cleared inherited overrides. Primary receives its explicit original data path. The fixture does not read real account storage.
- A real Claude copy was installed in a separate verification root and opened through the normal application launch path. Process inspection confirmed one native Claude main process in the account bundle and its isolated `--user-data-dir`. Native helper processes had accessory activation policies. No persistent launcher remained.
- Read the running process icon through `NSRunningApplication.icon`: it showed the Claude mark with the right-side S2 tag. Its macOS application name was Claude Secondary. Inspected the native window through accessibility: it reached Claude’s Get started sign-in screen.
- Verified that rename/recolor, remove, and uninstall refuse to mutate a running native account app and leave configuration intact. Repeating setup kept the current live bundle in place.
- Doctor verified the original official signature and both native-copy signatures with deep, strict checks. The bundled Squirrel installer is made non-executable in copies, with automatic updates disabled in their startup environment. Updating copies is handled by setup from the official app.
- Installed the updated manager, account copies, and menu helper without terminating the existing original Claude instances. Existing windows require quitting and reopening from Multi Claude to use tagged native copies; the manager shows this migration reminder.
- Previous targeted delivery of a harmless settings deep link to the isolated original Secondary instance succeeded through an open-URL Apple Event. Previous chooser inspection confirmed explicit account selection with no default and closed profiles disabled. Callback delivery to locally signed account copies still needs authenticated validation.
- Shell syntax checks and whitespace validation are included in the final verification. CI also cross-compiles the other Mac architecture.

The native-copy approach changes the local signing identity. It does not preserve Anthropic’s restricted Keychain groups. Existing Keychain permissions, enterprise/MSAL sign-in, passkeys, and services that validate the vendor signature may require the official app. No account credentials are copied between profiles. The original Claude app remains unchanged.

A completed second-account session, connector OAuth, and full Code/Cowork behavior remain **unverified**. Reaching the native sign-in screen and passing management tests do not establish successful authentication. The installed Claude build disables local pairing for relocated data folders; that restriction is preserved. Intel runtime behavior is unverified. The PR remains a draft until authenticated account behavior is checked.
