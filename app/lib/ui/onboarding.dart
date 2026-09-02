/// First run: what the app IS, then how to get your notes into it.
///
/// **Why this exists, and why it is mostly pictures.** The welcome used to be
/// a single text dialog offering three ways to get notes IN — sync, OneNote
/// import, start fresh — and never said a word about what the app actually
/// does. That is the wrong half to explain. Getting notes in is discoverable
/// (it is in the notebook manager and in Settings ▸ Sync); the CANVAS is not:
/// nothing on an empty page tells you that clicking anywhere and typing is
/// the whole interaction, and a switcher who does not learn that in the first
/// ten seconds concludes the page is broken.
///
/// So: three short steps, each led by a drawing rather than a paragraph, and
/// the getting-notes-in choices kept intact as the last one. The drawings are
/// painted in code rather than shipped as images — they cost no assets, they
/// follow the light/dark palette exactly, and they cannot go stale against a
/// screenshot taken three versions ago. The first one ANIMATES, because the
/// thing it has to teach is a sequence (click, type, and only then a box),
/// which a still picture cannot say.
///
/// The second-device case still leads step three: it *looks* for the notebook
/// rather than asking where it is. If your cloud folder already has an Openote
/// notebook in it, that is almost certainly the answer, and the difference
/// between offering it and asking for a path is the difference between sync
/// working and sync being a thing you gave up on.
library;

import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../export/import_job.dart';
import '../export/onenote_import.dart' show OneNoteUnavailable;
import '../math/math_view.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';
import 'sync_dialog.dart';

/// Show the welcome flow if this workspace has never been used.
///
/// "Never been used" means: the setting has not been stamped AND the workspace
/// holds nothing but the starter notebook. Both conditions, because someone
/// who upgraded into this version has notebooks and must not be greeted as a
/// beginner.
Future<void> maybeShowOnboarding(BuildContext context, AppState app) async {
  if (app.onboardingSeen) return;
  final fresh = app.notebooks.length <= 1 &&
      app.nodes.where((n) => n.kind == NodeKind.page).length <= 1;
  app.markOnboardingSeen();
  if (!fresh || !context.mounted) return;
  await showOnboarding(context, app);
}

/// Also reachable from Settings ▸ Help, so skipping it is not permanent —
/// which is the only thing that makes "Skip" a fair offer.
Future<void> showOnboarding(BuildContext context, AppState app) =>
    showOnoteDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _Onboarding(app: app),
    );

