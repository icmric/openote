/// **One door for every kind of link.**
///
/// The owner: *"i think we should change this to 'insert link' rather than
/// 'page link' as that makes me think that it only allows linking to internal
/// pages, which it doesnt."*
///
/// Worth recording that the old label was accurate — `insertPageLink` really
/// did only offer other pages in the notebook, and there was no route to a web
/// address from the Insert menu at all. But the instinct behind the note is
/// right, and it is the more useful thing to act on: somebody reaching for
/// "link" wants to attach an address to some words, and should not have to
/// know in advance whether the address happens to be inside this notebook.
///
/// So there is one dialog, it is reached by Ctrl+K as well as from the menu,
/// and the page picker is a section inside it rather than a different door.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/platform_open.dart';
import '../editor/live_markdown_controller.dart';
import '../theme/tokens.dart';

/// What the dialog came back with.
class LinkChoice {
  const LinkChoice.url(this.label, this.target) : wiki = false, remove = false;
  const LinkChoice.page(this.label, this.target) : wiki = true, remove = false;
  const LinkChoice.remove()
      : label = '',
        target = '',
        wiki = false,
        remove = true;

  /// The words the link is drawn as.
  final String label;

  /// The address, or the page id for a [wiki] link.
  final String target;
  final bool wiki;

  /// "Remove link": the words stay, the address goes.
  final bool remove;
}

/// A page this notebook could link to.
typedef LinkablePage = ({String id, String title});

/// Ask for a link.
///
/// [label] is what Ctrl+K found to attach to — a selection, or the word the
/// caret was against — and is empty when it found nothing, which is the one
/// case where the display-text field is REQUIRED rather than merely offered.
/// [target] non-null means an existing link is being edited, which adds
/// "Remove link" and changes the verb on the button.
Future<LinkChoice?> showLinkDialog(
  BuildContext context, {
  String label = '',
  String? target,
  bool wiki = false,
  List<LinkablePage> pages = const [],
}) =>
    showDialog<LinkChoice>(
      context: context,
      builder: (_) => _LinkDialog(
        label: label,
        target: target,
        wiki: wiki,
        pages: pages,
      ),
    );

/// **What somebody typed, read as generously as is still safe.**
///
/// `example.com` is what people type and `https://example.com` is what they
/// mean; refusing it would be pedantry. Anything already carrying a scheme is
/// left exactly as typed, including `mailto:` — guessing at an address that
/// already says what it is would be the bad kind of helpful.
///
/// Returns null when there is nothing here that could be opened, which is what
/// keeps a dead link out of a note rather than discovering it months later.
String? normaliseLinkTarget(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final withScheme =
      t.contains('://') || t.startsWith('mailto:') ? t : 'https://$t';
  return PlatformOpen.isOpenableUrl(withScheme) ? withScheme : null;
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({
    required this.label,
    required this.target,
    required this.wiki,
    required this.pages,
  });

  final String label;
  final String? target;
  final bool wiki;
  final List<LinkablePage> pages;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final _address = TextEditingController(
      text: widget.wiki ? '' : (widget.target ?? ''));
  late final _words = TextEditingController(text: widget.label);
  late final _addressFocus = FocusNode();
  late final _wordsFocus = FocusNode();

  /// True when Ctrl+K found nothing to attach to, so the words are the one
  /// thing the person MUST supply — there is no link without a label.
  bool get _mustName => widget.label.isEmpty;

  bool get _editing => widget.target != null;

  String? _error;

  @override
  void initState() {
    super.initState();
    // The address is what somebody came here to type; the words are usually
    // already right. Unless there are none, in which case they are the answer
    // to the first question the dialog asks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_mustName ? _wordsFocus : _addressFocus).requestFocus();
    });
  }

  @override
  void dispose() {
    _address.dispose();
    _words.dispose();
    _addressFocus.dispose();
    _wordsFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final words = _words.text.trim();
    if (words.isEmpty) {
      setState(() => _error = 'Give the link some words to show.');
      return;
    }
    final url = normaliseLinkTarget(_address.text);
    if (url == null) {
      setState(() => _error = "That doesn't look like an address Openote can "
          'open. Try something like https://example.com');
      return;
    }
    Navigator.pop(context, LinkChoice.url(words, url));
  }

  void _pickPage(LinkablePage p) {
    final words = _words.text.trim();
    Navigator.pop(
        context, LinkChoice.page(words.isEmpty ? p.title : words, p.id));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return AlertDialog(
      title: Text(_editing ? 'Edit link' : 'Link'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _words,
                focusNode: _wordsFocus,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Text to show',
                  // Said only when it is the thing standing in the way, so it
                  // reads as an instruction rather than as decoration.
                  helperText: _mustName
                      ? 'There was nothing selected to turn into a link'
                      : null,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                focusNode: _addressFocus,
                style: const TextStyle(fontSize: 13),
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Address',
                  hintText: 'https://example.com',
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).colorScheme.error)),
              ],
              if (widget.pages.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Divider(color: s.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('or link to a page',
                        style:
                            TextStyle(fontSize: 11, color: s.textSecondary)),
                  ),
                  Expanded(child: Divider(color: s.border)),
                ]),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.pages.length,
                    itemBuilder: (_, i) {
                      final p = widget.pages[i];
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading:
                            const Icon(Icons.description_outlined, size: 16),
                        title: Text(p.title,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                        onTap: () => _pickPage(p),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_editing)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const LinkChoice.remove()),
            child: const Text('Remove link'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_editing ? 'Update' : 'Insert'),
        ),
      ],
    );
  }
}

