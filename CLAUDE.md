# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Two companion files, and you should know when to open them:**
> **`قرارات-سابقة.md`** — the *why* behind rules that look arbitrary: exact
> measurements, failed approaches, and decisions already litigated with the
> owner. Sections below say "see the archive" where it matters; read that
> section **before** editing the thing it describes.
> **`الصفحات.md`** — the page map, written in Arabic for the owner. Keep it in
> sync when pages are added or renamed.

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

- **App path only:** `index.html` (splash), `app-user-type.html` (account-type gate), `app-welcome.html`, `app-register.html`.
- **Web path only:** `web-supplier.html` (factory gate), `web-reset.html` (password reset), `web-product.html` (product detail).
- **Deleted from the web path:** `web-register.html` and `web-welcome.html`. Registration merged into `web-login.html` as a tab; the welcome page was removed as useless ("مامنها فائدة"). **Don't recreate them** — `auth-guard.js` now points the web path at `web-login.html` and `web-login.html#register`.

**`index.html` is the one exception with no prefix.** It holds the *app* splash and redirects to `app-user-type.html`. The name is reserved — servers serve it automatically at a bare domain, so renaming it would break the site's root URL. **Do not rename it.**

### What the split changes

- **The two paths never link to each other.** Verified zero cross-links in both directions, including links built inside JS strings (`'href="app-factory.html?id=' + i + '"'`) — those are easy to miss in a rename, and 11 such sites exist.
- **A change to a shared component is a two-file edit.** The bottom nav lives in **10** files (home/account/factories/cart/messages × both paths); the desktop sidebar in **4** (`web-account`, `web-admin`, `web-profile`, `web-settings`).
- **`desktop.css` only reaches `web-` pages.** A rule added there cannot affect the app path. `mobile.css`, `i18n.js`, `auth-guard.js`, `supabase-config.js` are shared by both.
- **Creating a new `app-` copy: deleting the `desktop.css` link is not enough.** The rule that *hides* desktop-only markup (`.dt-bar`, `.dt-catbar`, `.dt-actions`, `.page-logo`, `.dash-side`, `.dash-stats`) lives inside `desktop.css` itself — so dropping the link also drops the hiding, and that markup renders as black boxes. This shipped once on `app-home.html` and the owner caught it in a screenshot. Grep for those six class names first; if present, delete the markup **and its scripts**.
- Some `app-` pages still carry a body archetype class (`chat-page`, `store-page`) from before the split. They are inert — no `desktop.css` reads them.

### Unprefixed page names below

Sections after this one predate the split and say `home.html`, `account.html`, etc. **Read every such name as *both* copies** unless the point is specifically about the desktop layer, in which case it is the `web-` one. `index.html` always means the literal file.

**But check the page-list above first — not every name has two copies any more.** `register` and `welcome` exist only on the app path; `supplier`, `reset`, and `product` only on the web path. Newer sections write these prefixed in full; an unprefixed `register.html` in an older section means the app one, or the register *tab* on a web gate.

### The grep trap: banner comments name the shared assets

Every page carries an Arabic header comment naming its path and assets — so `grep -l 'desktop.css' *.html` matches **all 29 files**, and `grep -c 'auth-guard.js'` reports 1 on pages that only *mention* it. This produced two wrong conclusions in a single session: that app pages carried `desktop.css`, and that the welcome/register pages had a redirect loop. **Match the tag, not the name:** `<link[^>]*desktop\.css` / `<script[^>]*auth-guard\.js`.

## Running / testing

No dev server, build, lint, or test suite — no `package.json`, no `node`. "Running" means opening a file in a browser. The checks below are the closest thing to a test suite; run the relevant ones after every edit.

