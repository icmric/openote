import 'dart:convert';
import 'dart:io';

/// Creating a repository on GitHub, from inside Openote.
///
/// "I want to be able to create and push my notebook to github from within the
/// app, no extra steps required outside the app."
///
/// **The one step that cannot move inside.** Creating a repository is an
/// authenticated call, so GitHub has to know who is asking. That means a
/// token, and a token has to be issued by GitHub — there is no way for an app
/// to mint one for you. What Openote can do is make it the ONLY thing you go
/// elsewhere for, once, and then never ask again: the button below opens the
/// right page with the right scope pre-selected, you paste the token back, and
/// everything after that — creating the repository, setting the remote,
/// pushing, and every sync from then on — happens here.
///
/// **The token is never written into the repository.** Not into
/// `.git/config`, not into the remote URL. The obvious shortcut is
/// `https://<token>@github.com/...`, and it leaves the token in plain text in
/// a file that gets copied around and occasionally pasted into bug reports.
/// It is handed to git through an inline credential helper on the command line
/// instead, per invocation — see `GitSync.push`.
class GitHubApi {
  GitHubApi(this.token, {HttpClient Function()? client, String? baseUrl})
      : _client = client ?? HttpClient.new,
        _base = baseUrl ?? 'https://api.github.com';

  final String token;
  final HttpClient Function() _client;

  /// Where the API lives. Overridden only by tests, which point it at a real
  /// local server rather than a mock — the interesting failures here are in
  /// headers, status codes and JSON shapes, and a mock would just agree with
  /// whatever this file already believes about them.
  final String _base;

  /// The page that issues a token with exactly the access this needs.
  ///
  /// `repo` and nothing else. It is broad — GitHub's classic tokens have no
  /// narrower scope that can still create a repository — and the description
  /// says so rather than hoping nobody looks.
  static const tokenPage =
      'https://github.com/settings/tokens/new'
      '?scopes=repo&description=Openote%20notebook%20sync';

  Future<GitHubResult> _send(
      String method, String path, Map<String, Object?>? body) async {
    final http = _client();
    try {
      final req = await http.openUrl(method, Uri.parse('$_base$path'));
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'Openote')
        ..set('X-GitHub-Api-Version', '2022-11-28');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text = await res.transform(utf8.decoder).join();
      return GitHubResult(res.statusCode, text);
    } catch (e) {
      return GitHubResult(-1, '$e');
    } finally {
      http.close(force: true);
    }
  }

  /// Who the token belongs to, and whether it works at all.
  ///
  /// Called before anything is created, so a bad or expired token is reported
  /// as "that token did not work" rather than as a failed repository creation
  /// the user then has to interpret.
  Future<String?> login() async {
    final r = await _send('GET', '/user', null);
    if (!r.ok) return null;
    try {
      return (jsonDecode(r.body) as Map)['login'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Create a repository and return its clone URL.
  ///
  /// PRIVATE by default, and not as a default anyone has to think about:
  /// these are somebody's notes. A public repository of a student's lecture
  /// notes, created by a checkbox they did not read, is not a mistake this
  /// should make on their behalf.
  Future<GitHubCreate> createRepo(String name,
      {bool private = true, String? description}) async {
    final r = await _send('POST', '/user/repos', {
      'name': name,
      'private': private,
      'description': description ?? 'Openote notebook',
      // No README, no licence, no .gitignore: an initial commit on the remote
      // is a second root the notebook has to be merged with on its first
      // push, for a file nobody asked for.
      'auto_init': false,
    });
    if (r.statusCode == 201) {
      try {
        final j = jsonDecode(r.body) as Map;
        return GitHubCreate.ok(
            j['clone_url'] as String, j['full_name'] as String);
      } catch (_) {
        return const GitHubCreate.failed('GitHub sent a reply I could not read');
      }
    }
    return GitHubCreate.failed(_explain(r));
  }

  /// Turn GitHub's answer into something worth reading.
  ///
  /// The raw JSON body is not: "Validation Failed" with a nested errors array
  /// tells a user nothing about the fact that they already have a repository
  /// with that name.
  static String _explain(GitHubResult r) {
    switch (r.statusCode) {
      case -1:
        return 'Could not reach GitHub. ${r.body}';
      case 401:
        return 'That token was not accepted. It may have expired, or been '
            'copied incompletely.';
      case 403:
        return 'That token does not have permission to create repositories. '
            'It needs the "repo" scope.';
      case 422:
        return r.body.contains('already exists')
            ? 'You already have a repository with that name.'
            : 'GitHub refused those details: ${r.message}';
      default:
        return 'GitHub said ${r.statusCode}: ${r.message}';
    }
  }
}

class GitHubResult {
  const GitHubResult(this.statusCode, this.body);
  final int statusCode;
  final String body;
  bool get ok => statusCode >= 200 && statusCode < 300;

  /// The human-readable part of an error body, when there is one.
  String get message {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['message'] is String) return j['message'] as String;
    } catch (_) {}
    return body.length > 200 ? '${body.substring(0, 200)}…' : body;
  }
}

class GitHubCreate {
  const GitHubCreate.ok(this.cloneUrl, this.fullName) : error = null;
  const GitHubCreate.failed(this.error)
      : cloneUrl = null,
        fullName = null;
  final String? cloneUrl;
  final String? fullName;
  final String? error;
  bool get ok => cloneUrl != null;
}

/// A repository name GitHub will accept, derived from a notebook title.
///
/// GitHub silently rewrites anything it does not like, so a notebook called
/// "Year 12 — Physics" becomes "Year-12-Physics" there and the app would
/// otherwise be reporting a name that does not exist.
String repoNameFor(String title) {
  final cleaned = title
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return cleaned.isEmpty ? 'openote-notebook' : cleaned;
}