class _Onboarding extends StatefulWidget {
  const _Onboarding({required this.app});
  final AppState app;

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding>
    with SingleTickerProviderStateMixin {
  AppState get app => widget.app;

  static const _steps = 3;
  int _step = 0;

  /// One pass of the click → type → box sequence on step one. Five seconds:
  /// long enough that each beat reads, short enough to come round again while
  /// someone is still looking at it.
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  /// **It plays twice and then rests on the finished frame**, rather than
  /// looping for as long as the dialog is open. Two reasons, and both matter:
  /// a demo that never stops is visual noise behind text somebody is trying
  /// to read, and an endlessly-repeating controller means the widget never
  /// settles — which hangs `pumpAndSettle`, so every test that opens this
  /// dialog would time out instead of asserting anything.
  static const _passes = 2;
  int _played = 0;

  /// The frame it rests on: box drawn, words in, before the loop's fade-out.
  static const _restFrame = 0.80;

  late final List<({String name, String path, dynamic folder})> _found =
      findExistingNotebooks()
          .map((e) => (name: e.name, path: e.path, folder: e.folder as dynamic))
          .toList();

  bool _oneNoteHelp = false;
  bool _importing = false;
  String? _error;

  /// The exception itself, shown only if the student asks for it.
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    _anim.addStatusListener(_onPass);
    _replay();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Play the sequence from the top again, and reset the count — coming back
  /// to step one deserves the demonstration, not the leftover final frame.
  void _replay() {
    _played = 0;
    _anim.forward(from: 0);
  }

  void _onPass(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (++_played < _passes) {
      _anim.forward(from: 0);
    } else {
      // Settles the controller as well as the picture: no ticker is left
      // running behind the words.
      _anim.value = _restFrame;
    }
  }

  /// The animation runs only while its own step is on screen — a dialog that
  /// keeps a ticker alive behind two other steps is a frame of work per frame
  /// for a picture nobody is looking at.
  void _goTo(int step) {
    setState(() => _step = step.clamp(0, _steps - 1));
    if (_step == 0) {
      _replay();
    } else {
      _anim.stop();
    }
  }

  Future<void> _open(String path) async {
    try {
      await app.openExistingNotebook(path);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // A sentence first, the exception behind the fold. The very first
      // screen of the app is the last place to print
      // "FileSystemException: ... errno = 32" and nothing else — the two
      // other failure surfaces in the app (`save_problem_dialog`,
      // `open_notice_dialog`) go to real trouble to keep exactly this text
      // behind "Details (advanced)", and this path had no such fold.
      if (mounted) {
        setState(() {
          _error = "Openote couldn't open that notebook.";
          _errorDetail = '$e';
        });
      }
    }
  }

  /// Pick a `.onepkg` and hand it to the background job. The dialog stays
  /// open: the whole point of importing first is doing the rest of this while
  /// it works.
  Future<void> _startImport() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'OneNote notebook package', extensions: ['onepkg'])
    ]);
    if (file == null || !mounted) return;
    try {
      final job = ImportJob.start(app, p.basename(file.name), file.path);
      if (job != null) setState(() => _importing = true);
    } on OneNoteUnavailable {
      setState(() => _error =
          'OneNote import needs the native core, which this build does not '
          'include.');
    } catch (e) {
      setState(() => _error = "Couldn't read that file: $e");
    }
  }

  // ── the frame ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    // Held still rather than looping when the machine asks for less motion
    // (PLAT-5). The sequence still reads: the final frame is the finished box.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _anim.isAnimating) _anim.stop();

    return AlertDialog(
      // No title bar: the picture is the title. A heading, an icon AND an
      // illustration all saying "welcome" is the redundancy this rewrite is
      // trying to remove.
      titlePadding: EdgeInsets.zero,
      contentPadding: EdgeInsets.zero,
      title: _band(s, still),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              OnoteSpace.x8, OnoteSpace.x6, OnoteSpace.x8, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title(), style: OnoteType.title.copyWith(color: s.textPrimary)),
              const SizedBox(height: OnoteSpace.x3),
              Text(_body(),
                  style: OnoteType.ui
                      .copyWith(color: s.textSecondary, height: 1.5)),
              if (_step == 2) ...[
                const SizedBox(height: OnoteSpace.x6),
                ..._startingPoints(s),
              ],
              if (_error != null) ...[
                const SizedBox(height: OnoteSpace.x5),
                Text(_error!,
                    style: OnoteType.small.copyWith(color: OnoteColors.danger)),
                if (_errorDetail != null) _details(s),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
          OnoteSpace.x8, OnoteSpace.x5, OnoteSpace.x5, OnoteSpace.x5),
      actions: [_footer(s)],
    );
  }

  /// The picture, full width, on its own tint — so the eye lands there first
  /// and the words are read second.
  Widget _band(OnoteSurfaces s, bool still) => ClipRRect(
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(OnoteRadius.xl)),
        child: Container(
          height: 148,
          width: double.infinity,
          color: s.chrome2,
          alignment: Alignment.center,
          child: switch (_step) {
            0 => AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => CustomPaint(
                  size: const Size(360, 116),
                  painter: _CanvasStoryPainter(
                    t: still ? _restFrame : _anim.value,
                    surfaces: s,
                    accent: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            1 => _mathAndInk(s),
            _ => CustomPaint(
                size: const Size(360, 116),
                painter: _OwnItPainter(
                  surfaces: s,
                  accent: Theme.of(context).colorScheme.primary,
                ),
              ),
          },
        ),
      );

  /// Step two draws its equation with the REAL renderer rather than a picture
  /// of one, so the illustration cannot promise notation the app would not
  /// actually produce.
  Widget _mathAndInk(OnoteSurfaces s) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OnoteMath(r'E=\frac{1}{2}mv^{2}',
              textStyle: OnoteType.display.copyWith(color: s.textPrimary)),
          const SizedBox(width: OnoteSpace.x8),
          Container(width: 1, height: 56, color: s.border),
          const SizedBox(width: OnoteSpace.x8),
          CustomPaint(
            size: const Size(120, 84),
            painter: _InkPainter(
                accent: Theme.of(context).colorScheme.primary, surfaces: s),
          ),
        ],
      );

  String _title() => switch (_step) {
        0 => 'The page is a canvas',
        1 => 'Maths and drawing, in with the words',
        _ => 'Your notes are a file you own',
      };

  String _body() => switch (_step) {
        0 => 'Click anywhere and start typing — a box appears where you '
            'clicked, and only once you type. Move one by the bar along its '
            'top, and drag pictures in from anywhere.',
        1 => 'Type 1/2 or press Alt+= and it builds up as real notation as '
            'you write, in a box of its own or mid-sentence. The Draw tab '
            'takes a pen, a finger or the mouse.',
        _ => 'One open, readable file per notebook — no account, no lock-in. '
            'Put it in a folder your cloud already keeps in step and every '
            'device stays together.',
      };

  /// The three real starting points, unchanged in substance from the first
  /// version of this dialog: found notebooks, OneNote, or just write.
  List<Widget> _startingPoints(OnoteSurfaces s) => [
        // Found notebooks first: on a second machine this is the answer,
        // and offering it beats asking for a path.
        if (_found.isNotEmpty)
          for (final n in _found)
            _row(
              s,
              title: n.name,
              body: p.dirname(n.path),
              action: 'Open',
              primary: true,
              onTap: () => _open(n.path),
            ),
        _row(
          s,
          title: 'Sync with another device',
          body: _found.isEmpty
              ? 'Drive, OneDrive, iCloud, Dropbox, Syncthing, a NAS — or a '
                  'GitHub repository.'
              : 'Not one of the above? Choose the folder yourself.',
          action: 'Set up…',
          onTap: () async {
            Navigator.of(context).pop();
            await showSyncDialog(context, app);
          },
        ),
        // The import runs in the BACKGROUND, and that is the design: picking
        // the .onepkg is the first thing a switcher should do, so that five
        // years of notes stream in while they finish this dialog and poke
        // around — instead of the app freezing for a minute the moment they
        // arrive.
        if (_importing)
          _importRow(s)
        else
          _row(
            s,
            title: 'Bring notes over from OneNote',
            body: 'Pages, formatting, images, ink and tags from a .onepkg. '
                'Runs in the background — keep going while it works.',
            action: 'Choose file…',
            onTap: _startImport,
            secondary: _oneNoteHelp ? 'Hide steps' : 'How do I export?',
            onSecondary: () => setState(() => _oneNoteHelp = !_oneNoteHelp),
          ),
        if (_oneNoteHelp) _oneNoteSteps(s),
      ];

  /// One starting point. Deliberately no leading icon: three of these stacked,
  /// each with its own little glyph, is decoration standing where the
  /// illustration above already did the work.
  Widget _row(
    OnoteSurfaces s, {
    required String title,
    required String body,
    required String action,
    required VoidCallback onTap,
    bool primary = false,
    String? secondary,
    VoidCallback? onSecondary,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: OnoteSpace.x3),
        padding: const EdgeInsets.fromLTRB(
            OnoteSpace.x5, OnoteSpace.x4, OnoteSpace.x4, OnoteSpace.x4),
        decoration: BoxDecoration(
          color: s.chrome2,
          borderRadius: OnoteRadius.mdAll,
          border: Border.all(color: s.border),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: OnoteType.uiStrong.copyWith(color: s.textPrimary)),
                const SizedBox(height: OnoteSpace.x1),
                Text(body,
                    style: OnoteType.small.copyWith(color: s.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                // The secondary action goes UNDER the words, not beside the
                // main one. Two full-size buttons plus a paragraph on one
                // 450px line is what overflowed this card — and a quiet link
                // is the right weight for "how do I export?" regardless.
                if (secondary != null)
                  Padding(
                    padding: const EdgeInsets.only(top: OnoteSpace.x2),
                    child: TextButton(
                      onPressed: onSecondary,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: OnoteType.small,
                      ),
                      child: Text(secondary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: OnoteSpace.x4),
          if (primary)
            FilledButton(onPressed: onTap, child: Text(action))
          else
            FilledButton.tonal(onPressed: onTap, child: Text(action)),
        ]),
      );

  /// The in-dialog echo of the floating progress card, so starting the import
  /// visibly *did something* right here — and so the dialog can say the one
  /// sentence that explains the new shape: you don't have to wait.
  Widget _importRow(OnoteSurfaces s) => ListenableBuilder(
        listenable: ImportJob.current ?? Listenable.merge(const []),
        builder: (context, _) {
          final job = ImportJob.current;
          if (job == null) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: OnoteSpace.x3),
            padding: const EdgeInsets.all(OnoteSpace.x5),
            decoration: BoxDecoration(
              color: s.chrome2,
              borderRadius: OnoteRadius.mdAll,
              border: Border.all(color: s.border),
            ),
            child: Row(children: [
              if (!job.isFinished)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2))
              else
                Icon(
                    job.state == ImportJobState.done
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: OnoteIcon.sm,
                    color: job.state == ImportJobState.done
                        ? OnoteColors.success
                        : OnoteColors.danger),
              const SizedBox(width: OnoteSpace.x5),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          job.state == ImportJobState.done
                              ? 'Your notebook is ready'
                              : 'Importing ${job.fileName}',
                          style: OnoteType.uiStrong
                              .copyWith(color: s.textPrimary)),
                      Text(
                          job.isFinished
                              ? job.message
                              : 'Keep going — this runs in the background, '
                                  'and the card in the corner will say when '
                                  "it's done.",
                          style: OnoteType.caption
                              .copyWith(color: s.textSecondary)),
                    ]),
              ),
              if (job.state == ImportJobState.done)
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.of(context).pop();
                    job.open();
                  },
                  child: const Text('Open'),
                ),
            ]),
          );
        },
      );

  /// Exporting from OneNote is the step people get stuck on, and it is not
  /// discoverable — the desktop app hides it, and the web and store versions
  /// cannot do it at all. Saying so plainly beats letting someone hunt.
  Widget _oneNoteSteps(OnoteSurfaces s) => Container(
        margin: const EdgeInsets.only(bottom: OnoteSpace.x3),
        padding: const EdgeInsets.all(OnoteSpace.x5),
        decoration: BoxDecoration(
          color: s.textSecondary.withValues(alpha: .08),
          borderRadius: OnoteRadius.mdAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Exporting from OneNote',
                style: OnoteType.uiStrong.copyWith(color: s.textPrimary)),
            const SizedBox(height: OnoteSpace.x3),
            Text(
              '1. Open OneNote for Windows (the desktop app — the Store and '
              'web versions cannot export).\n'
              '2. Let the notebook finish syncing, so everything is on this '
              'machine.\n'
              '3. File ▸ Export ▸ Notebook ▸ OneNote Package (*.onepkg), then '
              'Export.\n'
              '4. Come back here and choose that file.',
              style: OnoteType.small
                  .copyWith(color: s.textPrimary, height: 1.55),
            ),
            const SizedBox(height: OnoteSpace.x4),
            Text(
              'On a Mac, or with only the Store version: export one section at '
              'a time as .one, or ask a Windows machine to make the .onepkg. '
              'Openote never signs into your Microsoft account — it only reads '
              'the file you hand it.',
              style: OnoteType.caption
                  .copyWith(color: s.textSecondary, height: 1.45),
            ),
          ],
        ),
      );

  Widget _details(OnoteSurfaces s) => Theme(
        // The divider lines an ExpansionTile draws by default cut the dialog
        // in half for one folded line of text.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text('Details (advanced)',
              style: OnoteType.caption.copyWith(color: s.textSecondary)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(_errorDetail!,
                  style: OnoteType.mono.copyWith(color: s.textSecondary)),
            ),
          ],
        ),
      );

  /// Dots, Back, and one forward button that becomes "Start writing" on the
  /// last step — so the flow always ends by putting you on the page rather
  /// than leaving you to find the close button.
  Widget _footer(OnoteSurfaces s) => Row(children: [
        for (var i = 0; i < _steps; i++)
          Padding(
            padding: const EdgeInsets.only(right: OnoteSpace.x2),
            child: AnimatedContainer(
              duration: OnoteMotion.standard,
              curve: OnoteMotion.curve,
              width: i == _step ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _step
                    ? Theme.of(context).colorScheme.primary
                    : s.border,
                borderRadius: OnoteRadius.smAll,
              ),
            ),
          ),
        const Spacer(),
        if (_step > 0)
          TextButton(
              onPressed: () => _goTo(_step - 1), child: const Text('Back'))
        else
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Skip')),
        const SizedBox(width: OnoteSpace.x2),
        FilledButton(
          onPressed: _step == _steps - 1
              ? () => Navigator.of(context).pop()
              : () => _goTo(_step + 1),
          child: Text(_step == _steps - 1 ? 'Start writing' : 'Next'),
        ),
      ]);
}