```bash
# open a page for the owner (plain Windows path — no query string, no file:/// URL)
powershell Start-Process "web-home.html"

# brace balance after editing any HTML/CSS — the two numbers must match
awk '{o+=gsub(/{/,"{"); c+=gsub(/}/,"}")} END{print o, c}' web-home.html

# .sql balance — strip comments first (Arabic "1)" numbering gives false positives)
sed 's/--.*$//' schema.sql | awk '{o+=gsub(/\(/,"("); c+=gsub(/\)/,")")} END{print o, c}'

# every link resolves? (prints nothing when clean)
grep -oh 'href="[a-z][a-z0-9._-]*\.html' *.html | sed 's/href="//' | sort -u \
  | while read f; do [ -f "$f" ] || echo "BROKEN: $f"; done

# path isolation — both must print nothing
grep -o 'href="app-[a-z-]*\.html' web-*.html | sort -u
grep -o 'href="web-[a-z-]*\.html' app-*.html index.html | sort -u

# which pages actually query the database (prose mentions don't count)
for f in web-*.html; do echo "$(grep -oc 'sb\.from(' "$f" || true) $f"; done

# which pages really load a shared asset (tag, not name — see the grep trap)
grep -c '<link[^>]*desktop\.css' web-home.html
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

**Visual verification is the owner's job, and you must ask for it.** Open the page with `powershell Start-Process "web-home.html"`, then *ask what they see*. Never report a UI change as confirmed off a balance check — that check cannot see layout, z-index, animation, or runtime errors. Say plainly that you can't see the rendered page.

Several bugs passed review and were caught only by the owner looking: the `.auth-btn:active` fill-mode issue, the drawer escaping the phone column, `.composer` doing the same, missing account data.

### git, and no more `.bak` files

There **is** a git repository (branch `master`). The manual `.bak` convention is **retired**: the folder had grown to 68 backups against 15 live pages, and the owner twice opened a stale `.bak` believing it was the live page. All were deleted after archiving their pre-split states in commit `e0767a3`; `.gitignore` excludes `*bak`.

**Do not create `.bak` files — `git commit` before a bulk rewrite instead.** Unlike a `.bak`, a commit cannot be mistaken for a live page.

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

- **App path:** `index.html` → `app-user-type.html` → `app-welcome.html` → `app-login`/`app-register` → `app-home`. The type chosen at the gate is written to `sf_account_type` and **branches the three pages after it**.
- **Web path:** no type gate at all. Two separate doors, each a tabbed login/register page that **hardcodes its own type**:
  - `web-login.html` — individuals. `var accountType = "individual"; var isFactory = false;`
  - `web-supplier.html` — factories. `var accountType = "factory"; var isFactory = true;`

  The type is **fixed in the page source, not read from `localStorage`**, because the web path never passes through a gate that would set it. Reading `sf_account_type` here would make every web signup an individual — which is exactly the bug the split fixed: before it, factories had no way to register on the web at all.

Each gate is one file with three IIFEs in order — tab controller, login, register. Login-side element IDs are prefixed `l-` so they don't collide with the register side's `f-`.

The rest: `home` (map + categories + bestsellers), `factories` (1000-card grid), `factory` (per-factory storefront, `?id=<n>`), `messages`, `cart`, `account` (hub), `settings` (everything the hub used to hold, incl. the 90-language picker), `profile`, `help`, `admin` (factory approval, gated on `SF_PROFILE.is_admin`, not linked from any nav).

Per-page implementation details — save-on-input vs save-on-submit, the `isFactory` DOM branch, the date-field overlay, the bestsellers grid, the faked map border — are in **`قرارات-سابقة.md`**. Read the relevant section before touching any of them; several encode a fix that a "cleanup" would silently undo.

### Account types (`sf_account_type`)

Value is `"individual"` or `"factory"`; **absent/empty is treated as read-only**, so a visitor who never passed the gate cannot edit.

`factory.html` computes `canEdit = accountType === "factory"` and, when false, adds `.view-only` to `<body>` and **skips registering every edit listener**. The `.view-only` CSS is cosmetic; the absent listeners are the real enforcement.

**`sf_account_type` is not authentication** — it is a UI mode backed by a `localStorage` value any user can edit, and `factory.html` still trusts it. There is no link between a factory account and a specific factory `id`, so a factory-type account can edit *any* factory page. The database has the fix (`factories.owner_id` + an RLS policy), but the page hasn't been migrated. **Until it is, don't describe these pages as access-controlled.**

### Messaging

Stored entirely in `localStorage` under `sf_messages`. **Not migrated to the backend** — `conversations` and `messages` tables exist but nothing reads or writes them, so both sides of a conversation are the same browser. Don't describe it as real-time or as delivering anything to a factory; say it's local-only.

### Mobile layer (`mobile.css`)

Loaded **after** each page's `<style>`, holds only cross-cutting device concerns — never page-specific styling.

- **The bottom nav's height (`52px`) is duplicated in ~13 places across 10 files** and they must all move together. Miss one and content hides behind the bar or floats above it. **Grep, don't recall.**
- **Safe-area insets**: `env(safe-area-inset-*)` paired with `viewport-fit=cover` in every viewport meta — without which `env()` always resolves to `0`.
- **`font-size: 16px !important` on all inputs**: iOS Safari force-zooms when a focused input's font is under 16px. The `!important` is required because pages define higher-specificity selectors. Don't "fix" this by lowering it.
- **Phone column on wide screens** (`@media (min-width: 520px)`): the app is portrait-only, so `body` is capped at 430px and centered. **Any new fixed element must be added to that cap list** — this has been missed twice (`.composer`, `.map-watermark`) and the owner caught both.
  - `margin: auto` only centers elements the cap can shrink. An element with `inset: 0` is stretched by its own offsets and ignores the margin — those need explicit `right`/`left: calc(50% - 215px)`.
- **The page frame** (`body::after`) draws a border inside every page; add `class="dark-page"` for dark backgrounds or the frame is invisible. **Its corners are square, deliberately** — see the archive before changing that; four attempts failed.

### Desktop layer (`desktop.css`)

**The whole file lives inside `@media (min-width: 1024px)`**, with one closing `@media (max-width: 1023px)` block that hides desktop-only elements. Nothing sits outside a media query, and that is the core invariant: below 1024px the phone design is untouched. **Never add a bare top-level rule here.**

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

- **Desktop-only markup is always in the DOM**, hidden below 1024px by that closing block. Adding a desktop-only element means **adding it to the hide list too**.
- **Un-capping the phone column is the first thing the file does** — `body`'s `max-width`/`margin`/`box-shadow` are overridden with `!important`, `body::after` is killed, and `.bottom-nav` hidden.
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

- **Declarative markup**: `data-i18n="key"` sets `textContent`; `data-i18n-placeholder="key"` sets the placeholder. Prefer these over setting text in page JS.
- **Fallback chain**: `dict[lang][key] → dict.en[key] → dict.ar[key] → key`.
- **RTL whitelist**: `RTL_LANGS = ["ar", "fa", "ur", "he"]`.
- **Language switching is always `I18N.setLang(code); window.location.reload();`** — a full reload, never live re-rendering.
- **30 languages × 191 keys** in `dict`; the 90-entry picker lives in the settings pages, not `i18n.js`. Adding a language means touching both.
- **Adding a key means adding it to all 30 blocks.** Verify with `grep -c "^      <key>: " i18n.js` = 30 — anchor the pattern, or substrings of longer key names match too.

Coverage tiers, the `awk` insertion technique, and the orphaned keys (which must **not** be cleaned up) are in the archive.

**Wire new UI to i18n immediately.** Hardcoding Arabic into new buttons produced a visibly mixed interface and the question "لماذا يوجد بالعربي والانقليزي". Check for an existing key first.

## Backend (Supabase)

The app got a real backend partway through its life, so **the codebase is mid-migration**: auth is on the server, everything else runs on `localStorage`. **Assume any page is *not* wired to the database unless you've checked.**

Project `yhofxryhlrrwzztfowpa`. Loaded as plain script tags:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="supabase-config.js"></script>   <!-- defines the global `sb` -->
<script src="auth-guard.js"></script>        <!-- internal pages only -->
```

