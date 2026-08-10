import 'package:flutter/material.dart';

import '../theme/onote_theme.dart';
import 'keyboard_map.dart';

/// The Ctrl+/ shortcut reference — a rendering of [keyboardMap] and nothing
/// else, so what this shows IS what the map says. Adding a binding to the
/// map is the whole job of documenting it.
Future<void> showShortcutOverlay(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ShortcutOverlay(),
  );
}

class _ShortcutOverlay extends StatelessWidget {
  const _ShortcutOverlay();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final section in keyboardMap) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text(section.title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary)),
              ),
              for (final b in section.bindings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 200, child: _Keys(b.keys)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(b.action,
                              style: const TextStyle(
                                  fontSize: 12.5, height: 1.35)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    );
  }
}

/// The key combo as a keycap chip. Alternatives (` / `) each get their own
/// chip so `Ctrl+PgDn / Ctrl+PgUp` reads as two keys, not one long one.
class _Keys extends StatelessWidget {
  const _Keys(this.keys);
  final String keys;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final part in keys.split(' / '))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: dark ? OnoteColors.night100 : OnoteColors.paper100,
              border: Border.all(
                  color: dark
                      ? OnoteColors.graphite400.withValues(alpha: .45)
                      : OnoteColors.graphite400.withValues(alpha: .3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(part,
                style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontFamilyFallback: onoteFontFallback,
                    fontSize: 11)),
          ),
      ],
    );
  }
}
