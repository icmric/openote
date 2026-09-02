// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get commonBack => 'Back';

  @override
  String get commonSkip => 'Skip';

  @override
  String get commonNext => 'Next';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDetailsAdvanced => 'Details (advanced)';

  @override
  String get onboardingStep1Title => 'The page is a canvas';

  @override
  String get onboardingStep1Body =>
      'Click anywhere and start typing — a box appears where you clicked, and only once you type. Move one by the bar along its top, and drag pictures in from anywhere.';

  @override
  String get onboardingStep2Title => 'Maths and drawing, in with the words';

  @override
  String get onboardingStep2Body =>
      'Type 1/2 or press Alt+= and it builds up as real notation as you write, in a box of its own or mid-sentence. The Draw tab takes a pen, a finger or the mouse.';

  @override
  String get onboardingStep3Title => 'Your notes are a file you own';

  @override
  String get onboardingStep3Body =>
      'One open, readable file per notebook — no account, no lock-in. Put it in a folder your cloud already keeps in step and every device stays together.';

  @override
  String get onboardingStartWriting => 'Start writing';

  @override
  String get onboardingSyncTitle => 'Sync with another device';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive, OneDrive, iCloud, Dropbox, Syncthing, a NAS — or a GitHub repository.';

  @override
  String get onboardingSyncBodyAlso =>
      'Not one of the above? Choose the folder yourself.';

  @override
  String get onboardingSyncAction => 'Set up…';

  @override
  String get onboardingOneNoteTitle => 'Bring notes over from OneNote';

  @override
  String get onboardingOneNoteBody =>
      'Pages, formatting, images, ink and tags from a .onepkg. Runs in the background — keep going while it works.';

  @override
  String get onboardingOneNoteAction => 'Choose file…';

  @override
  String get onboardingOnePkgFileType => 'OneNote notebook package';

  @override
  String get onboardingOneNoteHowTo => 'How do I export?';

  @override
  String get onboardingOneNoteHideSteps => 'Hide steps';

  @override
  String get onboardingExportTitle => 'Exporting from OneNote';

  @override
  String get onboardingExportSteps =>
      '1. Open OneNote for Windows (the desktop app — the Store and web versions cannot export).\n2. Let the notebook finish syncing, so everything is on this machine.\n3. File ▸ Export ▸ Notebook ▸ OneNote Package (*.onepkg), then Export.\n4. Come back here and choose that file.';

  @override
  String get onboardingExportMacNote =>
      'On a Mac, or with only the Store version: export one section at a time as .one, or ask a Windows machine to make the .onepkg. Openote never signs into your Microsoft account — it only reads the file you hand it.';

  @override
  String onboardingImportingFile(String fileName) {
    return 'Importing $fileName';
  }

  @override
  String get onboardingImportRunning =>
      'Keep going — this runs in the background, and the card in the corner will say when it\'s done.';

  @override
  String get onboardingImportDone => 'Your notebook is ready';

  @override
  String get onboardingOpenFailed => 'Openote couldn\'t open that notebook.';

  @override
  String get onboardingNoNativeCore =>
      'OneNote import needs the native core, which this build does not include.';

  @override
  String onboardingReadFailed(String reason) {
    return 'Couldn\'t read that file: $reason';
  }
}
