# Openote — Style Guide & Design System

> **Document status:** v0.4 · **Implementation phase** · Last updated 2026-08-05
> **Reality check (2026-08-05):** colour tokens (§3) are implemented verbatim in
> `app/lib/theme/onote_theme.dart`; **fonts are bundled** (§4.1 met — Inter +
> JetBrains Mono, 2026-08-04); tags (§7) shipped, including OneNote import; the
> command bar (§7), navigator (§7b, rewritten this revision to match the
> 2026-08-04 two-column redesign), study panel and planner all exist. What is
> **not** yet real is the connective tissue: there is no token layer between
> this document and the widgets, no component themes behind the Material
> defaults, and one specified pairing fails its own AA rule (§3.3 note). The
> [v0.6 UI revamp plan](planning/v0.6-ui-revamp.md) is the audit of that gap
> and the plan to close it; the **operative values** it fixed are folded into
> this revision (§4.2a, §5.2, §3.7, §6, §7c) and marked *operative* — they are
> what new code must use.
> **Purpose:** The single source of truth for how Openote looks, feels, and speaks — brand, color, type, spacing, components, canvas interaction, motion, accessibility, and voice. Written so a designer or developer can build a consistent, professional product from it.
> **Related:** [Product Vision](00-product-vision.md) · [PRD](02-product-requirements.md) · [v0.6 UI revamp](planning/v0.6-ui-revamp.md)

---

## 1. Design philosophy

Openote is a tool for thinking. The interface should feel like good stationery: calm, precise, and quietly excellent — never loud, never in the way. Five principles govern every decision.

**1. The page is the hero.** Everything that is not the user's content is chrome, and chrome recedes. Toolbars are quiet, panels collapse, and the canvas gets the light. If a pixel isn't the user's note, it earns its place or disappears.

**2. Calm over clutter.** OneNote's cluttered ribbon is a stated user complaint; we do the opposite. Progressive disclosure — show the few things needed now, keep power a click away. White space is a feature.

**3. Interpret, don't interrupt.** Formatting appears where you make it. No modal preview panes, no jarring mode switches for everyday writing. The tool responds; it does not demand.

**4. Native in spirit, consistent in soul.** We honor each platform's conventions (menus, shortcuts, dialogs) while keeping one recognizable Openote character across all of them. Consistent, not uniform.

**5. Accessible by default.** Contrast, keyboard paths, screen-reader labels, reduced motion, and legible type are requirements, not settings we hope people find. Good accessibility is good design for everyone.

---

## 2. Brand

### 2.1 The idea: ink on an open page

The brand concept is **ink** — the fountain-pen line, the mathematician's margin note, the handwritten diagram — set on an **open page**. It ties together the three things that make Openote distinctive (handwriting, math, freeform canvas) and the one thing that defines it (openness). Two visual motifs recur: the **ink stroke** (a confident, slightly tapered line) and the **open corner** (a page corner lifting, suggesting both "a page" and "open").

### 2.2 Name & wordmark