// ── the drawings ─────────────────────────────────────────────────────────
//
// Painted rather than shipped as images: no assets to carry, exact light and
// dark palettes for free, and nothing that can quietly disagree with the app
// after a redesign. None of them draw a word — the caption underneath says
// what is happening, which also means there is nothing here to translate.

/// Progress of `t` through the window [a, b], clamped to 0..1 outside it.
double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

/// Click, type, and only THEN a box — the one thing a still picture cannot
/// say, and the whole interaction model of the app.
class _CanvasStoryPainter extends CustomPainter {
  _CanvasStoryPainter(
      {required this.t, required this.surfaces, required this.accent});

  final double t;
  final OnoteSurfaces surfaces;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final page = Rect.fromLTWH(0, 0, size.width, size.height);
    final r = RRect.fromRectAndRadius(page, const Radius.circular(6));
    canvas.drawRRect(r, Paint()..color = surfaces.canvas);
    canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = surfaces.border);

    // Two boxes that were already on the page, so the new one reads as
    // "another one, wherever you like" rather than "the only one".
    _ghostBox(canvas, const Rect.fromLTWH(14, 14, 104, 34), lines: 2);
    _ghostBox(canvas, const Rect.fromLTWH(232, 62, 112, 40), lines: 3);

    // The beat sheet. Everything below is a lookup into it.
    final move = _seg(t, 0.00, 0.10); // pointer travels to the spot
    final click = _seg(t, 0.10, 0.16); // and presses
    final caret = _seg(t, 0.16, 0.30); // a caret, and nothing else
    final typing = _seg(t, 0.30, 0.62); // words arrive
    final boxed = _seg(t, 0.62, 0.74); // the box catches up
    final fade = _seg(t, 0.93, 1.00); // and clears for the next loop

    const spot = Offset(52, 66);
    final alpha = 1 - fade;
    if (alpha <= 0) return;

    // The new box, drawn only once there is something in it — which is the
    // point being made.
    if (boxed > 0) {
      final grow = Curves.easeOutBack.transform(boxed);
      final box = Rect.fromLTWH(
          spot.dx - 10, spot.dy - 16, 150 * grow.clamp(0.0, 1.0), 42);
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(5));
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = accent.withValues(alpha: .55 * alpha));
      // The move bar — the answer to "how do I move this?", which is the
      // second thing everyone asks.
      final bar = Rect.fromLTWH(box.left + 3, box.top - 6, box.width - 6, 5);
      canvas.drawRRect(
          RRect.fromRectAndRadius(bar, const Radius.circular(2.5)),
          Paint()..color = accent.withValues(alpha: .75 * alpha));
    }

    // Two lines of text growing left to right, the caret riding the end.
    final lineW = [116.0, 74.0];
    var carriage = spot;
    for (var i = 0; i < lineW.length; i++) {
      final from = i / lineW.length, to = (i + 1) / lineW.length;
      final on = _seg(typing, from, to);
      if (on <= 0) continue;
      final y = spot.dy + i * 13;
      final w = lineW[i] * on;
      canvas.drawLine(
          Offset(spot.dx, y),
          Offset(spot.dx + w, y),
          Paint()
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..color = surfaces.textSecondary.withValues(alpha: .55 * alpha));
      carriage = Offset(spot.dx + w + 3, y);
    }

    // The caret: solid while it is the only thing there, blinking once the
    // words are in — the same beat a real one keeps.
    if (caret > 0) {
      final blink = typing >= 1 ? (math.sin(t * 22) > -0.3 ? 1.0 : 0.25) : 1.0;
      final at = typing > 0 ? carriage : spot;
      canvas.drawLine(
          Offset(at.dx, at.dy - 7),
          Offset(at.dx, at.dy + 7),
          Paint()
            ..strokeWidth = 1.6
            ..color = accent.withValues(alpha: alpha * blink));
    }

    // The pointer, and the ring the press leaves behind.
    if (click > 0 && click < 1) {
      canvas.drawCircle(
          spot,
          6 + 12 * click,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = accent.withValues(alpha: (1 - click) * .8));
    }
    if (typing < 1) {
      final from = spot + const Offset(-46, 34);
      _pointer(canvas, Offset.lerp(from, spot, Curves.easeOut.transform(move))!,
          alpha);
    }
  }

  void _ghostBox(Canvas canvas, Rect box, {required int lines}) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = surfaces.border);
    for (var i = 0; i < lines; i++) {
      final y = box.top + 10 + i * 10;
      canvas.drawLine(
          Offset(box.left + 8, y),
          Offset(box.right - (i.isEven ? 10 : 26), y),
          Paint()
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = surfaces.textDisabled.withValues(alpha: .45));
    }
  }

  /// A plain arrow cursor, outlined so it reads on paper or on a box.
  void _pointer(Canvas canvas, Offset at, double alpha) {
    final path = Path()
      ..moveTo(at.dx, at.dy)
      ..lineTo(at.dx, at.dy + 15)
      ..lineTo(at.dx + 4, at.dy + 11.5)
      ..lineTo(at.dx + 6.6, at.dy + 17)
      ..lineTo(at.dx + 9, at.dy + 15.8)
      ..lineTo(at.dx + 6.4, at.dy + 10.6)
      ..lineTo(at.dx + 11, at.dy + 10.2)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = surfaces.canvas.withValues(alpha: alpha));
    canvas.drawPath(
        path, Paint()..color = surfaces.textPrimary.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(_CanvasStoryPainter old) =>
      old.t != t || old.surfaces != surfaces || old.accent != accent;
}

