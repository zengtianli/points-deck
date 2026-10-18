"""Product strings stay bilingual; server/user data and shared copies are separate.

Run with the repository's parallel pytest lane. The Swift behavior probe is built
and run separately inside an offscreen bundle for each supported language.
"""
from collections import Counter
import json
from pathlib import Path
import re

import pytest


ROOT = Path(__file__).resolve().parents[1]
CATALOGS = ("Resources/Localizable.xcstrings", "Resources/InfoPlist.xcstrings")
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")
PRINTF = re.compile(
    r"%(?:(\d+)\$)?[-+#0 ']*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([diuoxXfFeEgGaAcCsSp@%])"
)


def uncomment_swift(source):
    """Remove line/nested block comments without mistaking URL strings for comments."""
    output = []
    i = 0
    while i < len(source):
        if source.startswith("//", i):
            end = source.find("\n", i)
            if end < 0:
                break
            output.append("\n")
            i = end + 1
        elif source.startswith("/*", i):
            depth = 1
            i += 2
            while i < len(source) and depth:
                if source.startswith("/*", i):
                    depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    output.append("\n" if source[i] == "\n" else " ")
                    i += 1
        elif source[i] == '"' or (
            source[i] == "#" and re.match(r'#+"', source[i:])
        ):
            start = i
            hashes = 0
            while source[i] == "#":
                hashes += 1
                i += 1
            quote = '"""' if source.startswith('"""', i) else '"'
            i += len(quote)
            close = quote + "#" * hashes
            escape = "\\" + "#" * hashes
            while i < len(source):
                if source.startswith(escape, i):
                    i += len(escape) + 1
                elif source.startswith(close, i):
                    i += len(close)
                    break
                else:
                    i += 1
            output.append(source[start:i])
        else:
            output.append(source[i])
            i += 1
    return "".join(output)


def printf_arguments(value):
    """Compare argument numbers and exact printf types, allowing translated order."""
    found = Counter()
    next_argument = 1
    for match in PRINTF.finditer(value):
        position, length, conversion = match.groups()
        if conversion == "%":
            continue
        index = int(position) if position else next_argument
        if not position:
            next_argument += 1
        found[index, (length or "") + conversion] += 1
    return found


def string_units(node):
    if isinstance(node, dict):
        if "stringUnit" in node:
            yield node["stringUnit"]
        for key, value in node.items():
            if key != "stringUnit":
                yield from string_units(value)


def product_swift_files():
    return sorted(
        path
        for directory in ("Sources", "Watch", "Widget")
        for path in (ROOT / directory).glob("*.swift")
        if path.name != "ProductBasicsSelfTest.swift"
    )


@pytest.mark.parametrize("path", product_swift_files(), ids=lambda path: str(path.relative_to(ROOT)))
def test_product_ui_has_no_embedded_chinese(path):
    code = uncomment_swift(path.read_text())
    # This is the real provider's SMS signature, not a translated product label.
    if path.name == "PhoneAccountView.swift":
        code = code.replace('"恒创联众"', '"<SMS signature>"')
    remaining = [
        f"{number}: {line.strip()}"
        for number, line in enumerate(code.splitlines(), 1)
        if HAN.search(line)
    ]
    assert not remaining, f"Unlocalized product text in {path.relative_to(ROOT)}:\n" + "\n".join(remaining)


@pytest.mark.parametrize("relative", CATALOGS)
def test_catalog_has_complete_english_and_simplified_chinese(relative):
    path = ROOT / relative
    assert path.is_file(), f"Missing String Catalog: {relative}"
    catalog = json.loads(path.read_text())
    assert catalog["sourceLanguage"] == "en"
    assert catalog["strings"], f"Empty catalog: {relative}"
    for key, entry in catalog["strings"].items():
        for language in ("en", "zh-Hans"):
            localization = entry.get("localizations", {}).get(language)
            assert localization is not None, f"{relative}: {key!r} lacks {language}"
            units = list(string_units(localization))
            assert units, f"{relative}: {key!r} has no {language} text"
            for unit in units:
                assert unit.get("state") == "translated", (relative, key, language, unit)
                assert isinstance(unit.get("value"), str) and unit["value"], (relative, key, language)
                if language == "en":
                    assert not HAN.search(unit["value"]), (relative, key, "English contains Chinese")


@pytest.mark.parametrize("relative", CATALOGS)
def test_catalog_preserves_printf_argument_types_and_positions(relative):
    catalog = json.loads((ROOT / relative).read_text())
    for key, entry in catalog["strings"].items():
        source_arguments = printf_arguments(key)
        for language in ("en", "zh-Hans"):
            for unit in string_units(entry.get("localizations", {}).get(language, {})):
                assert printf_arguments(unit["value"]) == source_arguments, (
                    relative, key, language, unit["value"]
                )
