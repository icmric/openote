// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class LDe extends L {
  LDe([String locale = 'de']) : super(locale);

  @override
  String get commonBack => 'Zurück';

  @override
  String get commonSkip => 'Überspringen';

  @override
  String get commonNext => 'Weiter';

  @override
  String get commonOpen => 'Öffnen';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonDetailsAdvanced => 'Details (für Fortgeschrittene)';

  @override
  String objectRowBackground(String kind) {
    return 'Hintergrund: $kind';
  }

  @override
  String get objectRowBackgroundBlank => 'leer';

  @override
  String get objectRowBackgroundGrid => 'kariert';

  @override
  String get objectRowBackgroundDotted => 'gepunktet';

  @override
  String get objectRowBackgroundRuled => 'liniert';

  @override
  String objectRowPageMode(String paper, String landscape) {
    return 'Seitenmodus: $paper$landscape — klicken für Leinwand';
  }

  @override
  String get objectRowLandscapeSuffix => ' quer';

  @override
  String get objectRowCanvasMode =>
      'Leinwandmodus: grenzenlos — klicken für Seiten';

  @override
  String get objectRowPaperSize => 'Papierformat';

  @override
  String get objectRowLandscape => 'Querformat';

  @override
  String get objectRowSnapOn =>
      'Am Raster ausrichten: EIN (beim Ziehen sichtbar)';

  @override
  String get objectRowSnapOff => 'Am Raster ausrichten: AUS — frei platzieren';

  @override
  String get objectRowZoomOut => 'Verkleinern  (Strg+-)';

  @override
  String get objectRowZoomIn => 'Vergrößern  (Strg+=)';

  @override
  String get objectRowZoomReset =>
      'Zurück auf 100 % und an den Seitenanfang  (Strg+0)';

  @override
  String get objectRowZoomFit => 'Auf den Inhalt zoomen';

  @override
  String get objectRowWordCount =>
      'Wörter auf dieser Seite — klicken für Zeichen und Lesezeit';

  @override
  String get objectRowWords => 'Wörter';

  @override
  String get objectRowCharacters => 'Zeichen';

  @override
  String get objectRowCharactersNoSpaces => 'Ohne Leerzeichen';

  @override
  String get objectRowReadingTime => 'Lesezeit';

  @override
  String objectRowMinutes(int n) {
    return '$n Min.';
  }

  @override
  String objectRowWordTally(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted Wörter',
      one: '1 Wort',
      zero: 'keine Wörter',
    );
    return '$_temp0';
  }

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent %';
  }

  @override
  String get barTabHome => 'Start';

  @override
  String get barTabInsert => 'Einfügen';

  @override
  String get barTabDraw => 'Zeichnen';

  @override
  String get barEquationBadge => 'Formel';

  @override
  String barUpdateTo(String version) {
    return 'Auf $version aktualisieren…';
  }

  @override
  String get barDone => 'Fertig';

  @override
  String get barStudy => 'Lernen';

  @override
  String get barPlanner => 'Planer';

  @override
  String get barFindTags => 'Markierungen finden';

  @override
  String get barPageOutline => 'Seitenübersicht';

  @override
  String get barLinks => 'Links und Rückverweise';

  @override
  String get barFindOnPage => 'Auf der Seite suchen';

  @override
  String get barFindOnPageTip => 'Auf der Seite suchen  (Strg+F)';

  @override
  String get barExport => 'Exportieren';

  @override
  String get barExportTip => 'Seite exportieren…';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

  @override
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPrint => 'Drucken…';

  @override
  String get barExportPdfPicture => 'PDF — Bild der Seite';

  @override
  String get barExportCanvas => 'Für Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => 'Nur die Zeichnung (.inkml)';

  @override
  String get barExportNotebook =>
      'Das ganze Notizbuch als Ordner und Dateien speichern…';

  @override
  String get barExportNotebookBusy => 'Notizbuch wird gespeichert…';

  @override
  String barExportPageProgress(int done, int total) {
    return 'Seite $done von $total…';
  }

  @override
  String barExportedTo(String path) {
    return 'Exportiert nach $path';
  }

  @override
  String get barSettings => 'Einstellungen';

  @override
  String get barSettingsTip => 'Einstellungen…';

  @override
  String get barUndo => 'Rückgängig  (Strg+Z)';

  @override
  String get barRedo => 'Wiederholen  (Strg+Y)';

  @override
  String get barBold => 'Fett  (Strg+B)';

  @override
  String get barItalic => 'Kursiv  (Strg+I)';

  @override
  String get barUnderline => 'Unterstrichen  (Strg+U)';

  @override
  String get barStrikethrough => 'Durchgestrichen';

  @override
  String get barInlineCode => 'Code im Text';

  @override
  String get barHighlight => 'Markieren';

  @override
  String get barHeading1 => 'Überschrift 1';

  @override
  String get barBulletList => 'Aufzählung';

  @override
  String get barNumberedList => 'Nummerierte Liste';

  @override
  String get barCheckbox => 'Kästchen';

  @override
  String get barQuote => 'Zitat';

  @override
  String get barTextColour => 'Textfarbe anwenden';

  @override
  String get barTextFont => 'Schriftart…';

  @override
  String get barClickIntoTextBox => 'Klicke in ein Textfeld';

  @override
  String get barToolSelect => 'Auswählen / verschieben  (V)';

  @override
  String get barToolText => 'Text  (T)';

  @override
  String get barToolPen => 'Stift  (P)';

  @override
  String get barToolHighlighter => 'Textmarker  (H)';

  @override
  String get barToolEraser => 'Radierer  (E)';

  @override
  String get barToolLasso => 'Handschrift mit dem Lasso auswählen';

  @override
  String get barEraserSplit => 'Trennt Striche dort, wo du reibst';

  @override
  String get barEraserWhole => 'Entfernt jeden Strich, den du berührst';

  @override
  String get barLassoHint =>
      'Ziehe eine Schlinge um die Handschrift — dann verschieben oder löschen';

  @override
  String get barPickPenHint =>
      'Nimm den Stift oder den Textmarker zum Zeichnen';

  @override
  String get barTouchDrawing =>
      'Mit dem Finger zeichnen.\nAuto: Der Finger zeichnet, bis du den Stift nimmst; danach schiebt der Finger die Seite, damit der Handballen nichts hinterlässt.\nZwei Finger schieben und zoomen immer.';

  @override
  String get barPenProximity =>
      'Den Stift an die Seite halten schaltet auf Tinte um.\nWählst du ein anderes Werkzeug, während der Stift in der Nähe\nist, bleibt es, bis der Stift weggeht und wiederkommt. Das\nhintere Ende des Stifts (oder seine Taste) radiert.';

  @override
  String get barTextSize => 'Schriftgröße (Punkt)';

  @override
  String get barTextSizeDisabled =>
      'Klicke in ein Textfeld, um seine Größe zu ändern';

  @override
  String get barFontSizeDefault => 'Standard';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barTagLine => 'Diese Zeile markieren (Aufgabe, Wichtig, Frage…)';

  @override
  String barTagged(String tags) {
    return 'Markiert: $tags';
  }

  @override
  String get barDueDateSet => 'Fällig am…';

  @override
  String get barDueDateChange => 'Fälligkeitsdatum ändern…';

  @override
  String get barDueDateClear => 'Fälligkeitsdatum entfernen';

  @override
  String get barDueDatePickerTitle => 'Fällig am';

  @override
  String get barDueDatePickerConfirm => 'Setzen';

  @override
  String get barMakeCardFromLine => 'Aus dieser Zeile eine Karteikarte machen';

  @override
  String get barNewCard => 'Neue Karteikarte';

  @override
  String get barQuestionCard => 'Frage-Karte';

  @override
  String get barDefinitionCard => 'Definitions-Karte';

  @override
  String get barBlankOut => 'Auswahl ausblenden';

  @override
  String get barBlankOutNeedsSelection =>
      'Markiere zuerst die Wörter, die ausgeblendet werden sollen.';

  @override
  String get barOpenStudyPanel => 'Lernbereich öffnen';

  @override
  String get barStudyEmpty =>
      'Lernen — markiere eine Zeile als Frage oder Definition, um eine Karte daraus zu machen';

  @override
  String barStudyDue(int due, int total, String countdown) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total Karten',
      one: '1 Karte',
    );
    return '$due von $_temp0 in diesem Abschnitt fällig$countdown';
  }

  @override
  String barStudyExamCountdown(String when) {
    return ' · Prüfung $when';
  }

  @override
  String get barPlannerEmpty => 'Planer — alle deine Termine an einem Ort';

  @override
  String barPlannerToday(int count) {
    return 'Planer — $count für heute';
  }

  @override
  String barPlannerOverdue(int count) {
    return 'Planer — $count für heute oder überfällig';
  }

  @override
  String barRemindersWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Erinnerungen',
      one: '1 Erinnerung',
    );
    return '$_temp0 warten';
  }

  @override
  String get barEscWhenDone => 'Esc, wenn du fertig bist';

  @override
  String barSaveFailed(String reason) {
    return 'Konnte nicht gespeichert werden: $reason';
  }

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get navSearchHint => 'Suchen oder springen zu…';

  @override
  String navNoMatches(String query) {
    return 'Keine Treffer für „$query“';
  }

  @override
  String get navInPageContent => 'Im Seiteninhalt';

  @override
  String get navUntitled => 'Ohne Titel';

  @override
  String get navNoSections =>
      'Noch keine Abschnitte.\nLege einen an, um loszulegen.';

  @override
  String get navNewSection => 'Neuer Abschnitt';

  @override
  String navNewPageIn(String section) {
    return 'Neue Seite in $section';
  }

  @override
  String get navNoPages => 'Noch keine Seiten';

  @override
  String get navSection => 'Abschnitt';

  @override
  String get navNewSectionGroup => 'Neue Abschnittsgruppe';

  @override
  String get navRecycleBin => 'Papierkorb';

  @override
  String get navHome => 'Start';

  @override
  String get navHomeTip => 'Start — Favoriten und zuletzt geöffnet';

  @override
  String get navHomeEmpty =>
      'Hier ist noch nichts.\n\nKlicke mit der rechten Maustaste auf eine Seite und wähle Favorit, um sie anzuheften; Seiten, die du öffnest, erscheinen unter Zuletzt.';

  @override
  String get navComingUp => 'DEMNÄCHST';

  @override
  String navAllCount(int total) {
    return 'Alle $total';
  }

  @override
  String get navOpen => 'Öffnen';

  @override
  String get navExpand => 'Navigator ausklappen  (Strg+\\)';

  @override
  String get navCollapse => 'Navigator einklappen  (Strg+\\)';

  @override
  String get navNotebooksTip =>
      'Notizbücher — wechseln, umbenennen, duplizieren, importieren';

  @override
  String get navDeletesSoon => 'Wird bald gelöscht';

  @override
  String navDeletesInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Wird in $days Tagen gelöscht',
      one: 'Wird in 1 Tag gelöscht',
    );
    return '$_temp0';
  }

  @override
  String get navBinEmpty => 'Nichts gelöscht.';

  @override
  String navBinRetention(int days) {
    return 'Was hier liegt, wird nach $days Tagen endgültig gelöscht.';
  }

  @override
  String get navBinNotebooks => 'Notizbücher';

  @override
  String get navBinItems => 'Einträge';

  @override
  String get navRestore => 'Wiederherstellen';

  @override
  String get navDeletePermanently => 'Endgültig löschen';

  @override
  String get navClose => 'Schließen';

  @override
  String get navDeleteForeverTitle => 'Endgültig löschen?';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '„$title“ und alle Seiten darin werden für immer entfernt. Das lässt sich nicht rückgängig machen.$caveat';
  }

  @override
  String get navDeleteForever => 'Für immer löschen';

  @override
  String navLockedCannotDelete(String title) {
    return '„$title“ ist gesperrt. Entferne den Code, bevor du sie löschst.';
  }

  @override
  String navDeletedRestorable(String title) {
    return '„$title“ gelöscht — du kannst sie im Papierkorb wiederherstellen.';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '„$title“ ist gesperrt. Sie ist in Openote versteckt, nicht in der Datei verschlüsselt.';
  }

  @override
  String navPasscodeRemoved(String title) {
    return 'Code von „$title“ entfernt.';
  }

  @override
  String navSavedTo(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String get navLinkCopied =>
      'Link kopiert — füge ihn in eine beliebige Seite ein';

  @override
  String get navMoveSectionTo => 'Abschnitt verschieben nach…';

  @override
  String get navNoGroupTopLevel => '(Keine Gruppe — oberste Ebene)';

  @override
  String get navSaveTemplateTitle => 'Als Vorlage speichern';

  @override
  String get navSave => 'Speichern';

  @override
  String get navTemplateNameHint => 'Name der Vorlage';

  @override
  String navTemplateSaved(String name) {
    return 'Vorlage „$name“ gespeichert';
  }

  @override
  String get navNoTemplates =>
      'Noch keine Vorlagen — nimm zuerst „Als Vorlage speichern…“.';

  @override
  String get navApplyTemplate => 'Vorlage anwenden';

  @override
  String get navColour => 'Farbe';

  @override
  String get navColourDefault => 'Standard';

  @override
  String navExamCountdown(String when, String countdown) {
    return 'Prüfung $when · $countdown…';
  }

  @override
  String get navMenuMoveUp => 'Nach oben';

  @override
  String get navMenuMoveDown => 'Nach unten';

  @override
  String get navMenuNewPage => 'Neue Seite';

  @override
  String get navMenuMoveToGroup => 'In eine Gruppe verschieben…';

  @override
  String get navMenuSortAZ => 'Seiten von A bis Z sortieren';

  @override
  String get navMenuSortEdited => 'Nach letzter Änderung sortieren';

  @override
  String get navMenuExportSectionPdf => 'Abschnitt als PDF exportieren…';

  @override
  String get navMenuPrintSection => 'Abschnitt drucken…';

  @override
  String get navMenuRemoveExam => 'Prüfungsdatum entfernen';

  @override
  String get navMenuSetExam => 'Prüfungsdatum setzen…';

  @override
  String get navMenuMakeSubpage => 'Zur Unterseite machen';

  @override
  String get navMenuMoveBackOut => 'Wieder herausholen';

  @override
  String get navMenuRemoveFavourite => 'Aus den Favoriten entfernen';

  @override
  String get navMenuAddFavourite => 'Zu den Favoriten';

  @override
  String get navMenuSharePdf => 'Als PDF teilen…';

  @override
  String get navMenuPrint => 'Drucken…';

  @override
  String get navMenuCopyLink => 'Link zur Seite kopieren';

  @override
  String get navMenuRecentChanges => 'Letzte Änderungen…';

  @override
  String get navMenuSaveTemplate => 'Als Vorlage speichern…';

  @override
  String get navMenuApplyTemplate => 'Eine Vorlage anwenden…';

  @override
  String get navMenuRemovePasscode => 'Code entfernen…';

  @override
  String get navMenuLock => 'Mit einem Code sperren…';

  @override
  String get navMenuDelete => 'Löschen';

  @override
  String get commonOn => 'Ein';

  @override
  String get commonOff => 'Aus';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonDone => 'Fertig';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonOpenEllipsis => 'Öffnen…';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsAppearance => 'Darstellung';

  @override
  String get settingsTheme => 'Design';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Hell';

  @override
  String get settingsThemeDark => 'Dunkel';

  @override
  String get settingsWriting => 'Schreiben und Zeichnen';

  @override
  String get settingsSpellCheck => 'Rechtschreibprüfung';

  @override
  String get settingsPenProximity => 'Stift in der Nähe schaltet auf Tinte um';

  @override
  String get settingsConnections => 'Verbindungen';

  @override
  String get settingsSync => 'Synchronisierung';

  @override
  String get settingsSyncHint =>
      'Dieses Notizbuch sichern und teilen — GitHub oder ein Ordner.';

  @override
  String get settingsAi => 'KI-Zugriff';

  @override
  String get settingsAiOn =>
      'Ein — KI-Assistenten auf diesem Rechner dürfen deine Notizen lesen.';

  @override
  String get settingsAiOff =>
      'Aus — verbinde Claude oder andere KI-Assistenten.';

  @override
  String get settingsHelp => 'Hilfe';

  @override
  String get settingsWelcomeTour => 'Einführung';

  @override
  String get settingsWelcomeTourHint =>
      'Die Drei-Minuten-Fassung: die Leinwand, Formeln und Handschrift, und wo deine Notizen liegen.';

  @override
  String get settingsShortcuts => 'Tastenkürzel';

  @override
  String get settingsShortcutsHint =>
      'Für alles gibt es eine Taste — die ganze Liste.  (Strg+/)';

  @override
  String get settingsAbout => 'Über';

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsCheckUpdates => 'Nach Updates suchen';

  @override
  String settingsUpToDate(String version) {
    return 'Alles aktuell ($version ist die neueste Version).';
  }

  @override
  String get settingsWhatsNew => 'Neuerungen';

  @override
  String get nbTitle => 'Notizbücher';

  @override
  String nbOpenCount(int count) {
    return '$count geöffnet';
  }

  @override
  String nbInBin(int days) {
    return 'Im Papierkorb · wird nach $days Tagen gelöscht';
  }

  @override
  String get nbImportInto => 'In ein neues Notizbuch importieren';

  @override
  String get nbNew => 'Neu';

  @override
  String get nbNewTitle => 'Neues Notizbuch';

  @override
  String get nbCreate => 'Anlegen';

  @override
  String get nbNameHint => 'Name des Notizbuchs';

  @override
  String get nbImport => 'Importieren';

  @override
  String get nbRepair => 'Reparieren';

  @override
  String get nbGetStarted => 'Loslegen';

  @override
  String get nbImportOnepkg => 'OneNote-Notizbuch (.onepkg)';

  @override
  String get nbImportOne => 'OneNote-Abschnitt (.one)';

  @override
  String get nbImportMarkdown => 'Markdown-Ordner';

  @override
  String get nbImportGit => 'Von einer git-Adresse';

  @override
  String get nbDuplicates =>
      'Mögliche Doppelte · gleicher Titel und gleiche Seitenzahl';

  @override
  String get nbDuplicatesHint =>
      'Behalte das größte — das kleinere kommt meist von einem abgebrochenen Import. Gelöschte Kopien landen im Papierkorb.';

  @override
  String get nbOpenThis => 'Dieses Notizbuch öffnen';

  @override
  String get nbRename => 'Umbenennen';

  @override
  String get nbDuplicate => 'Duplizieren';

  @override
  String get nbMoveToBin => 'In den Papierkorb';

  @override
  String get nbConfirmBin =>
      'In den Papierkorb legen? Von hier aus kannst du es wiederherstellen.';

  @override
  String get nbOnePkgFileType => 'OneNote-Notizbuchpaket';

  @override
  String get nbImportBusy => 'Es läuft schon ein Import — immer nur einer.';

  @override
  String get nbImportStarted =>
      'Import läuft im Hintergrund — arbeite weiter; die Karte in der Ecke meldet sich, wenn er fertig ist.';

  @override
  String nbImportedNamed(String name) {
    return '$name importiert';
  }

  @override
  String get nbReadingFolder => 'Ordner wird gelesen…';

  @override
  String nbImportedProgress(String done) {
    return '$done importiert';
  }

  @override
  String get nbNoMarkdown =>
      'In diesem Ordner wurden keine Markdown-Dateien gefunden.';

  @override
  String nbImportedPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten importiert',
      one: '1 Seite importiert',
    );
    return '$_temp0';
  }

  @override
  String get nbNeedsNativeCore =>
      'Der OneNote-Import braucht den Rust-Kern — baue onote_core.dll und lege sie neben die App.';

  @override
  String get nbCheckingPages => 'Seiten werden geprüft…';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return 'Seite $done von $total wird geprüft…';
  }

  @override
  String get nbNothingToRepair =>
      'Nichts zu reparieren — alle Seiten sind auf dem neuesten Stand.';

  @override
  String nbRepairedBoxes(int blocks) {
    String _temp0 = intl.Intl.pluralLogic(
      blocks,
      locale: localeName,
      other: '$blocks Felder',
      one: '1 Feld',
    );
    return '$_temp0';
  }

  @override
  String nbRepairedPages(int pages) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages Seiten',
      one: '1 Seite',
    );
    return '$_temp0';
  }

  @override
  String nbRepaired(String boxes, String pages) {
    return '$boxes auf $pages repariert.';
  }

  @override
  String nbRepairFailed(String reason) {
    return 'Reparatur fehlgeschlagen: $reason';
  }

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '$copies Kopien von „$title“ · je $pages Seiten · $size würden frei';
  }

  @override
  String get nbCoreMissing =>
      'Der OneNote-Import braucht den Rust-Kern — baue onote_core.dll (siehe rust/onote_core/INTEGRATION.md).';

  @override
  String nbReadFileFailed(String reason) {
    return 'Diese Datei konnte nicht gelesen werden: $reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return 'Dieser Ordner konnte nicht importiert werden: $reason';
  }

  @override
  String get nbOneFileEmpty =>
      'Aus dieser .one-Datei konnte nichts gelesen werden.';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return '$what aus OneNote importiert.$strokeNote';
  }

  @override
  String nbImportedPagesProgress(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten importiert…',
      one: '1 Seite importiert…',
    );
    return '$_temp0';
  }

  @override
  String mathSemanticLabel(String latex) {
    return 'Formel: $latex';
  }

  @override
  String get insertGroupWrite => 'Schreiben';

  @override
  String get insertGroupBringIn => 'Einfügen';

  @override
  String get insertGroupLinkUp => 'Verknüpfen';

  @override
  String get insertTextBox => 'Textfeld';

  @override
  String get insertEquation => 'Formel';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertTable => 'Tabelle';

  @override
  String get insertTableFromFile => 'Aus einer Datei';

  @override
  String get insertTableFromFileTip => 'CSV oder Excel';

  @override
  String get insertCode => 'Code';

  @override
  String get insertBoard => 'Board';

  @override
  String get insertBoardTip => 'Spalten mit Karten, die du weiterschiebst';

  @override
  String get insertPicture => 'Bild';

  @override
  String get insertPdfSlides => 'PDF-Folien';

  @override
  String get insertPdfPrintout => 'Ausdruck auf dieser Seite';

  @override
  String get insertPdfPerSlide => 'Eine Seite je Folie';

  @override
  String get insertPdfAsCard => 'Als Karte — öffnet ein Fenster';

  @override
  String get insertVideo => 'Video';

  @override
  String get insertVideoTip => 'Eine Vorlesungsaufnahme oder irgendein Weblink';

  @override
  String get insertFile => 'Datei';

  @override
  String get insertFlashcardItem => 'Karteikarte';

  @override
  String get insertPageLink => 'Seitenlink';

  @override
  String get insertPageWindow => 'Seitenfenster';

  @override
  String get insertTemplate => 'Vorlage';

  @override
  String get insertPickImages => 'Bilder';

  @override
  String get insertPickTables => 'Tabellen';

  @override
  String get insertPickVideo => 'Video und Audio';

  @override
  String get tagTodo => 'Aufgabe';

  @override
  String get tagImportant => 'Wichtig';

  @override
  String get tagQuestion => 'Frage';

  @override
  String get tagRemember => 'Merken';

  @override
  String get tagDefinition => 'Definition';

  @override
  String get tagIdea => 'Idee';

  @override
  String get tagCritical => 'Dringend';

  @override
  String get tagContact => 'Kontakt';

  @override
  String get tagCustom => 'Markierung';

  @override
  String get touchDrawAuto => 'Auto (Stift hat Vorrang)';

  @override
  String get touchDrawAlways => 'Immer';

  @override
  String get touchDrawNever => 'Nie';

  @override
  String get insertLinkToPage => 'Mit einer Seite verknüpfen';

  @override
  String get insertPdfUnreadable => 'Dieses PDF konnte nicht gelesen werden.';

  @override
  String insertPdfImported(int count, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Folien importiert',
      one: '1 Folie importiert',
    );
    return '$_temp0$where — nimm den Stift und schreib darauf. Der Folientext ist durchsuchbar.';
  }

  @override
  String get insertPdfOntoThisPage => ' auf diese Seite';

  @override
  String insertPdfFailed(String reason) {
    return 'PDF-Import fehlgeschlagen: $reason';
  }

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsLanguageAuto => 'Wie mein Rechner';

  @override
  String get settingsLanguageHelp =>
      'Openote wird von denen übersetzt, die es benutzen. Fehlt deine oder stimmt etwas nicht, ist es eine einzige Datei — der Link erklärt es.';

  @override
  String get settingsLanguageContribute =>
      'Wie man eine Sprache hinzufügt oder verbessert';

  @override
  String get shellNothingReplaced => 'Nichts ersetzt';

  @override
  String shellReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fundstellen ersetzt',
      one: '1 Fundstelle ersetzt',
    );
    return '$_temp0';
  }

  @override
  String get shellReplaceWith => 'Ersetzen durch…';

  @override
  String get shellReplace => 'Ersetzen';

  @override
  String get shellReplaceAll => 'Alle';

  @override
  String get shellFindOnThisPage => 'Auf dieser Seite suchen…';

  @override
  String get shellNoMatches => 'Keine Treffer';

  @override
  String get shellPreviousMatch => 'Vorheriger Treffer (Umschalt+Enter)';

  @override
  String get shellNextMatch => 'Nächster Treffer (Enter)';

  @override
  String get shellCloseEsc => 'Schließen (Esc)';

  @override
  String get shellNoTags =>
      'In diesem Notizbuch gibt es noch keine Markierungen.';

  @override
  String get shellTagsHint =>
      'Markierungen kennzeichnen eine Zeile — Aufgabe, Wichtig, Frage, Definition — damit du sie wiederfindest, daraus lernst oder ihr eine Frist gibst.';

  @override
  String get shellTagTheLine => 'Die Zeile markieren, in der du bist';

  @override
  String get shellNoHeadings => 'Auf dieser Seite gibt es keine Überschriften.';

  @override
  String get shellHeadingsHint =>
      'Beginne eine Zeile mit #, um eine Überschrift zu machen — die Übersicht baut sich beim Schreiben von selbst auf.';

  @override
  String get shellLinkedFrom => 'Verlinkt von';

  @override
  String get shellNoBacklinks => 'Noch verweist keine Seite hierher.';

  @override
  String get shellLinksTo => 'Verweist auf';

  @override
  String get shellNoLinks => 'Diese Seite verweist noch nirgendwohin.';

  @override
  String get shellSavedLocally =>
      'Diese Seite ist in deiner lokalen .onote-Datei gespeichert.';

  @override
  String get shellSaving => 'Wird gespeichert…';

  @override
  String get shellSavedOnDevice => 'Auf diesem Gerät gespeichert';

  @override
  String shellRustLinked(String build) {
    return 'Der Rust-Kern (onote-core) ist eingebunden und berechnet beim Speichern die Inhaltsprüfsumme dieser Seite.\n$build';
  }

  @override
  String get shellRustMissing =>
      'Läuft mit der reinen Dart-Engine. Baue die onote-core-Bibliothek, um den Rust-Kern einzubinden.';

  @override
  String get shellCheatSheet =>
      'V auswählen · T Text · P Stift · H markieren · E radieren · Strg+Z rückgängig · Strg+Rad zoomen';

  @override
  String get shellEmptyTitle => 'Eine offene Seite wartet';

  @override
  String get shellEmptyBody =>
      'Alles, was du hier machst, bleibt auf deinem Gerät,\nin einem offenen Format, das dir gehört.';

  @override
  String get shellCreateFirstPage => 'Leg deine erste Seite an';

  @override
  String get shellAlreadyUpToDate => 'Schon auf dem neuesten Stand.';

  @override
  String shellPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen geholt',
      one: '1 Änderung geholt',
    );
    return '$_temp0';
  }

  @override
  String shellPageLocked(String title) {
    return '„$title“ ist gesperrt';
  }

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag  ($count)';
  }

  @override
  String get shellUnlock => 'Entsperren';

  @override
  String get onboardingStep1Title => 'Die Seite ist eine Leinwand';

  @override
  String get onboardingStep1Body =>
      'Klicke irgendwohin und schreib los — das Feld erscheint da, wo du geklickt hast, und erst wenn du tippst. Verschieben kannst du es an der Leiste oben, und Bilder ziehst du von überall hinein.';

  @override
  String get onboardingStep2Title => 'Formeln und Zeichnungen, mitten im Text';

  @override
  String get onboardingStep2Body =>
      'Tippe 1/2 oder drücke Alt+=, und beim Schreiben entsteht echte Notation — in einem eigenen Feld oder mitten im Satz. Der Reiter Zeichnen nimmt Stift, Finger oder Maus.';

  @override
  String get onboardingStep3Title =>
      'Deine Notizen sind eine Datei, die dir gehört';

  @override
  String get onboardingStep3Body =>
      'Eine offene, lesbare Datei je Notizbuch — kein Konto, keine Abhängigkeit. Leg sie in einen Ordner, den deine Cloud ohnehin abgleicht, und alle Geräte bleiben beisammen.';

  @override
  String get onboardingStartWriting => 'Los schreiben';

  @override
  String get onboardingSyncTitle => 'Mit einem anderen Gerät abgleichen';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive, OneDrive, iCloud, Dropbox, Syncthing, ein NAS — oder ein GitHub-Repository.';

  @override
  String get onboardingSyncBodyAlso =>
      'Nichts davon? Dann wähle den Ordner selbst.';

  @override
  String get onboardingSyncAction => 'Einrichten…';

  @override
  String get onboardingOneNoteTitle => 'Notizen aus OneNote holen';

  @override
  String get onboardingOneNoteBody =>
      'Seiten, Formatierung, Bilder, Handschrift und Markierungen aus einer .onepkg. Läuft im Hintergrund — mach ruhig weiter.';

  @override
  String get onboardingOneNoteAction => 'Datei wählen…';

  @override
  String get onboardingFreshTitle => 'Neues Notizbuch beginnen';

  @override
  String get onboardingFreshBody =>
      'Ein leeres Notizbuch, bereit zum Schreiben. Notizen können Sie später jederzeit übernehmen.';

  @override
  String get onboardingFreshAction => 'Neu beginnen';

  @override
  String get onboardingCloudTitle => 'Notizen aus OneNote übernehmen';

  @override
  String get onboardingCloudBody =>
      'Bei Microsoft anmelden und ein Notizbuch auswählen. Nichts vorher exportieren, und es funktioniert auf jedem Computer.';

  @override
  String get onboardingCloudAction => 'Anmelden';

  @override
  String get oneNoteCloudTitle => 'Ein Notizbuch aus OneNote übernehmen';

  @override
  String get oneNoteCloudIntro =>
      'Openote liest Ihre Notizbücher aus OneNote. Es kann sie nicht ändern.';

  @override
  String get oneNoteCloudSignIn => 'Bei Microsoft anmelden';

  @override
  String get oneNoteCloudSigningIn => 'Warten auf Ihren Browser…';

  @override
  String get oneNoteCloudLoading => 'Ihre Notizbücher werden gesucht…';

  @override
  String get oneNoteCloudEmpty =>
      'Für dieses Konto wurden keine Notizbücher gefunden.';

  @override
  String get oneNoteCloudOther => 'Anderes Konto verwenden';

  @override
  String get oneNoteCloudNoInk =>
      'Handschrift kann auf diesem Weg nicht übernommen werden — alles andere schon.';

  @override
  String get onboardingOnePkgFileType => 'OneNote-Notizbuchpaket';

  @override
  String get onboardingOneNoteHowTo => 'Wie exportiere ich?';

  @override
  String get onboardingOneNoteHideSteps => 'Schritte ausblenden';

  @override
  String get onboardingExportTitle => 'Aus OneNote exportieren';

  @override
  String get onboardingExportSteps =>
      '1. Öffne OneNote für Windows (die Desktop-App — die Store- und die Web-Fassung können nicht exportieren).\n2. Lass das Notizbuch fertig synchronisieren, damit alles auf diesem Rechner liegt.\n3. Datei ▸ Exportieren ▸ Notizbuch ▸ OneNote-Paket (*.onepkg), dann Exportieren.\n4. Komm hierher zurück und wähle diese Datei.';

  @override
  String get onboardingExportMacNote =>
      'Auf einem Mac, oder mit nur der Store-Fassung: exportiere Abschnitt für Abschnitt als .one, oder lass einen Windows-Rechner die .onepkg machen. Openote meldet sich nie bei deinem Microsoft-Konto an — es liest nur die Datei, die du ihm gibst.';

  @override
  String onboardingImportingFile(String fileName) {
    return '$fileName wird importiert';
  }

  @override
  String get onboardingImportRunning =>
      'Mach ruhig weiter — das läuft im Hintergrund, und die Karte in der Ecke meldet sich, wenn es fertig ist.';

  @override
  String get onboardingImportDone => 'Dein Notizbuch ist fertig';

  @override
  String get onboardingOpenFailed =>
      'Openote konnte dieses Notizbuch nicht öffnen.';

  @override
  String get onboardingNoNativeCore =>
      'Der OneNote-Import braucht den nativen Kern, den diese Fassung nicht enthält.';

  @override
  String onboardingReadFailed(String reason) {
    return 'Diese Datei konnte nicht gelesen werden: $reason';
  }

  @override
  String get oneNoteFileTitle => 'Eine exportierte Datei verwenden';

  @override
  String get oneNoteFileBody =>
      'Ohne Anmeldung, und die Handschrift kommt mit. Sie brauchen OneNote unter Windows, um das Notizbuch zuerst zu exportieren.';

  @override
  String get oneNoteSignInBody =>
      'Ein Notizbuch auswählen, und es kommt direkt herüber — nichts vorher exportieren. Funktioniert auf jedem Computer.';

  @override
  String get oneNotePickTitle => 'Welches Notizbuch?';
}
