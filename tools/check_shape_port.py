#!/usr/bin/env python3
"""Checks the subject shapes here against the Android app's, number for number.

  python3 tools/check_shape_port.py ../Talis-Notes

Reads Android's model/ShapeTemplates.kt and model/ShapePacks.kt and this repo's ShapeTemplates*.swift
and ShapePacks.swift, and compares: the shapes with joints and their order, the numbers each is
drawn with (as a set, with the helpers written just above it), the panel's tile frames, and each
subject's shapes, names and fixed designs. A slip in a number, a shape left out or one out of order
shows up here. Differences that are only the two languages' ways of writing the same thing are in
SAME below, with why. Exits 1 if anything else differs.
"""
import re
import sys
from pathlib import Path

CORE = Path(__file__).resolve().parent.parent / "Packages/TaliCore/Sources/TaliCore"
NUMBER = re.compile(r"(?<![\w.])-?\d+(?:\.\d+)?")
MEMBER = re.compile(r"^(?:  (?![)}\]])\S|\S)", re.M)
ENTRY = re.compile(
    r'symbol\("(?P<id>[^"]*)", "(?P<label>[^"]*)"\)'
    r'|jointed\("(?P<name>[^"]*)", T\.(?P<template>\w+)\)'
    r"|builtIn\((?:ShapeKind)?\.(?P<kind>\w+)\)"
)

# Shape id -> (numbers only Kotlin writes, numbers only Swift writes): the same thing said two ways.
SAME = {
    # Kotlin turns radians into degrees in place (x * 180.0 / PI); Swift calls degrees().
    "pie-chart": ({180}, set()),
    "scales": ({180}, set()),
    "switch": ({180}, set()),
    "cycle": ({180}, set()),
    # List(31) { i -> … i / 30f } is (0...30).map here.
    "bell-curve": ({31}, set()),
    # bentCurve, written above "demand" in both, is List(17) { i / 16f } there and (0...16).map here.
    "demand": ({17}, set()),
    # Its joint's max(d.dot(d), 1f) is in pull(), which sits above "demand" here.
    "lorenz": ({1}, set()),
}


def numbers(text):
    text = re.sub(r"//.*", "", text)
    text = re.sub(r'"[^"]*"', "", text)
    text = re.sub(r"\$\d+", "", text)
    text = re.sub(r"\.\.[.<]?", " ", text)
    text = re.sub(r"(\d)[fF]\b", r"\1", text)
    return {float(n) for n in NUMBER.findall(text)}


def templates(text, declaration):
    """{id: the template's text with the helpers above it}, and the ids in order."""
    out, order, last = {}, [], 0
    for m in declaration.finditer(text):
        after = text.index("\n", m.start()) + 1
        nxt = MEMBER.search(text, after)
        end = nxt.start() if nxt else len(text)
        ident = re.search(r'"([^"]*)"', text[m.end():]).group(1)
        out[ident] = text[last:end]
        order.append(ident)
        last = end
    return out, order


def subjects(text, pack):
    """[(id, name, [(kind, id or label, label or template, numbers of a fixed design)])]."""
    out = []
    found = list(pack.finditer(text))
    for i, m in enumerate(found):
        body = text[m.end():found[i + 1].start() if i + 1 < len(found) else text.index("Every subject")]
        entries = list(ENTRY.finditer(body))
        shapes = []
        for j, e in enumerate(entries):
            if e.group("id") is not None:
                design = body[e.end():entries[j + 1].start() if j + 1 < len(entries) else len(body)]
                shapes.append(("symbol", e.group("id"), e.group("label"), tuple(sorted(numbers(design)))))
            elif e.group("name") is not None:
                shapes.append(("jointed", e.group("name"), e.group("template").replace("switchSymbol", "switch"), ()))
            else:
                shapes.append(("builtIn", e.group("kind"), "", ()))
        out.append((m.group(1), m.group(2), shapes))
    return out


