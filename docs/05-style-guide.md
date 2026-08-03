# Openote — Style Guide & Design System

> **Document status:** Draft v0.3 · **Implementation phase** · Last updated 2026-07-26
> **Reality check:** colour tokens (§3) are implemented verbatim in `app/lib/theme/onote_theme.dart`; §7a and §7b are normative and implemented; **typography (§4.1) is NOT yet met** — no fonts are bundled, see the status note there. Tags/chips (§7) are specified but unimplemented.
> **Purpose:** The single source of truth for how Openote looks, feels, and speaks — brand, color, type, spacing, components, canvas interaction, motion, accessibility, and voice. Written so a designer or developer can build a consistent, professional product from it.
> **Related:** [Product Vision](00-product-vision.md) · [PRD](02-product-requirements.md)

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
| `graphite-400` | `#9A968C` | tertiary text, placeholders |
| `graphite-500` | `#6E6B63` | secondary text |
| `graphite-700` | `#403D38` | body text (light) |
| `graphite-900` | `#211F1B` | headings / max-contrast text (light) |

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

> Never rely on color alone (§9). Pair every semantic color with an icon and/or text.

### 3.6 Content ink palette (for the user's pen & highlighter)

A default set of pen colors offered to users — chosen to be legible on paper *and* night surfaces, and colorblind-considerate. Users can pick any color; these are the curated defaults: Ink Black `#211F1B`, Ink Blue `#2F6FB3`, Ink Red `#C63838`, Forest `#2E8B57`, Violet `#6A4BC0`, Brass `#D9971F`, and Highlighter tints (yellow `#F7E27A`, green `#B6E39A`, pink `#F3B0C6`, blue `#A8CCF0`) at ~40% opacity.

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

> **Implementation status (2026-07-26): not yet met.** No fonts are bundled — `pubspec.yaml` has no `fonts:` section and `onoteTheme` sets `fontFamily: null`, so the app renders in each platform's **system UI font** (Segoe UI on Windows). Code/mono styles request the generic family `'monospace'`; math glyphs come from `flutter_math_fork`'s bundled KaTeX fonts (so the Math row above *is* satisfied). Consequences: type looks different per OS — the opposite of the "consistent in soul" principle — and the type scale below is only approximately realised. **To close:** add Inter + JetBrains Mono (both OFL/Apache, ~1–2 MB subset) to `pubspec.yaml` and set `fontFamily` in the theme; offer Source Serif as the reading-serif option. Tracked as a Phase 1 polish item (PLAT-1).

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

### 4.3 In-editor Markdown rendering

Rendered Markdown maps to the editor scale: `# `→`h1`, `## `→`h2`, etc.; inline code and code blocks use `mono` with a subtle tinted background (`paper-100`/`night-100`); block quotes get a `ink-300` left border and `graphite-500` text; links use `ink-600`/`ink-400` with underline-on-hover. When the caret enters a span, its Markdown markers reveal in `graphite-400` (dimmed) — visible but quiet.

---

## 5. Spacing, layout & shape

### 5.1 Spacing scale (4-pt base)

`0, 2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64`. Use tokens (`space-2` = 8px, etc.); avoid arbitrary values. Default control padding: 8×12. Default panel padding: 16. Section rhythm: 24.

### 5.2 Radius

| Token | Value | Use |
|-------|-------|-----|
| `radius-sm` | 4px | inputs, small chips |
| `radius-md` | 8px | buttons, cards, containers |
| `radius-lg` | 12px | panels, popovers, canvas text boxes |
| `radius-xl` | 16px | modals, large surfaces |
| `radius-full` | 999px | avatars, toggles, pills |

Text containers on the canvas use `radius-lg` with a near-invisible border until hovered/selected — echoing OneNote's containers but calmer.

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

## 6. Iconography

- **Style:** a single **outline** icon set, 1.75px stroke at 24px, rounded joins/caps — echoing the confident ink line. Filled variants only for active/selected toggle states.
- **Grid:** 24px with 2px padding; also ship 20px and 16px optically-adjusted sizes (not naive scaling).
- **Source:** a consistent open icon set (e.g. **Lucide/Feather** family) extended with Openote-specific glyphs (pen, highlighter, lasso, snap-grid, sigma/math, backlink).
- **Tool icons** get an active-state accent (`brass-400` fill or `ink-500` background) so the current tool is unmistakable.
- Always pair icon-only buttons with a tooltip and an accessible label.

---

## 7. Components

Baseline patterns; a component library/tokens file is a next-pass deliverable.

**Buttons** — Primary (`ink-500` fill, white text), Secondary (border + `graphite-700` text), Ghost (text only, tinted hover), Danger (uses danger semantic). Height 32 (compact) / 36 (default). `radius-md`. Clear hover/pressed/focus/disabled states; visible focus ring (`ink-400`, 2px, offset 2px).

**Inputs** — 1px `paper-300`/`night-300` border, `radius-sm`, focus → `ink-500` border + ring. Labels above, hint/error below. Error state uses danger color **plus** an icon and message.