/// A confident pen stroke and a highlighter swipe: what the Draw tab is for,
/// without a screenshot of it.
class _InkPainter extends CustomPainter {
  _InkPainter({required this.accent, required this.surfaces});
  final Color accent;
  final OnoteSurfaces surfaces;

  @override
  void paint(Canvas canvas, Size size) {
    // The highlighter first, so the pen sits on top of it exactly as it does
    // on a real page.
    canvas.drawLine(
        Offset(size.width * .12, size.height * .74),
        Offset(size.width * .88, size.height * .74),
        Paint()
          ..strokeWidth = 13
          ..strokeCap = StrokeCap.round
          ..color = OnoteColors.brass400.withValues(alpha: .38));

    final w = size.width, h = size.height;
    final stroke = Path()
      ..moveTo(w * .12, h * .52)
      ..cubicTo(w * .28, h * .10, w * .40, h * .88, w * .55, h * .40)
      ..cubicTo(w * .66, h * .06, w * .78, h * .52, w * .90, h * .24);
    canvas.drawPath(
        stroke,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = accent);
  }

  @override
  bool shouldRepaint(_InkPainter old) =>
      old.accent != accent || old.surfaces != surfaces;
}

/// One file, in a folder that happens to sync, reaching every machine you
/// own. No cloud account in the middle — which is the claim being made.
class _OwnItPainter extends CustomPainter {
  _OwnItPainter({required this.surfaces, required this.accent});
  final OnoteSurfaces surfaces;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = surfaces.border;

