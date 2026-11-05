#!/usr/bin/env python3
"""Check that shipped macOS localization tables are valid and complete."""
from pathlib import Path
import re
import sys
import plistlib

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "zh-Hans", "zh-Hant", "es", "ko", "ja", "de", "fr", "nl")


def keys(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    return set(re.findall(r'^\s*"((?:\\.|[^"])*)"\s*=', text, re.MULTILINE))


def formats(path: Path) -> dict[str, tuple[str, ...]]:
    text = path.read_text(encoding="utf-8")
    result = {}
    for key, value in re.findall(r'^\s*"((?:\\.|[^"])*)"\s*=\s*"((?:\\.|[^"])*)"\s*;', text, re.MULTILINE):
        result[key] = tuple(re.findall(r'%(?:\d+\$)?(?:[-+0 #]*\d*(?:\.\d+)?)?(?:hh|h|ll|l|z|t|j)?[@diuoxXfFeEgGcCsSp]', value))
    return result


def main() -> int:
    base = ROOT / "Resources" / f"{LANGUAGES[0]}.lproj" / "Localizable.strings"
    base_keys = keys(base)
    errors = []
    metadata = plistlib.loads((ROOT / "Info.plist").read_bytes())
    if set(metadata.get("CFBundleLocalizations", [])) != set(LANGUAGES):
        errors.append("Info.plist CFBundleLocalizations does not match LANGUAGES")
    declared = {p.name.removesuffix(".lproj") for p in (ROOT / "Resources").glob("*.lproj")}
    if declared != set(LANGUAGES):
        errors.append(f"Resource directories do not match LANGUAGES: {sorted(declared ^ set(LANGUAGES))}")

    for language in LANGUAGES:
        table = ROOT / "Resources" / f"{language}.lproj" / "Localizable.strings"
        info = ROOT / "Resources" / f"{language}.lproj" / "InfoPlist.strings"
        if not table.is_file() or not info.is_file():
            errors.append(f"{language}: missing localization table or InfoPlist.strings")
            continue
        current = keys(table)
        if len(re.findall(r'^\s*"((?:\\.|[^"])*)"\s*=', table.read_text(encoding="utf-8"), re.MULTILINE)) != len(current):
            errors.append(f"{language}: duplicate localization key(s)")
        missing = base_keys - current
        extra = current - base_keys
        if missing:
            errors.append(f"{language}: missing Localizable.strings keys: {sorted(missing)}")
        if extra:
            errors.append(f"{language}: unexpected Localizable.strings keys: {sorted(extra)}")
        if not {"CFBundleDisplayName", "CFBundleName", "NSAccessibilityUsageDescription"}.issubset(keys(info)):
            errors.append(f"{language}: InfoPlist.strings is missing required metadata keys")

    source_keys = set()
    for source in (ROOT / "Sources").glob("*.swift"):
        source_keys.update(re.findall(r'\btrf?\("([^"]+)"', source.read_text(encoding="utf-8")))
    missing_source = source_keys - base_keys
    if missing_source:
        errors.append(f"Source references missing localization keys: {sorted(missing_source)}")

    en_formats = formats(ROOT / "Resources/en.lproj/Localizable.strings")
    for language in LANGUAGES[1:]:
        locale_formats = formats(ROOT / "Resources" / f"{language}.lproj" / "Localizable.strings")
        for key in base_keys:
            if en_formats.get(key, ()) != locale_formats.get(key, ()):
                errors.append(f"Format placeholders differ between en and {language} for key: {key}")

    if errors:
        print("Localization validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"PASS: {len(base_keys)} UI localization keys, {len(source_keys)} source references, {len(LANGUAGES)} languages, matching format placeholders")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
