import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas/media_drop.dart';
import '../canvas/page_canvas.dart';
import '../math/math_field.dart';
import '../model/models.dart';
import '../model/tags.dart';
import '../core/onote_ffi.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'alert_popup.dart';
import 'import_progress.dart';
import 'command_bar.dart';
import 'context_menus.dart';
import 'object_row.dart';
import 'onboarding.dart';
import 'open_notice_dialog.dart';
import 'planner_panel.dart';
import 'side_panel.dart';
import 'protect_dialog.dart';
import 'save_problem_dialog.dart';
import 'shortcut_overlay.dart';
import 'sidebar.dart';
import '../export/print_page.dart';
import 'study_panel.dart';
import 'sync_dialog.dart';
import 'sync_dot.dart';
import '../theme/tokens.dart';

/// Layout per style guide §5.4: navigator | (toolbar / canvas-as-hero / status).
///
/// Keyboard handling uses a global HardwareKeyboard handler rather than
/// widget-tree Shortcuts. This is deliberate: on desktop, Flutter's
/// EditableText inserts printable characters via the text-input channel and
/// does NOT consume the raw KeyDownEvent, so ancestor `Shortcuts` with
/// bare-letter activators (V/T/P/H/E …) *shadow* text fields — the exact bug
/// that made those letters untypeable. Here we detect whether a text field is
/// focused and, if so, handle only Escape and let every other key through.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.app});
  final AppState app;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppState get app => widget.app;

  /// Whether the Ctrl+/ shortcut reference is up. Tracked here because the
  /// global handler runs even under a dialog: Ctrl+/ must toggle rather than
  /// stack, and Escape must close the overlay instead of falling through to
  /// clear-selection below it.
  bool _shortcutsOpen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    // The OneNote-style pending caret's arrow keys (live_markdown_engine.dart)
    // reuse this same block-to-block navigation rather than reimplementing it.
    app.navigateSpatial = _spatial;
    // One listener, every region: the moment focus leaves the region F6 put
    // it in, the ring is a lie and goes away.
    for (final n in [
      _canvasFocus,
      _sidebarRegion,
      _toolbarRegion,
      _objectRegion,
      _panelRegion,
      _alertRegion
    ]) {
      n.addListener(_regionFocusChanged);
    }
    // A notebook we were HANDED can arrive at any moment: at launch (from the
    // command line) or minutes later, when another double-click hands this
    // instance a file through core/single_instance.dart. One listener covers
    // both, so the second case cannot quietly go unreported the way a
    // launch-only check would leave it.
    app.addListener(_openNoticeChanged);
    // Post-frame: the welcome flow needs a Navigator, and there isn't one
    // until this shell is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The hand-off notice takes the slot when there is one. On a fresh
      // install whose shortcut points at a moved notebook BOTH would fire, and
      // two modal dialogs stacked on first run is a worse first minute than
      // either alone.
      if (app.pendingOpenNotice != null) {
        _openNoticeChanged();
      } else {
        maybeShowOnboarding(context, app);
      }
    });
  }

  /// True while the notice dialog is up, so a notify that arrives underneath
  /// it cannot stack a second copy.
  bool _noticeShowing = false;

  Future<void> _openNoticeChanged() async {
    if (_noticeShowing || !mounted) return;
    final notice = app.pendingOpenNotice;
    if (notice == null) return;
    app.pendingOpenNotice = null; // consumed — shown once, never on rebuild
    _noticeShowing = true;
    try {
      await showOpenNotebookNotice(context, notice);
    } finally {
      _noticeShowing = false;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    app.navigateSpatial = null;
    app.removeListener(_openNoticeChanged);
    for (final n in [
      _canvasFocus,
      _sidebarRegion,
      _toolbarRegion,
      _objectRegion,
      _panelRegion,
      _alertRegion
    ]) {
      n.removeListener(_regionFocusChanged);
      n.dispose();
    }
    _panelEntry.dispose();
    _ring.dispose();
    super.dispose();
  }

  /// True when a real text field (block editor, page title, find, or any
  /// dialog field) currently owns the keyboard.
  /// Is an EDITOR holding the keyboard?
  ///
  /// This gate is what makes the shell stand down: while it is true, chords
  /// that belong to the canvas (Ctrl+C, Ctrl+X, Delete, the arrows) are left
  /// alone for whatever is being typed into.
  ///
  /// A `MathField` counts, and used not to. It is a bare `Focus` rather than
  /// an `EditableText` — it has no linear string to own — so the shell did not
  /// recognise it as an editor and **Ctrl+X cut the whole block out from under
  /// a student mid-equation.** The field's own Ctrl+X never even ran: the
  /// shell's global handler sees the key first, before focus dispatch.
  bool _editableFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    bool isEditor(Widget w) => w is EditableText || w is MathField;
    if (isEditor(ctx.widget)) return true;
    var found = false;
    ctx.visitAncestorElements((e) {
      if (isEditor(e.widget)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  /// Whether the primary focus sits in a [MathField] specifically — gate TWO
  /// and THREE of v0.20 B.2.6. While an equation holds the keyboard, the
  /// shell's formatting chords must stand down (Ctrl+B used to BOLD THE
  /// PARAGRAPH from inside an inline equation) and the Escape ladder must
  /// leave the keystroke to the field, whose onExit knows where the caret
  /// goes. `_editableFocused` says "someone is typing"; this says "and it is
  /// an equation".
  bool _mathFieldFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is MathField) return true;
    var found = false;
    ctx.visitAncestorElements((e) {
      if (e.widget is MathField) {
        found = true;
        return false;
      }
      // An EditableText between the focus and any MathField means the focus
      // is in ordinary text (the LaTeX source view, a nested field) — stop.
      if (e.widget is EditableText) return false;
      return true;
    });
    return found;
  }

  /// The `=` key, however the platform reports it. `add` is the `+` CHARACTER
  /// — what a shifted `=` becomes on a layout that hands Flutter the shifted
  /// logical key — and `numpadAdd` is the keypad's own. The zoom chords below
  /// have always accepted `equal` and `add` for the same reason.
  /// The printable character this keystroke actually PRODUCED, or null.
  ///
  /// The marker chord has to key off the character, never the key: `*` is
  /// Shift+8 on a US layout, Shift+`+` on a German one and an unshifted key of
  /// its own on French AZERTY, and Flutter hands Windows the UNSHIFTED logical
  /// key (the same divergence `_isEqualsKey` exists for, where a shifted `=`
  /// arrives as `equal` plus a Shift flag on Windows and as `add` elsewhere).
  /// Binding `digit8` would give the chord to one keyboard and to no other.
  /// [KeyEvent.character] is what Flutter's own [CharacterActivator] compares,
  /// and its documented caveat is about Alt on macOS, not Control.
  ///
  /// Two guards, each for a concrete misfire:
  ///
  /// * control codes are rejected, because Windows reports Ctrl+letter as
  ///   U+0001…U+001A — Ctrl+F would otherwise arrive as U+0006 and Ctrl+^ as
  ///   U+001E, and a raw code point could collide with a marker;
  /// * the `keyLabel` fallback (for the embedders that report the SHIFTED key
  ///   as the logical one, where `character` may be absent) is taken only when
  ///   Shift is not held. With Shift down the label is ambiguous — on Windows
  ///   it is the unshifted key — so guessing would fire Ctrl+Shift+` as
  ///   backtick/code when the student asked for a tilde.
  static String? _producedCharacter(KeyEvent e, bool shift) {
    bool printable(String s) =>
        s.length == 1 && s.codeUnitAt(0) > 0x20 && s.codeUnitAt(0) != 0x7f;
    final c = e.character;
    if (c != null && printable(c)) return c;
    final label = e.logicalKey.keyLabel;
    if (!shift && printable(label)) return label;
    return null;
  }

  static bool _isEqualsKey(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.equal ||
      k == LogicalKeyboardKey.add ||
      k == LogicalKeyboardKey.numpadAdd;

  /// Alt+= — a new equation on the page, with the caret already in it.
  ///
  /// Deliberately the same two calls the Insert ribbon and the right-click
  /// menu make (`addBlock`, then `select(edit: true)`); `MathBlockView` takes
  /// the keyboard itself on its first editing build, so there is nothing more
  /// to do to land the caret.
  ///
  /// With text selected, the words come WITH you rather than being left
  /// behind as a duplicate — `x^2 + 1` written in prose becomes the equation
  /// it was always meant to be. The selection is seeded into BOTH
  /// `linearSource` and `latex`: an equation whose `latex` is empty is swept
  /// away when the editor closes, so seeding only the source would lose the
  /// text if the student pressed Escape without typing.
  void _startEquation({bool forceBlock = false}) {
    // Already writing an equation? Then the chord has nothing to add, and a
    // second empty block appearing underneath would be a surprise.
    for (final b in app.blocks) {
      if (b.id == app.editingBlockId && b.type == BlockType.math) return;
    }

    final ae = app.activeEditor;
    var seed = '';
    Offset at;
    if (ae != null && ae.block.type == BlockType.text) {
      final sel = ae.controller.selection;

      // **Writing in a paragraph, nothing selected.** This is the ordinary
      // case, and it used to drop a separate equation block below the
      // paragraph — which is why the owner reported that Openote "doesnt seem
      // to allow me to do equations inline with a regular text block yet".
      // Inline maths worked; there was simply no way to ASK for it that did
      // not involve knowing to type two dollar signs. Alt+= in a paragraph now
      // always means "an equation here"; Alt+Shift+= is the way to a block.
      if (!forceBlock &&
          sel.isValid &&
          sel.isCollapsed &&
          (app.activeSession?.startInlineMath() ?? false)) {
        return;
      }

      if (sel.isValid && !sel.isCollapsed) {
        seed = ae.controller.text.substring(sel.start, sel.end).trim();
        if (seed.isNotEmpty && !forceBlock) {
          // **In place, in the sentence.** Alt+= used to cut the selected words
          // OUT of the paragraph and drop a separate equation block below it —
          // so "the area is ½bh" became "the area is " with a floating block
          // underneath. Wrapping in `$…$` leaves the words exactly where the
          // student put them, and the live editor draws them as an equation
          // immediately; one click opens it. Alt+Shift+= is the way to a
          // display block on its own line.
          app.insertTextAtActiveCursor('\$$seed\$');
          return;
        }
        // Alt+SHIFT+= — a display equation of its own. The words come with it,
        // so they are cut from the paragraph here. Replacing the selection
        // with nothing is the existing "write at the caret" seam, so the text
        // block is committed and undoable exactly as any other edit would be.
        if (seed.isNotEmpty) app.insertTextAtActiveCursor('');
      }
      final b = ae.block;
      final h = b.h ?? app.renderSizes[b.id]?.height ?? 60;
      // `b.y + h + 14` is one of the candidates smartTextPosition snaps to,
      // so the equation lands directly under the paragraph it came from and
      // aligned to its left edge.
      at = app.smartTextPosition(Offset(b.x, b.y + h + 14));
    } else {
      final v = app.canvas.viewport;
      final c = app.canvas.screenToPage(Offset(v.width / 2, v.height / 2));
      at = Offset(c.dx - 180, c.dy - 30); // centred, same as Insert ▸ Equation
    }

    app.insertEquation(at: at, seed: seed);
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final k = e.logicalKey;
    final editable = _editableFocused();
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Escape: close find / exit our editors / clear selection. Gated on our
    // own state so a dialog's own Escape-to-cancel still works.
    if (k == LogicalKeyboardKey.escape) {
      if (_shortcutsOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        return true;
      }
      // Everything below is the SHELL's Escape ladder, and none of it may
      // run while a dialog owns the screen. This handler fires regardless of
      // what is on top, and a HardwareKeyboard handler's `true` does not stop
      // the framework popping the dialog on the same keystroke — so one
      // Escape aimed at a dialog was ALSO toggling find off and unfocusing
      // the dialog's own text field on the way past. Traversal already
      // checked this; the ladder never did.
      if (_routeOnTop) return false;
      // While an equation holds the keyboard, Escape means "leave the
      // equation" and nothing else — the field's own handler runs onExit,
      // and the HOST decides where the caret lands. Without this gate one
      // Escape both closed the equation AND deselected the block.
      if (_mathFieldFocused()) return false;
      if (app.findOpen) {
        app.toggleFind();
        return true;
      }
      if (app.editingBlockId != null || app.titleEditing) {
        FocusManager.instance.primaryFocus?.unfocus();
        // Hand focus back to the canvas so Tab/arrow traversal keeps
        // working after climbing out of an editor — the root scope would
        // otherwise let the framework's own focus walk take the arrows.
        _canvasFocus.requestFocus();
        app.select(null);
        return true;
      }
      if (!editable && app.selectedIds.isNotEmpty) {
        app.select(null);
        _canvasFocus.requestFocus();
        return true;
      }
      // Deliberately NOT a rung for the reminder cards, though they were the
      // one popup with no keyboard route at all (phase-3 audit). Dismissing a
      // reminder writes through to the store — `PlannerState.dismissAlert`
      // calls `reminders.dismiss`, which persists — so it is an action with a
      // consequence, not a step back, and a third idle Escape would silently
      // lose a reminder that had never been read. They join the F6 rotation
      // instead, which puts Done, Snooze and Dismiss all under the keyboard.
      return false;
    }

    // F6 / Shift+F6 — walk the window's big areas. Sits with the navigator
    // chords BEFORE the typing early-return on purpose: getting out of the
    // box you are writing in is most of what it is for, and no text field
    // types a character for F6.
    if (k == LogicalKeyboardKey.f6 &&
        !ctrl &&
        !HardwareKeyboard.instance.isAltPressed) {
      return _cycleRegion(shift ? -1 : 1);
    }

    // **Shift+F10 / the Menu key — the same menu the right button opens.**
    //
    // It was reachable from `kSecondaryMouseButton` and from nowhere else, so
    // half of what a student can add to a page had no keyboard route at all.
    // Anchored at the middle of the page area, which is also where the block
    // lands, so what you get is what the anchor said.
    if ((k == LogicalKeyboardKey.f10 && shift) ||
        k == LogicalKeyboardKey.contextMenu) {
      if (_routeOnTop) return false;
      final box = _canvasFocus.context?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return false;
      final b = app.selectedIds.length == 1
          ? app.blocks.where((x) => x.id == app.selectedBlockId).firstOrNull
          : null;
      if (b != null) {
        final at = box.localToGlobal(app.canvas.pageToScreen(Offset(b.x, b.y)));
        showBlockMenu(context, app, b, at);
      } else {
        final centre = box.size.center(Offset.zero);
        showCanvasMenu(context, app, box.localToGlobal(centre),
            app.canvas.screenToPage(centre));
      }
      return true;
    }

    // Alt+= — start a maths equation, OneNote's own chord. Here with the
    // navigator chords, BEFORE the typing early-return: that return lets only
    // Ctrl accelerators through, and reaching for an equation mid-sentence is
    // the whole point of the shortcut. Alt plus a printable key produces no
    // character on any desktop we ship, so nothing is taken away from the
    // field — and `_routeOnTop` keeps it out of a dialog's own text fields.
    if (HardwareKeyboard.instance.isAltPressed &&
        !ctrl &&
        _isEqualsKey(k) &&
        !_routeOnTop &&
        !_mathFieldFocused()) {
      // Shift keeps the old behaviour: a display equation in a block of its
      // own. Plain Alt+= now wraps a selection where it stands.
      _startEquation(forceBlock: HardwareKeyboard.instance.isShiftPressed);
      return true;
    }

    // Navigator chords, BEFORE the editable early-return: none of these can
    // collide with typing (no field inserts a character for Ctrl+PageDown),
    // and OneNote users reach for them mid-sentence.
    if (ctrl) {
      // Ctrl+/ — the shortcut reference (keyboard_map.dart). With the
      // navigator chords, before the typing early-return: the whole point is
      // reaching it from wherever you are, and no field types on Ctrl+/.
      if (k == LogicalKeyboardKey.slash) {
        _toggleShortcutOverlay();
        return true;
      }
      if (k == LogicalKeyboardKey.pageDown) return _cyclePage(1);
      if (k == LogicalKeyboardKey.pageUp) return _cyclePage(-1);
      if (k == LogicalKeyboardKey.tab) return _cycleSection(shift ? -1 : 1);
      if (k == LogicalKeyboardKey.backslash) {
        app.toggleNavCollapsed();
        return true;
      }
      // Ctrl+N — a new page beside the one you are on. OneNote's chord, and
      // it sits here with the other navigator chords, BEFORE the
      // typing early-return: no text field inserts a character for Ctrl+N, and
      // needing to leave the page you are writing on in order to make the next
      // one is exactly the friction a shortcut exists to remove.
      //
      // Ctrl+Shift+N makes a SUB-page of the current one, which is the other
      // half of the same thought and has no other keyboard route at all.
      if (k == LogicalKeyboardKey.keyN) {
        if (shift) {
          unawaited(app.addSubpage());
        } else {
          unawaited(app.addPage());
        }
        return true;
      }
    }

    // While typing: allow only formatting accelerators; everything else
    // flows to the field untouched.
    if (editable) {
      // Undo/redo INSIDE an equation go to the app's own stack. Unclaimed,
      // Ctrl+Z reached nothing at all in a block equation (the 700ms
      // coalescing built for exactly this was toolbar-only), and in an
      // inline one it reached the host TextField's built-in UndoHistory —
      // which rewrote the paragraph under the open session and corrupted
      // the note (probe-proven).
      if (ctrl && _mathFieldFocused()) {
        if (k == LogicalKeyboardKey.keyZ && !shift) {
          app.undo();
          return true;
        }
        if ((k == LogicalKeyboardKey.keyZ && shift) ||
            k == LogicalKeyboardKey.keyY) {
          app.redo();
          return true;
        }
      }
      if (ctrl && app.activeEditor != null && !_mathFieldFocused()) {
        if (k == LogicalKeyboardKey.keyB) {
          app.wrapSelection('**');
          return true;
        }
        if (k == LogicalKeyboardKey.keyI) {
          app.wrapSelection('*');
          return true;
        }
        if (k == LogicalKeyboardKey.keyU) {
          app.wrapSelection('++'); // underline (TEXT-1)
          return true;
        }
        // Ctrl+= / Ctrl+Shift+= — small text below / above the line
        // (`H~2~O`, `x^2^`), on OneNote's own chords. Reached only from
        // INSIDE a text box: the canvas keeps Ctrl+= for zoom, which is why
        // this sits behind the `editable` early-return and that one does not.
        //
        // `add` is the `+` CHARACTER a shifted `=` reports on layouts that
        // hand Flutter the shifted logical key, so it means "above the line"
        // however Shift arrives; `equal` plus the Shift flag is what Windows
        // sends.
        if (_isEqualsKey(k)) {
          app.wrapSelection(
              (shift || k == LogicalKeyboardKey.add) ? '^' : '~');
          return true;
        }
        // Ctrl+Shift+C — flick the selection to the last colour and back.
        if (shift && k == LogicalKeyboardKey.keyC) {
          app.toggleTextColor();
          return true;
        }
        // Ctrl+1/2/3 — tag the caret's line. OneNote's own chords, so the
        // muscle memory a switching student already has keeps working.
        final tag = switch (k) {
          LogicalKeyboardKey.digit1 => TagKind.todo,
          LogicalKeyboardKey.digit2 => TagKind.important,
          LogicalKeyboardKey.digit3 => TagKind.question,
          LogicalKeyboardKey.digit4 => TagKind.remember,
          LogicalKeyboardKey.digit5 => TagKind.definition,
          _ => null,
        };
        if (tag != null) {
          app.toggleTagOnSelection(tag);
          return true;
        }
        // Ctrl + a Markdown marker character — wrap the word at the caret in
        // it, and press again for another layer: `*w*`, `**w**`, `***w***`,
        // and then nothing, because `****w****` is not emphasis. Which
        // characters count, and where each one stops, come from the grammar
        // (`AppState.markerChordLadders`), so a Ctrl+chord with a character
        // Markdown does not use falls straight through to the field.
        //
        // LAST of the writing chords on purpose: every named accelerator
        // above keeps its meaning, which is why Ctrl+= is still subscript
        // rather than highlight even though `=` has a ladder.
        final produced = _producedCharacter(e, shift);
        if (produced != null && app.cycleMarker(produced)) return true;
        // Ctrl+V with an IMAGE on the clipboard. Flutter's own paste handles
        // text only, so screenshot → click in the box → Ctrl+V silently did
        // nothing. Handled here only when there is an image; anything else
        // falls through to the field's own paste, because breaking plain-text
        // paste into a note would be a far worse bug than the one being fixed.
        if (k == LogicalKeyboardKey.keyV) {
          // Maths on the clipboard is handled by `MathPasteFormatter` on the
          // field itself. It cannot be done here: reading the clipboard is a
          // Future, so by the time the answer came back the field had already
          // inserted the raw text — and inserting the wrapped form as well
          // pasted the equation TWICE.
          _pasteImageIntoEditor();
          return false; // never swallow the keystroke
        }
      }
      return false;
    }

    if (ctrl) {
      if (k == LogicalKeyboardKey.keyC) {
        if (app.selectedIds.isEmpty) return false;
        app.copySelectedBlocks();
        return true;
      }
      if (k == LogicalKeyboardKey.keyX) {
        if (app.selectedIds.isEmpty) return false;
        app.cutSelectedBlocks();
        return true;
      }
      if (k == LogicalKeyboardKey.keyV) {
        // System clipboard first (an image from a screenshot tool), our own
        // block clipboard second. The reverse order would make Ctrl+V paste a
        // stale block instead of the screenshot just taken — and copying a
        // block is far rarer than copying an image from elsewhere. The one
        // exception lives in _pasteFromSystemOrBlocks: plain text that is
        // OLDER than the blocks loses to them.
        _pasteFromSystemOrBlocks();
        return true;
      }
      if (k == LogicalKeyboardKey.keyF) {
        app.toggleFind();
        return true;
      }
      if (k == LogicalKeyboardKey.keyP) {
        // Muscle memory, and the reason P13 was worth doing at all: a student
        // printing a revision sheet reaches for Ctrl+P, not a menu. Unawaited
        // because the OS dialog owns the interaction from here.
        unawaited(printCurrentPage(app));
        return true;
      }
      if (k == LogicalKeyboardKey.keyZ && !shift) {
        app.undo();
        return true;
      }
      if ((k == LogicalKeyboardKey.keyZ && shift) ||
          k == LogicalKeyboardKey.keyY) {
        app.redo();
        return true;
      }
      if (k == LogicalKeyboardKey.keyD) {
        final s = app.selectedBlockId;
        if (s != null) app.duplicateBlock(s);
        return true;
      }
      if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.add) {
        app.canvas.setZoom(app.canvas.scale * 1.2);
        return true;
      }
      if (k == LogicalKeyboardKey.minus) {
        app.canvas.setZoom(app.canvas.scale / 1.2);
        return true;
      }
      if (k == LogicalKeyboardKey.digit0) {
        app.canvas.reset();
        return true;
      }
      return false;
    }

    // Bare keys — only reached when no text field is focused. Tool letters
    // additionally step aside when the selection is a box you can TYPE
    // into: there, a letter means "start writing" (type-through, handled
    // on the canvas focus node), not "switch tool".
    //
    // `editingBlockId == null` on both branches below, and not just
    // `editable`: a block can be under the keyboard without a TEXT FIELD
    // being under the keyboard. The board (phase 4) walks its cards on its
    // own focus node, and this handler runs BEFORE the widget tree — so
    // without the guard, Delete on a board card deleted the whole board and
    // P while choosing a card switched to the pen.
    if (!_selectedTypeable && app.editingBlockId == null) {
      if (k == LogicalKeyboardKey.keyV) return _tool(Tool.select);
      if (k == LogicalKeyboardKey.keyT) return _tool(Tool.text);
      if (k == LogicalKeyboardKey.keyP) return _tool(Tool.pen);
      if (k == LogicalKeyboardKey.keyH) return _tool(Tool.highlighter);
      if (k == LogicalKeyboardKey.keyE) return _tool(Tool.eraser);
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      if (app.editingBlockId == null && app.selectedIds.isNotEmpty) {
        app.removeSelected();
        return true;
      }
    }
    return false;
  }

  // ── Block traversal (v0.16 phase 2) ────────────────────────────────────
  //
  // Tab/Enter/arrows do NOT go through the global handler above: a
  // HardwareKeyboard handler's `true` does not stop the framework's own
  // Shortcuts, so consuming arrows globally left Flutter's directional
  // focus walk running in parallel — three arrow presses in, focus had
  // crept into the sidebar search box and traversal went dead (caught by
  // the phase-2 tests). Instead the canvas subtree owns a focus node and
  // overrides those keys with its own Shortcuts, which wins by
  // nearest-ancestor and switches the framework walk off. Dialogs and
  // text fields keep native behaviour for free: they hold focus, so the
  // canvas shortcuts are not on the focus path at all.

  final FocusNode _canvasFocus =
      FocusNode(debugLabel: 'canvas-traversal', skipTraversal: true);

  Widget _canvasKeys(Widget canvas) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.tab): _TraverseIntent(1),
        SingleActivator(LogicalKeyboardKey.tab, shift: true):
            _TraverseIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _SpatialIntent(-1, 0),
        SingleActivator(LogicalKeyboardKey.arrowRight): _SpatialIntent(1, 0),
        SingleActivator(LogicalKeyboardKey.arrowUp): _SpatialIntent(0, -1),
        SingleActivator(LogicalKeyboardKey.arrowDown): _SpatialIntent(0, 1),
        SingleActivator(LogicalKeyboardKey.enter): _EditIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _EditIntent(),
        // Nudges live here too, not in the global handler: with the canvas
        // focused, an unclaimed Ctrl+arrow falls through to the framework's
        // default ScrollAction, which asserts when more than one primary
        // scrollable exists (the sidebar and the page both do).
        SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            _NudgeIntent(-1, 0, fine: false),
        SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            _NudgeIntent(1, 0, fine: false),
        SingleActivator(LogicalKeyboardKey.arrowUp, control: true):
            _NudgeIntent(0, -1, fine: false),
        SingleActivator(LogicalKeyboardKey.arrowDown, control: true):
            _NudgeIntent(0, 1, fine: false),
        SingleActivator(LogicalKeyboardKey.arrowLeft,
            control: true, shift: true): _NudgeIntent(-1, 0, fine: true),
        SingleActivator(LogicalKeyboardKey.arrowRight,
            control: true, shift: true): _NudgeIntent(1, 0, fine: true),
        SingleActivator(LogicalKeyboardKey.arrowUp,
            control: true, shift: true): _NudgeIntent(0, -1, fine: true),
        SingleActivator(LogicalKeyboardKey.arrowDown,
            control: true, shift: true): _NudgeIntent(0, 1, fine: true),
      },
      child: Actions(
        // _CanvasAction gates every binding on THE CANVAS NODE ITSELF
        // holding focus. Without the gate, these Shortcuts sit between
        // every editor on the canvas and the app root, and nearest-ancestor
        // means they shadow the editors' own keys — the field bugs Eric
        // hit: arrows while editing jumped BOXES instead of moving the
        // caret, and Enter was eaten instead of making a new line. A
        // disabled action makes the ShortcutManager report the key
        // unhandled, so it bubbles on to normal text editing.
        actions: {
          _TraverseIntent: _CanvasAction<_TraverseIntent>(
              _canvasFocus, (i) => _traverse(i.dir)),
          _SpatialIntent: _CanvasAction<_SpatialIntent>(
              _canvasFocus, (i) => _spatial(i.dx, i.dy)),
          _EditIntent:
              _CanvasAction<_EditIntent>(_canvasFocus, (_) => _editSelected()),
          _NudgeIntent: _CanvasAction<_NudgeIntent>(
              _canvasFocus,
              (i) => _nudge(i.dx.toDouble(), i.dy.toDouble(), fine: i.fine)),
        },
        // Pointer-down (not tap: it must run even when a drag follows)
        // routes focus to the canvas, so click-a-block-then-arrow works
        // when focus was in the sidebar or toolbar. An editor opening on
        // the same gesture wins afterwards — its request is post-frame.
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (app.editingBlockId == null) _canvasFocus.requestFocus();
          },
          child: Focus(
            focusNode: _canvasFocus,
            autofocus: true,
            onKeyEvent: _onCanvasKey,
            child: canvas,
          ),
        ),
      ),
    );
  }

  // ── Region cycling (v0.16 phase 3) ─────────────────────────────────────
  //
  // F6 / Shift+F6 walk the window's big areas: sidebar → toolbar → page →
  // open panel. This is the ONLY keyboard route to the toolbar or a panel:
  // the canvas binds Tab to block traversal (above), so Tab never leaves the
  // page, and `_canvasFocus` is `skipTraversal`, so once focus has left, Tab
  // cannot bring it back either. Everything in the toolbar and the panels
  // was already a focusable Material control — it was simply unreachable.
  //
  // F6 because it is the key every desktop already uses for this (Windows
  // Explorer's panes, every browser's address-bar/page cycle). A guessable
  // key beats a clever one; nobody has to be taught it twice.

  final FocusNode _sidebarRegion =
      FocusNode(debugLabel: 'region-sidebar', skipTraversal: true);
  final FocusNode _toolbarRegion =
      FocusNode(debugLabel: 'region-toolbar', skipTraversal: true);
  /// The object row. **Unconditional** — unlike the panel it is always
  /// built, so it is always a stop, and from the page one Shift+F6 lands on
  /// the maths palette.
  final FocusNode _objectRegion =
      FocusNode(debugLabel: 'region-object', skipTraversal: true);
  final FocusNode _panelRegion =
      FocusNode(debugLabel: 'region-panel', skipTraversal: true);

  /// Where F6 lands INSIDE the open panel — attached around the panel body by
  /// [SidePanel] (see [PanelEntryFocus]), never around the header.
  final FocusNode _panelEntry =
      FocusNode(debugLabel: 'region-panel-body', skipTraversal: true);

  /// The floating reminder stack — attached by [AlertPopup] itself, because
  /// a `Positioned` must be a direct child of its `Stack` and so cannot be
  /// wrapped from here.
  final FocusNode _alertRegion =
      FocusNode(debugLabel: 'region-alerts', skipTraversal: true);

  /// Which region wears the focus ring, or null for none.
  final ValueNotifier<_Region?> _ring = ValueNotifier<_Region?>(null);

  List<_Region> _regions() => [
        _Region.sidebar,
        _Region.toolbar,
        _Region.object,
        _Region.page,
        // Asked of the focus tree rather than re-derived from the build's
        // conditions: a panel that is open but not currently BUILT (outline
        // and links need a page) must not be a stop that swallows F6.
        if (_panelRegion.context != null) _Region.panel,
        // Last, and only while a reminder is actually showing: it is a
        // transient card, not a place you live.
        if (_alertRegion.context != null) _Region.alerts,
      ];

  FocusNode _regionNode(_Region r) => switch (r) {
        _Region.sidebar => _sidebarRegion,
        _Region.toolbar => _toolbarRegion,
        _Region.object => _objectRegion,
        _Region.page => _canvasFocus,
        _Region.panel => _panelRegion,
        _Region.alerts => _alertRegion,
      };

  /// `hasFocus`, not `hasPrimaryFocus`: a block editor deep inside the canvas
  /// still means "you are on the page".
  _Region? _currentRegion() =>
      _regions().where((r) => _regionNode(r).hasFocus).firstOrNull;

  bool _cycleRegion(int dir) {
    if (_routeOnTop) return false;
    final regions = _regions();
    if (regions.length < 2) return false;
    final cur = _currentRegion();
    // Focus nowhere we recognise (a snackbar, a just-closed dialog): step in
    // from the near end rather than doing nothing.
    final i = cur == null ? (dir > 0 ? -1 : 0) : regions.indexOf(cur);
    final next = regions[(i + dir + regions.length) % regions.length];
    if (next == _Region.page) {
      // The canvas node is skipTraversal, so it is never a candidate below —
      // and it is the right target anyway: focusing it is what turns block
      // traversal back on.
      _canvasFocus.requestFocus();
    } else {
      _focusFirstIn(next == _Region.panel && _panelEntry.context != null
          ? _panelEntry
          : _regionNode(next));
    }
    _ring.value = next;
    return true;
  }

  /// Focus the first control in [region], in READING ORDER — the same
  /// y-then-x rule the canvas traverses blocks by, so "first" means the same
  /// thing everywhere in the app.
  ///
  /// Not `traversalDescendants.first`: that list is built post-order (a
  /// node's children are added before the node itself), so its first entry is
  /// the most deeply nested widget rather than the top-left one. In the study
  /// panel that is a grade button, and the Space that should have revealed a
  /// card would have graded one the reader had not seen.
  void _focusFirstIn(FocusNode region) {
    final candidates = region.traversalDescendants
        .where((n) => !n.rect.isEmpty)
        .toList()
      ..sort((a, b) {
        final dy = a.rect.top.compareTo(b.rect.top);
        return dy != 0 ? dy : a.rect.left.compareTo(b.rect.left);
      });
    (candidates.firstOrNull ?? region).requestFocus();
  }

  /// The ring tracks focus rather than only the F6 press: click away, or Tab
  /// out of the region, and the marker stops claiming you are still there.
  void _regionFocusChanged() {
    final r = _ring.value;
    if (r != null && !_regionNode(r).hasFocus) _ring.value = null;
  }

  /// Marks a region for F6 and paints its ring.
  ///
  /// The ring is an OVERLAY inside the region, not a border on it: a border
  /// would resize the child, and a two-pixel reflow of the canvas moves the
  /// line you are reading. It is drawn only for keyboard navigation and
  /// cleared by the next click — the rule the web's `:focus-visible` follows,
  /// because a permanent outline around whatever you last clicked is noise.
  Widget _regionWrap(_Region r, Widget child) {
    final marked = r == _Region.page
        ? child // the canvas already owns _canvasFocus, one node one Focus
        : Focus(focusNode: _regionNode(r), skipTraversal: true, child: child);
    return Stack(
      // `passthrough`, so wrapping a region cannot change its size. The
      // default `loose` would hand the canvas — which arrives with TIGHT
      // constraints from its `Expanded` — loose ones instead, and a page
      // that sized itself to its content rather than to the window is not a
      // focus ring, it is a layout bug wearing one.
      fit: StackFit.passthrough,
      children: [
      marked,
      Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<_Region?>(
            valueListenable: _ring,
            builder: (context, active, _) => active != r
                ? const SizedBox.shrink()
                : DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2),
                    ),
                  ),
          ),
        ),
      ),
    ]);
  }

  /// The one open panel, or null. A single switch rather than five `if`s in
  /// the Row so the F6 marker is applied in exactly one place — a panel that
  /// grew its own `if` would quietly drop out of the rotation.
  Widget? _openPanel(TreeNode? page) => switch (app.openPanel) {
        SidePanelKind.study => StudyPanel(app: app),
        SidePanelKind.planner => PlannerPanel(app: app),
        SidePanelKind.tags => _TagsPanel(app: app),
        SidePanelKind.outline => page == null ? null : _TocPanel(app: app),
        SidePanelKind.links => page == null ? null : _LinksPanel(app: app),
        null => null,
      };

  /// True when any route (dialog, viewer, menu) sits above the shell. The
  /// global handler fires regardless, so every canvas-traversal key checks
  /// this — Tab must not move block selection behind an open dialog.
  bool get _routeOnTop =>
      _shortcutsOpen ||
      !mounted ||
      Navigator.of(context, rootNavigator: true).canPop();

  /// Blocks in reading order — THE order, the same y-then-x sort the
  /// Markdown export and the MCP read_page projection use. Ink is skipped:
  /// selecting a stroke cluster by Tab helps nobody.
  List<Block> _traversable() =>
      app.blocks.where((b) => b.type != BlockType.ink).toList()
        ..sort((a, b) {
          final dy = a.y.compareTo(b.y);
          return dy != 0 ? dy : a.x.compareTo(b.x);
        });

  bool _traverse(int dir) {
    if (_routeOnTop) return false;
    final order = _traversable();
    if (order.isEmpty) return false;
    final cur = order.indexWhere((b) => b.id == app.selectedBlockId);
    final next = cur < 0
        ? (dir > 0 ? order.first : order.last)
        : order[(cur + dir + order.length) % order.length];
    app.select(next.id);
    return true;
  }

  bool _editSelected() {
    if (_routeOnTop) return false;
    final id = app.selectedBlockId;
    if (id == null || app.editingBlockId != null) return false;
    app.select(id, edit: true);
    return true;
  }

  /// Nearest block in the pressed direction, centre to centre, with drift
  /// off-axis costing double — the standard directional-navigation score.
  bool _spatial(int dx, int dy) {
    if (_routeOnTop) return false;
    final order = _traversable();
    if (order.isEmpty) return false;
    final cur =
        order.where((b) => b.id == app.selectedBlockId).firstOrNull;
    if (cur == null) {
      app.select(order.first.id);
      return true;
    }
    Offset centre(Block b) => Offset(b.x + b.w / 2, b.y + (b.h ?? 80) / 2);
    final c0 = centre(cur);
    Block? best;
    var bestScore = double.infinity;
    for (final b in order) {
      if (b.id == cur.id) continue;
      final c = centre(b);
      final along = (c.dx - c0.dx) * dx + (c.dy - c0.dy) * dy;
      if (along <= 0) continue;
      final cross = (dx != 0 ? (c.dy - c0.dy) : (c.dx - c0.dx)).abs();
      final score = along + cross * 2;
      if (score < bestScore) {
        bestScore = score;
        best = b;
      }
    }
    // At the edge with nothing further: still consumed, so the keystroke
    // can't fall through and wander the widget focus tree.
    if (best != null) app.select(best.id);
    return true;
  }

  /// A single selected block that accepts typing — the condition under
  /// which a bare letter means "write" rather than "switch tool".
  bool get _selectedTypeable {
    if (app.selectedIds.length != 1 || app.editingBlockId != null) {
      return false;
    }
    final t = app.blocks
        .where((x) => x.id == app.selectedBlockId)
        .firstOrNull
        ?.type;
    return t == BlockType.text || t == BlockType.code;
  }

  /// Type-through (Eric: "if i tap a key on my keyboard it should put me
  /// into editing mode, chuck me at the end of the box and put that
  /// character in"). Runs on the canvas focus node, so it exists exactly
  /// when a block is selected but nothing is being edited.
  KeyEventResult _onCanvasKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch == null || ch.isEmpty) return KeyEventResult.ignored;
    // Control characters and chords are someone else's business.
    if (ch.codeUnits.every((u) => u < 0x20)) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (app.selectedIds.length != 1 || app.editingBlockId != null) {
      return KeyEventResult.ignored;
    }
    final b =
        app.blocks.where((x) => x.id == app.selectedBlockId).firstOrNull;
    if (b == null ||
        (b.type != BlockType.text && b.type != BlockType.code)) {
      return KeyEventResult.ignored;
    }
    app.select(b.id, edit: true); // no caret token → the editor opens at
    _typeThrough(b.id, ch, tries: 8); // the end, which is the intent here
    return KeyEventResult.handled;
  }

  /// Deliver the typed character once the editor exists. The editor builds
  /// a frame (or two) after select(edit:true); it registers its controller
  /// via setActiveEditor, which is the delivery address.
  void _typeThrough(String id, String ch, {required int tries}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || app.editingBlockId != id) return;
      final ed = app.activeEditor;
      if (ed == null || ed.block.id != id) {
        if (tries > 0) _typeThrough(id, ch, tries: tries - 1);
        return;
      }
      final c = ed.controller;
      final sel = c.selection;
      final at = sel.isValid ? sel.start : c.text.length;
      final end = sel.isValid ? sel.end : c.text.length;
      c.value = c.value.copyWith(
        text: c.text.replaceRange(at, end, ch),
        selection: TextSelection.collapsed(offset: at + ch.length),
      );
      // Through the same write the editor's own onChanged would do.
      ed.block.content[ed.contentKey] = c.text;
      ed.block.updatedAt = nowMs();
      app.markDirty();
    });
  }

  /// One undo entry per nudge BURST, not per keypress — holding an arrow is
  /// one movement the way one drag is, and pausing ~a second starts a new
  /// undoable step.
  int _lastNudgeMs = 0;
  bool _nudge(double dx, double dy, {required bool fine}) {
    if (_routeOnTop) return false;
    if (app.selectedIds.isEmpty) return false;
    final step = fine ? 1.0 : (app.effectiveSnap ? app.gridSize : 8.0);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNudgeMs > 900) app.pushUndo();
    _lastNudgeMs = now;
    app.moveSelectedBy(dx * step, dy * step);
    for (final b in app.blocks.where((b) => app.selectedIds.contains(b.id))) {
      app.clampBlockToPage(b);
    }
    return true;
  }

  void _toggleShortcutOverlay() {
    if (_shortcutsOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      return;
    }
    _shortcutsOpen = true;
    unawaited(showShortcutOverlay(context)
        .whenComplete(() => _shortcutsOpen = false));
  }

  bool _tool(Tool t) {
    app.setTool(t);
    return true;
  }

  /// Ctrl+PageDown / Ctrl+PageUp — the next/previous page in the active
  /// section, in the navigator's visible order. OneNote's own chords.
  /// Clamped at the ends rather than wrapping: wrapping silently teleports
  /// you from the last page to the first, which reads as "it jumped".
  bool _cyclePage(int dir) {
    final sec = app.activeSectionId;
    if (sec == null) return false;
    final pages = app.pagesOf(sec);
    if (pages.isEmpty) return false;
    final i = pages.indexWhere((n) => n.id == app.pageId);
    final next = pages[(i + dir).clamp(0, pages.length - 1)];
    if (next.id != app.pageId) app.selectPage(next.id);
    return true;
  }

  /// Ctrl+Tab / Ctrl+Shift+Tab — the next/previous section. Wrapping IS right
  /// here: cycling a ring of sections is the mental model, same as browser
  /// tabs.
  bool _cycleSection(int dir) {
    final secs =
        app.nodes.where((n) => n.kind == NodeKind.section).toList();
    if (secs.isEmpty) return false;
    var i = secs.indexWhere((n) => n.id == app.activeSectionId);
    if (i < 0) i = 0;
    app.activateSection(secs[(i + dir + secs.length) % secs.length].id);
    return true;
  }

  /// Ctrl+V while the caret is in a text box, when the clipboard holds an
  /// image: splice an in-flow reference at the caret.
  ///
  /// Deliberately fire-and-forget and never blocking: the keystroke is passed
  /// through to Flutter's own paste regardless, so a clipboard with both an
  /// image and text still pastes the text if the image read fails. In the
  /// normal case the image read wins the race by a frame and the text branch
  /// finds nothing to do.
  Future<void> _pasteImageIntoEditor() async {
    final ae = app.activeEditor;
    if (ae == null) return;
    final bytes = await readClipboardImage();
    if (bytes == null || !mounted) return;
    if (app.activeEditor?.block.id != ae.block.id) return; // moved on
    // `tryAddBlob`: this path is fire-and-forget by design (see above), which
    // is exactly where a throwing `writeBlob` — full disk, read-only folder —
    // used to disappear without a word. The status bar now says so, and no
    // reference to unstored bytes is spliced into the text.
    final hash = app.tryAddBlob(bytes.bytes, bytes.mime);
    if (hash == null) return;
    app.insertTextAtActiveCursor('\n![](sha256:$hash)\n');
    ae.block.content['autoWidth'] = false;
  }

  /// Ctrl+V on the canvas: system clipboard media if there is any, else our
  /// own copied blocks.
  Future<void> _pasteFromSystemOrBlocks() async {
    final at = app.canvas.screenToPage(Offset(
        app.canvas.viewport.width / 2, app.canvas.viewport.height / 2));
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Images and files keep first claim — a screenshot just taken must beat
    // a block copied minutes ago (the comment at the Ctrl+V key handler).
    // But when the system offers ONLY plain text, that text can be the OLDER
    // of the two: cutting an equation block and pasting used to resurrect
    // the `$…$` its own Ctrl+C had left on the system clipboard, instead of
    // the block just cut. So look before pasting, and let the newer
    // clipboard win.
    final probe = await probeClipboard();
    if (probe.kind == PasteResult.text &&
        await app.blockClipboardIsNewer(probe.text)) {
      app.pasteBlocks();
      return;
    }
    final result = await pasteOntoCanvas(app, at, dark: dark);
    if (result == PasteResult.nothing && app.canPasteBlocks) {
      app.pasteBlocks();
    }
  }

  /// Memoised navigator. The whole shell sits under one `ListenableBuilder`, so
  /// *every* notify — each keystroke (`markDirty`), each drag frame — used to
  /// rebuild the navigator too: three `nodes.where(...)` scans plus a nested
  /// per-group scan, and a fresh `_PageTile` (`DragTarget` + `Draggable` +
  /// `InkWell`) for every visible page. Returning the identical widget when
  /// nothing the navigator displays has changed lets Flutter skip that subtree
  /// entirely (§7a.6 keystroke-to-paint budget).
  Widget? _navCache;
  List<Object?>? _navKey;

  Widget _navigator() {
    final key = <Object?>[
      app.nodesRevision,
      app.pageId,
      app.activeSectionId,
      app.notebookId,
      app.notebooks.length,
      // The two-column layout's own state. Every piece of state the navigator
      // RENDERS must appear here, or the change paints only after something
      // else happens to invalidate the memo — a stale-not-broken failure that
      // passes a quick smoke test and fails in real use.
      app.navCollapsed,
      app.navSectionsW,
      app.navPagesW,
      app.navHome,
      // Collapse toggles, favourites, Home — bumped explicitly. A counter and
      // not the sets' lengths, because one collapse plus one expand between
      // frames leaves the length identical while the CONTENTS changed.
      app.navRevision,
    ];
    final cached = _navCache;
    if (cached != null && _navKey != null && _listEq(_navKey!, key)) {
      return cached;
    }
    _navKey = key;
    return _navCache = Sidebar(app: app);
  }

  static bool _listEq(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final page = app.nodes.where((n) => n.id == app.pageId).firstOrNull;
        final panel = _openPanel(page);
        return Scaffold(
          // A `Stack`, so a reminder floats OVER the page rather than pushing
          // it. An alert that reflowed the canvas would move the line you were
          // typing on, which is a worse interruption than the one it is
          // delivering.
          // Any click means "I am steering with the mouse now", so the F6
          // ring stops advertising a region the user has left. `deferToChild`
          // so this changes no hit testing — it only listens on the way past.
          body: Listener(
            onPointerDown: (_) => _ring.value = null,
            child: Stack(children: [
            Row(
            children: [
              _regionWrap(_Region.sidebar, _navigator()),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    _regionWrap(_Region.toolbar, CommandBar(app: app)),
                    // **The object row**, permanent and always 36 px.
                    //
                    // Permanent because a band that appeared with the
                    // equation would push the page down and putting the page
                    // back is a pan the canvas controller discards on a short
                    // or zoomed-out page — so the page would jump exactly
                    // where a student most often starts an equation. See
                    // `object_row.dart`; the chrome is 112 px in every state
                    // of the app and the canvas box never moves.
                    _regionWrap(_Region.object, ObjectRow(app: app)),
                    if (app.findOpen) _FindBar(app: app),
                    // The breadcrumb is CONTEXT, not a second navigator
                    // (§7d). With the navigator expanded it repeats what is
                    // already on screen two inches to the left, so it spends a
                    // full-width row saying nothing. Collapsed — or on the
                    // rail — it is the only place the notebook and section are
                    // named, and it earns the row.
                    if (page != null && app.navCollapsed)
                      _PageHeader(app: app, page: page),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            // The gate is HERE, at the point the canvas would
                            // be built, rather than only on the click that
                            // opened the page. A page can become locked while
                            // it is on screen — the policy expires, or "Lock
                            // now" is pressed — and gating only the click
                            // would leave the content sitting there.
                            child: _regionWrap(
                                _Region.page,
                                page == null
                                    ? _EmptyState(app: app)
                                    : app.isLocked(page.id)
                                        ? _LockedPage(app: app, page: page)
                                        : _canvasKeys(PageCanvas(
                                            key: ValueKey(app.pageId),
                                            state: app))),
                          ),
                          if (panel != null) ...[
                            const VerticalDivider(width: 1),
                            PanelEntryFocus(
                              node: _panelEntry,
                              child: _regionWrap(_Region.panel, panel),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _StatusBar(app: app),
                  ],
                ),
              ),
            ],
          ),
            AlertPopup(app: app, regionFocus: _alertRegion),
            ImportProgressCard(app: app),
          ]),
          ),
        );
      },
    );
  }
}

