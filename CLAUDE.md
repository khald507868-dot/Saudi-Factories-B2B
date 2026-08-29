# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Two companion files, and you should know when to open them:**
> **`قرارات-سابقة.md`** — the *why* behind rules that look arbitrary: exact
> measurements, failed approaches, and decisions already litigated with the
> owner. Sections below say "see the archive" where it matters; read that
> section **before** editing the thing it describes.
> **`الصفحات.md`** — the page map, written in Arabic for the owner. Keep it in
> sync when pages are added or renamed.
> **`TODO-BEFORE-LAUNCH.md`** — the owner's launch checklist, in Arabic: what is
> done, what is deferred, and *why*. Check it before proposing work — several
> items on it are deliberately deferred, not forgotten. It is the owner's file;
> tick a box when something genuinely ships, don't rewrite it.

## What this is

A no-build multi-page web app: an **Alibaba-style B2B marketplace** for Saudi Arabian factories. There is no `package.json`, no bundler, no framework, and no Node.js — everything is hand-authored HTML/CSS/JS. It is no longer purely static: the gate pages (login/supplier/reset) and the admin pages talk to a hosted Supabase backend, but the dependency is still just a `<script>` tag from a CDN, not a toolchain.

Development is roughly two-thirds interface: the database and its security are solid and tested, while most pages still render placeholder data (see *Current state*).

**This is an Arabic-first product.** The owner communicates in Arabic; all UI copy and code comments are Arabic. Match that — new comments and user-facing strings in Arabic, with the English translation added to `dict.en`.

## The two paths — read before editing any page

The codebase is split into **two independent paths**. This is the most important structural fact here, and it changes what "edit a page" means.

| | prefix | carries `desktop.css` | on a wide screen |
|---|---|---|---|
| Browser site | **`web-`** | yes | wide desktop layout |
| Phone app | **`app-`** | **no** | stays a phone column |

**14 web pages and 15 app pages — and the two paths no longer mirror each other.** This was true once; it stopped being true when the web gates were rebuilt.

Shared by both paths: `home`, `factories`, `factory`, `messages`, `cart`, `account`, `login`, `settings`, `profile`, `help`, `admin`.

- **App path only:** `app-index.html` (splash), `app-user-type.html` (account-type gate), `app-welcome.html`, `app-register.html`.
- **Web path only:** `web-supplier.html` (factory gate), `web-reset.html` (password reset), `web-product.html` (product detail).
- **Deleted from the web path:** `web-register.html` and `web-welcome.html`. Registration merged into `web-login.html` as a tab; the welcome page was removed as useless ("مامنها فائدة"). **Don't recreate them** — `auth-guard.js` now points the web path at `web-login.html` and `web-login.html#register`.

**`index.html` is the one exception with no prefix, and it belongs to the *web* path.** It is the former `web-home.html`, renamed on 2026-08-25 so that a bare domain lands on the factories home page. The name is reserved — servers serve it automatically at the domain root — so **do not rename it**, and read it as a `web-` page everywhere below: it carries `desktop.css`, `SF_PUBLIC_PAGE`, `regions-geo.js`, and the desktop archetype layout.

**The app splash moved to `app-index.html`** (`<meta http-equiv="refresh">` → `app-user-type.html`). **Nothing links to it, deliberately** — it is the entry point for the installed app, not a page reachable from the site. A dead-link sweep will report it as orphaned; that is correct, **don't delete it.**

### What the split changes

- **The in-page back button is gone from the web path** (owner request, 2026-08-24, scoped explicitly to "كل صفحات web فقط" — browser arrows only). One global `.back-btn { display: none !important; }` at the end of `desktop.css`'s main block does it. Four narrower `.back-btn` rules from before it still sit earlier in the file; they are redundant but harmless, and were left alone deliberately. **The markup is still in the DOM on every page, and the app path still shows its button** — don't delete the markup.
- **The two paths never link to each other.** Verified zero cross-links in both directions, including links built inside JS strings (`'href="app-factory.html?id=' + i + '"'`) — those are easy to miss in a rename, and 11 such sites exist.
- **A change to a shared component is a multi-file edit.** The bottom nav lives in **10** files (home/account/factories/cart/messages × both paths); the desktop sidebar in **4** (`web-account`, `web-admin`, `web-profile`, `web-settings`) — and so does the `dash-myfactory` link *and its query*, in those same 4.
- **`desktop.css` only reaches `web-` pages.** A rule added there cannot affect the app path. `mobile.css`, `i18n.js`, `auth-guard.js`, `supabase-config.js` are shared by both.
- **Creating a new `app-` copy: deleting the `desktop.css` link is not enough.** The rule that *hides* desktop-only markup (`.dt-bar`, `.dt-catbar`, `.dt-actions`, `.page-logo`, `.dash-side`, `.dash-stats`) lives inside `desktop.css` itself — so dropping the link also drops the hiding, and that markup renders as black boxes. This shipped once on `app-home.html` and the owner caught it in a screenshot. Grep for those six class names first; if present, delete the markup **and its scripts**.
- Some `app-` pages still carry a body archetype class (`chat-page`, `store-page`) from before the split. They are inert — no `desktop.css` reads them.

### Unprefixed page names below

Sections after this one predate the split and say `home.html`, `account.html`, etc. **Read every such name as *both* copies** unless the point is specifically about the desktop layer, in which case it is the `web-` one. An unprefixed `home.html` means `index.html` on the web side and `app-home.html` on the app side.

**But check the page-list above first — not every name has two copies any more.** `register` and `welcome` exist only on the app path; `supplier`, `reset`, and `product` only on the web path. Newer sections write these prefixed in full; an unprefixed `register.html` in an older section means the app one, or the register *tab* on a web gate.

### The grep trap: banner comments name the shared assets

Every page carries an Arabic header comment naming its path and assets — so `grep -l 'desktop.css' *.html` matches **all 29 files**, and `grep -c 'auth-guard.js'` reports 1 on pages that only *mention* it. This produced two wrong conclusions in a single session: that app pages carried `desktop.css`, and that the welcome/register pages had a redirect loop. **Match the tag, not the name:** `<link[^>]*desktop\.css` / `<script[^>]*auth-guard\.js`.

## Running / testing

No dev server, build, lint, or test suite — no `package.json`, no `node`. "Running" means opening a file in a browser. The checks below are the closest thing to a test suite; run the relevant ones after every edit.

```bash
# open a page for the owner (plain Windows path — no query string, no file:/// URL)
powershell Start-Process "index.html"

# brace balance after editing any HTML/CSS — the two numbers must match
awk '{o+=gsub(/{/,"{"); c+=gsub(/}/,"}")} END{print o, c}' index.html

# .sql balance — strip comments first (Arabic "1)" numbering gives false positives)
sed 's/--.*$//' schema.sql | awk '{o+=gsub(/\(/,"("); c+=gsub(/\)/,")")} END{print o, c}'

# every link resolves? (prints nothing when clean)
grep -oh 'href="[a-z][a-z0-9._-]*\.html' *.html | sed 's/href="//' | sort -u \
  | while read f; do [ -f "$f" ] || echo "BROKEN: $f"; done

# path isolation — both must print nothing
grep -o 'href="app-[a-z-]*\.html' web-*.html | sort -u
grep -o 'href="web-[a-z-]*\.html' app-*.html | sort -u

# which pages actually query the database -- count the services too, and note
# index.html quotes it sb.from('products') with SINGLE quotes
for f in web-*.html index.html; do
  echo "$(grep -oc "sb\.from(\|sb\.rpc(\|SFCommerce\.\|SFMessages\.\|SFUpload\." "$f" || true) $f"
done

# which pages really load a shared asset (tag, not name — see the grep trap)
grep -c '<link[^>]*desktop\.css' index.html
grep -c '<script[^>]*auth-guard\.js' app-home.html

# an i18n key must exist in all 30 language blocks (anchor the pattern!)
grep -c '^      btn_update: ' i18n.js     # -> 30
```