**Script order is load-bearing** and goes after `i18n.js`: the CDN must define `window.supabase` before `createClient` runs, and `sb` must exist before `auth-guard.js` calls `getSession()`.

- **`supabase-config.js`** — the key is the **publishable** key and is *meant* to be public; RLS is the protection, not key secrecy. The **secret** key and DB password must never enter any file here — there is no server-side code to use them from.
- **`schema.sql`** — five tables (`profiles`, `factories`, `products`, `conversations`, `messages`) plus two storage buckets, all re-runnable.
- **`add-industrial-license.sql`** — a migration the owner **has not run yet**. `schema.sql` already declares `factories.industrial_license`, so a *fresh* rebuild is complete — but the owner's **live database predates the column**, and `create table if not exists` will never add it. Until they run this file, factory registration on `web-supplier.html` fails: the page sends a column the server doesn't have. **Re-flag this before touching factory signup.**
- **`add-posts-prices.sql`** — a **second applied migration**, not merged. Adds `posts` and `custom_prices` plus a `custom_price_id` column on `messages`. Already run and verified by attack. **Both tables are schema-only — no page reads them.** "Re-run `schema.sql`" does **not** restore them; a rebuild needs both files.
- Postgres functions are dollar-quoted with **`$fn$`**, not bare `$$`, which collides with shell expansion.

