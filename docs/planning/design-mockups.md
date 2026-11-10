# Design mockups

A recreation of the desktop UI as it is today, built in Claude Design on 11 November 2026 as a base to
work from. **It is not a redesign.** Two things it is for: trying changes to the desktop app before
building them, and starting the Android layout from a faithful copy rather than a blank page.

**Where:** <https://claude.ai/artifact/H9Zd1fhDphJ6HcGWptUc2x> — private to the owner's account; share
it from the page's Share menu if anyone else needs it. It is not in the repo, so if it is lost the
tables below are what it was made from.

## What is on the canvas

| Artboard | Shows | Source it was copied from |
|---|---|---|
| Workspace | The whole window: navigator (notebook switcher, search, section and page columns, footer), the four ribbon tabs (Home, Insert, Draw, Page) which switch when clicked, the page canvas with a selected box, the status bar. A **Tweaks** control flips dark and light | `app/lib/ui/sidebar.dart`, `command_bar.dart`, `command_faces.dart`, `insert_catalog.dart`, `app_shell.dart` |
| Notebooks dialog | The notebook list and its footer buttons | `notebook_manager.dart`, and the reporter's screenshot on [#41](https://github.com/icmric/openote/issues/41) |
| Settings dialog | The Appearance pane (the only one drawn) | `settings_dialog.dart`, screenshot on #41 |
| Sync this notebook | The not-yet-synced state, with the 460 px height cap and the scrollbar drawn over the controls — **as it is, faults included** ([#42](https://github.com/icmric/openote/issues/42)) | `sync_dialog.dart`, screenshot on #42 |
| Context menus | The box menu and the navigator row menu | `context_menus.dart`, `sidebar.dart`, screenshot on [#39](https://github.com/icmric/openote/issues/39) |

Colours, type sizes, radii and row heights are the real tokens in `app/lib/theme/tokens.dart` and
`onote_theme.dart` (Inter; 13 px body; 6/8/12 px radii; the surface and text colours). **The accent is
read off the screenshots, not out of the theme's colour scheme** — a periwinkle (the palette's `ink400`)
in dark and a deeper indigo (`ink600`) in light — as is the brass of the selected segment.

## What is approximate — check before trusting a pixel

- **Not looked at once built.** The files were written to the canvas's format and published; nobody has
  opened the canvas to compare it with the app. Expect small spacing differences.
- **Icons are line drawings in the same spirit, not the app's Material icons.** The sizes (16 and 18 px)
  are right; the shapes are not exact.
- **The navigator row menu's order is a guess.** Its items are the real ones from the strings; the
  order and the dividers are not known. The box menu is exact (screenshot).
- **Sample content is invented**: section and page names, the box text, "12 words", the status-bar
  shortcut hint (V, T, P, H, E, Ctrl+Z, Ctrl+scroll). The real hint text was not read.
- **Only the Appearance pane of Settings is drawn**, and only the not-yet-synced state of Sync.
- **Missing on purpose:** the canvas right-click menu (Paste, the insert grid, backgrounds), the
  Study and Planner panels, the equation face of the ribbon, Home (the favourites pane), the onboarding
  flow, light-theme dialogs, the web demo.
- **The OS title bar** is left out, as it is in the reporters' screenshots of the app's own area.

## Using it

**Desktop changes.** Duplicate an artboard and change the copy. The tracked fixes that touch the
layout are worth drawing first: the button heights ([#41](https://github.com/icmric/openote/issues/41):
buttons here are drawn 20 px tall, as built), the Sync dialog ([#42](https://github.com/icmric/openote/issues/42))
and the one create menu ([#43](https://github.com/icmric/openote/issues/43)).

**Android.** The desktop ribbon, a three-column navigator and hover-only affordances do not carry to a
phone or a tablet in portrait; what does carry is the content model (notebook → section → page → boxes)
and the dialogs' wording. A tablet in landscape is the nearest relative of this layout. Draw it from
the Workspace artboard, with the pen as the primary input. The part a mockup cannot settle is storage
and sync — see the Android row in the [backlog](backlog.md#3-decided-against--for-now).