    // The notebook file, with its corner folded — the one artefact everything
    // else in the picture is about.
    const w = 54.0, h = 68.0, fold = 14.0;
    final fileAt = Offset(18, mid - h / 2);
    final file = Path()
      ..moveTo(fileAt.dx, fileAt.dy)
      ..lineTo(fileAt.dx + w - fold, fileAt.dy)
      ..lineTo(fileAt.dx + w, fileAt.dy + fold)
      ..lineTo(fileAt.dx + w, fileAt.dy + h)
      ..lineTo(fileAt.dx, fileAt.dy + h)
      ..close();
    canvas.drawPath(file, Paint()..color = surfaces.canvas);
    canvas.drawPath(file, line..color = accent.withValues(alpha: .7));
    canvas.drawPath(
        Path()
          ..moveTo(fileAt.dx + w - fold, fileAt.dy)
          ..lineTo(fileAt.dx + w - fold, fileAt.dy + fold)
          ..lineTo(fileAt.dx + w, fileAt.dy + fold),
        line);
    for (var i = 0; i < 4; i++) {
      final y = fileAt.dy + 20 + i * 10;
      canvas.drawLine(
          Offset(fileAt.dx + 9, y),
          Offset(fileAt.dx + w - (i == 3 ? 22 : 11), y),
          Paint()
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round
            ..color = surfaces.textDisabled.withValues(alpha: .5));
    }

