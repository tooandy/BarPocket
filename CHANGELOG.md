# Changelog

## 0.5.0

- Add complete Spanish, Korean, Japanese, German, French, Dutch, and Traditional Chinese UI translations (nine supported languages total).
- Localize Accessibility permission descriptions, alerts, help, manager, and menus for all supported languages.
- Extend CI localization coverage and keep long-language filter labels compact for narrow windows.

## 0.4.0

- Add native Simplified Chinese and English localization for the menu bar, manager window, alerts, help, tooltips, and Accessibility usage description.
- Automatically follow the macOS preferred language; fall back to English for other languages.
- Add localization resource and format-placeholder checks to CI and release builds.

## 0.3.1

- Rename the user-facing app and distribution bundle to BarPocket.
- Preserve the existing bundle identifier and preference keys to reduce migration friction for existing users.
- Add public GitHub Actions CI and unsigned/ad-hoc release packaging.

## 0.3.0

- Add the optional black notch/menu-bar mode.
- Add the Accessibility-based menu-bar manager, visibility classification, and explicit menu-bar actions.
- Keep the app offline and avoid Screen Recording and Input Monitoring permissions.
