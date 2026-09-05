/// Don't rebuild a subtree whose inputs have not changed.
///
/// **The problem this solves.** `AppState.markDirty()` runs on every
/// keystroke — it has to, because the auto-width measurement that makes a box
/// grow as you type happens in the parent's build — and `AppShell` wraps the
/// whole application in one `ListenableBuilder`. So a character typed in the
/// middle of a paragraph rebuilds the command bar and the object row, neither
/// of which can possibly look different for it.
///
/// Measured on the `ui_perf_probe` notebook (3 sections × 30 pages, 40 blocks
/// on the open page, 1500×950), median frame after `markDirty()`, debug build,
/// by stubbing each region out in turn:
///
/// | region | cost of one keystroke frame |
/// |---|---|
/// | command bar | 31.6 ms |
/// | object row | 15.2 ms |
/// | navigator | 2.3 ms — already memoised, by hand, in `AppShell._navigator` |
/// | everything else | 13.6 ms |
///
/// The navigator row is the point: this technique already existed here and
/// already worked; it was written once, inline, for one widget.
///
/// **What this does NOT do.** `build` still runs, and [memoInputs] is still
/// evaluated, on every single notification — so anything that reads a value
/// and puts it in the list stays exactly as live as it was. Only the
/// *construction of the widget tree* is skipped, and only when every one of
/// those values compares equal to last time.
///
/// **The failure mode, named so it can be avoided.** A value the subtree
/// RENDERS but [memoInputs] does not list goes stale: the change lands in the
/// state and paints only when something else happens to invalidate the memo.
/// That is a bug which passes a quick look and fails in real use, so it is not
/// left to discipline — `test/chrome_memo_test.dart` reads the source of every
/// widget using this mixin, finds each `app.<member>` it touches, and fails if
/// one is neither declared in [memoInputs] nor listed there as an action that
/// renders nothing.
///
/// Two categories of input are handled for you and must NOT be listed:
///
///  * **Inherited widgets** — theme, media query, translations, text
///    direction. `didChangeDependencies` drops the cache, which covers every
///    one of them including ones added later.
///  * **This `State`'s own fields**, as long as they are changed through
///    `setState`, which drops the cache too.
///
/// Everything else belongs in [memoInputs] — every value read off a model, a
/// controller or a global, **and every constructor parameter of the widget
/// itself**. The widget's own fields are on that list rather than handled
/// here because `didUpdateWidget` is no help: a parent that rebuilds
/// constructs a fresh instance every frame, which is the whole situation this
/// exists for, so treating that as a change would mean the cache never
/// survived a single frame. (It did not, on the first attempt: the memo made
/// the bar measurably *slower* — 67.5 ms against a 62.7 ms baseline — because
/// it did all the same work plus building the key.)
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

mixin MemoBuild<T extends StatefulWidget> on State<T> {
  List<Object?>? _memoKey;
  Widget? _memoBuilt;

  /// Every value [buildMemo] renders. See the notes on the library above for
  /// what does not belong here.
  List<Object?> memoInputs();

  /// What `build` would otherwise have been.
  Widget buildMemo(BuildContext context);

  /// Throw the cache away. Call it from anywhere that changes what the
  /// subtree should look like without going through `setState` or an
  /// inherited widget.
  @protected
  void invalidateMemo() => _memoBuilt = null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    invalidateMemo();
  }

  @override
  void setState(VoidCallback fn) {
    invalidateMemo();
    super.setState(fn);
  }

  @override
  void reassemble() {
    // Hot reload changes the code that builds the subtree without changing
    // any of its inputs, so the cache would hide every edit until something
    // else happened to invalidate it.
    super.reassemble();
    invalidateMemo();
  }

  @override
  Widget build(BuildContext context) {
    final key = memoInputs();
    final built = _memoBuilt;
    if (built != null && listEquals(_memoKey, key)) return built;
    _memoKey = key;
    return _memoBuilt = buildMemo(context);
  }
}

/// The same idea for a leaf that also has to **listen for itself**.
///
/// A widget inside a memoised parent no longer gets rebuilt by that parent, so
/// anything whose contents really do change — a card count, a word count, the
/// tag on the current line — has to subscribe on its own account. Doing that
/// alone would put every one of them back on the per-keystroke path; doing it
/// with a key means each rebuilds only when its own numbers move.
///
/// [inputs] is evaluated on every notification, [builder] only when the result
/// differs from last time. A rebuild of the PARENT always rebuilds through
/// this, since it arrives with a fresh [builder] closure — which is right: the
/// parent rebuilt because something changed.
class MemoBuilder extends StatefulWidget {
  const MemoBuilder({
    super.key,
    required this.listenable,
    required this.inputs,
    required this.builder,
  });

  final Listenable listenable;
  final List<Object?> Function() inputs;
  final WidgetBuilder builder;

  @override
  State<MemoBuilder> createState() => _MemoBuilderState();
}

class _MemoBuilderState extends State<MemoBuilder> {
  List<Object?>? _key;
  Widget? _built;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_bump);
  }

  @override
  void didUpdateWidget(MemoBuilder old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_bump);
      widget.listenable.addListener(_bump);
    }
    // A new [builder] means the parent rebuilt, which is itself the signal
    // that something changed.
    _built = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  @override
  void reassemble() {
    super.reassemble();
    _built = null;
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_bump);
    super.dispose();
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.inputs();
    final built = _built;
    if (built != null && listEquals(_key, key)) return built;
    _key = key;
    return _built = widget.builder(context);
  }
}