### Which pages carry which scripts

Identical across both paths — verified by counting `<script>` tags, not name mentions.

| | supabase-js + config | auth-guard | `SF_PUBLIC_PAGE` |
|---|---|---|---|
| `index`, `app-welcome`, `app-user-type`, `*-help` | — | — | — |
| `*-login`, `app-register`, `web-supplier`, `web-reset` | ✓ | — | — |
| `*-home`, `*-factories`, `*-factory`, `web-product` | ✓ | ✓ | ✓ |
| `*-account`, `*-settings`, `*-cart`, `*-messages`, `*-profile`, `*-admin` | ✓ | ✓ | — |

Verified by counting `<script>` tags — 14 web pages, 15 app pages, as of commit `02f33a4`.

Adding the guard to a gate page would create a redirect loop, and the guard's *destination* is `app-welcome.html` on the app path and `web-login.html` on the web path. `web-reset.html` is guard-free for the same reason: it must open for someone who cannot sign in. Those pages' banner comments mention `auth-guard.js` — they do not load it.

### Public browsing (`SF_PUBLIC_PAGE`) and `sfRequireLogin()`

Modeled on Alibaba at the owner's request: someone arriving from a search engine must **see the storefront without an account**, and be asked to register only when they act.

A page opts in by declaring the flag **before** `auth-guard.js` loads:

```html
<script>var SF_PUBLIC_PAGE = true;</script>
<script src="auth-guard.js"></script>
```

The guard then skips the redirect when there's no session, but **still reads the session if one exists** — so the page knows whether the visitor is signed in (`SF_USER`).

`sfRequireLogin(nextPage)` is the other half: returns `true` when signed in, otherwise sends the visitor to the register page. **It is defined but not yet called anywhere** — buy/cart/message buttons don't gate. Wiring them is the unfinished half of the owner's Alibaba flow.

### Password reset (`web-reset.html`) — web path only

One page with **two modes, chosen by the URL**, reached from "نسيت كلمة المرور؟" on both web gates:

1. **No hash** → email field → `sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname })`.
2. **Arriving from the email link** → Supabase drops a recovery session and fires `PASSWORD_RECOVERY` via `sb.auth.onAuthStateChange` → password + confirm fields → `sb.auth.updateUser({ password })`.