The environment is Windows with **both PowerShell and Git Bash**. There is no `node` and no headless browser — **you cannot render the app yourself.**

**Two `grep` pitfalls that cost time here:**

- **`grep -c` exits non-zero when the count is zero**, so it silently aborts an `&&` chain — a batch of checks stops partway and looks like it passed. Append `|| true` in loops and chains.
- **Unanchored patterns match substrings.** `grep -c 'ilInput'` matched `emailInput`; use `-w` or anchor the pattern.

### Editing these files safely

**`python` is available (3.12.10) — but `python3` is not** (it hits the Windows Store stub). For precise multi-line replacements in these large UTF-8 Arabic files, a short Python script (read → `str.replace` with an `assert` → write with `encoding="utf-8"`) is far safer than `sed`/`perl`, both of which have mangled these files before.

Four traps, all hit in practice:

- **Always `assert s.count(old) == 1` before replacing.** A zero-match rewrites the file unchanged and looks like success; a two-match corrupts a second site you never inspected.
- **Arabic parentheses break Bash heredocs.** `(` and `)` in Arabic text cause `unexpected EOF while looking for matching`. Write the script with the Write tool, then execute it — or build the string with `chr(92)` where backslashes are involved.
- **Backslashes are escape sequences.** A Windows path in a normal literal raises `SyntaxError: truncated \UXXXXXXXX escape`. Use a **raw** literal (`r"..."`). Note `ur"..."` is Python-2 syntax and a hard `SyntaxError` in 3.12 — for a path that also needs Arabic, use `r"..."` alone and write Arabic as `\uXXXX` escapes.
- **Printing Arabic to stdout raises `UnicodeEncodeError`** — the Windows console is cp1252. Keep `print()` ASCII; never echo matched Arabic back.

`$TMPDIR` is unset in this Git Bash, so `"$TMPDIR/fix.py"` silently collapses to `/fix.py`. Assign the scratchpad's **full Windows path** to a shell variable in the same command.

### You cannot see the page — the owner must look

**Visual verification is the owner's job, and you must ask for it.** Open the page with `powershell Start-Process "index.html"`, then *ask what they see*. Never report a UI change as confirmed off a balance check — that check cannot see layout, z-index, animation, or runtime errors. Say plainly that you can't see the rendered page.

Several bugs passed review and were caught only by the owner looking: the `.auth-btn:active` fill-mode issue, the drawer escaping the phone column, `.composer` doing the same, missing account data.

### git, and no more `.bak` files

There **is** a git repository (branch `master`). The manual `.bak` convention is **retired**: the folder had grown to 68 backups against 15 live pages, and the owner twice opened a stale `.bak` believing it was the live page. All were deleted after archiving their pre-split states in commit `e0767a3`; `.gitignore` excludes `*bak`.

**Do not create `.bak` files — `git commit` before a bulk rewrite instead.** Unlike a `.bak`, a commit cannot be mistaken for a live page.

**The established habit is a checkpoint commit named for what is about to happen** — `نقطة حفظ قبل حذف زر الرجوع من صفحات web`, `نقطة حفظ قبل ربط صفحة المصانع بقاعدة البيانات`. Written in Arabic, before the risky edit, describing the *next* step rather than the last one — which is what makes "ارجع قبل اخر تعديل" ("revert to before the last edit") a one-command answer. **Expect that request; it is a normal part of how the owner works**, and it means the previous *visual* state, not necessarily the previous commit.

Two rules when the owner asks you to delete something:
- **"Don't delete backups" is guidance for Claude, not a constraint on the owner.** Confirm which file, then delete it. Explaining instead of acting got "لماذا لم تحذفه من الملفات؟؟؟؟".
- **`rm` via Bash is blocked by the permission classifier**; PowerShell `Remove-Item -Force -Confirm:$false` works. Bulk pipelines are refused — delete in explicit batches of ~10 named files.

### Database changes are applied by the owner, not by you

There is no `psql` and no Supabase CLI here. Edit `schema.sql` (or a focused one-off `.sql`), then tell the owner: Supabase → SQL Editor → New query → paste → Run. Everything in `schema.sql` is re-runnable, so a full re-paste is always safe.

## Architecture

Each page is a **fully self-contained** `<style>`/markup/`<script>` block in one `.html` file — page-specific styling is never extracted into a shared file. The shared assets are `i18n.js` and `mobile.css` (every page), `desktop.css` (the 14 `web-` pages), `regions-geo.js` (home pages only), and `supabase-config.js` / `auth-guard.js` (the subsets under *Backend*).

**There is not a single image file in this project** — every icon, flag, and logo is inline SVG, CSS, or generated glyphs. When the owner supplies a logo as a picture, the expected move is to rebuild it in markup, not save the file.

### Page flow

**The two paths now gate accounts differently — this is the biggest post-split divergence.**

- **App path:** `app-index.html` → `app-user-type.html` → `app-welcome.html` → `app-login`/`app-register` → `app-home`. The type chosen at the gate is written to `sf_account_type` and **branches the three pages after it**.
- **Web path:** no type gate at all. Two separate doors, each a tabbed login/register page that **hardcodes its own type**:
  - `web-login.html` — individuals. `var accountType = "individual"; var isFactory = false;`
  - `web-supplier.html` — factories. `var accountType = "factory"; var isFactory = true;`

  The type is **fixed in the page source, not read from `localStorage`**, because the web path never passes through a gate that would set it. Reading `sf_account_type` here would make every web signup an individual — which is exactly the bug the split fixed: before it, factories had no way to register on the web at all.

Each gate is one file with three IIFEs in order — tab controller, login, register. Login-side element IDs are prefixed `l-` so they don't collide with the register side's `f-`.

The rest: `home` (map + categories + bestsellers), `factories` (1000-card grid), `factory` (per-factory storefront, `?id=<n>`), `messages`, `cart`, `account` (hub), `settings` (everything the hub used to hold, incl. the language picker), `profile`, `help`, `admin` (factory approval, gated on `SF_PROFILE.is_admin`, not linked from any nav).

Per-page implementation details — save-on-input vs save-on-submit, the `isFactory` DOM branch, the date-field overlay, the bestsellers grid, the faked map border — are in **`قرارات-سابقة.md`**. Read the relevant section before touching any of them; several encode a fix that a "cleanup" would silently undo.

### Account types (`sf_account_type`)

Value is `"individual"` or `"factory"`; **absent/empty is treated as read-only**, so a visitor who never passed the gate cannot edit.

Both factory pages add `.view-only` to `<body>` when editing is off and **skip registering every edit listener**. The `.view-only` CSS is cosmetic; the absent listeners are the real enforcement.

**The two paths now decide `canEdit` differently — check which file you are in before reasoning about permissions.**

| | how `canEdit` is decided | trustworthy? |
|---|---|---|
| `web-factory.html` | `row.owner_id === SF_USER.id`, from the database | yes |
| `app-factory.html` | `row.owner_id === SF_USER.id`, from the database | yes |

**`sf_account_type` is not authentication** — it is a UI mode backed by a `localStorage` value any user can edit. It is no longer used for edit permission on either path: **as of 2026-08-24 `app-factory.html` carries the same database ownership check as the web page** (`sf_owner_<id>` in `sessionStorage`, two-way sync, one reload), so a factory-type account can no longer open the edit UI on someone else's factory. The app page still renders its *content* from `localStorage` — only the ownership decision comes from the server.

