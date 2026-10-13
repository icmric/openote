// Reading a drive's volume label, which is what tells two Google Drive
// accounts apart in the folder picker.
//
// Google Drive mounts one letter per signed-in account, so a personal and a
// work account are two rows both saying "Google Drive" with nothing to choose
// between them. Measured on the owner's machine: G: and I:, identical rows.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/sync/cloud_folders.dart';
import 'package:openote/sync/volume_label.dart';

void main() {
  group('volume labels', () {
    test('C: answers without throwing, on Windows', () {
      if (!Platform.isWindows) return markTestSkipped('Windows only');
      // Deliberately no assertion about the VALUE. A system drive may be
      // unlabelled, which is a null, and a test that demanded a string here
      // would fail on a perfectly ordinary machine. What matters is that the
      // call completes: this is FFI into kernel32 on a path that runs every
      // time the sync dialog opens.
      platformVolumeLabel('C');
    });

    test('a letter that is not mounted is null, not an exception', () {
      if (!Platform.isWindows) return markTestSkipped('Windows only');
      // Z: is conventionally free. If it happens to be mounted here, a label is
      // an equally fine answer — the point is that neither throws.
      platformVolumeLabel('Z');
    });

    test('nonsense input is null rather than a crash', () {
      expect(platformVolumeLabel(''), isNull);
    });
  });

  group('how a folder names itself', () {
    test('an account and a drive letter both reach the label', () {
      const f = CloudFolder(
          name: 'Google Drive',
          path: r'G:\My Drive',
          kind: CloudKind.googleDrive,
          account: 'someone@example.com -...');
      expect(f.label, 'Google Drive · someone@example.com (G:)',
          reason: "Windows' 32-character truncation is tidied away");
    });

    test('a label cut mid-word falls back to the address', () {
      // Measured on the owner's machine: the work account's label arrives as
      // `eric@wildwalks.com - Google D...`, which must not be shown as-is.
      const f = CloudFolder(
          name: 'Google Drive',
          path: r'I:\My Drive',
          kind: CloudKind.googleDrive,
          account: 'eric@wildwalks.com - Google D...');
      expect(f.label, 'Google Drive · eric@wildwalks.com (I:)');
    });

    test('a label that was never truncated is left exactly as it is', () {
      const f = CloudFolder(
          name: 'Google Drive',
          path: r'G:\My Drive',
          kind: CloudKind.googleDrive,
          account: 'Work');
      expect(f.label, 'Google Drive · Work (G:)');
    });

    test('a drive with no label still says which drive', () {
      const f = CloudFolder(
          name: 'Google Drive',
          path: r'G:\My Drive',
          kind: CloudKind.googleDrive);
      expect(f.label, 'Google Drive · G:',
          reason: 'the letter is the only thing distinguishing two accounts '
              'when the volume has no label');
    });

    test('a folder under the home directory is just its provider', () {
      const f = CloudFolder(
          name: 'Dropbox',
          path: '/home/eric/Dropbox',
          kind: CloudKind.dropbox);
      expect(f.label, 'Dropbox',
          reason: 'there is no drive letter to report and no account to read');
    });

    test('a deep path on C: does not advertise the system drive', () {
      // "OneDrive · C:" is noise. The letter earns its place only when it is
      // what distinguishes two mounts of the same provider.
      const f = CloudFolder(
          name: 'OneDrive',
          path: r'C:\Users\eric\OneDrive',
          kind: CloudKind.oneDrive);
      expect(f.label, 'OneDrive');
    });

    test('`name` is left alone, because prose uses it', () {
      // "Your notebook is in ${folder.name} now" must not become "Your
      // notebook is in Google Drive · someone@example.com (G:) now".
      const f = CloudFolder(
          name: 'Google Drive',
          path: r'G:\My Drive',
          kind: CloudKind.googleDrive,
          account: 'someone@example.com -...');
      expect(f.name, 'Google Drive');
    });
  });
}
