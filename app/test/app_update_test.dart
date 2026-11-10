// Update-through-app: the pure halves. Version comparison, release-JSON
// parsing (the network wrapper is a thin shell around these), and the
// drift guard — kAppVersion IS pubspec's version, enforced here rather
// than remembered.
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/update/app_update.dart';

void main() {
  group('compareVersions', () {
    test('orders plainly and numerically', () {
      expect(compareVersions('0.7.0', '0.6.2'), greaterThan(0));
      expect(compareVersions('0.6.2', '0.7.0'), lessThan(0));
      expect(compareVersions('0.7.0', '0.7.0'), 0);
      // Numeric, not lexicographic: 0.10 beats 0.9.
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
    });

    test('tolerates v-prefix, +build, and missing segments', () {
      expect(compareVersions('v0.7.0', '0.7.0'), 0);
      expect(compareVersions('0.7.0+12', '0.7.0'), 0);
      expect(compareVersions('0.7', '0.7.0'), 0);
      expect(compareVersions('1.0', '0.9.9'), greaterThan(0));
    });
  });

  group('parseLatestRelease', () {
    Map<String, dynamic> release(String tag,
            {List<String> assets = const [],
            bool draft = false,
            bool prerelease = false}) =>
        {
          'tag_name': tag,
          'draft': draft,
          'prerelease': prerelease,
          'html_url': 'https://github.com/icmric/openote/releases/tag/$tag',
          'body': 'notes for $tag',
          'assets': [
            for (final a in assets)
              {
                'name': a,
                'browser_download_url': 'https://example.com/$a',
              }
          ],
        };

    test('newer release with an installer: full auto-update offer', () {
      final u = parseLatestRelease(
          current: '0.6.2',
          json: release('v0.7.0', assets: [
            'openote-0.7.0.zip',
            'openote-0.7.0-windows-x64-setup.exe',
            'openote_0.7.0_amd64.deb',
          ]));
      expect(u, isNotNull);
      expect(u!.version, '0.7.0');
      expect(u.windowsSetupUrl,
          'https://example.com/openote-0.7.0-windows-x64-setup.exe');
      expect(u.notes, contains('v0.7.0'));
    });

    test('same or older: nothing to offer', () {
      expect(parseLatestRelease(current: '0.7.0', json: release('v0.7.0')),
          isNull);
      expect(parseLatestRelease(current: '0.8.0', json: release('v0.7.0')),
          isNull);
    });

    test('drafts and prereleases are never offered', () {
      expect(
          parseLatestRelease(
              current: '0.6.2', json: release('v0.7.0', draft: true)),
          isNull);
      expect(
          parseLatestRelease(
              current: '0.6.2', json: release('v0.7.0', prerelease: true)),
          isNull);
    });

    test('no installer asset: page URL still offered, no auto path', () {
      final u = parseLatestRelease(
          current: '0.6.2',
          json: release('v0.7.0', assets: ['openote-0.7.0.tar.gz']));
      expect(u, isNotNull);
      expect(u!.windowsSetupUrl, isNull);
      expect(u.pageUrl, contains('releases'));
    });
  });

  test('kAppVersion matches pubspec.yaml — the constant cannot drift', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9.]+)\+?', multiLine: true)
        .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml has no version line?');
    expect(kAppVersion, m!.group(1),
        reason: 'bump kAppVersion in update/app_update.dart with pubspec');
  });

  group('checksum of the installer', () {
    test('the checksum asset beside the installer is found', () {
      final u = parseLatestRelease(current: '1.0.0', json: {
        'tag_name': 'v1.0.1',
        'assets': [
          {
            'name': 'openote-1.0.1-windows-x64-setup.exe',
            'browser_download_url': 'https://example.com/a-setup.exe'
          },
          {
            'name': 'openote-1.0.1-windows-x64-setup.exe.sha256',
            'browser_download_url': 'https://example.com/a-setup.exe.sha256'
          },
        ],
      })!;
      expect(u.windowsSetupUrl, 'https://example.com/a-setup.exe');
      expect(u.windowsSetupSha256Url, 'https://example.com/a-setup.exe.sha256');
    });

    test('the checksum file is never mistaken for the installer', () {
      final u = parseLatestRelease(current: '1.0.0', json: {
        'tag_name': 'v1.0.1',
        'assets': [
          {
            'name': 'openote-1.0.1-windows-x64-setup.exe.sha256',
            'browser_download_url': 'https://example.com/sum'
          },
        ],
      })!;
      expect(u.windowsSetupUrl, isNull);
    });

    test('sha256sum output and a bare digest both parse', () {
      const d =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      expect(parseSha256File('$d  openote-setup.exe\n'), d);
      expect(parseSha256File(d.toUpperCase()), d);
      expect(parseSha256File('not a digest'), isNull);
    });

    test('a file matches only its own digest', () async {
      final dir = Directory.systemTemp.createTempSync('onote_sum_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/x.bin')..writeAsBytesSync([1, 2, 3]);
      final good = sha256.convert([1, 2, 3]).toString();
      expect(await fileMatchesSha256(f, good), isTrue);
      expect(await fileMatchesSha256(f, good.toUpperCase()), isTrue);
      expect(await fileMatchesSha256(f, '0' * 64), isFalse,
          reason: 'a different file must not pass');
      expect(await fileMatchesSha256(File('${dir.path}/missing'), good), isFalse);
    });
  });
}
