import 'dart:async';

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

/// **"When did an AI helper last reach Openote?"**, in words.
///
/// v1.0.2 #13. The dialog used to say "connected" when all it knew was that
/// a config file mentioned Openote. A request arriving is the only real
/// evidence that something is on the other end, so this is what is shown.
/// Coarse on purpose: a reader wants "is it working", not a timestamp.
String mcpLastUsedLabel(DateTime? at, DateTime now) {
  if (at == null) return 'No AI helper has used it since Openote opened.';
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'Last used by an AI helper just now.';
  if (d.inMinutes < 60) {
    final m = d.inMinutes;
    return 'Last used by an AI helper $m minute${m == 1 ? '' : 's'} ago.';
  }
  if (d.inHours < 24) {
    final h = d.inHours;
    return 'Last used by an AI helper $h hour${h == 1 ? '' : 's'} ago.';
  }
  return 'Last used by an AI helper more than a day ago.';
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

  /// Re-reads "N minutes ago" while the dialog is open, so it does not sit
  /// at "just now" for as long as somebody looks at it.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _refreshLinked();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

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

  /// Which tools Openote is already in, re-read after every connect so a
  /// button changes colour the moment it becomes true.
  ///
  /// Held in state rather than read in `build`: this dialog rebuilds on every
  /// notification the app makes, and four file reads per rebuild to colour
  /// four buttons is not a trade worth making.
  ({bool claudeCode, bool claudeApp, bool geminiCli, bool chatGpt})? _linked;

  void _refreshLinked() {
    try {
      _linked = connectedClients();
    } catch (_) {
      // Unknown is a fine answer; the buttons simply all read "Connect".
      _linked = null;
    }
  }

  void _connect(
      ClaudeConnectResult Function({required int port, required String token})
          connector) {
    setState(() {
      _result = connector(port: app.mcpPort!, token: app.mcpToken!);
      _refreshLinked();
    });
  }

  /// **Blue means set up, brass means not.**
  ///
  /// The two styles were already in use here and carried no meaning — Claude
  /// Code was filled and the rest tonal, which just looked arbitrary. Tying
  /// them to the one fact the reader wants makes the row consistent AND
  /// informative, and needs no colour that is not already in the theme.
  ///
  /// **"Set up", not "connected"** (v1.0.2 #13): what [connectedClients]
  /// knows is that the tool's config file has an `openote` entry. That is
  /// one step better than a flag flipped on click and still says nothing
  /// about whether the tool is running or can reach us. Whether anything
  /// actually has is the status line's job, from [McpServer.lastRequest].
  ///
  /// A set-up button stays pressable: pressing it again rewrites the entry,
  /// which is how a moved port or a regenerated token is put right by hand.
  Widget _clientButton(
      String name,
      bool setUp,
      ClaudeConnectResult Function({required int port, required String token})
          connector) {
    final icon = Icon(setUp ? Icons.check : Icons.add_link, size: 16);
    final label = Text(setUp ? '$name — set up' : 'Set up $name');
    void press() => _connect(connector);
    return setUp
        ? FilledButton.icon(icon: icon, label: label, onPressed: press)
        : FilledButton.tonalIcon(icon: icon, label: label, onPressed: press);
  }

  /// A notifier that never changes, for the moment before the server exists.
  static final _never = ValueNotifier<DateTime?>(null);

  /// **What is actually known**, in the words the reader would use.
  ///
  /// "Ready" only once the server has bound, which it either did or did not.
  /// Then when an AI helper last reached it — the one fact that answers "is
  /// anything talking to me". And while nothing has, the thing that would
  /// otherwise be unexplainable from inside the app: an AI helper looks for
  /// Openote once, when it starts, and never retries, so one that was opened
  /// first stays unable to see it however healthy Openote becomes.
  Widget _status(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ValueListenableBuilder<DateTime?>(
          valueListenable: app.mcpLastRequest ?? _never,
          builder: (context, at, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.circle,
                    size: 9,
                    color: at == null
                        ? OnoteColors.graphite400
                        : Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Ready. ${mcpLastUsedLabel(at, DateTime.now())}',
                      style: const TextStyle(fontSize: 12, height: 1.4)),
                ),
              ]),
              if (at == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 15),
                  child: Text(
                      'An AI helper looks for Openote when it starts. If '
                      'yours was already open, restart it.',
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: OnoteColors.graphite400)),
                ),
            ],
          ),
        ),
      );

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
              const SizedBox(height: 6),
              // Both halves, because the second is what keeps the first
              // honest: a passcode locks Openote's doors, not the file
              // (state/page_protection.dart), and Claude Code — one of the
              // buttons below — can open files.
              const Text(
                'Anything with a passcode stays private: an AI helper can\'t '
                'see it or change it, even while you have it unlocked. A '
                'passcode locks Openote, not the file itself, so an AI tool '
                'that can open files on your computer could still read it.',
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
              if (app.mcpEnabled && app.mcpListening) _status(context),
              if (app.mcpEnabled) ...[
                const SizedBox(height: 10),
                // One row, one style rule — see [_clientButton].
                //
                // The two apps are the ones most people actually use, so they
                // come first; the CLIs follow. "Claude app" and "ChatGPT app"
                // are named as apps deliberately, because the websites cannot
                // do this and the distinction is the whole point.
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _clientButton('Claude app', _linked?.claudeApp ?? false,
                      connectClaudeApp),
                  _clientButton('ChatGPT app', _linked?.chatGpt ?? false,
                      connectChatGpt),
                  _clientButton('Claude Code', _linked?.claudeCode ?? false,
                      connectClaudeCode),
                  _clientButton('Gemini CLI', _linked?.geminiCli ?? false,
                      connectGeminiCli),
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
                          "The ChatGPT website can't be connected: its "
                          "connectors run on OpenAI's servers, which can't "
                          'see your computer. The button above is for the '
                          'desktop app, which reads its settings from this '
                          'computer. The Gemini app is the website case too '
                          '— its CLI has a button.',
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
                    // The port, where the jargon lives. It either bound or it
                    // did not, so this is a fact rather than an inference.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          app.mcpListening
                              ? 'Listening on port ${app.mcpPort}, on this '
                                  'computer only.'
                              : 'Not listening.',
                          style: const TextStyle(
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
