"""Builds App/Resources/Localizable.xcstrings from the Android app's string resources.

Keys are the Android resource names, so the wording stays the same on both platforms.
Placeholders: %1$s -> %1$@, %1$d -> %1$lld, %s -> %@, %d -> %lld.
Strings only the Apple app has (Apple Pencil, where Android speaks of the S Pen) come from
tools/ios_strings.json, one entry per key with all six languages.

    python tools/import_strings.py C:/dev/Talis-Notes/app/src/main/res
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

LANGS = {"values": "en", "values-es": "es", "values-fr": "fr", "values-pt": "pt-BR", "values-ar": "ar", "values-iw": "he"}

BS = chr(92)  # a backslash


def unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == BS and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t"}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def text_of(el):
    s = (el.text or "") + "".join(ET.tostring(c, encoding="unicode") for c in el)
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        s = s[1:-1]
    else:
        s = s.strip()
    s = unescape(s)
    s = re.sub(r"%(\d+\$)?s", lambda m: "%" + (m.group(1) or "") + "@", s)
    s = re.sub(r"%(\d+\$)?d", lambda m: "%" + (m.group(1) or "") + "lld", s)
    return s


def main(res):
    res = Path(res)
    table = {}
    for folder, lang in LANGS.items():
        f = res / folder / "strings.xml"
        if not f.exists():
            continue
        root = ET.parse(f).getroot()
        for el in root.findall("string"):
            if el.get("translatable") == "false" and lang != "en":
                continue
            table.setdefault(el.get("name"), {})[lang] = text_of(el)
    extra = json.loads((Path(__file__).resolve().parent / "ios_strings.json").read_text(encoding="utf-8"))
    for key, texts in extra.items():
        if key in table:
            sys.exit(f"{key} is an Android string: ios_strings.json can't replace it")
        if set(texts) != set(LANGS.values()):
            sys.exit(f"{key} needs every language: {sorted(LANGS.values())}")
        table[key] = texts
    strings = {}
    for key in sorted(table):
        locs = {lang: {"stringUnit": {"state": "translated", "value": v}} for lang, v in table[key].items()}
        strings[key] = {"extractionState": "manual", "localizations": locs}
    out = Path(__file__).resolve().parent.parent / "App" / "Resources" / "Localizable.xcstrings"
    out.write_text(json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(strings)} keys -> {out}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "C:/dev/Talis-Notes/app/src/main/res")