**Command bar** *(revised per stakeholder direction, Phase 2)* — a **compact tabbed command bar** (Home · Insert · Draw · View): OneNote's few-clicks accessibility in Openote's calm language. A slim tab row (~32px) over one command row (~44px) of icon buttons in divided groups; never more than two rows, never wrapping (overflow → "more" menu). Tabs organize breadth; the row stays quiet. Right-click **context menus** on blocks and canvas carry the same commands to the pointer — most actions reachable in ≤2 clicks. *(Supersedes v0.1's "contextual toolbar only" stance: the stakeholder explicitly values OneNote's everything-close-at-hand model; we keep the calm, drop the clutter.)*

**Navigator (notebooks/sections/pages)** — a tree with clear affordances for the hierarchy: notebooks as top items, section groups collapsible, sections as colored tabs, pages/subpages indented. Drag-to-reorder with a clear drop indicator. Selected item uses `ink-100`/`ink-900` tint, not a heavy bar.

**Tabs** — sections render as OneNote-style colored tabs; the color is user-assignable from the content-ink palette.

**Menus & context menus** — `elevation-1`, `radius-md`, generous hit targets (≥32px rows), keyboard-navigable, with shortcut hints right-aligned. Full behavioural standards in §7a.

**Dialogs/modals** — `elevation-2`, `radius-xl`, focus-trapped, escapable, with a clear primary action. Reserve for genuinely modal decisions; prefer inline/non-blocking UI (the "interpret, don't interrupt" principle).

**Toasts** — bottom (desktop) / top (mobile), auto-dismiss, non-blocking; carry sync/save/undo confirmations. Always dismissible; destructive actions offer **Undo** in the toast rather than a confirm dialog where feasible.

**Empty states** — warm, brief, instructive; a light brand illustration (an open page / ink stroke) + one-line guidance + a primary action ("Create your first notebook").

**Tags/chips** — `radius-full`, subtle fill, small; the built-in tag library (to-do, important, question…) uses distinct icons, not just color. *(**Not implemented** as of 2026-07-27 — no tag model, tag UI, or tag query exists anywhere in the app (**TEXT-5**, and the tag half of ORG-5 / TEXT-1a). OneNote's tag library is a signature feature and a known switcher expectation; the closest shipped equivalent is Markdown checkboxes (`- [ ]`, TEXT-6). The OneNote importer also can't carry tags across, so tagged source notebooks lose that structure on import.)*

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

## 7b. The navigator *(added 2026-07-26 after the navigator rework — normative)*

The navigator is how users move through notebooks, and it was reworked from a single expand-everything tree to a **stacked two-zone pane** after a stakeholder UX review. That decision is now the standard; the alternative accordion-tree prototype was removed.

**Why stacked, not OneNote's layout.** OneNote web uses a "double fold-out" — a ~48px notebook rail plus a sections column plus a pages column, ≈480px of chrome before content. That buys clarity (you always see exactly one section's pages) at a real horizontal cost. Openote takes the clarity and drops the cost by **stacking the two columns vertically inside one ~250px pane**.

**Anatomy (top to bottom).**
1. **Notebook bar** — current notebook name + chevron; opens the notebook menu (switch · rename · delete · new · imports · recycle bin). Right-click the bar *or any notebook row in the menu* for that notebook's actions **without switching to it first**.
2. **Search / quick-jump** — filters sections and pages by title; a result opens the page (or focuses the section) and clears the query.
3. **Sections zone** — section groups → sections, each with its colour bar. Clicking a section makes it **active**; it does not dump its pages into the list.
4. **Resize divider** — drag to trade height between the zones; the ratio persists per workspace (`navSplit`).
5. **Pages zone** — the **active section's** pages and subpages only, indented by level. This is where users spend their time, so it gets the remaining height.
6. **Footer** — new section · new page · new section group · recycle bin.

**Rules.**
- **One active section** at a time (`AppState.activeSectionId`); it stays in sync with the open page, so navigating by any route (search, page link, backlink) keeps the navigator honest.
- **Direct manipulation first:** double-click renames inline (never a dialog); drag reparents (page→section, page→page = subpage, section→group); right-click opens the node menu. Every node kind — group, section, page, **and notebook** — must expose the same interaction vocabulary.
- **Destructive actions are recoverable:** delete soft-deletes to the recycle bin with an Undo affordance; a notebook delete additionally confirms, keeps its `.onote` file on disk, and can be restored losslessly. The bin auto-purges after **30 days** and shows each item's remaining lifetime.
- The last notebook cannot be deleted (there is always somewhere to be).

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

This guide defines the *system*; the next design pass should produce:

1. A **design-tokens file** (JSON/Style-Dictionary) encoding every value here for light/dark, consumed directly by the app.
2. A **component library** (Figma + code) realizing §7 with all states.
3. **Logo & icon assets** (wordmark, app icon, custom glyphs) in SVG.
4. A **canvas interaction spec** expanding §8 into a per-input gesture map.
5. **Accessibility test plan** (contrast matrix, keyboard map, screen-reader scripts).

---

*Colors, type, and spacing here are a coherent, accessible starting system — not immutable law. Validate every contrast pairing in implementation, and let real usage on the canvas refine the details. The principles in §1, however, are the fixed points: calm, page-first, interpret-don't-interrupt, native-in-spirit, accessible-by-default.*
