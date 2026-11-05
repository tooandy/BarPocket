# Testing and validation

## Automated checks

`Scripts/check-localizations.py` checks that all source keys exist in all nine `.lproj` languages, and that format placeholders match. CI and Release run this check and lint both `.strings` tables.

`./build.sh` performs the following checks:

1. Compile all Swift sources into the app bundle.
2. Run the built-in layout self-tests.
3. Apply a local ad-hoc code signature.
4. Verify the resulting app bundle signature.

The GitHub Actions CI workflow runs these checks on an Apple Silicon macOS hosted runner for pull requests and pushes to `main`.

## Manual checks required on a real Mac

The following behaviors depend on Window Server, menu-bar geometry, and the installed apps, so CI cannot fully validate them:

- Toggle the pocket closed and open; verify the divider and status items remain clickable.
- Enable and disable black notch mode; verify the top menu-bar row turns black and native menu titles/status items remain visible and interactive.
- Plug/unplug an external display while black notch mode is enabled.
- Grant Accessibility permission and verify menu-bar inventory, item descriptions, and visible/behind-notch/off-screen classification.
- Test `AXPress` and Command-drag against representative third-party menu-bar apps.
- Change the macOS preferred language to each of the nine supported languages in turn, relaunch BarPocket, and verify the menu, manager, alerts, and permission description follow the selected language. Other languages should fall back to English.
- Replace an installed release and verify whether macOS asks the user to re-authorize Accessibility (expected to be possible with ad-hoc signatures).

Do not claim that an AX action or drag is universally supported: macOS and individual apps may reject it.