/// Find-on-page bar (TEXT-7): live matches, next/prev cycles & centers.
class _FindBar extends StatefulWidget {
  const _FindBar({required this.app});
  final AppState app;

  @override
  State<_FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<_FindBar> {
  AppState get app => widget.app;

  /// Replace is opt-in: a permanently visible replace field doubles the height
  /// of the bar for a job most searches don't want.
  bool _showReplace = false;
  final _replaceCtl = TextEditingController();

  @override
  void dispose() {
    _replaceCtl.dispose();
    super.dispose();
  }

  void _replace({required bool all}) {
    final n = app.replaceAll(app.findQuery, _replaceCtl.text,
        onlyCurrent: !all);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'Nothing replaced'
            : 'Replaced $n occurrence${n == 1 ? '' : 's'}')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _findRow(context),
      if (_showReplace) _replaceRow(context),
    ]);
  }

  Widget _replaceRow(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border:
              Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(children: [
          const SizedBox(width: 24),
          Expanded(
            child: TextField(
              controller: _replaceCtl,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Replace with…',
              ),
              style: const TextStyle(fontSize: 13),
              onSubmitted: (_) => _replace(all: false),
            ),
          ),
          TextButton(
            onPressed: app.findMatches.isEmpty ? null : () => _replace(all: false),
            child: const Text('Replace', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: app.findMatches.isEmpty ? null : () => _replace(all: true),
            child: const Text('All', style: TextStyle(fontSize: 12)),
          ),
        ]),
      );

  Widget _findRow(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16),
          const SizedBox(width: 8),
          Expanded(
            // Enter and Shift+Enter walk the matches — forward and back, the
            // convention every browser and editor already uses.
            //
            // Shortcuts, NOT `onSubmitted`, and that is a fix rather than a
            // style choice. A single-line field's Enter arrives as
            // `TextInputAction.done`, and `EditableText._finalizeEditing`
            // UNFOCUSES the field for it — so Enter jumped to match 2 and
            // then killed its own field, and a second Enter did nothing at
            // all. Catching the key here means the field keeps focus, Enter
            // keeps cycling, and you can still edit the query afterwards.
            // `onSubmitted` also cannot tell Enter from Shift+Enter.
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): () =>
                    app.findNext(1),
                const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                    app.findNext(1),
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    () => app.findNext(-1),
              },
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Find on this page…',
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: app.setFindQuery,
              ),
            ),
          ),
          Text(
            app.findMatches.isEmpty
                ? (app.findQuery.isEmpty ? '' : 'No matches')
                : '${app.findIndex + 1} of ${app.findMatches.length}',
            style: TextStyle(fontSize: 12, color: context.surfaces.textSecondary),
          ),
          // The two buttons that had no tooltip at all: the chord is the
          // faster route and the button is where anyone would look for it.
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous match (Shift+Enter)',
            onPressed: app.findMatches.isEmpty ? null : () => app.findNext(-1),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Next match (Enter)',
            onPressed: app.findMatches.isEmpty ? null : () => app.findNext(1),
          ),
          IconButton(
            icon: Icon(
                _showReplace ? Icons.find_replace : Icons.find_replace_outlined,
                size: 18),
            visualDensity: VisualDensity.compact,
            isSelected: _showReplace,
            tooltip: 'Replace',
            onPressed: () => setState(() => _showReplace = !_showReplace),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Close (Esc)',
            onPressed: app.toggleFind,
          ),
        ],
      ),
    );
  }
}

