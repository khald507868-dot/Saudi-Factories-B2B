from __future__ import annotations

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
PAGES = [ROOT / "index.html", *sorted(ROOT.glob("web-*.html"))]


class RefParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.refs: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        data = dict(attrs)
        for attr in ("href", "src"):
            value = data.get(attr)
            if value:
                self.refs.append((attr, value))


def is_local_file(ref: str) -> bool:
    if ref.startswith(("#", "mailto:", "tel:", "javascript:", "data:")):
        return False
    parsed = urlparse(ref)
    return not parsed.scheme and not parsed.netloc


missing: list[str] = []
app_refs: list[str] = []
checked = 0

for page in PAGES:
    parser = RefParser()
    parser.feed(page.read_text(encoding="utf-8"))
    for attr, ref in parser.refs:
        clean = ref.split("#", 1)[0].split("?", 1)[0]
        if not clean:
            continue
        if "app-" in clean and clean.endswith(".html"):
            app_refs.append(f"{page.name}: {attr}={ref}")
        if not is_local_file(ref):
            continue
        target = (page.parent / clean).resolve()
        checked += 1
        if not target.exists():
            missing.append(f"{page.name}: {attr}={ref}")

print(f"web_pages={len(PAGES)}")
print(f"local_refs_checked={checked}")
print(f"missing_refs={len(missing)}")
print(f"removed_app_refs={len(app_refs)}")

if missing:
    print("MISSING")
    print("\n".join(missing))
if app_refs:
    print("APP_REFS")
    print("\n".join(app_refs))

raise SystemExit(1 if missing or app_refs else 0)