    // A folder that syncs — drawn as a folder, not a branded cloud, because
    // the promise is "any folder that already syncs", not one service.
    final folder = Rect.fromCenter(
        center: Offset(size.width / 2, mid), width: 66, height: 50);
    final tab = Path()
      ..moveTo(folder.left, folder.bottom)
      ..lineTo(folder.left, folder.top + 8)
      ..lineTo(folder.left + 22, folder.top + 8)
      ..lineTo(folder.left + 28, folder.top)
      ..lineTo(folder.right, folder.top)
      ..lineTo(folder.right, folder.bottom)
      ..close();
    canvas.drawPath(tab, Paint()..color = surfaces.canvas);
    canvas.drawPath(tab, line..color = surfaces.textSecondary);

    // Two machines, because "every device" is the whole point of the middle.
    _screen(canvas, Rect.fromLTWH(size.width - 92, mid - 34, 62, 40), line);
    _screen(canvas, Rect.fromLTWH(size.width - 62, mid + 6, 44, 30), line);

    // Arrows both ways: it is the same notebook in both places, not a copy
    // pushed one direction.
    _arrows(canvas, Offset(fileAt.dx + w + 8, mid),
        Offset(folder.left - 8, mid), accent);
    _arrows(canvas, Offset(folder.right + 8, mid),
        Offset(size.width - 96, mid), accent);
  }

  void _screen(Canvas canvas, Rect r, Paint line) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(4));
    canvas.drawRRect(rr, Paint()..color = surfaces.canvas);
    canvas.drawRRect(rr, line..color = surfaces.textSecondary);
    canvas.drawLine(
        Offset(r.left + 8, r.top + 11),
        Offset(r.right - 12, r.top + 11),
        Paint()
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = surfaces.textDisabled.withValues(alpha: .5));
    canvas.drawLine(
        Offset(r.left + 8, r.top + 19),
        Offset(r.right - 20, r.top + 19),
        Paint()
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = surfaces.textDisabled.withValues(alpha: .5));
  }

  void _arrows(Canvas canvas, Offset a, Offset b, Color colour) {
    final p = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = colour.withValues(alpha: .8);
    canvas.drawLine(a, b, p);
    for (final (tip, dir) in [(b, 1.0), (a, -1.0)]) {
      canvas.drawLine(tip, tip + Offset(-4.5 * dir, -3.5), p);
      canvas.drawLine(tip, tip + Offset(-4.5 * dir, 3.5), p);
    }
  }

  @override
  bool shouldRepaint(_OwnItPainter old) =>
      old.surfaces != surfaces || old.accent != accent;
}
