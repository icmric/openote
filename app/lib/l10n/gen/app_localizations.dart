import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Button: return to the previous step of a multi-step flow.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Button: leave a flow without completing it.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get commonSkip;

  /// Button: advance to the next step of a multi-step flow.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// Button: open the notebook named beside it.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// Button: dismiss a dialog without acting.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Fold-out label hiding a raw technical error message from someone who does not want it.
  ///
  /// In en, this message translates to:
  /// **'Details (advanced)'**
  String get commonDetailsAdvanced;

  /// Welcome flow, step 1 of 3. Heading over an animation of clicking on an empty page and typing.
  ///
  /// In en, this message translates to:
  /// **'The page is a canvas'**
  String get onboardingStep1Title;

  /// Welcome flow, step 1 of 3. The core interaction: the page is free-form, not a document that flows top to bottom.
  ///
  /// In en, this message translates to:
  /// **'Click anywhere and start typing — a box appears where you clicked, and only once you type. Move one by the bar along its top, and drag pictures in from anywhere.'**
  String get onboardingStep1Body;

  /// Welcome flow, step 2 of 3. Heading over a rendered equation and a pen stroke.
  ///
  /// In en, this message translates to:
  /// **'Maths and drawing, in with the words'**
  String get onboardingStep2Title;

  /// Welcome flow, step 2 of 3. 'Alt+=' is a keyboard shortcut and must stay as typed. '1/2' is literally what the user types to get a fraction.
  ///
  /// In en, this message translates to:
  /// **'Type 1/2 or press Alt+= and it builds up as real notation as you write, in a box of its own or mid-sentence. The Draw tab takes a pen, a finger or the mouse.'**
  String get onboardingStep2Body;

  /// Welcome flow, step 3 of 3. Heading over a diagram of one file, a synced folder, and two computers.
  ///
  /// In en, this message translates to:
  /// **'Your notes are a file you own'**
  String get onboardingStep3Title;

  /// Welcome flow, step 3 of 3. 'no lock-in' means the notes are not trapped in a proprietary service.
  ///
  /// In en, this message translates to:
  /// **'One open, readable file per notebook — no account, no lock-in. Put it in a folder your cloud already keeps in step and every device stays together.'**
  String get onboardingStep3Body;

  /// Button ending the welcome flow and putting the user on the page.
  ///
  /// In en, this message translates to:
  /// **'Start writing'**
  String get onboardingStartWriting;

  /// Welcome flow: one of three ways to get notes in.
  ///
  /// In en, this message translates to:
  /// **'Sync with another device'**
  String get onboardingSyncTitle;

  /// Shown when no existing notebook was found nearby. All names are products and stay untranslated; 'NAS' is a network drive at home.
  ///
  /// In en, this message translates to:
  /// **'Drive, OneDrive, iCloud, Dropbox, Syncthing, a NAS — or a GitHub repository.'**
  String get onboardingSyncBodyFirst;

  /// Shown when Openote DID find notebooks and has already listed them above.
  ///
  /// In en, this message translates to:
  /// **'Not one of the above? Choose the folder yourself.'**
  String get onboardingSyncBodyAlso;

  /// Button opening the sync setup dialog.
  ///
  /// In en, this message translates to:
  /// **'Set up…'**
  String get onboardingSyncAction;

  /// Welcome flow: importing an existing Microsoft OneNote notebook. 'OneNote' is a product name.
  ///
  /// In en, this message translates to:
  /// **'Bring notes over from OneNote'**
  String get onboardingOneNoteTitle;

  /// '.onepkg' is a file extension and must not be translated. 'ink' means handwriting.
  ///
  /// In en, this message translates to:
  /// **'Pages, formatting, images, ink and tags from a .onepkg. Runs in the background — keep going while it works.'**
  String get onboardingOneNoteBody;

  /// Button opening the file picker for a .onepkg.
  ///
  /// In en, this message translates to:
  /// **'Choose file…'**
  String get onboardingOneNoteAction;

  /// The file-type name shown in the operating system's own file picker, next to the .onepkg extension it filters on.
  ///
  /// In en, this message translates to:
  /// **'OneNote notebook package'**
  String get onboardingOnePkgFileType;

  /// Link folding out the OneNote export instructions.
  ///
  /// In en, this message translates to:
  /// **'How do I export?'**
  String get onboardingOneNoteHowTo;

  /// Link folding the OneNote export instructions away again.
  ///
  /// In en, this message translates to:
  /// **'Hide steps'**
  String get onboardingOneNoteHideSteps;

  /// Heading over the numbered instructions for getting a .onepkg out of OneNote.
  ///
  /// In en, this message translates to:
  /// **'Exporting from OneNote'**
  String get onboardingExportTitle;

  /// Four numbered steps. 'File ▸ Export ▸ Notebook ▸ OneNote Package' is a menu path INSIDE OneNote — translate it to match OneNote's own wording in this language, or leave it in English if unsure. Keep the newlines and the numbering.
  ///
  /// In en, this message translates to:
  /// **'1. Open OneNote for Windows (the desktop app — the Store and web versions cannot export).\n2. Let the notebook finish syncing, so everything is on this machine.\n3. File ▸ Export ▸ Notebook ▸ OneNote Package (*.onepkg), then Export.\n4. Come back here and choose that file.'**
  String get onboardingExportSteps;

  /// '.one' and '.onepkg' are file extensions and must not be translated.
  ///
  /// In en, this message translates to:
  /// **'On a Mac, or with only the Store version: export one section at a time as .one, or ask a Windows machine to make the .onepkg. Openote never signs into your Microsoft account — it only reads the file you hand it.'**
  String get onboardingExportMacNote;

  /// Progress row while a OneNote package is being read.
  ///
  /// In en, this message translates to:
  /// **'Importing {fileName}'**
  String onboardingImportingFile(String fileName);

  /// Reassurance under the progress spinner: the user does not have to wait.
  ///
  /// In en, this message translates to:
  /// **'Keep going — this runs in the background, and the card in the corner will say when it\'s done.'**
  String get onboardingImportRunning;

  /// Shown when the OneNote import has finished successfully.
  ///
  /// In en, this message translates to:
  /// **'Your notebook is ready'**
  String get onboardingImportDone;

  /// Error shown when opening a notebook Openote found on this computer failed. The reason itself is behind commonDetailsAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Openote couldn\'t open that notebook.'**
  String get onboardingOpenFailed;

  /// Error: this build was compiled without the Rust library that reads .onepkg files. 'the native core' is a component of Openote.
  ///
  /// In en, this message translates to:
  /// **'OneNote import needs the native core, which this build does not include.'**
  String get onboardingNoNativeCore;

  /// Error shown when the chosen .onepkg could not be read at all.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that file: {reason}'**
  String onboardingReadFailed(String reason);
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return LEn();
  }

  throw FlutterError(
      'L.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