What actually holds on both paths is RLS: the server refuses a write to a factory the caller doesn't own, so the app-path hole exposes the *editing UI*, not the data.

**`web-factory.html`'s ownership check, and why it looks convoluted:**

```js
var OWNER_FLAG = "sf_owner_" + factoryId;   // sessionStorage, per-tab
var canEdit = false;                         // starts closed — fail safe
```

Edit listeners are registered at build time, so a change in ownership needs one reload. The `sessionStorage` flag exists **only to break the reload loop** — it is written *before* `location.reload()`, and the sync is two-way (`if (mine !== canEdit) { setOwnerFlag(mine); return null; }`) so a stale or forged flag is revoked on the next load rather than trusted. **It is not a permission** — forging it grants a visitor nothing but a UI that RLS then refuses.

The page renders from `localStorage` first and swaps in database rows when they arrive, because ownership isn't known until the network answers and the owner shouldn't stare at a blank page.

### Messaging — backed by the database since 2026-08-27

**This section used to say messaging was `localStorage`-only. That is no longer true**, and the stale claim misled a session. `messages-service.js` (`SFMessages`) reads and writes the `conversations` / `messages` tables, and `SFMessages.subscribe` opens a realtime subscription — the two sides of a conversation are now genuinely different browsers.

`web-messages.html` and `app-messages.html` no longer read or write `sf_messages`: both wait for `SFMessages.load()` and paint only server rows. Text and attachment sends also fail visibly when the service is unavailable instead of falling back to browser-only messages.

**Thread keys are the conversation's database id** (`String(row.id)`), not the old `factory-<n>` form. The msg-dock in `web-factory.html` now reads `SFMessages` and links with the database id. `openFromQuery()` still accepts a legacy `factory-<n>` link and converts it to a server conversation for old saved URLs.

### Mobile layer (`mobile.css`)

Loaded **after** each page's `<style>`, holds only cross-cutting device concerns — never page-specific styling.

- **The bottom nav's height (`52px`) is duplicated in ~13 places across 10 files** and they must all move together. Miss one and content hides behind the bar or floats above it. **Grep, don't recall.**
- **Safe-area insets**: `env(safe-area-inset-*)` paired with `viewport-fit=cover` in every viewport meta — without which `env()` always resolves to `0`.
- **`font-size: 16px !important` on all inputs**: iOS Safari force-zooms when a focused input's font is under 16px. The `!important` is required because pages define higher-specificity selectors. Don't "fix" this by lowering it.
- **Phone column on wide screens** (`@media (min-width: 520px)`): the app is portrait-only, so `body` is capped at 430px and centered. **Any new fixed element must be added to that cap list** — this has been missed twice (`.composer`, `.map-watermark`) and the owner caught both.
  - `margin: auto` only centers elements the cap can shrink. An element with `inset: 0` is stretched by its own offsets and ignores the margin — those need explicit `right`/`left: calc(50% - 215px)`.
- **The page frame** (`body::after`) draws a border inside every page; add `class="dark-page"` for dark backgrounds or the frame is invisible. **Its corners are square, deliberately** — see the archive before changing that; four attempts failed.

### Desktop layer (`desktop.css`)

**The whole file lives inside `@media (min-width: 0px)`**, with one closing `@media (max-width: 0px)` block that hides desktop-only elements. Nothing sits outside a media query, and that is the core invariant. **Never add a bare top-level rule here.**

**Those two breakpoints used to be `1024px` / `1023px`, and they were widened deliberately on 2026-08-24** — the owner asked for the phone layout to be gone from the web path entirely ("ما ابغا شكل جوال في صفحات web"), not just suppressed on large screens. `min-width: 0px` always matches, so the desktop layout now applies to `web-` pages at **every** width; `max-width: 0px` never matches, so the hide-block is inert.

**The empty media wrappers are load-bearing and must not be "cleaned up".** They look redundant, but deleting either one shifts every rule inside it out one nesting level and changes what it applies to. The comment at the top of the file says exactly this. If the owner ever wants a responsive web path again, the fix is to restore the two numbers — not to unwrap the blocks.

**A brace-balance check does not prove a rule landed in the right block.** A rule inserted between the two media blocks — after the first one's closing brace, before the second opens — balances perfectly and applies at **no** screen size at all. That happened here and cost a round. After inserting into this file, verify containment, not just balance:

```bash
# which media block does each new rule sit in?
python - <<'EOF'
import io, re
d = io.open("desktop.css", encoding="utf-8").read()
depth, stack = 0, []
for n, ln in enumerate(d.split("
"), 1):
    m = re.search(r'@media\s*\(([^)]*)\)', ln)
    if m: stack.append((depth, m.group(1).strip()))
    if ".your-new-class" in ln and "{" in ln:
        print(n, "->", stack[-1][1] if stack else "TOP LEVEL - BAD")
    depth += ln.count("{") - ln.count("}")
    while stack and depth <= stack[-1][0]: stack.pop()
EOF
```

Carried by the **14 `web-` pages and nothing else**.

- **Desktop-only markup is always in the DOM.** The closing block used to hide it below 1024px; with the breakpoint now at `0px` that block never matches, so the hide list is currently inert on the web path. **Keep adding new desktop-only elements to it anyway** — it is what makes restoring a responsive web path a two-number change.
- **Un-capping the phone column is the first thing the file does** — `body`'s `max-width`/`margin`/`box-shadow` are overridden with `!important` and `.bottom-nav` is hidden.
- **`body::after` is no longer killed here — it is re-enabled and recolored.** The web path draws a **green page frame** (owner request: "ضع حدود خضراء على كامل الصفحه") via `display: block !important; max-width: none !important; border-color: #1c6b34;`. **Thickness is inherited from `mobile.css` (3px) on purpose** — a `border-width: 1px !important` was added once and the owner asked for it back out ("ارجع قبل اخر التعديل"). Don't re-add a width override without being asked.
- **The animated wordmark (`.page-logo`) is on every web page**, sized `168px` / `19px` font, and joined to the `wmType`/`wmCaret` keyframe selectors *and* the `prefers-reduced-motion` block — miss the latter and the logo animates for users who asked it not to.
  - **Its width must be `min-width`, never `width`, and its `line-height` must clear the raised B2B.** A fixed `width` clipped the final **B** of "B2B"; the superscript is lifted by `vertical-align: 0.68em`, so a tight `line-height` cropped it from above. Fixed 2026-08-25 as `min-width: <n>; width: auto` plus `line-height: 1.55`–`1.6`.
  - **This lives in five places and a partial fix looks complete.** `desktop.css` alone carries **three**: `.top-bar-logo` (~line 89), the grid `.page-logo` (~758), and — the one missed on the first two attempts — the **non-grid** `.page-logo` for `store`/`cart`/`chat`/`doc`/classless bodies (~1115), which is more specific and silently overrode the earlier fix on six pages. The other two are `.auth-brandbar .wm-title` (duplicated in `web-login`, `web-supplier`, `web-reset`) and `index.html`'s own `108px` copy. **Grep `min-width: 168px` and `wm-title` before declaring this fixed.**
  - **It sits at the visual *left* in Arabic**, which is the opposite of the sidebar. Grid archetypes use `justify-self: end` under **both** `dir`s; non-grid archetypes (`store`/`cart`/`chat`/`doc`/classless) use `display: flex` with `margin-inline-start: auto; margin-inline-end: 24px`.
  - **`display: inline-flex` ignores `margin: auto`** — that single fact cost three failed attempts at this. It must be `display: flex`. Use the logical `margin-inline-*` properties, not `margin-left`/`right`: they flip with `dir` on their own, which is what keeps the logo mirroring correctly without a second `html[dir="ltr"]` rule.