/// Slim breadcrumb — the editable TITLE lives in the page itself.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.app, required this.page});
  final AppState app;
  final TreeNode page;

  @override
  Widget build(BuildContext context) {
    final section = app.node(page.parentId ?? '');
    final notebook =
        app.notebooks.firstWhere((n) => n.id == app.notebookId);
    final crumbStyle =
        TextStyle(fontSize: 12, color: context.surfaces.textSecondary);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Text(notebook.title, style: crumbStyle),
          if (section != null) ...[
            Text('  ›  ', style: crumbStyle),
            Text(section.title, style: crumbStyle),
          ],
        ],
      ),
    );
  }
}

/// Right-side links panel: incoming backlinks + outgoing links (TEXT-8).
/// Find tags (TEXT-5): every tagged line in the notebook, grouped by tag.
///
/// This is half the value of tags in OneNote — marking a line is only useful
/// if you can later ask "what did I mark?". Scanning page mirrors rather than
/// maintaining an index, for the same reason as notebook-wide search: one
/// source of truth beats an index that can silently drift.
class _TagsPanel extends StatelessWidget {
  const _TagsPanel({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final all = app.allTags();
    final byKind = <TagKind, List<TaggedLine>>{};
    for (final e in all) {
      byKind.putIfAbsent(e.tag.kind, () => []).add(e);
    }
    return SidePanel(
      title: SidePanelKind.tags.label,
      icon: Icons.label_outline,
      onClose: app.closePanel,
      child: all.isEmpty
          ? PanelEmpty(
              headline: 'No tags in this notebook yet.',
              body: 'Tags mark a line — to do, important, question, '
                  'definition — so you can find it again, revise from it, or '
                  'give it a deadline.',
              actions: [
                PanelAction(
                    icon: Icons.label_outline,
                    label: 'Tag the line you are on',
                    onTap: () => app.toggleTagOnSelection(TagKind.todo)),
              ],
            )
          : ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final kind in byKind.keys)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                          child: Row(children: [
                            Icon(kind.icon, size: 16, color: kind.color),
                            const SizedBox(width: 5),
                            Text('${kind.label}  (${byKind[kind]!.length})',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        for (final e in byKind[kind]!)
                          InkWell(
                            onTap: () => app.selectPage(e.pageId),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(30, 3, 12, 3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      e.text.isEmpty ? '(empty line)' : e.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12,
                                          decoration:
                                              (e.tag.checked ?? false)
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                          color: (e.tag.checked ?? false)
                                              ? context.surfaces.textSecondary
                                              : null)),
                                  Text(e.pageTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: context.surfaces.textSecondary)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
    );
  }
}

/// Page outline (TEXT-10): the current page's headings, click to jump.
///
/// Deliberately derived from the Markdown rather than stored: a heading IS
/// `# text` in a text block, so an outline that could disagree with the page
/// would be a second source of truth for no gain.
class _TocPanel extends StatelessWidget {
  const _TocPanel({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final items = app.pageOutline();
    return SidePanel(
      title: SidePanelKind.outline.label,
      icon: Icons.toc,
      onClose: app.closePanel,
      child: items.isEmpty
          ? const PanelEmpty(
              headline: 'No headings on this page.',
              body: 'Start a line with # to make a heading — the outline '
                  'follows the page, so there is nothing separate to keep up '
                  'to date.',
            )
          : ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i];
                  return InkWell(
                    onTap: () => app.jumpToBlock(it.blockId),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          12.0 + (it.level - 1) * 14.0, 5, 12, 5),
                      child: Text(
                        it.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: it.level == 1 ? 13 : 12,
                          fontWeight: it.level == 1
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                },
              ),
    );
  }
}

class _LinksPanel extends StatelessWidget {
  const _LinksPanel({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final backlinks = app.backlinksForCurrent();
    final outgoing = app.outgoingLinksForCurrent();

    Widget section(String label, IconData icon, List<TreeNode> pages,
        String empty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                OnoteSpace.x5, OnoteSpace.x5, OnoteSpace.x5, OnoteSpace.x1),
            child: Row(children: [
              Icon(icon,
                  size: OnoteIcon.sm, color: context.surfaces.textSecondary),
              const SizedBox(width: OnoteSpace.x3),
              Expanded(
                child: Text(label.toUpperCase(),
                    style: OnoteType.overline
                        .copyWith(color: context.surfaces.textSecondary)),
              ),
              // A plain count, not a badge: a badge in a list header is
              // decoration, and this number is never actionable (§7e).
              Text('${pages.length}',
                  style: OnoteType.caption
                      .copyWith(color: context.surfaces.textSecondary)),
            ]),
          ),
          if (pages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Text(empty,
                  style:
                      TextStyle(fontSize: 12, color: context.surfaces.textSecondary)),
            )
          else
            for (final p in pages)
              InkWell(
                onTap: () => app.selectPage(p.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    Icon(Icons.description_outlined,
                        size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(p.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13))),
                  ]),
                ),
              ),
        ],
      );
    }

    return SidePanel(
      title: SidePanelKind.links.label,
      icon: Icons.account_tree_outlined,
      onClose: app.closePanel,
      child: ListView(
        children: [
          section('Linked from', Icons.call_received, backlinks,
              'No pages link here yet.'),
          const SizedBox(height: OnoteSpace.x4),
          section('Links to', Icons.call_made, outgoing,
              'This page links nowhere yet.'),
        ],
      ),
    );
  }
}

