#!/usr/bin/env python3
"""Merge per-language translation files into a single Xcode String Catalog.

Validates, before writing anything:
  * every language covers every key,
  * format specifiers match the source key exactly (allowing positional forms),
  * plural entries supply the categories the language actually requires.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).parent
SCRATCH = ROOT / "translations"
OUT = pathlib.Path(__file__).parent.parent / "CostPerDay/Resources/Localizable.xcstrings"

LANGS = ["zh-Hant", "zh-Hans", "ja", "ko", "id", "es", "fr", "de", "pt-BR", "ru", "vi"]

# CLDR categories each language must supply for a plural entry.
REQUIRED_PLURALS = {
    "zh-Hant": {"other"}, "zh-Hans": {"other"}, "ja": {"other"},
    "ko": {"other"}, "id": {"other"}, "vi": {"other"},
    "es": {"one", "other"}, "fr": {"one", "other"}, "de": {"one", "other"},
    "pt-BR": {"one", "other"},
    "ru": {"one", "few", "many", "other"},
    "en": {"one", "other"},
}

SPEC = re.compile(r"%(?:(\d+)\$)?(@|lld|d|lf|f)")


def specs(text):
    """Multiset of format specifiers, normalising %1$@ to %@ so word-order
    changes are allowed but argument count/type changes are not."""
    out = []
    for _, kind in SPEC.findall(text.replace("%%", "")):
        out.append(kind)
    return sorted(out)


def check(lang, key, value, errors):
    want = specs(key)
    for form, text in (value.items() if isinstance(value, dict) else [(None, value)]):
        got = specs(text)
        if got != want:
            errors.append(
                f"[{lang}] specifier mismatch on {key!r}"
                + (f" ({form})" if form else "")
                + f"\n      key wants {want}, translation has {got}: {text!r}"
            )


def main():
    keys = json.loads((ROOT / "keys.json").read_text())
    en_plurals = json.loads((ROOT / "en_plurals.json").read_text())
    errors = []

    langs = {}
    for lang in LANGS:
        path = SCRATCH / f"{lang}.json"
        if not path.exists():
            errors.append(f"[{lang}] missing file {path.name}")
            continue
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            errors.append(f"[{lang}] invalid JSON: {exc}")
            continue

        missing = set(keys) - set(data)
        extra = set(data) - set(keys)
        if missing:
            errors.append(f"[{lang}] missing {len(missing)} keys, e.g. {sorted(missing)[:3]}")
        if extra:
            errors.append(f"[{lang}] {len(extra)} unknown keys, e.g. {sorted(extra)[:3]}")

        for key, value in data.items():
            if key not in keys:
                continue
            if isinstance(value, dict):
                need = REQUIRED_PLURALS[lang]
                have = set(value)
                if not need <= have:
                    errors.append(f"[{lang}] {key!r} missing plural forms {sorted(need - have)}")
                if key not in en_plurals:
                    errors.append(f"[{lang}] {key!r} is not a plural-sensitive key but has plural forms")
            elif not isinstance(value, str):
                errors.append(f"[{lang}] {key!r} is neither a string nor a plural object")
                continue
            check(lang, key, value, errors)
        langs[lang] = data

    for key, value in en_plurals.items():
        check("en", key, value, errors)

    if errors:
        print(f"VALIDATION FAILED — {len(errors)} problem(s):\n")
        for e in errors[:40]:
            print("  " + e)
        if len(errors) > 40:
            print(f"  … and {len(errors) - 40} more")
        return 1

    def unit(text):
        return {"stringUnit": {"state": "translated", "value": text}}

    def plural_unit(forms):
        return {
            "variations": {
                "plural": {cat: unit(text) for cat, text in sorted(forms.items())}
            }
        }

    strings = {}
    for key, comment in sorted(keys.items()):
        entry = {}
        if comment:
            entry["comment"] = comment
        localizations = {}

        if key in en_plurals:
            localizations["en"] = plural_unit(en_plurals[key])
        else:
            # A key whose source text is the key itself needs no explicit en entry,
            # but stating it makes the catalog self-describing in the Xcode editor.
            localizations["en"] = unit(key)

        for lang in LANGS:
            value = langs[lang][key]
            localizations[lang] = plural_unit(value) if isinstance(value, dict) else unit(value)

        entry["localizations"] = localizations
        entry["extractionState"] = "manual"
        strings[key] = entry

    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    total = len(keys) * (len(LANGS) + 1)
    print(f"OK — wrote {OUT}")
    print(f"     {len(keys)} keys x {len(LANGS) + 1} languages = {total} localisations")
    return 0


if __name__ == "__main__":
    sys.exit(main())