- **`html` carries the page tint, not just `body`.** `html { background: #f6f7f6 }` matches the shared `body` background. It was `#ffffff`, producing a white band below `messages.html`, and the owner asked twice to remove it. **The first fix targeted the wrong thing** — it read as a layout gap, so height rules went onto `body.chat-page`; the answer was "لم تتغير". **Telling them apart: a layout gap moves the content when fixed; an `html` background leaves content exactly where it is and only the color changes.**

**Six page archetypes**, selected by a class on `<body>`:

| `<body>` class | Pages (all `web-`) | Desktop shape |
|---|---|---|
| `account-page` | `account`, `profile`, `settings`, `admin` | dashboard: `250px 1fr` |
| `cart-page` | `cart` | items + summary |
| `chat-page` | `messages` | thread list beside chat |
| `doc-page` | `help` | centered single column |
| `store-page` | `factory`, `product` | full-width cover, info column + product grid |
| `auth-page` | `login`, `supplier`, `reset` | centered 460px form, `.back-btn` hidden |

A new dashboard page needs the class, the `.page-logo` anchor, and a copy of the `.dash-side` markup — the sidebar is **duplicated per page**, not templated.

**Sidebar flyouts (`.dash-sub`) are RTL-critical.** The sidebar sits at the **right** edge in RTL, so panels open leftward via `right: 100%`, flipped to `left: 100%` under `html[dir="ltr"]`. Using `left: 100%` in RTL pushes the panel off-screen — that shipped once and the owner caught it.

Grid/column gotchas (explicit ids not `nth-of-type`, `minmax(0, 1fr)`, narrow column first, the `.content-wrap` cap, `padding-top: 0 !important`) and the whole categories-panel anchoring story are in **`قرارات-سابقة.md`** — read it before laying out a new archetype.

### RTL is the project's most repeated bug class

`i18n.js` flips `dir` for 26 of 30 languages, so a missing counterpart breaks the majority case. **When adding any horizontally-asymmetric layout, add the `html[dir="ltr"]` counterpart in the same edit.**

**But the inverse error is just as real.** Ask first whether the element is a **mirror** (a panel tracking its button, a bar following reading order) or a **fixed arrangement** (columns the owner chose visually, and the dividers and arrows attached to them). Mirroring the second kind shipped once and the owner caught it with an English screenshot.

Direction-relative CSS silently flips, and physical values don't:
- `border-inline-end` flips with `dir`; `border-right` does not.
- `transform-origin: left center` produced a **right**-side sweep under RTL; `0% center` is safe.
- `inset()` offsets don't respond to writing direction — which is why the logo animation uses `clip-path`, not a mask (see archive; the mask version failed repeatedly).
- Flexbox `order` under `row-reverse` is counter-intuitive: the **lowest** order sits visually **left**.

**After any horizontal-layout edit, ask the owner to check both languages, not just Arabic.**

### i18n (`i18n.js`)

Dependency-free IIFE loaded synchronously in `<head>` so `dir`/`lang` are set before body parse. The IIFE takes `window` as `global` and ends with `global.I18N = {...}` — **grepping for `window.I18N` finds nothing.** Exported surface: `getLang`, `setLang`, `t`, `regionName`, `categories`, `categoryName`, `applyTranslations`.

**`I18N.categories` is an array, not a function — six of the seven exports are callable and this one is not.** Writing `I18N.categories()` throws `TypeError: not a function`, and because these pages are one big IIFE, the throw **kills the rest of the page script**: every listener registered after that line silently never binds. This shipped, and the symptom was a dead "add product" button several hundred lines away — nothing pointed at i18n. Use `I18N.categories || []`.

**Read the generalisation, not just the fix: on a page whose script is one IIFE, "a button does nothing" usually means an exception earlier in the file, not a problem with the button.** Ask the owner for the F12 Console first — it names the real line in seconds. Guessing at CSS, z-index, or RTL cost a full session before the Console was consulted.

**The same failure has a second, more alarming signature: a `web-` page suddenly rendering as the phone layout.** The desktop shape depends on page JS running to completion, so one SyntaxError anywhere in the IIFE collapses the whole layout — and it looks like a CSS regression. This was self-inflicted once: a Python patch wrote `
` escapes as **literal newlines inside JS string literals**, producing an unterminated string. The owner's report was "لماذا ظهر واجهة التطبيق", and only their Console screenshot found it.

**So: when injecting JS through a Python patch, verify no string literal gained a real newline.** And when a web page "goes mobile", check the Console before touching `desktop.css` — the CSS is very likely innocent.

- **Declarative markup**: `data-i18n="key"` sets `textContent`; `data-i18n-placeholder="key"` sets the placeholder. Prefer these over setting text in page JS.
- **Fallback chain**: `dict[lang][key] → dict.en[key] → dict.ar[key] → key`.
- **RTL whitelist**: `RTL_LANGS = ["ar", "fa", "ur", "he"]`.
- **Language switching is always `I18N.setLang(code); window.location.reload();`** — a full reload, never live re-rendering.
- **30 languages × 191 keys** in `dict`; a parallel 30-entry picker array lives in the settings pages, not `i18n.js`. Adding a language means touching both. The picker held 90 entries until the 60 untranslated ones were deleted — **it must never list a code `dict` lacks**, or picking it falls back to English and looks broken.
- **Adding a key means adding it to all 30 blocks.** Verify with `grep -c "^      <key>: " i18n.js` = 30 — anchor the pattern, or substrings of longer key names match too.

Coverage tiers, the `awk` insertion technique, and the orphaned keys (which must **not** be cleaned up) are in the archive.

**Wire new UI to i18n immediately.** Hardcoding Arabic into new buttons produced a visibly mixed interface and the question "لماذا يوجد بالعربي والانقليزي". Check for an existing key first.

## The service layer — the exception to "no shared page-JS"

**Added 2026-08-27 in four merged PRs, and it contradicts a rule stated elsewhere in this file.**
Sections below still say *"this project has no shared page-JS file"* as the reason `.dash-side` and
the four-line factory-id query are duplicated per page. **That reason no longer holds** — four shared
JS files now exist. The duplication is still there, but treat it as history, not as a rule to uphold.

Each file is the same IIFE-over-`global` shape as `i18n.js` and `auth-guard.js`, and each opens with a
`ready()` guard that rejects (with an Arabic message) unless both `sb` and `SF_USER` exist.

| file | global | methods | loaded by |
|---|---|---|---|
| `commerce-service.js` | `SFCommerce` | `loadCart` `addToCart` `setQuantity` `removeItem` `createOrder` | `web-cart`, `app-cart`, `web-product` |
| `messages-service.js` | `SFMessages` | `load` `listFactories` `ensureFactoryConversation` `sendText` `sendAttachment` `subscribe` | `web-messages`, `app-messages`, `web-factory` |
| `media-upload.js` | `SFUpload` | `uploadFile` `uploadDataUrl` | `web-factory`, `app-factory`, `web-profile`, `app-profile` |
| `payment-provider.js` | `SFPayment` | `isEnabled` `start` | **no page loads it** |

**Script order gained a slot.** It is now `i18n` → CDN → `supabase-config` (defines `sb`) → *services*
→ `auth-guard`. Services must come after `supabase-config`; they read `SF_USER` lazily so they may sit
either side of `auth-guard`, and both orders are present in the tree.

