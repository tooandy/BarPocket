# BarPocket

**A lightweight macOS menu bar organizer with notch-aware management and a black notch mode.**

BarPocket helps reclaim menu-bar space on MacBooks with a notch. It uses a draggable divider as a pocket boundary, offers an optional manager for menu-bar items exposed by macOS Accessibility, and can turn the full top menu-bar row black so the notch blends into it.

> Current distribution: Apple Silicon (arm64), macOS 13 or later. The app is ad-hoc signed and is not notarized by Apple. See [Installation](#installation-and-gatekeeper) before downloading a release.

## Features

- **Collapse / expand:** click the menu-bar toggle to hide or reveal items placed on the pocket side of the divider.
- **Manual organization:** hold `⌘` while dragging menu-bar items across the divider.
- **Menu-bar manager:** optionally enumerate running apps' `AXExtrasMenuBar` items, search them, and classify them as visible, behind the notch, or off-screen.
- **Explicit actions:** try `AXPress` on a selected item, or move a visible item into the pocket / restore an off-screen item when macOS exposes a usable position.
- **Black notch mode:** draw a full-width black backing immediately beneath the system menu-bar window. The backing ignores mouse events, leaving native menu titles and status items interactive.
- **Offline and lightweight:** no analytics, telemetry, network service, background daemon, or third-party runtime dependency.

## Installation and Gatekeeper

1. Open [GitHub Releases](https://github.com/tooandy/BarPocket/releases) and download the latest `BarPocket-*-arm64.dmg` or `.zip`.
2. Move `BarPocket.app` into Applications (or `~/Applications`).
3. Because releases are **not signed with an Apple Developer ID and are not notarized**, macOS Gatekeeper may block the first launch. If macOS displays an unidentified-developer warning, use Finder's **Control-click → Open** flow, or review the app-specific option under **System Settings → Privacy & Security**. The exact wording varies by macOS version.
4. The basic divider and black notch mode do not require Accessibility permission. To use the cross-app menu-bar manager, open it from the BarPocket menu and grant Accessibility access when prompted.

BarPocket does not ask users to disable Gatekeeper globally. Only install builds you trust; the source code and build workflow are public for inspection.

## Permissions and security

- **App Sandbox:** disabled. macOS does not allow this app's cross-process Accessibility inventory to work from its current sandboxed configuration. This means the process has the normal file and process access of the logged-in user; it is not restricted to a container.
- **Accessibility:** optional. Requested only after the user clicks the permission button. Used to read menu-bar item descriptions/positions and, on explicit user action, invoke `AXPress` or simulate a Command-drag.
- **Not requested:** Screen Recording, Input Monitoring, Apple Events automation, administrator privileges, or a privileged helper.
- **Network:** no network access is used by the app.
- **Signing:** local builds and public releases use an ad-hoc signature (`codesign --sign -`). There is no Developer ID identity, Apple notarization, or stapled ticket.

Because ad-hoc signatures do not provide a stable Developer ID identity, macOS may ask users to re-confirm Accessibility access after replacing the app with a newly built release. This cannot be made equivalent to a Developer ID-signed upgrade without an Apple developer identity.

## Build from source

Requirements: Xcode Command Line Tools, Swift compiler, macOS 13+, Apple Silicon.

```sh
git clone https://github.com/tooandy/BarPocket.git
cd BarPocket
./build.sh
open dist/BarPocket.app
```

To install into `~/Applications/BarPocket.app`:

```sh
./build.sh --install
```

The build script runs the built-in layout self-tests, ad-hoc signs the app, and verifies the resulting bundle. It does not need signing secrets.

## CI and releases

- Pull requests and pushes to `main` run the macOS ARM64 build, self-tests, and code-signature verification.
- Creating a `v*` tag runs the release workflow, builds an ad-hoc signed app, packages ZIP and DMG files, writes `SHA256SUMS`, and publishes a GitHub Release.
- Public repositories use GitHub's standard hosted runners at no charge. No Apple Developer membership or signing secrets are required.

Example release:

```sh
git tag v0.3.1
git push origin v0.3.1
```

The tag version must match `CFBundleShortVersionString` in `Info.plist`.

## Known limitations

- The manager can only show menu-bar elements that an app exposes through `AXExtrasMenuBar`; some apps and system items are not exposed.
- Without Screen Recording, the list uses the owning app's icon rather than a screenshot of each individual menu-bar glyph.
- macOS has no public API for arbitrary cross-app status-item ordering. Moving items is a best-effort, user-triggered Command-drag; some apps/system items may refuse it.
- An item still physically covered by the notch may be impossible to drag until menu-bar space is freed.
- The black notch backing relies on current Window Server menu-bar window ordering. macOS updates may change this behavior and should be tested on real hardware.
- External-display menu bars are not the primary target of the current notch mode.

## License

MIT. See [LICENSE](LICENSE).