def tiles(text, end, pair):
    part = text[text.index("tileFrames"):]
    return {m.group(1): (float(m.group(2)), float(m.group(3))) for m in pair.finditer(part[:part.index(end)])}


def show(ns):
    return sorted(int(n) if n == int(n) else n for n in ns)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    android = Path(sys.argv[1]) / "app/src/main/java/com/tali/notes/model"
    kt_templates = (android / "ShapeTemplates.kt").read_text()
    kt_packs = (android / "ShapePacks.kt").read_text()
    sw_templates = (CORE / "ShapeTemplates.swift").read_text() + (CORE / "ShapeTemplatesMore.swift").read_text()
    sw_packs = (CORE / "ShapePacks.swift").read_text()
    problems = []

    kt, kt_order = templates(kt_templates[kt_templates.index("// ---- Social sciences"):], re.compile(r"^  val \w+ =\s*(?:sized|natural|line)\(", re.M))
    sw, sw_order = templates(sw_templates[sw_templates.index("// MARK: Social sciences"):], re.compile(r"^  static let \w+ = (?:sized|natural|line)\(", re.M))
    if kt_order != sw_order:
        problems.append(f"shapes with joints differ or are out of order:\n  Android {kt_order}\n  here    {sw_order}")
    for ident in kt_order:
        if ident not in sw:
            continue
        a, b = numbers(kt[ident]), numbers(sw[ident])
        same_kt, same_sw = SAME.get(ident, (set(), set()))
        only_kt, only_sw = a - b - same_kt, b - a - same_sw
        if only_kt or only_sw:
            problems.append(f"{ident}: only on Android {show(only_kt)}, only here {show(only_sw)}")

    kt_tiles = tiles(kt_templates, "fun get", re.compile(r'"([\w-]+)" to \((\d+)f to (\d+)f\)'))
    sw_tiles = tiles(sw_templates, "public static let all", re.compile(r'"([\w-]+)": \((\d+), (\d+)\)'))
    if kt_tiles != sw_tiles:
        problems.append(f"tile frames differ: {sorted(set(kt_tiles.items()) ^ set(sw_tiles.items()))}")

    # Swift makes each static on first use, so nothing registers itself: `all` has to list every one.
    listed = re.search(r"public static let all: \[ShapeTemplate\] = \[(.*?)\n  \]", sw_templates, re.S).group(1)
    declared = re.findall(r"^  static let (\w+) = (?:sized|natural|line)\(", sw_templates, re.M)
    if re.findall(r"\w+", listed) != declared:
        problems.append(f"ShapeTemplates.all and the templates differ: {set(declared) ^ set(re.findall(r'[a-zA-Z]+', listed))}")

    kt_all = subjects(kt_packs, re.compile(r'ShapePack\(\s*"([\w-]+)",\s*"([^"]*)",'))
    sw_all = subjects(sw_packs, re.compile(r'ShapePack\(\s*id: "([\w-]+)", name: "([^"]*)",'))
    if [p[:2] for p in kt_all] != [p[:2] for p in sw_all]:
        problems.append(f"subjects differ: {[p[:2] for p in kt_all]} against {[p[:2] for p in sw_all]}")
    for (pid, _, a), (_, _, b) in zip(kt_all, sw_all):
        if len(a) != len(b):
            problems.append(f"{pid}: {len(a)} shapes on Android, {len(b)} here")
        for x, y in zip(a, b):
            if x[:3] != y[:3]:
                problems.append(f"{pid}: {x[:3]} on Android is {y[:3]} here")
            elif x[3] != y[3]:
                problems.append(f"{pid} {x[1]}: numbers differ {show(set(x[3]) ^ set(y[3]))}")

    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print(f"in step with Android: {len(sw_order)} shapes with joints, {len(sw_all)} subjects of {sum(len(p[2]) for p in sw_all)} shapes, {len(sw_tiles)} tile frames")


if __name__ == "__main__":
    main()
