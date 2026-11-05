# Security policy

BarPocket is a local macOS utility. It does not need a network connection for its core features.

## Permission boundary

- The app is not App-Sandboxed because its optional cross-app menu-bar inventory uses macOS Accessibility APIs.
- Accessibility access is optional and is requested only when the user clicks the permission button in the manager window.
- The app does not request Screen Recording, Input Monitoring, Apple Events automation, administrator privileges, or a helper daemon.
- The inventory reads exposed menu-bar element descriptions and positions. It does not read other apps' document contents or capture the screen.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository when available. If it is not enabled, contact the maintainer privately through GitHub before publishing details. Do not include secrets or personal data in public issues.
