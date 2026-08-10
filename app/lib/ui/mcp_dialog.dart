import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// AI access (spec 14): the switch for the local MCP server, and the
/// ready-to-paste client config once it is on. The dialog IS the security
/// briefing — what turns on, what can reach it, and that off is off.
Future<void> showMcpDialog(BuildContext context, AppState app) {
  return showDialog<void>(
    context: context,
    builder: (_) => _McpDialog(app: app),
  );
}

class _McpDialog extends StatelessWidget {
  const _McpDialog({required this.app});
  final AppState app;

  String get _config => '''
{
  "mcpServers": {
    "openote": {
      "type": "http",
      "url": "http://127.0.0.1:${app.mcpPort}/mcp",
      "headers": { "Authorization": "Bearer ${app.mcpToken}" }
    }
  }
}''';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => AlertDialog(
        title: const Text('AI access (MCP)'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lets AI tools you already use — Claude, editors, agents — '
                'read your notes, search them, create pages and flashcards. '
                'Only while Openote is running, only from this computer, '
                'and only with the key below. Changes they make are ordinary '
                'edits: they sync, and Ctrl+Z undoes them.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Switch(
                  value: app.mcpEnabled,
                  onChanged: (v) => app.setMcpEnabled(v),
                ),
                const SizedBox(width: 6),
                Text(app.mcpEnabled
                    ? 'On — serving at 127.0.0.1:${app.mcpPort}'
                    : 'Off'),
              ]),
              if (app.mcpError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Could not start: ${app.mcpError}',
                      style: const TextStyle(
                          fontSize: 11, color: OnoteColors.danger)),
                ),
              if (app.mcpEnabled) ...[
                const SizedBox(height: 8),
                const Text('Paste into your MCP client\'s config:',
                    style: TextStyle(
                        fontSize: 11, color: OnoteColors.graphite400)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? OnoteColors.night100
                        : OnoteColors.paper100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    _config,
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontFamilyFallback: onoteFontFallback,
                        fontSize: 10.5),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy config'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _config));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Copied. The key inside is a '
                              'password — paste it only into your own '
                              'tools.')));
                    },
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
      ),
    );
  }
}