/// **Ctrl+K, wherever the keyboard happens to be.**
///
/// The paragraph and a table cell are both a `TextEditingController` over the
/// same grammar, so they get the same function rather than two that will drift.
/// That is not tidiness: the thing that must not vary between them is which
/// places refuse, and a second copy of those rules is a second chance to get
/// one of them wrong — on a table's own reference, say, where the cost is a
/// payload nothing can reach again.
///
/// Returns true when the buffer changed, so the caller can save. Everything
/// that is not a change — a refusal, a cancel, an address that cannot be
/// opened — returns false and has already said so on screen.
Future<bool> runLinkFlow(
  BuildContext context,
  TextEditingController ctl, {
  List<LinkablePage> pages = const [],
}) async {
  final site = linkSiteAt(ctl.text, ctl.selection);
  if (!site.ok) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(linkRefusal(site.blocked!))));
    return false;
  }
  final choice = await showLinkDialog(
    context,
    label: site.label,
    target: site.url,
    wiki: site.wiki,
    pages: pages,
  );
  if (choice == null) return false;

  final edit = choice.remove
      ? removeLink(ctl.text, site)
      : applyLink(ctl.text, site,
          label: choice.label, url: choice.target, wiki: choice.wiki);
  ctl.value = ctl.value.copyWith(
    text: edit.text,
    selection: edit.selection,
    composing: TextRange.empty,
  );
  return true;
}

/// Why a link cannot go where somebody asked for it.
///
/// Said in the words of the note rather than of the format — nobody typing a
/// link needs to hear "inline run" or "atom reference" — and each one names the
/// thing they are pointing at, so the sentence is actionable rather than a
/// refusal with no door out of it.
String linkRefusal(LinkBlocked why) => switch (why) {
      LinkBlocked.noCaret => 'Put the cursor where the link should go first.',
      LinkBlocked.lines =>
        'A link has to sit on one line. Select some words on a single line.',
      LinkBlocked.object =>
        "A picture, a table or a card can't carry a link. Put it on some "
            'words instead.',
      LinkBlocked.maths =>
        "An equation can't carry a link — the brackets belong to the maths.",
      LinkBlocked.bracket =>
        "A link's words can't contain square brackets. Select something "
            'without them.',
      LinkBlocked.nested =>
        "That text is already formatted or linked. Select some plain words, "
            'or click inside the link to edit it.',
    };
