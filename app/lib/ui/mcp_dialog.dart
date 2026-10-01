import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/mcp_connect.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// AI access (spec 14 §8). The audience is a student who has never heard
/// the word MCP: the visible path is a switch and ONE button — "Connect
/// Claude Code" — and Openote writes the connection itself. Every piece of
/// jargon (MCP, server, port, token, config) lives behind the Advanced
/// fold, for people connecting some other tool.
Future<void> showMcpDialog(BuildContext context, AppState app) {
  return showOnoteDialog<void>(
    context: context,
    builder: (_) => _McpDialog(app: app),
  );
}

class _McpDialog extends StatefulWidget {
  const _McpDialog({required this.app});
  final AppState app;

  @override
  State<_McpDialog> createState() => _McpDialogState();
}

class _McpDialogState extends State<_McpDialog> {
  AppState get app => widget.app;

  ClaudeConnectResult? _result;

  /// The one-line setup for other MCP clients' CLIs, shown under Advanced.
  String get _cli => 'claude mcp add --transport http --scope user openote '
      'http://127.0.0.1:${app.mcpPort}/mcp '
      '--header "Authorization: Bearer ${app.mcpToken}"';

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

  void _connect(
      ClaudeConnectResult Function({required int port, required String token})
          connector) {
    setState(() {
      _result = connector(port: app.mcpPort!, token: app.mcpToken!);
    });
  }

  Widget _snippet(BuildContext context, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? OnoteColors.night100
              : OnoteColors.paper100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: SelectableText(
          text,
          style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontFamilyFallback: onoteFontFallback,
              fontSize: 10.5),
        ),
      );

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copied. The key inside is a password — paste it only '
            'into your own tools.')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => AlertDialog(
        title: const Text('AI access'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Let an AI helper — like Claude — read your notes, search '
                'them, quiz you, and make flashcards from them. It only '
                'works while Openote is open, only on this computer, and '
                'anything it adds is a normal edit: Ctrl+Z undoes it.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11))),
                segments: const [
                  ButtonSegment(value: false, label: Text('Off')),
                  ButtonSegment(value: true, label: Text('On')),
                ],
                selected: {app.mcpEnabled},
                onSelectionChanged: (s) => app.setMcpEnabled(s.first),
              ),
              if (app.mcpError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Could not start: ${app.mcpError}',
                      style: const TextStyle(
                          fontSize: 11, color: OnoteColors.danger)),
                ),
              if (app.mcpEnabled) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Connect Claude Code'),
                    onPressed: () => _connect(connectClaudeCode),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Connect Gemini CLI'),
                    onPressed: () => _connect(connectGeminiCli),
                  ),
                  // **The Claude APP, not Claude Code** — which is how most
                  // people use Claude, and was missing here. It reads its own
                  // manifest and takes a URL with headers, so the server this
                  // app already runs needs nothing new.
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Connect Claude app'),
                    onPressed: () => _connect(connectClaudeApp),
                  ),
                ]),
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _result!.message,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: _result!.status == ClaudeConnect.failed
                              ? OnoteColors.danger
                              : scheme.primary),
                    ),
                  ),
                // **Values to paste, not a button** — because this one is
                // typed into ChatGPT's own settings rather than read from a
                // file Openote could write, and which of its modes allows a
                // local server has been moving. A button that might be
                // writing nothing is worse than two values and a sentence
                // saying where they go.
                //
                // The ChatGPT WEBSITE still cannot reach a loopback server,
                // and neither can the Gemini app's. That part is unchanged.
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'ChatGPT: the desktop app can take this in its own '
                          'Settings ▸ MCP servers — look for the '
                          'mode that runs on your computer. Give it the '
                          'address below, with the token as an Authorization '
                          "header. The ChatGPT website can't: its connectors "
                          "run on OpenAI's servers, which can't see your "
                          'computer. Same for the Gemini app.',
                          style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: OnoteColors.graphite400)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.link, size: 14),
                          label: const Text('Copy address',
                              style: TextStyle(fontSize: 11.5)),
                          onPressed: () =>
                              _copy(context, mcpUrl(app.mcpPort!)),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.data_object, size: 14),
                          label: const Text('Copy configuration',
                              style: TextStyle(fontSize: 11.5)),
                          onPressed: () => _copy(context,
                              manualConfigJson(app.mcpPort!, app.mcpToken!)),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  title: const Text('Other AI tools (advanced)',
                      style: TextStyle(fontSize: 12.5)),
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          'Openote speaks MCP, the standard AI tools use to '
                          'connect to apps. Any MCP-capable tool can use '
                          'this — the key inside is a password, so paste it '
                          'only into tools you trust.',
                          style: TextStyle(
                              fontSize: 11, color: OnoteColors.graphite400)),
                    ),
                    const SizedBox(height: 6),
                    _snippet(context, _config),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('Copy config'),
                        onPressed: () => _copy(context, _config),
                      ),
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          'Or, for tools with a command line, run once:',
                          style: TextStyle(
                              fontSize: 11, color: OnoteColors.graphite400)),
                    ),
                    const SizedBox(height: 4),
                    _snippet(context, _cli),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('Copy command'),
                        onPressed: () => _copy(context, _cli),
                      ),
                    ),
                  ],
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
