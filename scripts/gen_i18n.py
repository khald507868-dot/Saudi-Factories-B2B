# -*- coding: utf-8 -*-
"""Convert i18n.js dict/regions/categories into Dart source.

The JS blocks are plain object literals with string values, so we parse them
with a small tokenizer rather than eval: keys may be bare or quoted, values are
single- or double-quoted strings possibly containing escaped quotes.
"""
import io, re, json, os

# الجذر يُشتقّ من موقع السكربت نفسه — وكان مساراً ثابتاً
# يشير إلى نسخة قديمة من المشروع، فكان يقرأ ويكتب خارج المستودع.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "i18n.js")
OUT = os.path.join(ROOT, "app_flutter", "lib", "core", "i18n_data.dart")

s = io.open(SRC, encoding="utf-8").read()

# ---- locate the dict literal ------------------------------------------------
start = s.index("var dict = {")
brace = s.index("{", start)
depth, i = 0, brace
while True:
    c = s[i]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
dict_body = s[brace + 1:i]

LANG_RE = re.compile(r'(?:^|,)\s*("?)([a-z][a-z-]*)\1\s*:\s*\{', re.M)


def parse_pairs(body):
    """key: 'value' pairs inside one language block."""
    out = {}
    pos = 0
    pair = re.compile(
        r'\s*("?)([A-Za-z_][A-Za-z0-9_]*)\1\s*:\s*'
        r'''(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')\s*,?''')
    while True:
        m = pair.match(body, pos)
        if not m:
            break
        key = m.group(2)
        raw = m.group(3) if m.group(3) is not None else m.group(4)
        # unescape JS string escapes
        val = raw.replace('\\"', '"').replace("\\'", "'").replace("\\\\", "\\")
        val = val.replace("\\n", "\n")
        out[key] = val
        pos = m.end()
    return out


langs = {}
for m in LANG_RE.finditer(dict_body):
    code = m.group(2)
    b = m.end() - 1
    d, j = 0, b
    while True:
        c = dict_body[j]
        if c == "{":
            d += 1
        elif c == "}":
            d -= 1
            if d == 0:
                break
        j += 1
    langs[code] = parse_pairs(dict_body[b + 1:j])

assert "ar" in langs and "en" in langs, "missing base languages"
print("languages:", len(langs))
print("ar keys:", len(langs["ar"]), "en keys:", len(langs["en"]))

# ---- regions ----------------------------------------------------------------
rstart = s.index("var regionNames = {")
rb = s.index("{", rstart)
d, j = 0, rb
while True:
    c = s[j]
    if c == "{":
        d += 1
    elif c == "}":
        d -= 1
        if d == 0:
            break
    j += 1
regions_src = s[rb + 1:j]
region_re = re.compile(r'"([a-z-]+)"\s*:\s*\{\s*ar:\s*"([^"]*)"\s*,\s*en:\s*"([^"]*)"\s*\}')
regions = [(m.group(1), m.group(2), m.group(3)) for m in region_re.finditer(regions_src)]
print("regions:", len(regions))

# ---- categories -------------------------------------------------------------
cstart = s.index("var categories = [")
cb = s.index("[", cstart)
d, j = 0, cb
while True:
    c = s[j]
    if c == "[":
        d += 1
    elif c == "]":
        d -= 1
        if d == 0:
            break
    j += 1
cats_src = s[cb + 1:j]
cat_re = re.compile(r'\{\s*ar:\s*"([^"]*)"\s*,\s*en:\s*"([^"]*)"\s*\}')
cats = [(m.group(1), m.group(2)) for m in cat_re.finditer(cats_src)]
print("categories:", len(cats))


def dq(v):
    """Dart double-quoted literal."""
    v = v.replace("\\", "\\\\").replace('"', '\\"')
    v = v.replace("\n", "\\n").replace("$", "\\$")
    return '"' + v + '"'


lines = []
lines.append("// ============================================================")
lines.append("//  \u0645\u0644\u0641 \u0645\u064f\u0648\u0644\u064e\u0651\u062f \u0622\u0644\u064a\u0627\u064b \u0645\u0646 i18n.js \u2014 \u0644\u0627 \u062a\u0639\u062f\u0651\u0644\u0647 \u064a\u062f\u0648\u064a\u0627\u064b.")
lines.append("//  \u0623\u0639\u062f \u062a\u0648\u0644\u064a\u062f\u0647 \u0628\u0640: python scripts/gen_i18n.py")
lines.append("// ============================================================")
lines.append("")
lines.append("/// \u0627\u0644\u0644\u063a\u0627\u062a \u0627\u0644\u062a\u064a \u062a\u064f\u0643\u062a\u0628 \u0645\u0646 \u0627\u0644\u064a\u0645\u064a\u0646 \u0625\u0644\u0649 \u0627\u0644\u064a\u0633\u0627\u0631.")
lines.append('const List<String> kRtlLangs = ["ar", "fa", "ur", "he"];')
lines.append("")
lines.append("/// \u0623\u0633\u0645\u0627\u0621 \u0627\u0644\u0645\u0646\u0627\u0637\u0642 (\u0627\u0644\u0645\u0639\u0631\u0651\u0641 \u2190 \u0639\u0631\u0628\u064a/\u0625\u0646\u062c\u0644\u064a\u0632\u064a).")
lines.append("const Map<String, Map<String, String>> kRegionNames = {")
for rid, ar, en in regions:
    lines.append('  %s: {"ar": %s, "en": %s},' % (dq(rid), dq(ar), dq(en)))
lines.append("};")
lines.append("")
lines.append("/// \u0641\u0626\u0627\u062a \u0627\u0644\u0645\u0635\u0627\u0646\u0639 \u0628\u062a\u0631\u062a\u064a\u0628\u0647\u0627 \u0627\u0644\u0623\u0635\u0644\u064a.")
lines.append("const List<Map<String, String>> kCategories = [")
for ar, en in cats:
    lines.append('  {"ar": %s, "en": %s},' % (dq(ar), dq(en)))
lines.append("];")
lines.append("")
lines.append("/// \u062c\u062f\u0648\u0644 \u0627\u0644\u062a\u0631\u062c\u0645\u0629 \u0627\u0644\u0643\u0627\u0645\u0644 \u2014 %d \u0644\u063a\u0629." % len(langs))
lines.append("const Map<String, Map<String, String>> kDict = {")
order = ["ar", "en"] + sorted(k for k in langs if k not in ("ar", "en"))
for code in order:
    lines.append("  %s: {" % dq(code))
    for k in langs[code]:
        lines.append("    %s: %s," % (dq(k), dq(langs[code][k])))
    lines.append("  },")
lines.append("};")
lines.append("")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
io.open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("wrote i18n_data.dart")
print("total lines:", len(lines))