**`grep 'sb.from('` is no longer a valid census of which pages touch the database.** `web-cart` and
`web-messages` report **zero** while being the most database-driven pages in the project — they go
through the services. Count `SFCommerce\.|SFMessages\.|SFUpload\.|sb\.rpc(` too, and note that
`index.html` quotes its call as `sb.from('products')` with single quotes, which a double-quoted grep
misses.

### Server-side RPCs — where the money logic lives

Four RPCs are called from the client: `get_or_create_cart`, `add_to_cart`, `create_order_from_cart`,
`save_factory_content`.

**`create_order_from_cart` accepts no amount from the client.** It computes
`sum(quantity * coalesce(custom_price, price))` inside PostgreSQL and takes the buyer from
`auth.uid()`. Price tampering is impossible *structurally*, not by a policy someone could forget.
It also rejects an empty cart, caps quantity at 100000, refuses to mix two factories in one order,
and de-duplicates via `idempotency_key`. **Never add a total/price parameter to this function.**

**`save_factory_content` truncates every value with `left(value, 2048)`.** That limit is sized for a
URL (~170 chars), not for base64 (tens of thousands) — a base64 image sent through it arrives as a
corrupt fragment that renders as a grey box. This shipped: images looked lost, but the Storage upload
had worked all along and the intact URL was sitting in `images[1]` while pages read the truncated
`image` column. **Send Storage URLs only; filter `u.indexOf("http") === 0` before saving, and prefer
`images[]` over `image` when reading.**

### Storage buckets

`factory-media` (covers, logos, product images, post video) and `chat-media` (message attachments).
A `post-media` string appears once. Paths are `<user-id>/<folder>/<uuid>.<ext>`; Storage policies do
the authorization, and an anonymous upload or delete is refused with `403`.

### Migrations live in `supabase/migrations/`

Three ordered files, all applied to the live database (verified 2026-08-28). **They are not
`schema.sql`-style re-runnable-in-any-order** — apply in filename order.

The ~20 loose `.sql` files still in the repo root are the older one-offs and check scripts described
further down; they are not part of the migration sequence.

Verifying what is actually applied, without `psql`: query the live REST API with the publishable key
(see *Auditing the backend yourself* below), or paste `check-migrations.sql` into the SQL Editor.

### Static validation (CI)

`.github/workflows/validate.yml` runs `scripts/validate-static.py` on push and PR to `master`. It
`node --check`s every inline `<script>` in every HTML file and checks dollar-quoting in the
migrations. **It cannot run locally — there is no `node` here** — but the SQL half can:

```bash
python -c "
from pathlib import Path
for f in sorted(Path('supabase/migrations').glob('*.sql')):
    t = f.read_text(encoding='utf-8')
    if t.count('\$fn\$') % 2: print(f.name, 'unbalanced dollar quotes')
"
```

Both files sat in the repo root at first, where GitHub never reads them and the declared
`scripts/validate-static.py` path did not exist — so the check silently never ran. Moved 2026-08-28.

### Auditing the backend yourself

The publishable key in `supabase-config.js` is enough to read the database over REST, so you can
verify data and attack RLS without waiting for the owner to paste anything:

```bash
KEY=$(grep -oE 'sb_publishable_[A-Za-z0-9_-]+' supabase-config.js | head -1)
curl -s "https://yhofxryhlrrwzztfowpa.supabase.co/rest/v1/products?select=id,name,price" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

**Test security by attacking, and always send `Prefer: return=representation`.** A blocked write
often answers `HTTP 200`/`204` — a success code — and only the returned `[]` proves zero rows were
touched. Reading the status alone would have scored a *failed* privilege-escalation attempt as a
breach. A full 13-attack pass is recorded in `SECURITY-AUDIT-2026-08-28.md`.

Writes and deletes are blocked by the permission classifier, and that is correct — hand the owner a
guarded `.sql` file instead. Keep `print()` output ASCII: this console is cp1252 and dies on Arabic.

## Backend (Supabase)

The app got a real backend partway through its life, so **the codebase is mid-migration**. Auth, factories, products, profiles, cart/orders, and messaging have server-backed paths; some pages still render a local recovery copy first. **Check the specific page and its shared service before assuming either state.**

Project `yhofxryhlrrwzztfowpa`. Loaded as plain script tags:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="supabase-config.js"></script>   <!-- defines the global `sb` -->
<script src="auth-guard.js"></script>        <!-- internal pages only -->
```

**Script order is load-bearing** and goes after `i18n.js`: the CDN must define `window.supabase` before `createClient` runs, and `sb` must exist before `auth-guard.js` calls `getSession()`.