/// One line naming the loaded core's build, for the engine tooltip.
String _coreBuildLine() {
  final id = OnoteCore.instance?.buildId;
  if (id == null) {
    return 'This library predates the build stamp — it is an OLD core. '
        'Rebuild it (flutter build, or sync-core.bat on Windows) before '
        'trusting any importer or repair behaviour.';
  }
  final t = id.built.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  // The path matters as much as the timestamp: the loader picks the NEWEST of
  // several candidates, so "which file won" is half of any stale-library
  // question.
  final from = OnoteCore.loadedFrom;
  return 'Core built ${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)} from ${id.commit}.'
      '${from == null ? '' : '\nLoaded: $from'}';
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final saved = !app.hasUnsavedChanges;
    final rust = app.engineLabel.startsWith('Rust');
    final hash = app.pageContentHash;
    // A failed save must never read as "Saved" — it stays dirty and says so.
    //
    // The chip carries the SHORT form and the tooltip the whole sentence;
    // neither is allowed to contain the exception, which is what
    // `'${app.saveError}'` used to put on the status bar. Clicking opens the
    // dialog that keeps the technical half behind an Advanced fold.
    final problem = app.saveError;
    final failed = problem != null;
    return Container(
      height: 24,
      // Tighter at the trailing edge than the leading one, on purpose. The
      // left-hand cluster is a run of icon-and-label pairs whose glyphs need
      // breathing room from the frame; the right-hand end is the shortcut
      // cheat-sheet, which is a single line of text and reads as *detached*
      // when it floats 12px in from the window edge — the "the UI doesn't
      // reach the sides" complaint. 6px is the optical match.
      padding: const EdgeInsets.only(left: OnoteSpace.x5, right: OnoteSpace.x3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: failed
                ? '${problem.message}\n\nMore detail.'
                : saved
                    ? 'This page is saved to your local .onote file.'
                    : 'Saving…',
            child: MouseRegion(
              cursor: failed ? SystemMouseCursors.click : MouseCursor.defer,
              child: GestureDetector(
                onTap:
                    failed ? () => showSaveProblemDialog(context, problem) : null,
                child: Row(children: [
                  Icon(
                      failed
                          ? Icons.error_outline
                          : saved
                              ? Icons.check_circle_outline
                              : Icons.sync,
                      size: OnoteIcon.sm,
                      color: failed
                          ? OnoteColors.danger
                          : saved
                              ? OnoteColors.success
                              : context.surfaces.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                      failed
                          ? problem.short
                          : saved
                              ? 'Saved on this device'
                              : 'Saving…',
                      style: TextStyle(
                          fontSize: 11,
                          color: failed
                              ? OnoteColors.danger
                              : context.surfaces.textSecondary)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Sync (ADR-0006). Shown only once a second device has touched this
          // notebook — until then there is nothing to say, and a permanent
          // "1 device" chip would be noise.
          if (app.notebookId != null) _SyncChip(app: app),
          // Background housekeeping, when there is any. Nothing to click and
          // nothing to decide — it says what is happening and goes away.
          // "Without requiring direct input" is not the same as "in secret":
          // a notebook that quietly rewrites itself is alarming if you notice.
          if (app.housekeepingNote != null) ...[
            const SizedBox(width: 10),
            Text(app.housekeepingNote!,
                style: TextStyle(
                    fontSize: 11, color: context.surfaces.textSecondary)),
          ],
          const SizedBox(width: 12),
          // Active compute engine (§ADR-0002): green chip when the Rust core
          // is linked, with the live page content-hash it computed on save.
          //
          // DEBUG BUILDS ONLY. The stale-library trap this chip exists for
          // is a developer problem; a student reading "Rust · a3f9c210"
          // learns nothing except that the app is talking to itself. The
          // user-facing health signals (saved state, sync) stay.
          if (kDebugMode)
            Tooltip(
            // The build stamp is here because the stale-library trap keeps
            // costing real time: the app loads a compiled artefact, so being on
            // the right branch says nothing about what is actually running.
            // Importer and repair fixes live in that library, so "I pulled and
            // it still does the old thing" is answered by reading this line.
            message: rust
                ? 'The Rust core (onote-core) is linked and computing this '
                    "page's content hash on save.\n${_coreBuildLine()}"
                : 'Running the pure-Dart engine. Build the onote-core library '
                    'to link the Rust core.',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.memory,
                  size: 16,
                  color: rust ? OnoteColors.success : context.surfaces.textSecondary),
              const SizedBox(width: 4),
              Text(
                rust && hash != null && hash.length >= 8
                    ? '${app.engineLabel} · ${hash.substring(0, 8)}'
                    : app.engineLabel,
                style: TextStyle(
                    fontSize: 11,
                    color: rust ? OnoteColors.success : context.surfaces.textSecondary),
              ),
            ]),
          ),
          // The cheat-sheet (§7a.4), dropped whole rather than ellipsised
          // (§7d). Truncating it produces "V select · T text · P pen · H…",
          // which is not a shorter version of the message — it is a different,
          // useless one, and it also drags the state cluster on its left into
          // truncation with it. Below the threshold the shortcuts are still on
          // every button's tooltip, which is where they are actually read.
          //
          // **One flex child, not a `Spacer` plus a `Flexible`.** That pairing
          // splits the free space evenly between them, so the measurement ran
          // against half the width the text was then allowed to occupy — the
          // text passed the fits-whole check and was clipped anyway, which is
          // precisely the outcome this widget exists to prevent. `Expanded` +
          // right alignment gives the measurement and the layout the same
          // number.
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _DropIfTight(
                text: 'V select · T text · P pen · H highlight · E erase · '
                    'Ctrl+Z undo · Ctrl+scroll zoom',
                style: OnoteType.caption
                    .copyWith(color: context.surfaces.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders [text] only when it fits whole, and nothing at all when it doesn't.
///
/// The status bar's rule (§7d): **drop, never truncate.** "V select · T text ·
/// P pen · H…" is not a shorter version of the cheat-sheet, it is a different
/// and useless message — and letting it ellipsise also drags the state cluster
/// beside it into competing for the same pixels.
///
/// Measured against the constraints this actually receives rather than against
/// the window width: the right-hand panel slot takes 320px out of the row, so
/// a window-width threshold is wrong exactly when a panel is open.
class _DropIfTight extends StatelessWidget {
  const _DropIfTight({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final tp = TextPainter(
            text: TextSpan(text: text, style: style),
            maxLines: 1,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          // A pixel of slack. `TextPainter` and the `Text` that follows it lay
          // out the same string with the same style, but they round
          // independently, and a sub-pixel disagreement at exactly the
          // threshold is the difference between "dropped cleanly" and "one
          // glyph sliced off at the window edge".
          if (tp.width > c.maxWidth - 1) return const SizedBox.shrink();
          return Text(text, style: style, maxLines: 1, softWrap: false);
        },
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories_outlined,
              size: OnoteIcon.xl, color: context.surfaces.textSecondary),
          const SizedBox(height: 12),
          const Text('An open page awaits',
              style: OnoteType.headline),
          const SizedBox(height: 6),
          Text(
            'Everything you make here lives on your device,\nin an open format you own.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.surfaces.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.note_add_outlined, size: 18),
            label: const Text('Create your first page'),
            onPressed: () => app.addPage(),
          ),
        ],
      ),
    );
  }
}

/// Sync state in the status bar.
///
/// Driven by [SyncStatus] — where the notebook LIVES — rather than by how many
/// devices have written logs. The old chip used the device count as a proxy,
/// so a notebook correctly placed in Google Drive still read "Not synced yet"
/// until a second machine appeared: the app disagreeing with what the user had
/// just successfully done.
class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final nb = app.notebookId!;
    final s = app.syncStatus(nb);
    final scheme = Theme.of(context).colorScheme;
    // Green once it is actually somewhere that syncs; grey when it is only on
    // this machine. The colour is the whole at-a-glance answer.
    final color = s.isSynced ? OnoteColors.success : context.surfaces.textSecondary;

    return Tooltip(
      message: syncChipTooltip(s),
      child: InkWell(
        onTap: () => showSyncDialog(context, app),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(s.icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(s.label, style: TextStyle(fontSize: 11, color: color)),
            // "Check now". Offered whenever this notebook is synced at all,
            // not only once a second device has appeared: a git-synced
            // notebook had no manual pull anywhere in the app, and the moment
            // someone most wants one is right after setting a second machine
            // up — which is precisely when the device count is still 1.
            if (s.isSynced) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: app.gitBusy
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        // Through git when git is what syncs this notebook:
                        // `syncPull` only reads what is already on disk, so on
                        // its own it would report "already up to date" without
                        // ever having asked the remote.
                        final n = s.gitRemote != null
                            ? await app.syncGitNow()
                            : await app.syncPull(nb);
                        messenger.showSnackBar(SnackBar(
                            content: Text(n == 0
                                ? 'Already up to date.'
                                : 'Pulled $n change${n == 1 ? '' : 's'}.')));
                      },
                child: Icon(Icons.refresh, size: 16, color: scheme.primary),
              ),
            ],
          ]),
        ),
      ),
    );
  }

