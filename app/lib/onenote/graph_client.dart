/// **Reading a OneNote notebook out of Microsoft Graph.**
///
/// The fetching half, kept apart from [readGraphPage]'s conversion half so
/// that everything expensive to get wrong stays testable without an account.
/// This file is deliberately thin: list, fetch, retry, paginate.
///
/// ## What it is careful about
///
///  * **Throttling.** The OneNote endpoints throttle harder than most of
///    Graph, and a five-year notebook is hundreds of requests. A 429 carries
///    `Retry-After`; honouring it is the difference between an import that
///    takes a few minutes and one that gets the account rate-limited.
///  * **Paging.** Graph returns at most a hundred pages per request and hands
///    back `@odata.nextLink`. Ignoring it silently imports the first hundred
///    pages of a section and nothing else, which is exactly the kind of quiet
///    partial success this project refuses.
///  * **Section groups.** They nest arbitrarily, so they are walked
///    recursively and flattened into the `/`-joined path the importer already
///    understands from `.one` files.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// One notebook, as the picker shows it.
class GraphNotebook {
  const GraphNotebook(
      {required this.id, required this.name, this.lastModified});
  final String id;
  final String name;
  final DateTime? lastModified;
}

/// A section, carrying the section-group path it was found under.
class GraphSectionRef {
  const GraphSectionRef(
      {required this.id, required this.name, this.groupPath = ''});
  final String id;
  final String name;

  /// `Y1/S2`, the way the `.one` parser spells a nested group. Empty at the
  /// notebook's top level.
  final String groupPath;
}

/// A page's metadata, before its content is fetched.
class GraphPageRef {
  const GraphPageRef({
    required this.id,
    required this.title,
    this.level = 0,
    this.createdIso,
  });
  final String id;
  final String title;
  final int level;
  final String? createdIso;
}

/// Something went wrong talking to Graph. Always a sentence: these reach a
/// person.
class GraphException implements Exception {
  GraphException(this.message, {this.details});
  final String message;
  final String? details;
  @override
  String toString() => details == null ? message : '$message ($details)';
}

/// Talks to Graph on behalf of a signed-in student.
class GraphClient {
  GraphClient({required this.token, HttpClient? client})
      : _client = client ?? HttpClient();

  /// How the client gets a live access token. A callback rather than a string
  /// because an import can outlast the one-hour token, and asking for it per
  /// request is what makes the refresh invisible.
  final Future<String> Function() token;

  final HttpClient _client;

  static const String _base = 'https://graph.microsoft.com/v1.0/me/onenote';

  /// Test seam: answers requests without a network.
  @visibleForTesting
  static Future<(int, String, Map<String, String>)> Function(String url)?
      debugFetch;

  /// How many times a throttled request is retried before giving up.
  static const int _maxRetries = 5;

  void close() => _client.close(force: true);

  /// Every notebook the signed-in account can read.
  Future<List<GraphNotebook>> notebooks() async {
    final rows = await _all('$_base/notebooks?\$select=id,displayName,'
        'lastModifiedDateTime&\$orderby=lastModifiedDateTime%20desc');
    return [
      for (final r in rows)
        GraphNotebook(
          id: r['id'] as String,
          name: (r['displayName'] as String?)?.trim().isNotEmpty == true
              ? (r['displayName'] as String).trim()
              : 'Untitled notebook',
          lastModified: DateTime.tryParse(
              (r['lastModifiedDateTime'] as String?) ?? ''),
        ),
    ];
  }

  /// Every section in a notebook, including those inside section groups.
  ///
  /// Flattened, because the importer takes a `/`-joined group path per section
  /// rather than a tree — the same shape the `.one` parser produces from a
  /// folder hierarchy.
  Future<List<GraphSectionRef>> sections(String notebookId) async {
    final out = <GraphSectionRef>[];
    await _collectSections(
        '$_base/notebooks/$notebookId/sections', '', out);
    await _collectGroups(
        '$_base/notebooks/$notebookId/sectionGroups', '', out);
    return out;
  }

  Future<void> _collectSections(
      String url, String groupPath, List<GraphSectionRef> out) async {
    for (final r in await _all('$url?\$select=id,displayName')) {
      out.add(GraphSectionRef(
        id: r['id'] as String,
        name: (r['displayName'] as String?)?.trim().isNotEmpty == true
            ? (r['displayName'] as String).trim()
            : 'Untitled section',
        groupPath: groupPath,
      ));
    }
  }

