import 'package:flutter/material.dart';

import '../core/system_fonts.dart';
import '../theme/tokens.dart';

/// Searchable system-font picker (§7a.3): every installed family, each row
/// rendered in its own face. Returns the family name, or null.
Future<String?> showFontPicker(BuildContext context, {String? current}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _FontPickerDialog(current: current),
  );
}

class _FontPickerDialog extends StatefulWidget {
  const _FontPickerDialog({this.current});
  final String? current;

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Font'),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search fonts…',
            ),
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: SystemFonts.families(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = [
                  'Default',
                  // The bundled faces never appear in the OS font enumeration,
                  // so they'd be unpickable without this — and they are the
                  // two we most want people to pick.
                  'Inter',
                  'JetBrains Mono',
                  ...snap.data!.where(
                      (f) => f != 'Inter' && f != 'JetBrains Mono'),
                ];
                final shown = _query.isEmpty
                    ? all
                    : [
                        for (final f in all)
                          if (f.toLowerCase().contains(_query)) f
                      ];
                if (shown.isEmpty) {
                  return Center(
                      child: Text('No fonts match',
                          style:
                              TextStyle(color: context.surfaces.textSecondary)));
                }
                return ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final f = shown[i];
                    final isCurrent = f == widget.current ||
                        (f == 'Default' && widget.current == null);
                    return ListTile(
                      dense: true,
                      selected: isCurrent,
                      title: Text(
                        f,
                        style: TextStyle(
                            fontSize: 15,
                            fontFamily: f == 'Default' ? null : f),
                      ),
                      subtitle: f == 'Default'
                          ? null
                          : Text('The quick brown fox jumps over the lazy dog',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: f,
                                  color: context.surfaces.textSecondary)),
                      onTap: () =>
                          Navigator.pop(context, f == 'Default' ? '' : f),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