// The chip's tooltip lives in `sync_dot.dart` as `syncChipTooltip`. It was a
// private method on this private widget, which is why nothing could reach it
// — and it was the `folder!` that survived two rounds of fixing the same bug
// elsewhere and took the status bar down on the first frame.
}

/// What stands in for a locked page's content.
///
/// Deliberately says what the lock is and is not, in one line, where someone
/// who set it a month ago will read it — the setting dialog's fuller warning
/// is long gone by then. A lock screen that implies more protection than
/// exists is the same lie told later.
class _LockedPage extends StatelessWidget {
  const _LockedPage({required this.app, required this.page});

  final AppState app;
  final TreeNode page;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final root = app.governingNode(page.id);
    final rootTitle =
        app.nodes.where((n) => n.id == root).firstOrNull?.title ?? page.title;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: scheme.primary),
            const SizedBox(height: 14),
            Text('“$rootTitle” is locked',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Enter the passcode to read it. This hides the page inside '
              'Openote — it is not encrypted, so anyone with the notebook '
              'file can still read it.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.lock_open_outlined, size: 18),
              label: const Text('Unlock'),
              onPressed: () => promptUnlock(context, app, page.id),
            ),
          ],
        ),
      ),
    );
  }
}

/// The window's big areas, in the order F6 walks them — which is the order
/// they are read on screen: left, top, middle, right.
enum _Region { sidebar, toolbar, object, page, panel, alerts }

/// An action that exists only while the canvas node itself is focused —
/// the moment focus moves into any editor (or anywhere else), it reports
/// disabled and the keystroke bubbles on to whoever actually owns it.
class _CanvasAction<T extends Intent> extends CallbackAction<T> {
  _CanvasAction(this.node, OnInvokeCallback<T> onInvoke)
      : super(onInvoke: onInvoke);
  final FocusNode node;

  @override
  bool isEnabled(T intent) => node.hasPrimaryFocus;
}

/// Canvas traversal intents (v0.16 phase 2). Private to the shell: the
/// canvas is the only surface that binds them, and the keyboard map is
/// where their meaning is documented.
class _TraverseIntent extends Intent {
  const _TraverseIntent(this.dir);
  final int dir;
}

class _SpatialIntent extends Intent {
  const _SpatialIntent(this.dx, this.dy);
  final int dx;
  final int dy;
}

class _EditIntent extends Intent {
  const _EditIntent();
}

class _NudgeIntent extends Intent {
  const _NudgeIntent(this.dx, this.dy, {required this.fine});
  final int dx;
  final int dy;
  final bool fine;
}