- **`supabase-config.js`** — the key is the **publishable** key and is *meant* to be public; RLS is the protection, not key secrecy. The **secret** key and DB password must never enter any file here — there is no server-side code to use them from.
- **`schema.sql`** — five tables (`profiles`, `factories`, `products`, `conversations`, `messages`) plus two storage buckets, all re-runnable.
- **`add-industrial-license.sql`** — **applied.** Added `factories.industrial_license` to the owner's live database, which predated the column. Kept because `create table if not exists` in `schema.sql` will never add a column to an existing table — a rebuild from `schema.sql` alone is complete, but *this* database needed the `alter`.
- **`add-factory-profile.sql`** — **applied** (2026-08-24). Until it ran, `web-factory.html`'s 12-column `select` failed whole with `42703`, so the ownership check after it never ran and the owner silently got a read-only page. **A missing column anywhere in a select list disables every feature that select feeds.**
- **`add-media-columns.sql`** — **applied** (2026-08-24; verified: `products.images` and `posts.video` both answer instead of `42703`).
- **`fix-privileges.sql`** — **applied.** The section-8.5 guard triggers, as a standalone file. See *RLS is the real enforcement* below.
- **`make-admin.sql`** / **`check-admin.sql`** — grant and verify `is_admin`. `make-admin.sql` disables `profiles_guard` inside one transaction, because the guard silently reverts `is_admin` for anyone not already an admin — so editing the checkbox in Table Editor appears to work and does nothing. **Applied**; `khald507868@gmail.com` is admin.
- **`cleanup-test-data.sql`** — deletes `%@example.com` accounts left from attack-testing, and resets any stray `approved` / `is_admin` rows.
- **`add-posts-prices.sql`** — a **second applied migration**, not merged. Adds `posts` and `custom_prices` plus a `custom_price_id` column on `messages`. Already run and verified by attack. **Both tables are schema-only — no page reads them.** "Re-run `schema.sql`" does **not** restore them; a rebuild needs both files.
- **One-off operational scripts from 2026-08-24**, all Arabic-commented with click-by-click steps for the owner: `approve-my-factory.sql` (approve the owner's factory), `check-guard.sql` (is `factories_guard` still enabled?), `check-admin-now.sql` (is this account really an admin?), `fix-my-factory.sql`, `cleanup-test-account.sql` (removes the `sec.test.factory@gmail.com` security-test account). **`cleanup-test-account.sql` has not been run yet** — that account's "Test Attacker" factory still appears in the factories list.
- **Any script that writes a guarded column must disable the trigger inside a transaction.** `approve-my-factory.sql` and `make-admin.sql` both do this, and the reason is subtle: guards call `is_admin()`, which reads `auth.uid()` — and **in the SQL Editor there is no logged-in user, so `auth.uid()` is null and `is_admin()` returns false.** The guard then silently reverts the write and the editor reports success with no rows changed. **A plain `update ... set status='approved'` in the SQL Editor does nothing at all.** Always re-enable the trigger in the same transaction.
- **Only the *last* statement's result is shown** in the Supabase SQL Editor — which is why the check scripts here contain exactly one `select`. Adding a second hides the first.
- Postgres functions are dollar-quoted with **`$fn$`**, not bare `$$`, which collides with shell expansion.

### Which pages carry which scripts

Identical across both paths — verified by counting `<script>` tags, not name mentions.

| | supabase-js + config | auth-guard | `SF_PUBLIC_PAGE` |
|---|---|---|---|
| `app-index`, `app-welcome`, `app-user-type`, `*-help` | — | — | — |
| `*-login`, `app-register`, `web-supplier`, `web-reset` | ✓ | — | — |
| `index`, `app-home`, `*-factories`, `*-factory`, `web-product` | ✓ | ✓ | ✓ |
| `*-account`, `*-settings`, `*-cart`, `*-messages`, `*-profile`, `*-admin` | ✓ | ✓ | — |

Verified by counting `<script>` tags — 14 web pages, 15 app pages.

Adding the guard to a gate page would create a redirect loop, and the guard's *destination* is `app-welcome.html` on the app path and `web-login.html` on the web path. `web-reset.html` is guard-free for the same reason: it must open for someone who cannot sign in. Those pages' banner comments mention `auth-guard.js` — they do not load it.

### Public browsing (`SF_PUBLIC_PAGE`) and `sfRequireLogin()`

Modeled on Alibaba at the owner's request: someone arriving from a search engine must **see the storefront without an account**, and be asked to register only when they act.

A page opts in by declaring the flag **before** `auth-guard.js` loads:

```html
<script>var SF_PUBLIC_PAGE = true;</script>
<script src="auth-guard.js"></script>
```

The guard then skips the redirect when there's no session, but **still reads the session if one exists** — so the page knows whether the visitor is signed in (`SF_USER`).

`sfRequireLogin(nextPage)` is the other half: returns `true` when signed in, otherwise sends the visitor to the register page. **It is now wired** — `web-product.html` calls it on both the add-to-cart button and the message buttons. The rest of the flow is gated a second way, at the service layer: every `SFCommerce` / `SFMessages` / `SFUpload` method starts with a `ready()` guard that rejects without `SF_USER`, so an ungated button fails with an Arabic message rather than a silent no-op.

### Password reset (`web-reset.html`) — web path only

One page with **two modes, chosen by the URL**, reached from "نسيت كلمة المرور؟" on both web gates:

1. **No hash** → email field → `sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname })`.
2. **Arriving from the email link** → Supabase drops a recovery session and fires `PASSWORD_RECOVERY` via `sb.auth.onAuthStateChange` → password + confirm fields → `sb.auth.updateUser({ password })`.

Mode 2 also has a fallback check on `location.hash.indexOf("type=recovery")`, because the hash can be consumed before the listener registers. **Keep both** — the listener alone is racy.

**The success message is identical whether or not the account exists.** That is deliberate: a different message would let anyone enumerate which emails are registered. Don't "improve" it into a helpful "no such account".

**Not yet testable.** It needs the redirect URL registered at Supabase → Authentication → URL Configuration → Redirect URLs, which requires a real domain — the project currently runs from `file:///`. **Outstanding owner task.** No `app-` equivalent exists yet.

### The landing page (`index.html`) — category bar, sector filter, watermark

Three mechanisms added 2026-08-25. Each spans more than one file, which is what makes them easy to half-break.

**The sector filter is a three-file contract, and it was broken in three places at once.** A category link carries `?cat=<English category name>`; `web-factories.html` reads it and applies `.eq("industry", wantedCat)`. The value must be **`cat.en`**, never the category object — `I18N.categories` holds `{ar, en}` pairs, so passing the object to `encodeURIComponent` yields the string `[object Object]` and matches nothing. **There are three link-building sites in `index.html`**; a fix to one is not a fix.

The English name is the join key because that is what the factory page stores in `industry`. **A factory whose `industry` is empty appears under no sector at all** — that is data, not a bug; `check-industry.sql` reports it.

When a filter is active the page retitles its `<h1>` and must `removeAttribute("data-i18n")` first, or `applyTranslations()` overwrites the new title on the next language pass. The empty state uses class **`grid-state`** (what `showState()` builds), not `state`.

**The category bar scrolls an inner wrapper, not the bar.** All 40 categories render; `.dt-catscroll` holds only the links and carries the `overflow-x`. **Putting `overflow` on `.dt-catbar-inner` clips the ☰ dropdown panel**, which escapes those bounds — the CSS says so at the rule. Edge arrows are `.dt-catnav`, shown on hover via `.dt-catbar-inner:hover .dt-catnav.is-active`.

Its RTL handling is a **mirror** — the "more" arrow follows reading order, so it sits left in Arabic and right in English. `scrollLeft` **is negative in RTL** in modern browsers, so position is measured with `Math.abs()` and the step direction is signed off `dir`. Hover-scroll runs 4px every 20ms and sets `scrollBehavior = "auto"` for the duration, restoring `""` on mouseleave: with `smooth` left on, each tiny step starts its own overlapping transition and the motion stutters. The click-jump keeps `smooth`.

**The watermark map (`.map-watermark`) is sized by height, not width.** The Saudi map SVG is taller than it is wide, so constraining width alone pushes its top and bottom outside the page frame — `height: 74vh; width: auto; max-width: 88%`. It is `position: fixed; inset: 0; z-index: 0; pointer-events: none`, with `.content` lifted to `z-index: 1`. Its 13 `deco-region` paths are copied verbatim from `app-user-type.html`. Per the `mobile.css` phone-column rule, **a fixed element with `inset: 0` ignores `margin: auto`** — this one is already in the cap list; don't add another without it.

### The factory page is modelled on LinkedIn (`web-factory.html`)

Built to the owner's reference screenshots of a LinkedIn company page. Two mechanisms carry the design and both are easy to undo by accident.

**Tabs switch content; they do not scroll to it.** An early version scrolled and the owner rejected it. Four tabs — الرئيسية / المنشورات / نبذة / المنتجات — driven by a class on `<body>`:

```js
var TAB_CLASSES = ["tab-posts", "tab-about", "tab-products"];
// "home" adds NO class — that is what makes about + posts show together
if (name !== "home") document.body.classList.add("tab-" + name);
```

**الرئيسية is the absence of a class, not a `tab-home` class.** The CSS hides the cards each *other* tab excludes, so with no class nothing is hidden and the home tab shows نبذة and المنشورات together — which is exactly what the owner asked for ("الرئيسية ابغا يكون فيها النبذه والمنشورات و تظهر معاً"). Adding a `tab-home` class to "tidy this up" would break that pairing.

**The cover uses a fixed `height`, never `aspect-ratio`.** It was `aspect-ratio: 16/9`, then `3/1`, and the owner still said "لاتزال كبيره" — because a ratio grows with the container, and `body.store-page` was 1500px wide. The fix was fixed heights (134px phone / 172px desktop) **plus** narrowing the body. Per the archive rule, "still too big" meant the wrong property, not too small a number.

**Page width is 970px, matching LinkedIn's main column — not its 1128px page.** LinkedIn splits 1128px into a ~970px column plus a right sidebar; this page has no sidebar, so filling 1128px read as wider than the reference. One value in `desktop.css`.

**The message dock (`.msg-dock`) is fixed bottom-right**, collapsing via an `is-open` class and a `max-height` transition. It loads `SFMessages` from Supabase and links to `web-messages.html?open=<conversationId>`, handled at the top of `openFromQuery()`. It has an `html[dir="ltr"]` counterpart in both `web-factory.html` and `desktop.css` — it is a **mirror**, so keep both.

An inline message button used to sit in the right-hand column; the owner had it removed as intrusive ("انها مزعجه"). Don't reintroduce one.

### Product detail and the chat draft handoff

`web-product.html?factory=<n>&p=<index>` reads `sf_factories` from `localStorage`. Reached from bestseller cards on `index.html` and product cards on `web-factory.html` — both previously opened the whole storefront, which the owner reported as wrong.

Its three buttons all lead to chat, passing a prefilled message:

```js
"web-messages.html?factory=" + encodeURIComponent(factoryId) + "&draft=" + encodeURIComponent(draft)
```

`web-messages.html` reads `?draft=` inside `openFromQuery()` and drops it into the composer, resizing the textarea. **Badge values must match the home cards exactly** — `years = (idNum % 17) + 1`, `reorder = (idNum % 61) + 12` — or the card and the page it opens disagree.

### Session guard (`auth-guard.js`)

Same IIFE-over-`global` shape as `i18n.js`. Exports `SF_AUTH_READY` (a promise), `SF_USER`, `SF_PROFILE`, `sfSignOut`.

- **Path-aware.** `LOGIN_PAGE` is gone; `currentPage()` / `isWebPath()` / `loginPage()` / `registerPage()` pick the destination from the current filename, used in three places (session expiry, `sfRequireLogin()`, sign-out). **`isWebPath()` special-cases `index.html` and `""`** — without that, the unprefixed landing page would fall into the "not `web-`" branch and send a desktop visitor whose session expired to `app-welcome.html`, i.e. the phone layout in a wide window.
- It reads `account_type` **from `profiles`**, then writes it back to `sf_account_type` — a compatibility shim for un-migrated pages, not the source of truth.
- **A network failure does not sign the user out** — the `.catch` returns `null` rather than redirecting.
- **This is a UX guard, not data protection.** Disabling JavaScript opens the page — but it renders empty, because RLS refuses the data. Don't present the guard as the security boundary.
- Pages must await `SF_AUTH_READY`; `SF_USER` is `null` at parse time.
- The profile `select` list is explicit. **A page needing another column must add it here**, or `SF_PROFILE` won't have the field.

### RLS is the real enforcement — `with check` alone is not enough

`with check (id = auth.uid())` validates **who** is editing, **not what**. Two privilege-escalation holes were live in an earlier schema, written by a previous session, reviewed as correct, and found only by attacking the running API:

- a factory `PATCH`ing `{"status":"approved"}` onto its own row → self-approval, making the review workflow decorative
- any user `PATCH`ing `{"is_admin":true}` onto their own profile → full admin

The fix is section **8.5**: `BEFORE UPDATE` trigger guards that silently revert protected columns unless `is_admin()`. **Any new column a user must not set for themselves needs a line in the relevant guard — a policy alone will not do it.**

**Security claims must be tested by attack, not by reading the policy.** When you add or change an RLS policy, run the attack it is supposed to stop and show the result. Details, trigger names (they differ from the function names), and the first-admin recipe are in the archive.

### The admin approve button, and the `approve` / `approved` trap

`web-admin.html` and `app-admin.html` build their buttons with
`data-act="approve"` and pass that value straight through to
`setStatus()`. But `factories.status` is constrained to
`pending` / `approved` / `rejected` — so the click sent **`approve`**
and Postgres answered
`violates check constraint "factories_status_check"`.

**Approval was broken for every factory, not just one**, and it looked
like a permissions problem: the owner was a verified admin
(`is_admin = true`) and `factories_guard` was enabled, so both of the
obvious suspects checked out clean. The alert box naming the constraint
is what identified it.

Fixed at the single call site in each file
(`act === "approve" ? "approved" : act`) rather than in the button
markup — one guard covers every button, present and future. The reject
path was never affected: it calls `setStatus(id, "rejected")` with the
literal.

**The general lesson: a silent or misattributed failure here is usually
a value the database rejects, not a permission.** Read the error text
before theorising about RLS — three sessions' worth of guesses
(missing row, not an admin, guard disabled) were all wrong, and the
alert settled it in one line.

### Signup flow

The register tab (`web-login.html` / `web-supplier.html` / `app-register.html`) → `sb.auth.signUp()` with all initial profile/factory fields in user metadata. The `after insert on auth.users` trigger `handle_new_user` creates the complete `profiles` row — **plus**, for factories, a `factories` row at `status = 'pending'`. The canonical definition lives in `schema.sql`; `fix-signup-email-confirmation.sql` is the focused migration for the existing hosted database.

**Email confirmation changes the client flow:** with confirmation enabled, a successful `signUp()` returns a user but no session. Therefore the register pages must **never** update `profiles` or `factories` after signup; RLS would reject those writes because `auth.uid()` is null. They show the email-confirmation message and wait for the user to sign in. If confirmation is disabled in a development environment and a session is returned, the trigger has still created the rows and the page may redirect normally.

So a factory account **always** has a factory row from the moment it exists, invisible to the public until an admin approves it. `account_type` cannot be changed afterward (the guard reverts it) — a mistake at signup means a new account.

### Current state / deliberate gaps

- **Email confirmation is now ENABLED**, and **`Allow anonymous sign-ins` must stay OFF.** Anonymous sign-ins were switched on by accident once; they hand every visitor the `authenticated` role, which opens every RLS policy written for signed-in users. If a policy suddenly looks too permissive, check that toggle before rewriting the policy.
- **Supabase's built-in email sender is rate-limited** (a few messages per hour) — fine for testing, not for launch. A real sender (Resend or similar) is an outstanding item.
- **Every `web-` page now reads real data — the fake-data generators are gone.** Verified
  2026-08-28: no `for (i=1; i<=1000)` factory generator survives anywhere. Remember the census
  caveat from the service-layer section — `grep 'sb.from('` under-reports badly.

  | page | data source |
  |---|---|
  | `index` | `products` + `factories` (`LIMIT = 24`) |
  | `web-factories` | `factories` — RLS filters, so **don't add `eq("status","approved")`**; it would hide the owner's own pending factory from them |
  | `web-factory` | `factories`/`products`/`posts` + `save_factory_content` + `SFUpload` |
  | `web-product` | `products` — paints from `localStorage` first, then `applyLiveProduct(row)` swaps in the server row |
  | `web-cart` | `SFCommerce` end to end: load, quantity, remove, order |
  | `web-messages` | `SFMessages` with a realtime subscription |
  | `web-account`, `web-settings`, `web-admin` | `factories` |
  | `web-profile` | `profiles` + `factories` + `SFUpload` |
  | `web-help`, `web-reset` | none — deliberate; `web-reset` must open for someone who cannot sign in |

  **The app path lags behind.** `app-cart` and `app-messages` do load the services, but the rest of
  the app path is still mostly `localStorage`. `app-factory` renders its content from
  `localStorage`; its database call reads `owner_id` for the ownership check only.

  **The three dashboard pages' single call is the same 4-line query, duplicated.** `web-account`,
  `web-settings`, and `web-profile` each read `factories.id` by `owner_id` for one reason only: to
  build the "مصنعي" sidebar link, whose href needs a factory id the client cannot know.
  `web-admin` carries a fourth copy. **Changing that link means a four-file edit**, and in
  `web-admin.html` the copy must stay **above** the `is_admin` gate that returns early, or it never
  runs for a non-admin factory owner. (This was once justified by "no shared page-JS file" — see the
  service-layer section; that justification has expired, the duplication has not.)

- **The cart writes optimistically and reconciles from the server.** `−`/`+` repaint the row and the
  total immediately, then a 400ms debounce sends one `setQuantity` for a burst of clicks. If the
  write is refused, the page alerts and re-renders from `loadCart()` — the server stays the source of
  truth. Pending writes are flushed before `createOrder` and on `beforeunload`, so an order is never
  built on a quantity the server has not seen. **Delete is not debounced** — it is irreversible, so it
  fires immediately and dims the row.

  `web-product.html` deliberately does **not** redirect to the cart after adding (the owner asked to
  keep shopping); it shows a bottom bar whose count comes from `loadCart()`, not a local counter.

- **`web-factory.html` saves through a debounce, and products/posts are delete-then-insert.** `save()` writes `localStorage` immediately (so nothing is lost offline), then queues `pushToDb()` after 700ms; `beforeunload` flushes anything pending. Products and posts are replaced wholesale rather than diffed — fine at five products, and the reason a save is one round-trip per table, not per row.
- **`web-product.html` renders from `localStorage`, and deliberately never refuses.** An earlier version bailed out with a "product not found" message when `sf_factories` held no entry for the requested index; that contradicted the card the user had just clicked. The page now always renders, showing what exists and hiding what doesn't, with the title falling back product name → factory name → `مصنع <n>`. **Don't reintroduce the guard.** (The `product_not_found` i18n key is now unused but stays — see the archive on not mass-deleting keys.)

  The original reason was that `web-home.html` fabricated bestseller cards for all 1000 factory slots, so most pointed at empty ones. **That generator is gone** — `index.html` now reads up to `LIMIT = 24` real rows from `products`, filtered by RLS. The guard still shouldn't come back: the page is public and reachable by direct URL.
- `region_id` is never written at signup (no region field), so the map cannot find a region's factories.
- **Images now upload to Storage** via `SFUpload`; `localStorage` base64 remains only as the first paint on some pages. Legacy rows may still hold a base64 `image` truncated at 2048 chars — see `save_factory_content` above; read `images[]` and prefer the `http` entry.
- `posts` has a UI in `web-factory` (the المنشورات tab); `custom_prices` is still schema-only, though `create_order_from_cart` already honours it when pricing an order — private-price-in-chat is the remaining UI work.
- **Online payment is deferred by explicit owner decision (2026-08-28).** Orders run on manual payment: the buyer submits, the factory contacts them. `payment-provider.js` is a neutral boundary that refuses every attempt and holds no keys — that is the design, not a gap. **Don't re-litigate it, and don't add gateway keys to any file here**; there is no server-side code to use them from. Payment-brand logos belong with the gateway too — three attempts at hand-drawing mada / Apple Pay / stc pay in SVG all shipped visibly broken and were reverted; the gateway supplies licensed assets on contract.
- **Commercial-register verification is deferred by explicit owner decision.** It cannot be done client-side; the agreed plan is manual review of `pending` factories. **Don't re-litigate this.**

## Working with the owner

Learned over many sessions; it will save you rework.

- **The owner is not a programmer, and asks to be taught** ("علمني ايش فعلنا"). Terms like "backend", "RLS", "email confirmation" need defining the first time. For dashboard tasks give literal click-by-click steps — "Supabase → Authentication → Providers → Email → Confirm email → Save" — not a description of the goal. **"مافهمت" means slow down and define, not repeat.**
- **Requests arrive in Arabic, short and visual** ("اجعلها أعرض", "ليست جميلة"). They describe an *outcome*, not an implementation. Styling asks often arrive as successive nudges in one direction — **make the single change asked for and stop.**
- **A one-word follow-up continues the previous request.** "زياده" after "ارفعها قليلاً" means *more of that same nudge*, not a fresh instruction.
- **"لا لا" / "انت لم تفهم" means the goal was misread, not that the code is buggy.** Re-read the original wording literally before editing again.
- **"لاتزال موجودة" means your fix targeted the wrong element, not that it was too weak.** Don't repeat the same change harder — find what *actually* paints the pixels. Twice it was a second rule the element carried; once it was `body`'s background rather than any panel.
- **An ambiguous Arabic verb is worth one question.** "ابعدها" can mean *move it away* or *get rid of it*. Two rounds went into spacing, each answered "لاتزال موجوده", before one question with concrete options got "نعم شيله" — remove it.
- **Screenshots are marked up.** A red line is a target measurement, not decoration — read the drawing before editing.
- **If a screenshot looks identical after your edit, suspect browser caching first.** Grep to confirm the edit landed, say so, and suggest Ctrl+F5 — don't pile on a larger change.
- **Open the page in the browser after every change, without being asked.** A standing instruction ("افتحلي دايم الصفحه بعد اي تغيير اطلبه"). Remind them to press **Ctrl + F5** — a plain reload serves cached CSS and makes a landed edit look like it failed.
- **Do exactly what was asked and nothing adjacent.** "حط الشعار حقي" was answered with a whole top bar — search box, icons, the lot — which rendered broken. The reply was **"ماذا فعلت"** then **"اعدها انت خربتها قلتلك ضيف الشعار على اليسار فقط"**, and the page had to be restored. Add the logo; stop.
- **When a request would change a shared component, say which pages it touches before editing.** The bottom nav lives in 10 files; "change the text to green" on one page may or may not mean all ten. This is the ambiguity most worth one targeted question.
- **Never run a blanket `sed` across a shared CSS file.** One meant for a single dashboard rule silently rewrote `.bestsellers-section` and `.cart-page .checkout-bar`. Prefer an anchored Python replacement with an `assert`, and grep afterward.
- **`Start-Process` chokes on a query string**, and on percent-encoded `file:///` URLs too — this folder's name is Arabic, so it usually is encoded. Use the plain Windows path with no query string.
- **Do not ask for, and do not accept, the `service_role` / `sb_secret_` key or the database password.** The publishable key is the only credential that belongs here. If offered a secret one, decline and explain why.
- When a request is genuinely ambiguous, ask **one** targeted question with concrete options rather than guessing broadly.

## Conventions

- Default document is `<html lang="ar" dir="rtl">`; see *RTL* above for the counterpart rule.
- Arabic text in SVG renders with **system fonts** — no embedded webfont, so letterforms shift between platforms. Don't tune SVG text positioning to pixel precision against one machine.
- Bottom nav has 6 items, each with a `data-i18n` label; keep new pages in sync.
- **Flag emoji are generated at runtime** from ISO codes via regional-indicator math (`String.fromCodePoint(127397 + c.charCodeAt(0))`) — reuse this rather than adding flag images.
- **Bottom-sheet modal pattern** (language picker, country picker, cart protection detail): overlay + `.open` class, `translateY(100%→0)`, close via Escape/backdrop/×, `body.style.overflow` locked while open. Picker variants add a filtering search input. Reuse this rather than introducing another modal style.
- Password fields use a show/hide eye toggle swapping the input `type` and the SVG's inner path — not a library.
- **Image uploads must downscale.** A hidden `<input type="file">` triggered by a styled placeholder, then `FileReader.readAsDataURL`, then a `<canvas>` resize before storage. `factory.html` uses `resizeImage(dataUrl, maxSize, done)` with per-use caps (640 cover, 180 logo, 400 product); the register tabs and profile carry local copies. **This was a live bug**: the register form once stored the raw result, so a phone photo blew the ~5MB quota and — because its `setItem` catch is empty — silently lost the **whole** `sf_account` record. The empty catch is still there; downscaling is what keeps it from being hit.
- **localStorage keys**: `sf_lang`, `sf_account_type`, `sf_account`, `sf_factories`, `sf_messages`, and legacy `sf_factory_images`. **The ~5MB quota is the real ceiling** — a few dozen photos, not 1000 factories' worth, and chat attachments compete for the same budget. Any "make this hold real data" request needs a backend or IndexedDB, not more localStorage.
- **`profile.html` mirrors the register tab's `isFactory` branch** and both write the identical `sf_account` shape — anything added to one form must be added to the other, including the save payload. But **their save triggers deliberately differ** (see archive).
