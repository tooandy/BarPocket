# Contributing

Thanks for helping improve BarPocket.

## Before opening a pull request

1. Keep changes focused and explain the user-visible behavior.
2. Build and run the local self-tests with `./build.sh`.
3. Verify the app on a real Mac when changing menu-bar layout, Accessibility, or notch behavior. Window-server behavior is difficult to validate in a headless environment.
4. Do not add network access, analytics, screen recording, Input Monitoring, Apple Events, or broader permissions without a clear need and explicit discussion.
5. Never commit signing identities, private keys, tokens, provisioning profiles, or personal machine paths.

Pull requests run the public macOS CI workflow automatically. Release artifacts are produced only from version tags.