  /// Section groups nest, so this recurses and joins the names with `/`.
  Future<void> _collectGroups(
      String url, String parentPath, List<GraphSectionRef> out) async {
    for (final g in await _all('$url?\$select=id,displayName')) {
      final id = g['id'] as String;
      final name = (g['displayName'] as String?)?.trim() ?? '';
      final path = parentPath.isEmpty
          ? name
          : '$parentPath/$name';
      await _collectSections('$_base/sectionGroups/$id/sections', path, out);
      await _collectGroups(
          '$_base/sectionGroups/$id/sectionGroups', path, out);
    }
  }

  /// A section's pages, oldest first so the imported order matches OneNote's.
  Future<List<GraphPageRef>> pages(String sectionId) async {
    final rows = await _all('$_base/sections/$sectionId/pages'
        '?\$select=id,title,level,order,createdDateTime'
        '&\$orderby=order&\$top=100');
    return [
      for (final r in rows)
        GraphPageRef(
          id: r['id'] as String,
          title: (r['title'] as String?)?.trim().isNotEmpty == true
              ? (r['title'] as String).trim()
              : 'Untitled page',
          level: (r['level'] as num?)?.toInt() ?? 0,
          createdIso: r['createdDateTime'] as String?,
        ),
    ];
  }

  /// One page's HTML.
  ///
  /// `includeIDs` is asked for because it also turns on the absolute-position
  /// styles the converter reads to place boxes; without it a page comes back
  /// as one undifferentiated flow and every outline lands on top of the next.
  Future<String> pageHtml(String pageId) async {
    final (status, body, _) =
        await _fetch('$_base/pages/$pageId/content?includeIDs=true');
    if (status != 200) {
      throw GraphException('A page could not be read from OneNote.',
          details: 'HTTP $status');
    }
    return body;
  }

  /// An image or attachment's bytes, or null when it cannot be had.
  ///
  /// Null rather than throwing: one unreadable picture must cost that picture
  /// and nothing else, and the page around it is still worth importing.
  Future<Uint8List?> resource(String url) async {
    try {
      final t = await token();
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final chunks = <int>[];
      await for (final c in res) {
        chunks.addAll(c);
      }
      return Uint8List.fromList(chunks);
    } catch (_) {
      return null;
    }
  }

  /// Follow `@odata.nextLink` until Graph stops offering one.
  Future<List<Map<String, dynamic>>> _all(String url) async {
    final out = <Map<String, dynamic>>[];
    var next = url;
    // A notebook with more pages than this is not a notebook any more, and an
    // unbounded loop over a server-supplied link is not something to ship.
    for (var guard = 0; guard < 200; guard++) {
      final (status, body, _) = await _fetch(next);
      if (status != 200) {
        throw GraphException(_friendly(status), details: 'HTTP $status');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      for (final v in (json['value'] as List? ?? const [])) {
        out.add((v as Map).cast<String, dynamic>());
      }
      final link = json['@odata.nextLink'] as String?;
      if (link == null || link.isEmpty) return out;
      next = link;
    }
    return out;
  }

  /// One request, with the throttling retry Graph's OneNote endpoints need.
  Future<(int, String, Map<String, String>)> _fetch(String url) async {
    final fake = debugFetch;
    for (var attempt = 0;; attempt++) {
      final (status, body, headers) = fake != null
          ? await fake(url)
          : await _realFetch(url);
      // 429 is throttling and 503 is "busy, come back"; both carry
      // Retry-After, and both are normal on a large notebook rather than
      // exceptional.
      if ((status == 429 || status == 503) && attempt < _maxRetries) {
        final after = int.tryParse(headers['retry-after'] ?? '') ?? 0;
        // Exponential backoff when the server did not say, because hammering
        // a throttled endpoint is how an account gets a longer ban.
        final wait = after > 0
            ? Duration(seconds: after.clamp(1, 120))
            : Duration(milliseconds: 500 * (1 << attempt));
        await Future<void>.delayed(wait);
        continue;
      }
      return (status, body, headers);
    }
  }

  Future<(int, String, Map<String, String>)> _realFetch(String url) async {
    try {
      final t = await token();
      final req = await _client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final headers = <String, String>{};
      res.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(','));
      return (res.statusCode, body, headers);
    } on SocketException catch (e) {
      throw GraphException(
          'Openote lost its connection to Microsoft. Check your internet and '
          'try again — nothing already imported has been lost.',
          details: '$e');
    }
  }

  static String _friendly(int status) => switch (status) {
        401 => 'Your Microsoft sign-in has expired. Sign in again to carry on.',
        403 => 'Microsoft would not allow Openote to read that notebook.',
        404 => 'That notebook is no longer in OneNote.',
        429 => 'Microsoft is asking Openote to slow down. Try again shortly.',
        >= 500 => 'Microsoft is having trouble at the moment. Try again '
            'shortly — nothing already imported has been lost.',
        _ => 'OneNote could not be read just now.',
      };
}