Mode 2 also has a fallback check on `location.hash.indexOf("type=recovery")`, because the hash can be consumed before the listener registers. **Keep both** — the listener alone is racy.

**The success message is identical whether or not the account exists.** That is deliberate: a different message would let anyone enumerate which emails are registered. Don't "improve" it into a helpful "no such account".

**Not yet testable.** It needs the redirect URL registered at Supabase → Authentication → URL Configuration → Redirect URLs, which requires a real domain — the project currently runs from `file:///`. **Outstanding owner task.** No `app-` equivalent exists yet.

### Product detail and the chat draft handoff

`web-product.html?factory=<n>&p=<index>` reads `sf_factories` from `localStorage`. Reached from bestseller cards on `web-home.html` and product cards on `web-factory.html` — both previously opened the whole storefront, which the owner reported as wrong.

Its three buttons all lead to chat, passing a prefilled message:

```js
"web-messages.html?factory=" + encodeURIComponent(factoryId) + "&draft=" + encodeURIComponent(draft)
```

`web-messages.html` reads `?draft=` inside `openFromQuery()` and drops it into the composer, resizing the textarea. **Badge values must match the home cards exactly** — `years = (idNum % 17) + 1`, `reorder = (idNum % 61) + 12` — or the card and the page it opens disagree.

### Session guard (`auth-guard.js`)

Same IIFE-over-`global` shape as `i18n.js`. Exports `SF_AUTH_READY` (a promise), `SF_USER`, `SF_PROFILE`, `sfSignOut`.

- **Path-aware.** `LOGIN_PAGE` is gone; `currentPage()` / `isWebPath()` / `loginPage()` / `registerPage()` pick the destination from the current filename, used in three places (session expiry, `sfRequireLogin()`, sign-out). `index.html` has no prefix so it falls into the "not web-" branch — the app path, which is correct.
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

### Signup flow

The register tab (`web-login.html` / `web-supplier.html` / `app-register.html`) → `sb.auth.signUp()` with `account_type` and `full_name` in user metadata. An `after insert on auth.users` trigger creates the `profiles` row — **plus**, for factories, a `factories` row at `status = 'pending'`. The page then `update`s both; it never `insert`s them.

So a factory account **always** has a factory row from the moment it exists, invisible to the public until an admin approves it. `account_type` cannot be changed afterward (the guard reverts it) — a mistake at signup means a new account.

### Current state / deliberate gaps

- **Email confirmation is DISABLED** in the dashboard — a dev convenience, and the first mandatory item in `TODO-BEFORE-LAUNCH.md`. Anyone can register with an address they don't own.
- **The UI is almost entirely un-wired from the database.** Counting `sb.from(` per page: only `*-admin` (2 calls) and the gate pages `web-login` / `web-supplier` (3 each) touch Supabase. Home, account, settings, factories, factory, cart, messages, profile, product make **zero** on both paths. The factory grids, product cards, and bestsellers are generated placeholders. **Don't describe any of them as showing real data.**
- **`web-product.html` renders from `localStorage`, and deliberately never refuses.** An earlier version bailed out with a "product not found" message when `sf_factories` held no entry for the requested index. That contradicted the card the user had just clicked: `web-home.html` generates bestseller cards for **all 1000 factory slots** regardless of stored data, so most cards point at empty slots. The page now always renders, showing what exists and hiding what doesn't, with the title falling back product name → factory name → `مصنع <n>`. **Don't reintroduce the guard.** (The `product_not_found` i18n key is now unused but stays — see the archive on not mass-deleting keys.)
- `region_id` is never written at signup (no region field), so the map cannot find a region's factories.
- Images are base64 in `localStorage`; the storage buckets exist but nothing writes to them.
- `posts` and `custom_prices` are schema-only — the factory feed and private-price-in-chat are the next UI work.
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
