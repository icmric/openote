/// Update through the app (PLANNING.md, shipped v0.7.0).
///
/// The shape: a silent check against GitHub's latest-release API on every
/// launch; when something newer exists, a button appears in the command
/// bar. Clicking it opens a dialog that saves everything, downloads the
/// Windows installer with a progress bar behind a modal barrier, then runs
/// it silently and exits — the installer replaces the files and relaunches
/// Openote itself (the .iss has a silent-mode relaunch entry). Platforms
/// without an installer artifact get an "open the download page" button
/// instead of a pretend-automatic flow.
///
/// Every network path here fails SILENT and NULL: an update check must
/// never cost a user who is offline, rate-limited, or behind a captive
/// portal anything at all.
library;

import 'dart:convert';
import 'dart:io';

/// The running app's version. pubspec.yaml is the source of truth;
/// app_update_test.dart fails the build the moment the two drift.
const kAppVersion = '0.7.1';

const _kLatestReleaseApi =
    'https://api.github.com/repos/icmric/openote/releases/latest';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.pageUrl,
    this.notes,
    this.windowsSetupUrl,
  });

  final String version;

  /// The human release page — the fallback for every platform.
  final String pageUrl;
  final String? notes;

  /// The `-setup.exe` asset, when the release has one.
  final String? windowsSetupUrl;
}

/// Numeric dotted-version compare. Tolerates a leading `v`, a `+build`
/// suffix and unequal segment counts; 0.10.0 beats 0.9.9.
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final dash = s.indexOf('-');
    if (dash >= 0) s = s.substring(0, dash);
    return [for (final p in s.split('.')) int.tryParse(p) ?? 0];
  }

  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}

/// Pure half of the check, so tests can feed it release JSON directly.
/// Returns null when there is nothing newer to offer.
UpdateInfo? parseLatestRelease(
    {required String current, required Map<String, dynamic> json}) {
  if (json['draft'] == true || json['prerelease'] == true) return null;
  final tag = '${json['tag_name'] ?? ''}';
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  if (version.isEmpty || compareVersions(version, current) <= 0) return null;

  String? setup;
  final assets = json['assets'];
  if (assets is List) {
    for (final a in assets.whereType<Map>()) {
      if ('${a['name']}'.endsWith('-setup.exe')) {
        setup = a['browser_download_url'] as String?;
      }
    }
  }
  return UpdateInfo(
    version: version,
    notes: json['body'] as String?,
    windowsSetupUrl: setup,
    pageUrl: json['html_url'] as String? ??
        'https://github.com/icmric/openote/releases',
  );
}

/// The launch-time check. Null on ANY failure, by design.
Future<UpdateInfo?> fetchLatestUpdate({String current = kAppVersion}) async {
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_kLatestReleaseApi));
      req.headers.set(HttpHeaders.userAgentHeader, 'openote/$current');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final json = jsonDecode(await utf8.decodeStream(res));
      if (json is! Map<String, dynamic>) return null;
      return parseLatestRelease(current: current, json: json);
    } finally {
      client.close();
    }
  } catch (_) {
    return null;
  }
}

/// Stream a release asset to [toPath]. GitHub asset URLs redirect to a
/// CDN; HttpClient follows redirects on GET by itself. Null on failure.
Future<File?> downloadUpdate(String url, String toPath,
    {void Function(int received, int total)? onProgress}) async {
  try {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'openote/$kAppVersion');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final total = res.contentLength;
      final file = File(toPath);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      // A truncated download must not be handed to the OS as an installer.
      if (total > 0 && received != total) {
        try {
          file.deleteSync();
        } catch (_) {}
        return null;
      }
      return file;
    } finally {
      client.close();
    }
  } catch (_) {
    return null;
  }
}