- **Name:** *Openote* — always one word, capital O, lowercase rest. Not "OpeNote," "Open Note," or "openote" in body text (lowercase acceptable in code/URLs/handles).
- **Wordmark:** the name set in the brand display weight, with the leading **"O" doubling as an open page corner or an ink dot** (design exploration — the "O" is the logo's home). The wordmark reads confidently at small sizes; it must remain legible at 16 px height.
- **App icon:** a single ink stroke forming an "O" / open-page corner on the brand Ink field, with a warm nib-brass highlight. Must work as a small favicon and a large tablet icon; test on light *and* dark OS backgrounds.
- **Clear space:** keep at least the height of the "O" clear on all sides.
- **Don'ts:** don't stretch, recolor outside the palette, add drop shadows/gradients not defined here, or place the wordmark on low-contrast backgrounds.

### 2.3 Tagline options

Primary: **"Your notes. Your format. Every platform."**
Alternates: *"The open notebook."* · *"OneNote's freedom, without the lock-in."* · *"Ink, math, and ideas — openly yours."*

### 2.4 Brand personality

Openote is the **knowledgeable, unpretentious craftsperson**: competent, calm, a little opinionated about openness, generous with control. Not a hype startup, not a corporate suite. Think "well-made open-source tool by people who care," expressed with quiet confidence.

---

## 3. Color system

Color is built around two brand hues — **Ink** (deep indigo, the primary) and **Brass** (warm amber, the accent, evoking a pen nib) — on a family of warm-neutral "paper" grays. The palette is chosen to be distinct from OneNote's magenta-purple while staying in the considered, ink-on-paper world.

> All pairings below are designed to meet **WCAG 2.1 AA** (≥4.5:1 for body text, ≥3:1 for large text and UI boundaries). Hex values are the design tokens; verify final contrast in implementation (see §3.5).

### 3.1 Brand — Ink (primary)

| Token | Hex | Use |
|-------|-----|-----|
| `ink-50` | `#EEF0FF` | tinted backgrounds, hover fills (light) |
| `ink-100` | `#DFE2FF` | selected row fills, subtle emphasis |
| `ink-200` | `#C2C7FB` | borders on tinted surfaces |
| `ink-300` | `#9AA0F5` | disabled primary, decorative |
| `ink-400` | `#7B7FEE` | interactive hover (dark mode accents) |
| `ink-500` | `#5B5BE6` | **primary — default interactive** |
| `ink-600` | `#4A45D6` | primary pressed / hover (light) |
| `ink-700` | `#3D38B4` | primary text on light, focus |
| `ink-800` | `#302B8C` | headings on light (brand), dark surfaces |
| `ink-900` | `#20205C` | deepest brand, dark-mode canvas ink |

**Primary interactive = `ink-500`** on light; `ink-400` on dark (for contrast against dark surfaces). Primary button text is white (`#FFFFFF`) — verify AA on `ink-500`/`ink-600`.

### 3.2 Brand — Brass (accent)

Used sparingly — highlights, the pen/ink tool active state, small celebratory moments, and the nib accent in the logo. Never the dominant color.

| Token | Hex | Use |
|-------|-----|-----|
| `brass-100` | `#FBEFD3` | accent tint background |
| `brass-300` | `#F4CE7C` | decorative, highlight fills |
| `brass-400` | `#EBB24A` | **accent — default** |
| `brass-500` | `#D9971F` | accent pressed / text-on-light |
| `brass-700` | `#9A6A12` | accent text meeting AA on light |

> Accessibility note: amber on white rarely meets 4.5:1 — use `brass-700` for accent *text*, and reserve `brass-400` for fills, indicators, and iconography with sufficient area/contrast.

### 3.3 Neutrals — Paper & Graphite

Warm-tinted neutrals so surfaces read as "paper," not clinical gray.

| Token | Hex (light) | Role |
|-------|-------------|------|
| `paper-0` | `#FFFFFF` | canvas / primary surface (light) |
| `paper-50` | `#FAF9F7` | app background |
| `paper-100` | `#F2F1ED` | sidebar / secondary surface |
| `paper-200` | `#E7E5DF` | dividers, borders |
| `paper-300` | `#D6D3CA` | strong borders, disabled |
| `graphite-400` | `#9A968C` | **disabled & decorative ONLY** — see note |
| `graphite-500` | `#6E6B63` | secondary & tertiary text, placeholders |
| `graphite-700` | `#403D38` | body text (light) |
| `graphite-900` | `#211F1B` | headings / max-contrast text (light) |

> **Correction (2026-08-05).** Earlier revisions assigned `graphite-400` the
> role "tertiary text" — but it measures **2.80:1 on `paper-50`** (2.95:1 on
> white), failing AA for text at any size, so this document contradicted its
> own §9. The role moves to `graphite-500` (5.06:1 ✓); `graphite-400` is
> reserved for disabled states and decorative strokes, where 3:1 does not
> apply. The app currently uses `graphite-400` as its default metadata colour
> in ~130 places — migrating them is v0.6 stage 3. Dark mode was already
> compliant (`moon-400` on `night-50` = 4.97:1).

### 3.4 Dark theme ("Night ink")

Not pure black — a deep warm charcoal so ink and brass glow without harshness. OLED-friendly but not clinical.

| Token | Hex (dark) | Role |
|-------|------------|------|
| `night-0` | `#17161C` | canvas / primary surface (dark) |
| `night-50` | `#1E1D24` | app background |
| `night-100` | `#26252E` | sidebar / secondary surface |
| `night-200` | `#33313C` | dividers, borders |
| `night-300` | `#45424F` | strong borders |
| `moon-400` | `#8E8A99` | tertiary text |
| `moon-300` | `#B8B4C2` | secondary text |
| `moon-100` | `#E6E3EC` | body text (dark) |
| `moon-0` | `#F6F4FA` | headings / max-contrast (dark) |

Dark-mode interactive uses `ink-400`; dark-mode accent uses `brass-400`. Both are tuned to sit above 3:1 against `night-0`/`night-100`.

### 3.5 Semantic colors

| Meaning | Light | Dark | Use |
|---------|-------|------|-----|
| Success | `#2E8B57` | `#5FCB8A` | saved, synced, confirmations |
| Warning | `#C67A12` | `#F0B03E` | reversible caution (distinct from brass accent by context/icon) |
| Danger | `#C63838` | `#F07373` | destructive actions, errors |
| Info | `#2F6FB3` | `#6FB0EA` | neutral information, tips |
| Sync-live | `ink-500` | `ink-400` | active sync / collaboration presence |

> Implementation note (2026-08-05): `danger` and `success` exist in
> `OnoteColors`; `warning` and `info` are specified here but not yet defined in
> code — add them to `tokens.dart` when first needed rather than inventing
> near-misses inline.

> Never rely on color alone (§9). Pair every semantic color with an icon and/or text.

### 3.6 Content ink palette (for the user's pen & highlighter)

A default set of pen colors offered to users — chosen to be legible on paper *and* night surfaces, and colorblind-considerate. Users can pick any color; these are the curated defaults: Ink Black `#211F1B`, Ink Blue `#2F6FB3`, Ink Red `#C63838`, Forest `#2E8B57`, Violet `#6A4BC0`, Brass `#D9971F`, and Highlighter tints (yellow `#F7E27A`, green `#B6E39A`, pink `#F3B0C6`, blue `#A8CCF0`) at ~40% opacity.

### 3.7 Surface roles *(operative, added 2026-08-05 — the region → token map)*

The tokens above say what colours exist; this says **which region wears
which**, in both modes, so no widget ever decides for itself. The 2026-08 UI
review found this mapping being improvised per widget — 16 files branch on
`Brightness.dark` by hand, and in dark mode the planner picked the *canvas*
colour so panel and page merged into one black.

| Role | Light | Dark | Regions |
|---|---|---|---|
| `canvas` | `paper-0` | `night-0` | the page itself — **nothing else** |
| `chrome` | `paper-50` | `night-50` | command bar, status bar, side panels |
| `chrome-2` | `paper-100` | `night-100` | navigator sections column, wells, insets, code-block tints |
| `raised` | `paper-0` | `night-100` | menus, popovers, dialogs — always with elevation (§5.3) |
| `border` | `paper-200` | `night-200` | every hairline; regions do not draw private borders on top of shell dividers |

Rules: **widgets name a role, never check the brightness** (the roles live in
a `ThemeExtension`, v0.6 stage 1); the canvas is the only `canvas` surface, so
in dark mode the page reads as the deepest layer and chrome sits visibly above
it — "the page is the hero" holds at night too; adjacent regions of the same
role share one border, drawn by the shell, not one each.

**Interaction tints (operative).** State overlays are the *named* alphas of the
role's foreground colour — `hover .05` · `selected .10` · `selected-strong .14`
· `drag .18` · `border-on-tint .35` — replacing the twelve ad-hoc opacity
values counted in the 2026-08 review. Clicks never ripple (§7 Buttons).

---

## 4. Typography

### 4.1 Typefaces

| Role | Typeface | Rationale |
|------|----------|-----------|
| **UI** | **Inter** (or the platform system UI font as fallback) | Neutral, highly legible, excellent at small sizes, open-source (OFL). |
| **Editor body (default)** | Inter / system serif option offered | Users can choose; a clean sans is the default for on-screen notes. |
| **Reading serif (option)** | **Source Serif / Literata** | For users who prefer a book-like note; open licenses. |
| **Monospace / code** | **JetBrains Mono** or **Fira Code** | Clear code, distinguishable glyphs (0/O, 1/l/I), ligatures optional; open. |
| **Math** | **KaTeX / STIX Two Math** fonts | Proper math glyph coverage; matches the LaTeX rendering pipeline. |
| **Brand display** | A geometric display cut for the wordmark only | Distinct brand voice; not used in UI body. |

All chosen faces are **open-licensed** — consistent with the project's ethos and avoiding redistribution friction.

> **Implementation status (2026-08-05): met.** Inter (4 weights + italics) and
> JetBrains Mono are bundled (`pubspec.yaml` `fonts:`, style rows in
> LICENSING.md) and `onoteTheme` sets `fontFamily: 'Inter'` — the app looks
> the same on every OS. The `onoteFontFallback` chain sits *behind* the
> bundled faces and resolves the math/symbol glyphs Inter lacks; its order is
> load-bearing (see the comment in `onote_theme.dart`). Still open: the
> reading-serif option (Source Serif) is not offered yet.

### 4.2 Type scale (UI)

A modular scale (~1.20 ratio), in px at base 14 for dense desktop UI; the editor uses a comfier base 16.

| Token | Size / Line | Weight | Use |
|-------|-------------|--------|-----|
| `display` | 32 / 40 | 600 | brand moments, empty states |
| `h1` | 24 / 32 | 600 | page/section titles |
| `h2` | 20 / 28 | 600 | sub-sections |
| `h3` | 17 / 24 | 600 | group labels |
| `body-lg` | 16 / 24 | 400 | editor default |
| `body` | 14 / 20 | 400 | UI default |
| `label` | 13 / 16 | 500 | buttons, field labels |
| `caption` | 12 / 16 | 400 | metadata, hints |
| `mono` | 13.5 / 20 | 400 | code |

**Rules:** one to two weights per view (400 + 600). Avoid all-caps except tiny labels with tracking. Line length in the editor targets 60–80 characters for the linear-reading fallback (the freeform canvas is exempt). Never justify body text.

### 4.2a The operative UI ramp *(added 2026-08-05 — what chrome code actually uses)*

§4.2 is the aspirational scale and remains right for the editor and for large
surfaces. The app's *chrome*, however, grew *seventeen* distinct font sizes —
including half-pixel one-offs (10.5, 11.5, 12.5) — with the mass sitting
1–3px below the scale above. The revamp replaces all of them with this ramp,
**integer px only**, dense enough for a desktop tool and rhythmical enough to
read as one system:

| Token | Size / line | Weight | Use |
|---|---|---|---|
| `ui-title` | 15 / 20 | 600 | dialog & sheet titles |
| `ui` | 13 / 18 | 400 | default chrome text — rows, menus, inputs, buttons |
| `ui-strong` | 13 / 18 | 600 | emphasis inside `ui` (row titles, counts) |
| `ui-sm` | 12 / 16 | 400 | secondary text, subtitles, tooltips |
| `caption` | 11 / 14 | 400 | metadata, hints, badges, the status bar |
| `overline` | 11 / 14 | 700, +0.5 tracking, caps | panel titles and list-group labels — the **only** all-caps style |

Sizes 9–10.5 are retired (badge counts move to `caption`); anything larger
than `ui-title` in chrome should be questioning why it isn't the editor scale.
These land as `TextTheme` + named constants in `tokens.dart` (v0.6 stage 1);
after stage 3, a bare `fontSize:` literal in `lib/ui` is a review flag.

### 4.3 In-editor Markdown rendering

Rendered Markdown maps to the editor scale: `# `→`h1`, `## `→`h2`, etc.; inline code and code blocks use `mono` with a subtle tinted background (`paper-100`/`night-100`); block quotes get a `ink-300` left border and `graphite-500` text; links use `ink-600`/`ink-400` with underline-on-hover. When the caret enters a span, its Markdown markers reveal in `graphite-400` (dimmed) — visible but quiet.

---

## 5. Spacing, layout & shape

### 5.1 Spacing scale (4-pt base)

`0, 2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64`. Use tokens (`space-2` = 8px, etc.); avoid arbitrary values. Default control padding: 8×12. Default panel padding: 16. Section rhythm: 24.

### 5.2 Radius *(revised 2026-08-05 — operative set)*

| Token | Value | Use |
|-------|-------|-----|
| `radius-sm` | 4px | inputs, checkboxes, small chips |
| `radius-md` | 6px | buttons, menu items, toggles, small controls |
| `radius-lg` | 8px | menus, popovers, cards, banners |
| `radius-xl` | 12px | dialogs, large floating surfaces, canvas text boxes |
| `radius-full` | 999px | avatars, pills |

> Revision note: the earlier set (4/8/12/16) never made it into code — the app
> shipped **thirteen** ad-hoc radii from 1.5 to 14. The operative set is one
> step tighter than the original because the app's realised character is denser
> than v0.1 imagined; 16px is retired (it reads consumer-mobile at this
> density). Stock Material 3 must never show through: un-themed M3 dialogs are
> 28px and M3 buttons are full stadiums, both of which the component themes
> (v0.6 stage 2) override.

Text containers on the canvas use `radius-xl` with a near-invisible border until hovered/selected — echoing OneNote's containers but calmer.

### 5.3 Elevation

Prefer **borders and subtle tints over heavy shadows** (flat, paper-like). Three levels only:

- `elevation-0` — flush, border-only (`paper-200`/`night-200`).
- `elevation-1` — popovers/menus: `0 2px 8px rgba(20,18,30,.08)` (light) / `0 2px 8px rgba(0,0,0,.4)` (dark) + 1px border.
- `elevation-2` — modals/dialogs: `0 8px 32px rgba(20,18,30,.16)` + 1px border.

### 5.4 App layout (desktop)

```
┌───────┬───────────────────────────────────────────────┬────────┐
│       │  Toolbar (contextual, quiet)                    │        │
│  Nav  ├───────────────────────────────────────────────┤ Optional│
│ side  │                                                │ panel  │
│ bar   │            THE CANVAS (the hero)               │(back-  │
│(note- │                                                │ links, │
│ books,│         infinite, pan/zoom, blocks             │ search,│
│ sect- │                                                │ props) │
│ ions, │                                                │        │
│ pages)│                                                │        │
└───────┴───────────────────────────────────────────────┴────────┘
```

- **Left navigator** collapses to icons or hides entirely (focus mode).
- **Toolbar** is contextual — it shows tools for the current selection/tool, not a fixed ribbon.
- **Right panel** is optional and on-demand (backlinks, search, page properties).
- **Tablet:** navigator becomes a slide-over; the pen toolbar can dock to a screen edge and be repositioned. **Phone (later):** single-column, canvas-first, gestures over chrome.

---

## 6. Iconography *(revised 2026-08-05)*

- **Current reality:** the app uses the **Material outline set** throughout —
  and that stays for v0.6. A swap to a Lucide/Feather-class set (1.75px stroke,
  rounded joins, closer to the ink line) remains the recorded aspiration, but
  it is a *content* change the token layer will make cheap later; changing
  1,000 glyph references mid-revamp would be churn without system gain.
- **Operative sizes: 16 / 18 / 20** — 16 default (rows, panel headers,
  inline), 18 command bar, 20 rail and empty states. The eleven ad-hoc sizes
  in use (12–20) migrate to these three; a bare `size:` on an `Icon` in
  `lib/ui` is a review flag after v0.6 stage 3. Filled variants only for
  active/selected toggle states.
- **Tool icons** get an active-state accent (`brass-400` fill or `ink-500` background) so the current tool is unmistakable.
- Always pair icon-only buttons with a tooltip and an accessible label.

---

## 7. Components

Baseline patterns; a component library/tokens file is a next-pass deliverable.

**Buttons** — Primary (`ink-500` fill, white text), Secondary (border + `graphite-700` text), Ghost (text only, tinted hover), Danger (uses danger semantic). Height 28 (compact) / 32 (default), `radius-md`, `ui` label — **never the Material stadium shape**. Clear hover/pressed/focus/disabled states; visible focus ring (`ink-400`, 2px, offset 2px). Clicks respond with hover/pressed *tints* (the §3.7 named alphas), not the mobile ink ripple — `NoSplash` app-wide.

**Inputs** — 1px `paper-300`/`night-300` border, `radius-sm`, focus → `ink-500` border + ring. Labels above, hint/error below. Error state uses danger color **plus** an icon and message.

**Command bar** *(implemented)* — a **compact tabbed command bar** (Home · Insert · Draw · View): OneNote's few-clicks accessibility in Openote's calm language. A slim tab row (~32px) over one command row (~44px) of icon buttons in divided groups; never more than two rows, never wrapping (overflow → "more" menu). Tabs organize breadth; the row stays quiet. Right-click **context menus** on blocks and canvas carry the same commands to the pointer — most actions reachable in ≤2 clicks. *(Supersedes v0.1's "contextual toolbar only" stance: the stakeholder explicitly values OneNote's everything-close-at-hand model; we keep the calm, drop the clutter.)*
Two refinements from the 2026-08 review (v0.6 stage 4): with no editor
focused, formatting groups **collapse to their group heads** instead of
rendering ~20 disabled glyphs — "disabled ≠ hidden" (§7a.2) holds, but the
first paint must not read as a wall of grey; and the right-hand cluster groups
into a panel switcher (§7c) + find + export rather than eight adjacent
unlabelled icon buttons.

**Navigator (notebooks/sections/pages)** — a tree with clear affordances for the hierarchy: notebooks as top items, section groups collapsible, sections as colored tabs, pages/subpages indented. Drag-to-reorder with a clear drop indicator. Selected item uses `ink-100`/`ink-900` tint, not a heavy bar.

**Tabs** — sections render as OneNote-style colored tabs; the color is user-assignable from the content-ink palette.

**Menus & context menus** — `elevation-1`, `radius-lg`, `raised` surface (§3.7), generous hit targets (≥32px rows), keyboard-navigable, with shortcut hints right-aligned. Full behavioural standards in §7a. *(Until themed in v0.6 stage 2, stock M3 menus show through at mobile row heights.)*

**Dialogs/modals** — `elevation-2`, `radius-xl`, focus-trapped, escapable, with a clear primary action. Reserve for genuinely modal decisions; prefer inline/non-blocking UI (the "interpret, don't interrupt" principle).

**Toasts** — **desktop spec (operative):** floating, max-width 440px,
bottom-left (clear of the right panel slot), `radius-lg`, `raised` surface,
`ui-sm` text; auto-dismiss, non-blocking; destructive actions offer **Undo**
in the toast rather than a confirm dialog where feasible. *(The app's 52
`SnackBar` sites currently render the stock full-window-width mobile slab —
one `SnackBarTheme` in v0.6 stage 2 converts all of them.)* Top on mobile,
later.

**Empty states** — warm, brief, instructive; a light brand illustration (an open page / ink stroke) + one-line guidance + a primary action ("Create your first notebook").

**Tags** — **shipped (TEXT-5, 2026-08)**, and the realised model is stronger
than the chip spec this section used to carry: a tag is a **per-paragraph
gutter marker** (OneNote's model — icon per `TagKind`, distinct icons not just
colour, to-dos with a live checkbox, an optional due date rendered as a quiet
`caption` chip), applied from the command-bar tag menu, imported from OneNote
files, rolled up in the find-tags panel, and feeding flashcards and the
planner. Normative rule the implementation must still meet: **the gutter must
not shift the tagged line's text** — markers hang in reserved space so a
tagged bullet aligns exactly with its untagged siblings *(currently violated;
v0.6 stage 5)*. `radius-full` chips remain the style for tag *pickers/filters*
if those surfaces appear later.

**Live embeds (transclusion boxes)** — an embed must read as *a window onto another page*, not native content, without shouting: a 1px `ink-200`/`night-300` border with a subtle `ink-50`/`night-100` tint, `radius-lg`, and a compact **source badge** (page icon + page title, `caption` size) pinned to the top edge; the badge and empty areas click through to the source, while links inside the embedded content keep their own behavior. States: **live** (badge normal), **syncing** (badge with subtle progress affordance, snapshot content shown), **source deleted** (content grayed, badge in `danger` tone, actions: remove / detach as copy), **circular** (placeholder chip, never a recursive render). Embedded content is visually read-only — no hover editing affordances inside.

---

## 7a. Interaction & component behaviour standards *(added at stakeholder request, Phase 2 — normative)*

These standardise what every menu, button, and click does, so the UI stays consistent as it grows. Any new surface MUST follow these unless a spec'd exception exists.

### 7a.1 Menus (dropdown & context)
- **Anatomy:** rows are 36px tall; a 16px leading icon; 13px label; right-aligned shortcut hint in `caption` size/`graphite-400` where a shortcut exists; `PopupMenuDivider`/thin divider between logical groups; max ~9 items per group before a submenu or dialog is preferred.
- **Context menus** open at the pointer, never centered. Every context-menu action must also be reachable from the command bar or a dialog (menus are accelerators, not sole homes).
- **Dismissal:** Esc, click-away, or action. Menus never nest more than one level.
- **Destructive items** (Delete, Remove permanently) sit last, coloured `danger`, separated by a divider.

### 7a.2 Buttons & clicks
- **Single click** = primary action (select an object; *editable blocks: enter editing*; navigator: open page). **Drag** = move. **Right-click** = context menu. **Double-click** is never the *only* path to anything.
- **Toggle buttons** (snap, panels, tools) show selected state via `primary` tint + `primary.withValues(.14)` fill — never colour alone; the tooltip states the current state and what a click does ("Snap to grid: ON …").
- **Split buttons** (e.g. text colour): the main area applies the *current/last* value; the attached arrow (or long-press) opens the full picker. The button displays the current value (colour swatch underline, font name).
- **Icon-only buttons** always carry a tooltip; tooltips always include the shortcut in the form "Label  (Ctrl+X)".
- **Disabled ≠ hidden:** commands that could apply but currently don't (formatting with no editor focused) render disabled with a nearby one-line hint, so users learn *how* to enable them.

### 7a.3 Dialogs & pickers
- Dialogs are for **choices too rich for a menu** (colour wheel, font list, templates, recycle bin, version history). `radius-xl`, max-height 60% of window, content scrolls — never the chrome.
- **Pickers over ~10 options are searchable** (font picker). Lists render each option in its own value where meaningful (fonts in their face, colours as swatches).
- Enter = confirm/primary, Esc = cancel, focus starts in the search field where present.
- **Colour picker standard:** preset palette grid (theme colours + standard hues) → recent/custom row → expandable custom area with hue slider + saturation/value field + RGBA sliders + hex entry. "Custom" colours persist per workspace.

### 7a.4 Shortcuts
- Shortcuts are **accelerators only** — never the sole route to a function (the colour-flick Ctrl+Shift+C accelerates the picker's last-used value; the picker is the primary path).
- Bare-letter shortcuts exist only when no text field is focused; formatting accelerators (Ctrl+B/I, Ctrl+Shift+C) work *while* typing; shortcuts never shadow text input.
- The status bar surfaces the core set; every shortcut also appears in its button's tooltip.

### 7a.5 State persistence (feel)
- The app **remembers where you were**: last notebook + page on launch; per-page scroll position and zoom when flicking between pages. Restoring is instant (no animation). Panels (links, find) and theme persist per session.
- Every stateful control reflects persisted state on first paint — no flash of defaults.

### 7a.6 Feedback & latency
- Every action gives feedback within 100ms (state change, snackbar, or visible result). Long operations (>300ms: exports) show a snackbar on completion with the target path.
- **Performance budgets (PLAT-4 restated for UI):** page switch < 100ms; notebook switch < 250ms; keystroke-to-paint < 16ms on typical pages. No per-frame JSON decoding or allocation storms on hot paths (decoded content is cached and invalidated by `updatedAt`).

## 7b. The navigator *(rewritten 2026-08-05 for the two-column redesign — normative)*

The navigator is how users move through notebooks. It has been through three
shapes: an expand-everything tree, then a **stacked two-zone pane** (v0.3 of
this guide), and — after real use showed the two zones fighting over one
column's height, and the stakeholder asked for OneNote's width flexibility —
the current **two-column** layout (2026-08-04), which this section now
describes. The stacked description this section used to carry is superseded.

**Shape.** A notebook bar and search box over **two side-by-side columns** —
sections on the left, the active section's pages on the right — each
independently scrollable and **independently resizable** (sections 96–220px,
pages 140–320px), the whole navigator collapsible to a **44px rail** (Ctrl+\)
holding the notebook, Home, and a chip per section. This is knowingly the
OneNote shape; what Openote adds is the **Home pane** (favourites · recents ·
the planner's coming-up summary), a **remembered per-section page** so
browsing never loses your place, and the rail.

**Anatomy (top to bottom).**
1. **Notebook bar** — current notebook name + switcher; opens the notebook menu (switch · rename · delete · new · imports · recycle bin). Right-click the bar *or any notebook row in the menu* for that notebook's actions **without switching to it first**.
2. **Search / quick-jump** — filters sections and pages by title; a result opens the page (or focuses the section) and clears the query.
3. **Columns** — left: **Home**, then section groups → sections (groups indent their sections behind a guide rail; colours user-assignable). Right: the active section's pages and subpages, indented by level, collapsible per branch.
4. **Footer** — new section · new page/section group · recycle bin.

**Rules.**
- **One active section** at a time (`AppState.activeSectionId`); it stays in sync with the open page, so navigating by any route (search, page link, backlink) keeps the navigator honest.
- **Activating a section restores your place there** — the page you were last on, not its first page.
- **Direct manipulation first:** double-click renames inline (never a dialog); drag reparents (page→section, page→page = subpage, section→group); right-click opens the node menu. Every node kind — group, section, page, **and notebook** — must expose the same interaction vocabulary.
- **Destructive actions are recoverable:** delete soft-deletes to the recycle bin with an Undo affordance; a notebook delete additionally confirms, keeps its `.onote` file on disk, and can be restored losslessly. The bin auto-purges after **30 days** and shows each item's remaining lifetime.
- The last notebook cannot be deleted (there is always somewhere to be).
- **Default widths must not truncate a typical title** ("Week 1 — Propositional
  logic"); ellipsis is for the outliers, not the norm (v0.6 stage 5 tunes the
  defaults and minimums).

## 7c. Side panels *(added 2026-08-05 — normative)*

The app grew five right-hand panels (study, planner, find-tags, links/backlinks,
page outline) that each hand-rolled the same anatomy at four different widths
(240–320px), and all five could open at once — 1,360px of chrome on a Row,
which zeroes the canvas on a 1366px laptop. The pattern is now fixed:

- **One slot, one panel.** Right-hand panels share a single **320px** slot;
  opening one closes the current one. The command bar presents the panel
  toggles as one segmented group. *(Rationale: no found workflow needs two at
  once, and OneNote's task-pane model is the familiar shape. If a real
  two-panel workflow emerges, the slot gains a pin — the Row does not gain a
  sixth width.)*
- **Shared scaffold.** Every panel is `SidePanel(title, actions, body,
  footer?)`: an `overline` title with a 16px leading icon, trailing compact
  icon actions ending in close; body; optional footer row. Panels do not draw
  their own outer borders (§3.7) or invent private header styles.
- **Surface:** `chrome` (§3.7) — in dark mode panels sit *above* the canvas,
  never on the same black.
- **Empty states** follow §7: one `ui-strong` line, one short `ui-sm`
  paragraph, then real actions — never skeleton/placeholder bars, which read
  as content that failed to load.
- **Every state offers a next action** (the study-panel rule, adopted
  app-wide): a panel with nothing to show says what would put something there,
  with the affordance in reach.

## 8. Canvas interaction guidelines

The canvas is the product; its interaction model deserves explicit rules so it stays predictable across platforms and input methods.

### 8.1 Tools & modes
- **Select/Move** (default): a container's **top bar** is the only place a drag moves it — inside a text box, click places the caret where you clicked and drag selects text, because that is what a click-drag in a text box means to everyone who has ever used one. Handles on the right edge, bottom edge and corner resize; marquee-drag empty space to multi-selects; clicking the bar selects the whole container (the reliable way into a multi-selection). Escape hatches for moving without the bar: **Alt-drag** the body, or **long-press then drag** on touch. Blocks with nothing to select — pictures, attachments — still drag by their body, as OneNote does.
  - Chrome is *reserved* around the block, never overflowed: `RenderBox.hitTest` rejects anything outside a box's own size (`Clip.none` affects painting only), so chrome drawn at negative offsets is mostly ungrabbable.
- **Text**: click empty canvas to create a text container and start typing (CANVAS-3). Double-click empty space also creates text (familiar OneNote behavior).
- **Pen / Highlighter / Eraser**: ink tools; while active, single-finger/pen draws and palm is rejected (INK-4). Two-finger gesture still pans/zooms.
- **Lasso** (later): freehand-select ink and mixed content.
- **Shapes/connectors** (later).

### 8.2 Pan & zoom (CANVAS-2)
- **Pan:** space-drag or hand tool (mouse); two-finger drag (trackpad/touch); scrollbars for both axes; middle-drag optional.
- **Zoom:** Ctrl/⌘-scroll, pinch, and `Ctrl +/-`; zoom centers on the cursor/pinch point. Provide **zoom-to-fit**, **reset (100%)**, and a zoom indicator.
- Momentum/inertial scroll on touch; never trap the user with no way back to content (edge hints / minimap, CANVAS-10/12).

### 8.3 Placement: free vs. snap (CANVAS-5)
- A visible, one-tap toggle switches **Free** ↔ **Snap-to-grid**. In snap mode, an optional light grid shows and objects align on move/resize; holding a modifier temporarily inverts the mode (snap→free or free→snap) for one action.
- **Alignment guides** (magenta-free — use `ink-400`) appear when a moved object nears another's edge/center (Should, P2).

### 8.4 Selection feedback
- Selected block: 2px `ink-500` outline + resize handles at corners/edges; multi-select shows a bounding box. Hovered-but-unselected: 1px quiet border. Keep it minimal — the content, not the chrome, should dominate.

### 8.5 Input parity
Every core canvas action works with **mouse, trackpad, touch, and pen**. Document the gesture map per input in the component library. Keyboard users can create, navigate, and move blocks via shortcuts and arrow-nudge.

---

## 9. Accessibility

Non-negotiable, per PLAT-5. Targets **WCAG 2.1 AA**.

- **Contrast:** all text and meaningful UI meet AA (verify every token pairing; the palette is designed for it). Never encode meaning in color alone — pair with icon/text/pattern.
- **Keyboard:** every action reachable without a pointer; logical focus order; a visible focus ring everywhere (`ink-400`, 2px, 2px offset); no keyboard traps; documented shortcuts with a discoverable cheat-sheet.
- **Screen readers:** semantic roles/labels on all controls; the navigator exposes the hierarchy; canvas blocks expose type + content to assistive tech (a known hard area for own-canvas frameworks — treat as a first-class engineering task, not an afterthought — see [Tech Evaluation](03-technology-evaluation.md)).
- **Text sizing & zoom:** respect OS text-scaling; the editor offers its own text-size control; UI reflows without clipping to at least 200%.
- **Motion:** honor "reduce motion" — replace movement with fades; never animate essential information.
- **Targets:** minimum 32×32px (44×44 on touch) hit areas.
- **Color-vision:** the content-ink and semantic palettes are chosen to remain distinguishable across common color-vision deficiencies; verify with a simulator.

---

## 10. Motion

Motion clarifies, never decorates. It should feel like paper and ink — physical, quick, unfussy.

- **Durations:** micro (hover/press) 80–120ms; standard (panels, menus) 160–220ms; large (page/notebook transitions) 240–320ms. Nothing slower without reason.
- **Easing:** standard `cubic-bezier(0.2, 0, 0, 1)` (decelerate-in); exits slightly faster.
- **Purposeful only:** animate to show relationship (where a panel came from), state change (saved/synced), or spatial continuity (zoom origin). No looping/idle animation.
- **Ink replay** (future) is the one expressive exception — replaying strokes in order is a delightful, content-driven animation.
- Always gated by "reduce motion."

---

## 11. Voice & tone (product writing)

How Openote speaks in UI copy, docs, and messages.

- **Clear, warm, unpretentious.** Plain language over jargon. Short sentences. Respect the user's intelligence and time.
- **Confident, not boastful.** State what things do; don't oversell. We're proud of openness — we say it plainly, not breathlessly.
- **Calm in errors.** Errors explain what happened and what to do next, without blame or alarm. "Couldn't reach your sync server — your notes are safe on this device. Retry?" not "Error 0x8007: sync failed."
- **Second person, active voice.** "Create a notebook," "Your notes are stored on your device."
- **Never scold, never dumb down.** No dark patterns, no guilt, no fake urgency.
- **Honesty about openness.** When we talk about the open format or lock-in, we're *precise* (e.g. we don't call OneNote's format "completely closed" — it's "documented but impractical to use elsewhere"). Accuracy is part of the brand.

Microcopy examples: empty page → "Click anywhere to start writing, or grab the pen to draw." · first launch → "Everything you make here lives on your device, in an open format you own." · sync off → "Working offline. Turn on sync to use these notes on your other devices."

---

## 12. Do & don't (quick reference)

**Do:** let the canvas breathe · use Ink for one primary action per view · pair color with icon/text · animate with purpose · write plainly · meet AA · honor platform conventions · keep tools contextual.

**Don't:** rebuild the cluttered ribbon · use brass as a dominant color · rely on color alone · add gratuitous shadows/gradients · use modal dialogs where inline undo works · overstate claims · trap the user in a zoom/pan dead-end · ship an inaccessible canvas.

---

## 13. Tokens & next steps

This guide defines the *system*; realising it is now a concrete, staged plan —
**[v0.6 — the UI revamp](planning/v0.6-ui-revamp.md)** — whose first two
stages produce the two artifacts this section has asked for since v0.1:

1. **`app/lib/theme/tokens.dart`** — the operative values of §4.2a, §5.1–5.3,
   §3.7 and §6 as code (type ramp, spacing, radii, icon sizes, named alphas,
   motion durations, surface roles as a `ThemeExtension`), consumed directly
   by widgets. This replaces the earlier "JSON/Style-Dictionary" ambition —
   one consumer, one language; indirection through JSON bought nothing.
2. **Component themes** filling `onoteTheme()` so no stock-Material metric or
   shape is visible anywhere (buttons, menus, dialogs, pickers, toasts,
   checkboxes, focus, hover, splash).

Still ahead of the app, unchanged: logo & icon assets (wordmark, app icon,
custom glyphs) in SVG; a canvas interaction spec expanding §8 into a per-input
gesture map; an accessibility test plan (contrast matrix — first run 2026-08-05,
see §3.3 — keyboard map, screen-reader scripts). The **UI screenshot harness**
(`app/test/ui_screenshots_test.dart`) is the standing review instrument: any
visual change of substance regenerates its set before merging.

---

*Colors, type, and spacing here are a coherent, accessible starting system — not immutable law. Validate every contrast pairing in implementation, and let real usage on the canvas refine the details. The principles in §1, however, are the fixed points: calm, page-first, interpret-don't-interrupt, native-in-spirit, accessible-by-default.*
