// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class LDe extends L {
  LDe([String locale = 'de']) : super(locale);

  @override
  String atomNewerVersion(String version) {
    return 'Erstellt mit Openote $version';
  }

  @override
  String get atomNewerVersionUnknown =>
      'Mit einer neueren Openote-Version erstellt';

  @override
  String get atomUpdateToView => 'Openote aktualisieren, um es anzuzeigen';

  @override
  String get barBackToEquation => 'Zurück zu den Gleichungswerkzeugen';

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get barBlankOut => 'Auswahl ausblenden';

  @override
  String get barBlankOutNeedsSelection =>
      'Markiere zuerst die Wörter, die ausgeblendet werden sollen.';

  @override
  String get barBold => 'Fett  (Strg+B)';

  @override
  String get barBulletList => 'Aufzählung';

  @override
  String get barCheckbox => 'Kästchen';

  @override
  String get barClickIntoTextBox => 'Klicke in ein Textfeld';

  @override
  String get barDefinitionCard => 'Definitions-Karte';

  @override
  String get barDueDateChange => 'Fälligkeitsdatum ändern…';

  @override
  String get barDueDateClear => 'Fälligkeitsdatum entfernen';

  @override
  String get barDueDatePickerConfirm => 'Setzen';

  @override
  String get barDueDatePickerTitle => 'Fällig am';

  @override
  String get barDueDateSet => 'Fällig am…';

  @override
  String get barEquationBadge => 'Formel';

  @override
  String get barEraserSplit => 'Trennt Striche dort, wo du reibst';

  @override
  String get barEraserWhole => 'Entfernt jeden Strich, den du berührst';

  @override
  String get barEscWhenDone => 'Esc, wenn du fertig bist';

  @override
  String get barExport => 'Exportieren';

  @override
  String get barExportCanvas => 'Für Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => 'Nur die Zeichnung (.inkml)';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

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
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPdfPicture => 'PDF — Bild der Seite';

  @override
  String get barExportPrint => 'Drucken…';

  @override
  String get barExportTip => 'Seite exportieren…';

  @override
  String barExportedTo(String path) {
    return 'Exportiert nach $path';
  }

  @override
  String get barFindOnPage => 'Auf der Seite suchen';

  @override
  String get barFindOnPageTip => 'Auf der Seite suchen  (Strg+F)';

  @override
  String get barFontSizeDefault => 'Standard';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barHeading1 => 'Überschrift 1';

  @override
  String get barHighlight => 'Markieren';

  @override
  String get barInkColourTitle => 'Stiftfarbe';

  @override
  String get barInkDefaultColour => 'Standardtinte — passt sich der Seite an';

  @override
  String get barInkHighlighterColourTitle => 'Markerfarbe';

  @override
  String get barInkMoreColours => 'Weitere Farben…';

  @override
  String get barInkPickColour => 'Farbe von der Seite aufnehmen';

  @override
  String get barInkPickingHint =>
      'Auf etwas auf der Seite klicken, um dessen Farbe zu übernehmen';

  @override
  String get barInlineCode => 'Code im Text';

  @override
  String get barItalic => 'Kursiv  (Strg+I)';

  @override
  String get barLassoHint =>
      'Ziehe eine Schlinge um die Handschrift — dann verschieben oder löschen';

  @override
  String get barMakeCardFromLine => 'Aus dieser Zeile eine Karteikarte machen';

  @override
  String get barNewCard => 'Neue Karteikarte';

  @override
  String get barNumberedList => 'Nummerierte Liste';

  @override
  String get barOpenStudyPanel => 'Lernbereich öffnen';

  @override
  String get barPageOverview => 'Seitenübersicht';

  @override
  String get barPenProximity =>
      'Den Stift an die Seite halten schaltet auf Tinte um.\nWählst du ein anderes Werkzeug, während der Stift in der Nähe\nist, bleibt es, bis der Stift weggeht und wiederkommt. Das\nhintere Ende des Stifts (oder seine Taste) radiert.';

  @override
  String barPenSize(String size) {
    return 'Stiftgröße $size';
  }

  @override
  String get barPenSizeExact => 'Genaue Größe…';

  @override
  String get barPlanner => 'Planer';

  @override
  String get barPlannerEmpty => 'Planer — alle deine Termine an einem Ort';

  @override
  String barPlannerOverdue(int count) {
    return 'Planer — $count für heute oder überfällig';
  }

  @override
  String barPlannerToday(int count) {
    return 'Planer — $count für heute';
  }

  @override
  String get barQuestionCard => 'Frage-Karte';

  @override
  String get barQuote => 'Zitat';

  @override
  String get barRedo => 'Wiederholen  (Strg+Y)';

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
  String barSaveFailed(String reason) {
    return 'Konnte nicht gespeichert werden: $reason';
  }

  @override
  String get barSettings => 'Einstellungen';

  @override
  String get barSettingsTip => 'Einstellungen…';

  @override
  String get barStrikethrough => 'Durchgestrichen';

  @override
  String get barStudy => 'Lernen';

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
  String get barStudyEmpty =>
      'Lernen — markiere eine Zeile als Frage oder Definition, um eine Karte daraus zu machen';

  @override
  String barStudyExamCountdown(String when) {
    return ' · Prüfung $when';
  }

  @override
  String get barTabDraw => 'Zeichnen';

  @override
  String get barTabHome => 'Start';

  @override
  String get barTabInsert => 'Einfügen';

  @override
  String get barTabPage => 'Seite';

  @override
  String get barTagLine => 'Diese Zeile markieren (Aufgabe, Wichtig, Frage…)';

  @override
  String barTagged(String tags) {
    return 'Markiert: $tags';
  }

  @override
  String get barTextColour => 'Textfarbe anwenden';

  @override
  String get barTextFont => 'Schriftart…';

  @override
  String get barTextSize => 'Schriftgröße (Punkt)';

  @override
  String get barTextSizeDisabled =>
      'Klicke in ein Textfeld, um seine Größe zu ändern';

  @override
  String get barToolEraser => 'Radierer  (E)';

  @override
  String get barToolHighlighter => 'Textmarker  (H)';

  @override
  String get barToolLasso => 'Handschrift mit dem Lasso auswählen';

  @override
  String get barToolPen => 'Stift  (P)';

  @override
  String get barToolSelect => 'Auswählen / verschieben  (V)';

  @override
  String get barToolText => 'Text  (T)';

  @override
  String get barUnderline => 'Unterstrichen  (Strg+U)';

  @override
  String get barUndo => 'Rückgängig  (Strg+Z)';

  @override
  String barUpdateTo(String version) {
    return 'Auf $version aktualisieren…';
  }

  @override
  String get canvasDeleteSelection => 'Löschen  (Entf)';

  @override
  String get canvasGroupSelection => 'Gruppieren  (Strg+G)';

  @override
  String get canvasUngroupSelection =>
      'Gruppierung aufheben  (Strg+Umschalt+G)';

  @override
  String get commandNotInDemo => 'Nicht in der Web-Demo';

  @override
  String get commonBack => 'Zurück';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonCopy => 'Kopieren';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonDetailsAdvanced => 'Details (für Fortgeschrittene)';

  @override
  String get commonDone => 'Fertig';

  @override
  String get commonNext => 'Weiter';

  @override
  String get commonOff => 'Aus';

  @override
  String get commonOn => 'Ein';

  @override
  String get commonOpen => 'Öffnen';

  @override
  String get commonOpenEllipsis => 'Öffnen…';

  @override
  String get commonSkip => 'Überspringen';

  @override
  String importBringingIn(String name, int done, int total) {
    return '„$name\" wird übertragen — $done von $total Seiten…';
  }

  @override
  String get importCancelledLabel => 'Import abgebrochen.';

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten importiert.',
      one: '1 Seite importiert.',
    );
    return '$_temp0';
  }

  @override
  String importDoneButLost(int count, String detail) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Seiten importiert, aber $detail konnte nicht übernommen werden.',
      one: '1 Seite importiert, aber $detail konnte nicht übernommen werden.',
    );
    return '$_temp0';
  }

  @override
  String get importEmptyNotebook => 'Dieses Notizbuch enthielt keine Seiten.';

  @override
  String get importFailedGeneric =>
      'Dieses Notizbuch konnte nicht übertragen werden.';

  @override
  String importFoundPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten zu übertragen. Es geht los…',
      one: '1 Seite zu übertragen. Es geht los…',
    );
    return '$_temp0';
  }

  @override
  String importFoundSections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Abschnitte gefunden — Inhalt wird geprüft…',
      one: '1 Abschnitt gefunden — Inhalt wird geprüft…',
    );
    return '$_temp0';
  }

  @override
  String get importLookingAround => 'Dein Notizbuch wird durchgesehen…';

  @override
  String importPartialBroke(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Unterwegs ging etwas schief, aber die $count bereits übertragenen Seiten sind da. Openote holt den Rest später selbst nach.',
    );
    return '$_temp0';
  }

  @override
  String importPartialThrottled(String detail, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$detail Die $count bereits übertragenen Seiten sind da. Openote holt den Rest später selbst nach, oder du startest es jederzeit erneut.',
    );
    return '$_temp0';
  }

  @override
  String get importReading => 'Notizbuch wird gelesen…';

  @override
  String get importSigningIn => 'Anmeldung bei OneNote…';

  @override
  String importStoppedKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Angehalten — die $count bereits übertragenen Seiten bleiben. Du kannst jederzeit fortfahren.',
      one:
          'Angehalten — die 1 bereits übertragene Seite bleibt. Du kannst jederzeit fortfahren.',
    );
    return '$_temp0';
  }

  @override
  String get importStopping => 'Wird angehalten…';

  @override
  String importThrottled(int seconds) {
    return 'Microsoft hat Openote gebeten, langsamer zu machen — weiter in ${seconds}s. Nichts bereits Übertragenes geht verloren.';
  }

  @override
  String get importThrottledSoon =>
      'Microsoft hat Openote gebeten, langsamer zu machen — gleich geht es weiter. Nichts bereits Übertragenes geht verloren.';

  @override
  String importWritingPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten werden importiert…',
      one: '1 Seite wird importiert…',
    );
    return '$_temp0';
  }

  @override
  String importWritingSection(String name) {
    return '„$name\" wird importiert…';
  }

  @override
  String get insertBoard => 'Board';

  @override
  String get insertBoardTip => 'Spalten mit Karten, die du weiterschiebst';

  @override
  String get insertCode => 'Code';

  @override
  String get insertEquation => 'Formel';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertFile => 'Datei';

  @override
  String get insertFlashcardItem => 'Karteikarte';

  @override
  String get insertGroupBringIn => 'Einfügen';

  @override
  String get insertGroupLinkUp => 'Verknüpfen';

  @override
  String get insertGroupWrite => 'Schreiben';

  @override
  String get insertLinkToPage => 'Mit einer Seite verknüpfen';

  @override
  String get insertPageLink => 'Seitenlink';

  @override
  String get insertPageWindow => 'Seitenfenster';

  @override
  String get insertPdfAsCard => 'Als Karte — öffnet ein Fenster';

  @override
  String insertPdfFailed(String reason) {
    return 'PDF-Import fehlgeschlagen: $reason';
  }

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
  String get insertPdfPerSlide => 'Eine Seite je Folie';

  @override
  String get insertPdfPrintout => 'Ausdruck auf dieser Seite';

  @override
  String get insertPdfSlides => 'PDF-Folien';

  @override
  String get insertPdfUnreadable => 'Dieses PDF konnte nicht gelesen werden.';

  @override
  String get insertPickImages => 'Bilder';

  @override
  String get insertPickTables => 'Tabellen';

  @override
  String get insertPickVideo => 'Video und Audio';

  @override
  String get insertPicture => 'Bild';

  @override
  String get insertTable => 'Tabelle';

  @override
  String get insertTableFromFile => 'Aus einer Datei';

  @override
  String get insertTableFromFileTip => 'CSV oder Excel';

  @override
  String get insertTextBox => 'Textfeld';

  @override
  String get insertVideo => 'Video';

  @override
  String get insertVideoTip => 'Eine Vorlesungsaufnahme oder irgendein Weblink';

  @override
  String get linkEdit => 'Link bearbeiten…';

  @override
  String mathSemanticLabel(String latex) {
    return 'Formel: $latex';
  }

  @override
  String navAllCount(int total) {
    return 'Alle $total';
  }

  @override
  String get navBinEmpty => 'Nichts gelöscht.';

  @override
  String get navBinItems => 'Einträge';

  @override
  String get navBinNotebooks => 'Notizbücher';

  @override
  String navBinRetention(int days) {
    return 'Was hier liegt, wird nach $days Tagen endgültig gelöscht.';
  }

  @override
  String get navClose => 'Schließen';

  @override
  String get navCollapse => 'Navigator einklappen  (Strg+\\)';

  @override
  String get navColour => 'Farbe';

  @override
  String get navColourDefault => 'Standard';

  @override
  String get navComingUp => 'DEMNÄCHST';

  @override
  String get navDeleteForever => 'Für immer löschen';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '„$title“ und alle Seiten darin werden für immer entfernt. Das lässt sich nicht rückgängig machen.$caveat';
  }

  @override
  String get navDeleteForeverTitle => 'Endgültig löschen?';

  @override
  String get navDeletePermanently => 'Endgültig löschen';

  @override
  String navDeletedGroup(String title) {
    return 'Gruppe „$title“ in den Papierkorb verschoben';
  }

  @override
  String navDeletedPage(String title) {
    return 'Seite „$title“ in den Papierkorb verschoben';
  }

  @override
  String navDeletedSection(String title) {
    return 'Abschnitt „$title“ in den Papierkorb verschoben';
  }

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
  String get navDeletesSoon => 'Wird bald gelöscht';

  @override
  String navExamCountdown(String when, String countdown) {
    return 'Prüfung $when · $countdown…';
  }

  @override
  String get navExpand => 'Navigator ausklappen  (Strg+\\)';

  @override
  String get navSectionsHeader => 'Abschnitte';

  @override
  String get navNewSectionOrGroup => 'Neuer Abschnitt oder Gruppe';

  @override
  String get dropMoveAbove => 'Darüber einfügen';

  @override
  String get dropMoveBelow => 'Darunter einfügen';

  @override
  String get dropMakeSubpage => 'Als Unterseite einfügen';

  @override
  String get dropGroupTogether => 'Zusammen gruppieren';

  @override
  String get dropMoveIntoGroup => 'In die Gruppe verschieben';

  @override
  String get dropMoveToSection => 'In diesen Abschnitt verschieben';

  @override
  String get navBinEmptyAction => 'Leeren';

  @override
  String get navBinEmptyTitle => 'Papierkorb leeren?';

  @override
  String get navBinEmptyBody =>
      'Alles darin wird endgültig entfernt. Das lässt sich nicht rückgängig machen.';

  @override
  String get navBinEmptySharedNote =>
      'Notizbücher in einem geteilten Ordner werden nur von diesem Computer entfernt.';

  @override
  String navBinDeleteOneBody(String title) {
    return '„$title“ wird endgültig entfernt. Das lässt sich nicht rückgängig machen.';
  }

  @override
  String get navBinKindPage => 'Seite';

  @override
  String get navBinKindSection => 'Abschnitt';

  @override
  String get navBinKindGroup => 'Gruppe';

  @override
  String get navBinKindNotebook => 'Notizbuch';

  @override
  String navBinItemLine(String kind, String when) {
    return '$kind · $when';
  }

  @override
  String get navBinWhenToday => 'heute';

  @override
  String get navBinWhenYesterday => 'gestern';

  @override
  String navBinWhenDaysAgo(int days) {
    return 'vor $days Tagen';
  }

  @override
  String get reviewTitle => 'Text prüfen';

  @override
  String reviewChip(int count) {
    return '$count zu prüfen';
  }

  @override
  String get reviewChipClear => 'Keine Schreibprobleme';

  @override
  String get reviewTooltip => 'Text prüfen (F7)';

  @override
  String get reviewChecking => 'Text wird geprüft …';

  @override
  String fixNoticeRevert(String word) {
    return '„$word“ wiederherstellen';
  }

  @override
  String reviewSubtitle(int count, String language) {
    return 'Auf dieser Seite · $count zu prüfen · $language';
  }

  @override
  String get reviewSpelling => 'Rechtschreibung';

  @override
  String get reviewGrammar => 'Grammatik';

  @override
  String get reviewPunctuation => 'Zeichensetzung';

  @override
  String get reviewFixAll => 'Alle korrigieren';

  @override
  String get reviewAccept => 'Übernehmen';

  @override
  String get reviewIgnore => 'Ignorieren';

  @override
  String get reviewAddToDictionary => 'Zum Wörterbuch hinzufügen';

  @override
  String get reviewNotInDictionary => 'Nicht im Wörterbuch';

  @override
  String get reviewRemove => 'Entfernen';

  @override
  String get reviewAllClear => 'Auf dieser Seite gibt es nichts zu prüfen.';

  @override
  String reviewFixedSpelling(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Rechtschreibfehler korrigiert',
      one: '1 Rechtschreibfehler korrigiert',
    );
    return '$_temp0';
  }

  @override
  String reviewFixedGrammar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Grammatikfehler korrigiert',
      one: '1 Grammatikfehler korrigiert',
    );
    return '$_temp0';
  }

  @override
  String reviewFixedPunctuation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Zeichensetzungsfehler korrigiert',
      one: '1 Zeichensetzungsfehler korrigiert',
    );
    return '$_temp0';
  }

  @override
  String get navHideSections => 'Abschnittsliste ausblenden';

  @override
  String get navRecent => 'Zuletzt';

  @override
  String get navHomeEmpty =>
      'Hier ist noch nichts.\n\nKlicke mit der rechten Maustaste auf eine Seite und wähle Favorit, um sie anzuheften; Seiten, die du öffnest, erscheinen unter Zuletzt.';

  @override
  String get navRecentTip => 'Zuletzt geöffnete Seiten und Favoriten';

  @override
  String get navInPageContent => 'Im Seiteninhalt';

  @override
  String get navLinkCopied =>
      'Link kopiert — füge ihn in eine beliebige Seite ein';

  @override
  String navLockedCannotDelete(String title) {
    return '„$title“ ist gesperrt. Entferne den Code, bevor du sie löschst.';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '„$title“ ist gesperrt. Sie ist in Openote versteckt, nicht in der Datei verschlüsselt.';
  }

  @override
  String get navMenuAddFavourite => 'Zu den Favoriten';

  @override
  String get navMenuCopyLink => 'Link zur Seite kopieren';

  @override
  String get navMenuDelete => 'Löschen';

  @override
  String get navMenuDuplicate => 'Duplizieren';

  @override
  String get navMenuExportSectionPdf => 'Abschnitt als PDF exportieren…';

  @override
  String get navMenuLock => 'Mit einem Code sperren…';

  @override
  String get navMenuMakeSubpage => 'Zur Unterseite machen';

  @override
  String get navMenuMoveBackOut => 'Wieder herausholen';

  @override
  String get navMenuMoveDown => 'Nach unten';

  @override
  String get navMenuMoveToGroup => 'In eine Gruppe verschieben…';

  @override
  String get navMenuMoveUp => 'Nach oben';

  @override
  String get navMenuNewPage => 'Neue Seite';

  @override
  String get navMenuPrint => 'Drucken…';

  @override
  String get navMenuPrintSection => 'Abschnitt drucken…';

  @override
  String get navMenuRecentChanges => 'Letzte Änderungen…';

  @override
  String get navMenuRemoveExam => 'Prüfungsdatum entfernen';

  @override
  String get navMenuRemoveFavourite => 'Aus den Favoriten entfernen';

  @override
  String get navMenuRemovePasscode => 'Code entfernen…';

  @override
  String get navMenuRename => 'Umbenennen';

  @override
  String get navMenuSetExam => 'Prüfungsdatum setzen…';

  @override
  String get navMenuSharePdf => 'Als PDF teilen…';

  @override
  String get navMenuSortAZ => 'Seiten von A bis Z sortieren';

  @override
  String get navMenuSortEdited => 'Nach letzter Änderung sortieren';

  @override
  String get navMoveSectionTo => 'Abschnitt verschieben nach…';

  @override
  String navNewPageIn(String section) {
    return 'Neue Seite in $section';
  }

  @override
  String get navNewSection => 'Neuer Abschnitt';

  @override
  String get navNewSectionGroup => 'Neue Gruppe';

  @override
  String get navNoGroupTopLevel => '(Keine Gruppe — oberste Ebene)';

  @override
  String navNoMatches(String query) {
    return 'Keine Treffer für „$query“';
  }

  @override
  String get navNoPages => 'Noch keine Seiten';

  @override
  String get navNoSections =>
      'Noch keine Abschnitte.\nLege einen an, um loszulegen.';

  @override
  String get navNotebooksTip =>
      'Notizbücher — wechseln, umbenennen, duplizieren, importieren';

  @override
  String get navOpen => 'Öffnen';

  @override
  String navPasscodeRemoved(String title) {
    return 'Code von „$title“ entfernt.';
  }

  @override
  String get navRecycleBin => 'Papierkorb';

  @override
  String get navRestore => 'Wiederherstellen';

  @override
  String get navSave => 'Speichern';

  @override
  String navSavedTo(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String get navSearchHint => 'Suchen oder springen zu…';

  @override
  String get navSection => 'Abschnitt';

  @override
  String get navShowSections => 'Abschnittsliste einblenden';

  @override
  String get navUndo => 'Rückgängig';

  @override
  String get navUntitled => 'Ohne Titel';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return 'Seite $done von $total wird geprüft…';
  }

  @override
  String get nbCheckingPages => 'Seiten werden geprüft…';

  @override
  String get nbConfirmBin =>
      'In den Papierkorb legen? Von hier aus kannst du es wiederherstellen.';

  @override
  String get nbConfirmBinShared =>
      'Dieses Notizbuch liegt in einem geteilten Ordner. Wenn du es von diesem Computer entfernst, bleibt es im Ordner und auf deinen anderen Geräten — mit „Öffnen“ holst du es jederzeit zurück.';

  @override
  String get nbRemoveFromComputer => 'Von diesem Computer entfernen';

  @override
  String get nbDeleteEverywhere => 'Überall löschen…';

  @override
  String nbDeleteEverywhereTitle(String title) {
    return '„$title“ überall löschen?';
  }

  @override
  String get nbDeleteEverywhereBody =>
      'Das löscht es aus dem geteilten Ordner und damit von jedem Gerät, das ihn nutzt. Das lässt sich nicht rückgängig machen.';

  @override
  String get nbDeleteEverywhereConfirm => 'Überall löschen';

  @override
  String nbRemoveSharedTitle(String title) {
    return '„$title“ von diesem Computer entfernen?';
  }

  @override
  String get nbRemoveSharedBody =>
      'Es bleibt im geteilten Ordner und auf deinen anderen Geräten. Mit „Öffnen“ holst du es jederzeit zurück.';

  @override
  String get nbCoreMissing =>
      'Der OneNote-Import braucht den Rust-Kern — baue onote_core.dll (siehe rust/onote_core/INTEGRATION.md).';

  @override
  String get nbCreate => 'Anlegen';

  @override
  String get nbDuplicate => 'Duplizieren';

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '$copies Kopien von „$title“ · je $pages Seiten · $size würden frei';
  }

  @override
  String get nbDuplicates =>
      'Mögliche Doppelte · gleicher Titel und gleiche Seitenzahl';

  @override
  String get nbDuplicatesHint =>
      'Behalte das größte — das kleinere kommt meist von einem abgebrochenen Import. Gelöschte Kopien landen im Papierkorb.';

  @override
  String get nbGetStarted => 'Loslegen';

  @override
  String get nbImport => 'Importieren';

  @override
  String get nbImportBusy => 'Es läuft schon ein Import — immer nur einer.';

  @override
  String get nbImportGit => 'Von einer git-Adresse';

  @override
  String get nbImportDriveFolder => 'Aus einem Drive-Ordner öffnen';

  @override
  String get nbImportInto => 'In ein neues Notizbuch importieren';

  @override
  String get nbImportMarkdown => 'Markdown-Ordner';

  @override
  String get nbImportOne => 'OneNote-Abschnitt (.one)';

  @override
  String get nbImportOnepkg => 'OneNote-Notizbuch (.onepkg)';

  @override
  String get nbImportStarted =>
      'Import läuft im Hintergrund — arbeite weiter; die Karte in der Ecke meldet sich, wenn er fertig ist.';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return '$what aus OneNote importiert.$strokeNote';
  }

  @override
  String nbImportedNamed(String name) {
    return '$name importiert';
  }

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
  String nbImportedProgress(String done) {
    return '$done importiert';
  }

  @override
  String nbInBin(int days) {
    return 'Im Papierkorb · wird nach $days Tagen gelöscht';
  }

  @override
  String get nbMoveToBin => 'In den Papierkorb';

  @override
  String get nbNameHint => 'Name des Notizbuchs';

  @override
  String get nbNeedsNativeCore =>
      'Der OneNote-Import braucht den Rust-Kern — baue onote_core.dll und lege sie neben die App.';

  @override
  String get nbNew => 'Neu';

  @override
  String get nbNewTitle => 'Neues Notizbuch';

  @override
  String get nbNoMarkdown =>
      'In diesem Ordner wurden keine Markdown-Dateien gefunden.';

  @override
  String get nbNothingToRepair =>
      'Nichts zu reparieren — alle Seiten sind auf dem neuesten Stand.';

  @override
  String get nbOneFileEmpty =>
      'Aus dieser .one-Datei konnte nichts gelesen werden.';

  @override
  String get nbOnePkgFileType => 'OneNote-Notizbuchpaket';

  @override
  String nbOpenCount(int count) {
    return '$count geöffnet';
  }

  @override
  String get nbOpenThis => 'Dieses Notizbuch öffnen';

  @override
  String nbReadFileFailed(String reason) {
    return 'Diese Datei konnte nicht gelesen werden: $reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return 'Dieser Ordner konnte nicht importiert werden: $reason';
  }

  @override
  String get nbReadingFolder => 'Ordner wird gelesen…';

  @override
  String get nbRename => 'Umbenennen';

  @override
  String get nbRepair => 'Reparieren';

  @override
  String nbRepairFailed(String reason) {
    return 'Reparatur fehlgeschlagen: $reason';
  }

  @override
  String nbRepaired(String boxes, String pages) {
    return '$boxes auf $pages repariert.';
  }

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
  String get nbTitle => 'Notizbücher';

  @override
  String objectRowBackground(String kind) {
    return 'Hintergrund: $kind';
  }

  @override
  String get objectRowBackgroundBlank => 'leer';

  @override
  String get objectRowBackgroundDotted => 'gepunktet';

  @override
  String get objectRowBackgroundGrid => 'kariert';

  @override
  String get objectRowBackgroundRuled => 'liniert';

  @override
  String get objectRowCanvasMode =>
      'Leinwandmodus: grenzenlos — klicken für Seiten';

  @override
  String get objectRowCharacters => 'Zeichen';

  @override
  String get objectRowCharactersNoSpaces => 'Ohne Leerzeichen';

  @override
  String get objectRowLandscape => 'Querformat';

  @override
  String get objectRowLandscapeSuffix => ' quer';

  @override
  String objectRowMinutes(int n) {
    return '$n Min.';
  }

  @override
  String objectRowPageMode(String paper, String landscape) {
    return 'Seitenmodus: $paper$landscape — klicken für Leinwand';
  }

  @override
  String get objectRowPaperSize => 'Papierformat';

  @override
  String get objectRowReadingTime => 'Lesezeit';

  @override
  String get objectRowSnapOff => 'Am Raster ausrichten: AUS — frei platzieren';

  @override
  String get objectRowSnapOn =>
      'Am Raster ausrichten: EIN (beim Ziehen sichtbar)';

  @override
  String get objectRowWordCount =>
      'Wörter auf dieser Seite — klicken für Zeichen und Lesezeit';

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
  String get objectRowWords => 'Wörter';

  @override
  String get objectRowZoomFit => 'Auf den Inhalt zoomen';

  @override
  String get objectRowZoomIn => 'Vergrößern  (Strg+=)';

  @override
  String get objectRowZoomOut => 'Verkleinern  (Strg+-)';

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent %';
  }

  @override
  String get objectRowZoomReset =>
      'Zurück auf 100 % und an den Seitenanfang  (Strg+0)';

  @override
  String get onboardingCloudAction => 'Anmelden';

  @override
  String get onboardingCloudBody =>
      'Bei Microsoft anmelden und ein Notizbuch auswählen. Nichts vorher exportieren, und es funktioniert auf jedem Computer.';

  @override
  String get onboardingCloudTitle => 'Notizen aus OneNote übernehmen';

  @override
  String get onboardingExportMacNote =>
      'Auf einem Mac, oder mit nur der Store-Fassung: exportiere Abschnitt für Abschnitt als .one, oder lass einen Windows-Rechner die .onepkg machen. Openote meldet sich nie bei deinem Microsoft-Konto an — es liest nur die Datei, die du ihm gibst.';

  @override
  String get onboardingExportSteps =>
      '1. Öffne OneNote für Windows (die Desktop-App — die Store- und die Web-Fassung können nicht exportieren).\n2. Lass das Notizbuch fertig synchronisieren, damit alles auf diesem Rechner liegt.\n3. Datei ▸ Exportieren ▸ Notizbuch ▸ OneNote-Paket (*.onepkg), dann Exportieren.\n4. Komm hierher zurück und wähle diese Datei.';

  @override
  String get onboardingExportTitle => 'Aus OneNote exportieren';

  @override
  String get onboardingFreshAction => 'Neu beginnen';

  @override
  String get onboardingFreshBody =>
      'Ein leeres Notizbuch, bereit zum Schreiben. Notizen kannst du später jederzeit übernehmen.';

  @override
  String get onboardingFreshTitle => 'Neues Notizbuch beginnen';

  @override
  String get onboardingImportDone => 'Dein Notizbuch ist fertig';

  @override
  String get onboardingImportRunning =>
      'Mach ruhig weiter — das läuft im Hintergrund, und die Karte in der Ecke meldet sich, wenn es fertig ist.';

  @override
  String onboardingImportingFile(String fileName) {
    return '$fileName wird importiert';
  }

  @override
  String get onboardingNoNativeCore =>
      'Der OneNote-Import braucht den nativen Kern, den diese Fassung nicht enthält.';

  @override
  String get onboardingOneNoteAction => 'Datei wählen…';

  @override
  String get onboardingOneNoteBody =>
      'Seiten, Formatierung, Bilder, Handschrift und Markierungen aus einer .onepkg. Läuft im Hintergrund — mach ruhig weiter.';

  @override
  String get onboardingOneNoteHideSteps => 'Schritte ausblenden';

  @override
  String get onboardingOneNoteHowTo => 'Wie exportiere ich?';

  @override
  String get onboardingOneNoteTitle => 'Notizen aus OneNote holen';

  @override
  String get onboardingOnePkgFileType => 'OneNote-Notizbuchpaket';

  @override
  String get onboardingOpenFailed =>
      'Openote konnte dieses Notizbuch nicht öffnen.';

  @override
  String onboardingReadFailed(String reason) {
    return 'Diese Datei konnte nicht gelesen werden: $reason';
  }

  @override
  String get onboardingStartWriting => 'Los schreiben';

  @override
  String get onboardingStep1Body =>
      'Klicke irgendwohin und schreib los — das Feld erscheint da, wo du geklickt hast, und erst wenn du tippst. Verschieben kannst du es an der Leiste oben, und Bilder ziehst du von überall hinein.';

  @override
  String get onboardingStep1Title => 'Die Seite ist eine Leinwand';

  @override
  String get onboardingStep2Body =>
      'Tippe 1/2 oder drücke Alt+=, und beim Schreiben entsteht echte Notation — in einem eigenen Feld oder mitten im Satz. Der Reiter Zeichnen nimmt Stift, Finger oder Maus.';

  @override
  String get onboardingStep2Title => 'Formeln und Zeichnungen, mitten im Text';

  @override
  String get onboardingStep3Body =>
      'Eine offene, lesbare Datei je Notizbuch — kein Konto, keine Abhängigkeit. Leg sie in einen Ordner, den deine Cloud ohnehin abgleicht, und alle Geräte bleiben beisammen.';

  @override
  String get onboardingStep3Title =>
      'Deine Notizen sind eine Datei, die dir gehört';

  @override
  String get onboardingSyncAction => 'Einrichten…';

  @override
  String get onboardingSyncBodyAlso =>
      'Nichts davon? Dann wähle den Ordner selbst.';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive, OneDrive, iCloud, Dropbox, Syncthing, ein NAS — oder ein GitHub-Repository.';

  @override
  String get onboardingSyncTitle => 'Mit einem anderen Gerät abgleichen';

  @override
  String get oneNoteCloudContinue => 'Mit Microsoft fortfahren';

  @override
  String get oneNoteCloudEmpty =>
      'Für dieses Konto wurden keine Notizbücher gefunden.';

  @override
  String get oneNoteCloudIntro =>
      'Openote liest deine Notizbücher aus OneNote. Es kann sie nicht ändern.';

  @override
  String get oneNoteCloudLoading => 'Deine Notizbücher werden gesucht…';

  @override
  String get oneNoteCloudNoInk =>
      'Tabellen werden an die Seite angepasst statt in ihrer genauen Breite übernommen, und Textfarbe und Schriftart kommen nicht mit.';

  @override
  String get oneNoteCloudOther => 'Anderes Konto verwenden';

  @override
  String get oneNoteCloudSignIn => 'Bei Microsoft anmelden';

  @override
  String get oneNoteCloudSigningIn => 'Warten auf deinen Browser…';

  @override
  String get oneNoteCloudTitle => 'Ein Notizbuch aus OneNote übernehmen';

  @override
  String get oneNoteFileBody =>
      'Ohne Anmeldung, und die genaueste Kopie: Tabellen behalten ihre exakte Breite. Du brauchst OneNote unter Windows, um das Notizbuch zuerst zu exportieren.';

  @override
  String get oneNoteFileTitle => 'Eine exportierte Datei verwenden';

  @override
  String get oneNotePickTitle => 'Welches Notizbuch?';

  @override
  String get oneNoteSignInBody =>
      'Ein Notizbuch auswählen, und es kommt direkt herüber — nichts vorher exportieren. Funktioniert auf jedem Computer.';

  @override
  String get penButtonEraser => 'Radierer';

  @override
  String get penButtonLasso => 'Lasso';

  @override
  String get penButtonNothing => 'Nichts';

  @override
  String get penButtonSelect => 'Auswählen';

  @override
  String get settingsAbout => 'Über';

  @override
  String get settingsAi => 'KI-Zugriff';

  @override
  String get settingsAiOff =>
      'Aus — verbinde Claude oder andere KI-Assistenten.';

  @override
  String get settingsAiOn =>
      'Ein — KI auf diesem Rechner darf deine Notizen lesen.';

  @override
  String get settingsAppearance => 'Darstellung';

  @override
  String get settingsCheckUpdates => 'Nach Updates suchen';

  @override
  String get settingsConnections => 'Verbindungen';

  @override
  String get settingsDiagnostics => 'Diagnose';

  @override
  String get settingsHelp => 'Hilfe';

  @override
  String get settingsUiScale => 'Größe der Oberfläche';

  @override
  String get settingsUiScaleHint =>
      'Macht das ganze Fenster größer oder kleiner.';

  @override
  String settingsUiScaleLimited(String size) {
    return 'Angezeigt mit $size: Dieses Fenster ist für mehr zu klein.';
  }

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsLanguageAuto => 'Systemstandard';

  @override
  String get settingsLanguageContribute =>
      'Wie man eine Sprache hinzufügt oder verbessert';

  @override
  String get settingsPenAndTouch => 'Stift und Touch';

  @override
  String get settingsPenButton => 'Die Seitentaste des Stifts';

  @override
  String get settingsPenButtonHint =>
      'Gedrückt halten, um dieses Werkzeug kurz zu nutzen.';

  @override
  String get settingsPenTest => 'Stift- und Berührungstest';

  @override
  String get settingsPenTestHint => 'Was dein Stift und seine Tasten melden.';

  @override
  String get settingsShortcuts => 'Tastenkürzel';

  @override
  String get settingsShortcutsHint => 'Strg+/';

  @override
  String get settingsReportProblem => 'Problem melden oder Idee teilen';

  @override
  String get settingsReportProblemHint =>
      'Öffnet GitHub. Ein kostenloses GitHub-Konto ist nötig.';

  @override
  String get settingsSpellCheck => 'Rechtschreibprüfung';

  @override
  String get settingsSync => 'Synchronisierung';

  @override
  String get settingsSyncHint =>
      'Dieses Notizbuch auf GitHub oder in einen Ordner sichern.';

  @override
  String get settingsTheme => 'Design';

  @override
  String get settingsThemeDark => 'Dunkel';

  @override
  String get settingsThemeLight => 'Hell';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsTouchDrawing => 'Mit dem Finger zeichnen';

  @override
  String get settingsTouchDrawingHint =>
      'Zwei Finger verschieben und zoomen immer.';

  @override
  String settingsUpToDate(String version) {
    return 'Alles aktuell ($version ist die neueste Version).';
  }

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsWelcomeTour => 'Einführung';

  @override
  String get settingsWelcomeTourHint =>
      'Drei Minuten darüber, wie die Leinwand funktioniert.';

  @override
  String get settingsWhatsNew => 'Neuerungen';

  @override
  String get settingsWriting => 'Schreiben und Zeichnen';

  @override
  String get shellAlreadyUpToDate => 'Schon auf dem neuesten Stand.';

  @override
  String get shellCheatSheet =>
      'V auswählen · T Text · P Stift · H markieren · E radieren · Strg+Z rückgängig · Strg+Rad zoomen';

  @override
  String get shellCloseEsc => 'Schließen (Esc)';

  @override
  String get shellCreateFirstPage => 'Leg deine erste Seite an';

  @override
  String get shellDemoNothingSaved => 'Demo — nichts wird gespeichert';

  @override
  String get shellEmptyBody =>
      'Alles, was du hier machst, bleibt auf deinem Gerät,\nin einem offenen Format, das dir gehört.';

  @override
  String get shellEmptyTitle => 'Eine offene Seite wartet';

  @override
  String get shellFindOnThisPage => 'Auf dieser Seite suchen…';

  @override
  String get shellHeadingsHint =>
      'Beginne eine Zeile mit #, um eine Überschrift zu machen — die Übersicht baut sich beim Schreiben von selbst auf.';

  @override
  String get shellLinkedFrom => 'Verlinkt von';

  @override
  String get shellLinksTo => 'Verweist auf';

  @override
  String get shellNextMatch => 'Nächster Treffer (Enter)';

  @override
  String get shellNoBacklinks => 'Noch verweist keine Seite hierher.';

  @override
  String get shellNoHeadings => 'Auf dieser Seite gibt es keine Überschriften.';

  @override
  String get shellNoLinks => 'Diese Seite verweist noch nirgendwohin.';

  @override
  String get shellNoMatches => 'Keine Treffer';

  @override
  String get shellNoTags =>
      'In diesem Notizbuch gibt es noch keine Markierungen.';

  @override
  String get shellNothingReplaced => 'Nichts ersetzt';

  @override
  String shellPageLocked(String title) {
    return '„$title“ ist gesperrt';
  }

  @override
  String get shellPreviousMatch => 'Vorheriger Treffer (Umschalt+Enter)';

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
  String get shellReplace => 'Ersetzen';

  @override
  String get shellReplaceAll => 'Alle';

  @override
  String get shellReplaceWith => 'Ersetzen durch…';

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
  String shellRustLinked(String build) {
    return 'Der Rust-Kern (onote-core) ist eingebunden und berechnet beim Speichern die Inhaltsprüfsumme dieser Seite.\n$build';
  }

  @override
  String get shellRustMissing =>
      'Läuft mit der reinen Dart-Engine. Baue die onote-core-Bibliothek, um den Rust-Kern einzubinden.';

  @override
  String get shellSavedLocally =>
      'Diese Seite ist in deiner lokalen .onote-Datei gespeichert.';

  @override
  String get shellSavedOnDevice => 'Auf diesem Gerät gespeichert';

  @override
  String get shellSaving => 'Wird gespeichert…';

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag  ($count)';
  }

  @override
  String get shellTagTheLine => 'Die Zeile markieren, in der du bist';

  @override
  String get shellTagsHint =>
      'Markierungen kennzeichnen eine Zeile — Aufgabe, Wichtig, Frage, Definition — damit du sie wiederfindest, daraus lernst oder ihr eine Frist gibst.';

  @override
  String get shellUnlock => 'Entsperren';

  @override
  String get tableColumnLeft => 'Spalte links einfügen';

  @override
  String get tableColumnRight => 'Spalte rechts einfügen';

  @override
  String get tableDeleteColumn => 'Spalte löschen';

  @override
  String get tableDeleteRow => 'Zeile löschen';

  @override
  String get tableRowAbove => 'Zeile oberhalb einfügen';

  @override
  String get tableRowBelow => 'Zeile unterhalb einfügen';

  @override
  String get tagContact => 'Kontakt';

  @override
  String get tagCritical => 'Dringend';

  @override
  String get tagCustom => 'Markierung';

  @override
  String get tagDefinition => 'Definition';

  @override
  String get tagIdea => 'Idee';

  @override
  String get tagImportant => 'Wichtig';

  @override
  String get tagQuestion => 'Frage';

  @override
  String get tagRemember => 'Merken';

  @override
  String get tagTodo => 'Aufgabe';

  @override
  String get touchDrawAlways => 'Immer';

  @override
  String get touchDrawAuto => 'Auto (Stift hat Vorrang)';

  @override
  String get touchDrawNever => 'Nie';

  @override
  String updateAvailable(String version) {
    return 'Openote $version ist verfügbar';
  }

  @override
  String updateYouHave(String version) {
    return 'Du hast $version.';
  }

  @override
  String get updateDownloading => 'Wird heruntergeladen…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Wird heruntergeladen… $percent %';
  }

  @override
  String get updateSavedClosing =>
      'Deine Notizen sind gespeichert. Openote wird geschlossen, aktualisiert sich und öffnet sich wieder.';

  @override
  String get updateWillRestart =>
      'Deine Notizen werden zuerst gespeichert. Openote schließt sich während der Installation und öffnet sich dann von selbst wieder.';

  @override
  String get updateInstallYourself =>
      'Du musst sie selbst herunterladen und installieren.';

  @override
  String get updateNotNow => 'Jetzt nicht';

  @override
  String get updateNow => 'Jetzt aktualisieren';

  @override
  String get updateDownload => 'Herunterladen';

  @override
  String get settingsGrammarCheck => 'Grammatik prüfen';

  @override
  String get settingsAutoCorrect => 'Kleine Tippfehler automatisch korrigieren';

  @override
  String get settingsAutoCapitalize => 'Satzanfänge großschreiben';

  @override
  String get settingsSpellLanguage => 'Sprache der Rechtschreibung';

  @override
  String get settingsSpellLanguageSystem => 'Systemstandard';

  @override
  String get settingsSpellLanguageOther => 'Andere Sprache (nicht geprüft)';

  @override
  String get settingsEnglishAU => 'Englisch (Australien)';

  @override
  String get settingsEnglishGB => 'Englisch (Vereinigtes Königreich)';

  @override
  String get settingsEnglishUS => 'Englisch (USA)';

  @override
  String get settingsEnglishCA => 'Englisch (Kanada)';

  @override
  String get settingsEnglishIN => 'Englisch (Indien)';

  @override
  String get settingsWritingEnglishOnly =>
      'Grammatik, Tippfehlerkorrektur und Großschreibung funktionieren vorerst nur auf Englisch. In allen anderen Sprachen bleiben sie aus.';

  @override
  String get barTabWrite => 'Schreiben';

  @override
  String get insertNotYet => 'Noch nicht';

  @override
  String get barHideKeyboard => 'Tastatur ausblenden';

  @override
  String get pageSheetBlank => 'Leer';

  @override
  String get pageSheetGrid => 'Raster';

  @override
  String get pageSheetDots => 'Punkte';

  @override
  String get pageSheetRuled => 'Liniert';

  @override
  String get pageSheetPaper => 'Papier';

  @override
  String get pageSheetCanvas => 'Leinwand';

  @override
  String get pageSheetSnap => 'Einrasten';

  @override
  String get pageSheetFit => 'Einpassen';

  @override
  String get navOpening => 'Dieses Notizbuch wird geöffnet…';

  @override
  String get openFolderTitle => 'Notizbuch aus einem Ordner öffnen';

  @override
  String get openFolderBody =>
      'Wähle den Ordner, in dem deine Notizbücher liegen, zum Beispiel einen in Google Drive, OneDrive oder Dropbox. Openote sucht darin nach Notizbüchern.';

  @override
  String get openFolderChoose => 'Ordner wählen…';

  @override
  String get openFolderNone =>
      'Dort wurde kein Notizbuch gefunden. Wähle den Ordner, der deine Notizbücher enthält, oder den eigenen Ordner eines Notizbuchs (sein Name endet auf .onotebook).';

  @override
  String get openFolderLooking => 'Notizbücher werden gesucht…';

  @override
  String get openFolderAndroidHint =>
      'Wähle den Ordner mit deinen Notizbüchern. In Google Drive ist das meist der Ordner „Openote“. Tippe dann auf „Diesen Ordner verwenden“.';

  @override
  String get openFolderFound => 'Gefundene Notizbücher';

  @override
  String protectLockTitle(String title) {
    return '„$title“ sperren';
  }

  @override
  String protectLockedTitle(String title) {
    return '„$title“ ist gesperrt';
  }

  @override
  String get protectBetaHeadline =>
      'Beta: Damit wird die Seite in Openote versteckt, aber noch nicht verschlüsselt.';

  @override
  String get protectBetaBody =>
      'Vorerst kann jeder, der deine Notizbuchdatei hat, die Seite trotzdem lesen, und ein vergessener Code lässt sich nicht wiederherstellen. Echte Verschlüsselung ist geplant.';

  @override
  String get protectPasscode => 'Code';

  @override
  String get protectPasscodeAgain => 'Code wiederholen';

  @override
  String get protectAskAgain => 'Erneut abfragen …';

  @override
  String get protectLock => 'Sperren';

  @override
  String get protectEnterPasscode => 'Gib einen Code ein.';

  @override
  String get protectMismatch => 'Die beiden Eingaben stimmen nicht überein.';

  @override
  String get protectWrong => 'Das ist nicht der Code.';

  @override
  String get protectPolicyAlways => 'Bei jedem Öffnen';

  @override
  String get protectPolicyTenMinutes => 'Für 10 Minuten';

  @override
  String get protectPolicyOneHour => 'Für 1 Stunde';

  @override
  String get protectPolicySession => 'Bis Openote geschlossen wird';

  @override
  String get linkTitleNew => 'Link';

  @override
  String get linkTitleEdit => 'Link bearbeiten';

  @override
  String get linkTextToShow => 'Angezeigter Text';

  @override
  String get linkNothingSelected =>
      'Es war nichts ausgewählt, das zu einem Link werden könnte';

  @override
  String get linkAddress => 'Adresse';

  @override
  String get linkOrPage => 'oder auf eine Seite verlinken';

  @override
  String get linkRemove => 'Link entfernen';

  @override
  String get linkUpdate => 'Aktualisieren';

  @override
  String get linkInsert => 'Einfügen';

  @override
  String get linkNeedWords => 'Gib dem Link einen Text zum Anzeigen.';

  @override
  String get linkBadAddress =>
      'Das sieht nicht nach einer Adresse aus, die Openote öffnen kann. Versuch etwas wie https://example.com';

  @override
  String get linkNoCaret =>
      'Setz zuerst den Cursor dorthin, wo der Link hin soll.';

  @override
  String get linkOneLine =>
      'Ein Link muss in einer Zeile stehen. Wähle Wörter in einer einzigen Zeile aus.';

  @override
  String get linkOnObject =>
      'Ein Bild, eine Tabelle oder eine Karte kann keinen Link tragen. Setz ihn stattdessen auf Wörter.';

  @override
  String get linkOnMaths =>
      'Eine Gleichung kann keinen Link tragen – die Klammern gehören zur Mathematik.';

  @override
  String get linkBrackets =>
      'Der Text eines Links darf keine eckigen Klammern enthalten. Wähle etwas ohne sie aus.';

  @override
  String get linkNested =>
      'Dieser Text ist bereits formatiert oder verlinkt. Wähle einfache Wörter aus oder klick in den Link, um ihn zu bearbeiten.';

  @override
  String get alertsTitle => 'Erinnerungen vor Lehrveranstaltungen';

  @override
  String get alertsIntro =>
      'Openote kann sich melden, bevor etwas in deinem Stundenplan beginnt. Die Art eines Termins wird aus seinem Namen erkannt; wähle also die Arten, bei denen du wirklich unterbrochen werden möchtest.';

  @override
  String get alertsPreset => '10 Minuten vor Lehrveranstaltungen erinnern';

  @override
  String get alertsAllOff => 'Alle ausschalten';

  @override
  String get alertsWhileRunning =>
      'Erinnerungen erscheinen in Openote und erreichen dich daher nur, solange es läuft. Was du verpasst hast, findest du beim nächsten Öffnen in diesem Bereich.';

  @override
  String get alertsAtStart => 'Zu Beginn';

  @override
  String alertsMinutes(int minutes) {
    return '$minutes Min.';
  }

  @override
  String get eventKindLecture => 'Vorlesung';

  @override
  String get eventKindTutorial => 'Tutorium';

  @override
  String get eventKindLab => 'Labor / Praktikum';

  @override
  String get eventKindWorkshop => 'Workshop';

  @override
  String get eventKindSeminar => 'Seminar';

  @override
  String get eventKindExam => 'Prüfung / Test';

  @override
  String get eventKindMeeting => 'Besprechung';

  @override
  String get eventKindOther => 'Alles andere';

  @override
  String get commonOk => 'OK';

  @override
  String get saveProblemNotAddedShort => 'Das wurde nicht hinzugefügt';

  @override
  String get saveProblemNotAdded =>
      'Openote konnte das Bild oder die Datei, die du gerade hinzugefügt hast, nicht speichern; es ist daher nicht in deinem Notizbuch.\n\nPrüfe, ob der Datenträger voll ist und ob der Ordner des Notizbuchs schreibgeschützt ist, und füge es dann erneut ein oder zieh es erneut hinein.';

  @override
  String get saveProblemNotOnDriveShort => 'Noch nicht in Drive';

  @override
  String get saveProblemNotOnDrive =>
      'Deine Änderungen sind auf diesem Telefon gespeichert. Sie konnten gerade nicht an den Drive-Ordner gesendet werden (keine Verbindung oder der Ordner ist nicht erreichbar) und werden gesendet, sobald er erreichbar ist.';

  @override
  String get saveProblemNotRecordedShort => 'Gespeichert, aber nicht erfasst';

  @override
  String get saveProblemNotRecorded =>
      'Openote hat deine Notizen auf diesem Computer gespeichert, konnte die Änderung aber nicht in den Verlauf dieses Notizbuchs aufnehmen.\n\nAus dem Verlauf lesen deine anderen Geräte, deine Sicherungen und deine geteilten Ordner. Sie können daher zurückfallen, bis das wieder funktioniert. Nichts, was du geschrieben hast, ist verloren.\n\nPrüfe, ob der Datenträger voll ist, ob der Ordner des Notizbuchs schreibgeschützt ist und ob eine Cloud-App wie OneDrive oder Google Drive damit fertig ist. Openote versucht es bei jedem Speichern erneut.';

  @override
  String get saveProblemPageShort => 'Nicht gespeichert — noch im Speicher';

  @override
  String get saveProblemPage =>
      'Openote konnte diese Seite nicht auf deinem Computer speichern.\n\nDeine Änderungen sind noch auf dem Bildschirm, und Openote versucht es erneut, wenn du das nächste Mal tippst oder das Fenster schließt. Beim ersten Schließen bleibt das Fenster offen, damit du das Problem beheben kannst; schließt du es erneut, beendet sich Openote ohne diese Änderungen.\n\nPrüfe, ob der Datenträger voll ist und ob das Notizbuch in einem anderen Programm geöffnet ist.';

  @override
  String get saveProblemPicturesShort => 'Einige Bilder fehlen möglicherweise';

  @override
  String saveProblemPictures(int count) {
    return 'Openote bewahrt von jedem Bild und jeder Zeichnung eine zweite Kopie im eigenen Ordner dieses Notizbuchs auf, damit deine anderen Geräte und deine Sicherungen sie ebenfalls anzeigen können.\n\nFür $count davon konnte Openote nirgends auf diesem Computer intakte Daten finden — weder in dieser zweiten Kopie noch in der Arbeitsdatei des Notizbuchs. Bis sie wieder auftauchen (von einem anderen Gerät, aus einer Sicherung oder indem du das Bild erneut hinzufügst), bleiben sie überall leer, wo sie verwendet werden, auf diesem Computer wie auf jedem anderen.\n\nPrüfe, ob der Datenträger voll ist und ob der Ordner schreibgeschützt ist, und schließ das Notizbuch und öffne es dann erneut. Openote versucht es bei jedem Öffnen erneut.';
  }

  @override
  String get saveProblemListLockedShort => 'Deine Notizbuchliste ist gesperrt';

  @override
  String get saveProblemNewerShort => 'Schreibgeschützt — von neuerem Openote';

  @override
  String get saveProblemNewer =>
      'Dieses Notizbuch enthält Änderungen, die mit einer neueren Version von Openote gemacht wurden, und diese Version kann sie nicht lesen.\n\nDeshalb zeigt Openote dir dieses Notizbuch, ohne es zu verändern. Alles darin ist sicher, und nichts, was du hier tust, kann es beschädigen — aber was du jetzt eingibst, wird nicht behalten.\n\nWenn du Openote auf die neueste Version aktualisierst, kannst du es wieder bearbeiten.';

  @override
  String get saveProblemListShort => 'Notizbuchliste nicht gespeichert';

  @override
  String get saveProblemList =>
      'Openote konnte deine Notizbuchliste und Einstellungen nicht speichern. Beim ersten Schließen bleibt das Fenster offen. Prüfe den Datenträger und versuch es erneut, oder schließ das Fenster noch einmal, um trotzdem zu beenden.';

  @override
  String get mcpTitle => 'KI-Zugriff';

  @override
  String get mcpIntro =>
      'Lass einen KI-Assistenten – etwa Claude – deine Notizen lesen und durchsuchen, dich abfragen und Karteikarten daraus erstellen. Das funktioniert nur, solange Openote geöffnet ist, nur auf diesem Computer, und alles, was er hinzufügt, ist eine normale Änderung: Strg+Z macht sie rückgängig.';

  @override
  String get mcpPasscodeNote =>
      'Alles mit einem Code bleibt privat: Ein KI-Assistent kann es weder sehen noch ändern, auch nicht, während du es entsperrt hast. Ein Code sperrt Openote, nicht die Datei selbst. Ein KI-Werkzeug, das Dateien auf deinem Computer öffnen kann, könnte sie also trotzdem lesen.';

  @override
  String mcpCouldNotStart(String error) {
    return 'Start fehlgeschlagen: $error';
  }

  @override
  String mcpReady(String lastUsed) {
    return 'Bereit. $lastUsed';
  }

  @override
  String get mcpNeverUsed =>
      'Seit dem Start von Openote hat noch kein KI-Assistent darauf zugegriffen.';

  @override
  String get mcpUsedJustNow =>
      'Zuletzt gerade eben von einem KI-Assistenten verwendet.';

  @override
  String mcpUsedMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Zuletzt vor $minutes Minuten von einem KI-Assistenten verwendet.',
      one: 'Zuletzt vor 1 Minute von einem KI-Assistenten verwendet.',
    );
    return '$_temp0';
  }

  @override
  String mcpUsedHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Zuletzt vor $hours Stunden von einem KI-Assistenten verwendet.',
      one: 'Zuletzt vor 1 Stunde von einem KI-Assistenten verwendet.',
    );
    return '$_temp0';
  }

  @override
  String get mcpUsedOverADay =>
      'Zuletzt vor mehr als einem Tag von einem KI-Assistenten verwendet.';

  @override
  String get mcpRestartHint =>
      'Ein KI-Assistent sucht beim Start nach Openote. War deiner schon geöffnet, starte ihn neu.';

  @override
  String mcpClientIsSetUp(String name) {
    return '$name – eingerichtet';
  }

  @override
  String mcpSetUpClient(String name) {
    return '$name einrichten';
  }

  @override
  String get mcpClaudeApp => 'Claude-App';

  @override
  String get mcpChatGptApp => 'ChatGPT-App';

  @override
  String get mcpWebsiteNote =>
      'Die ChatGPT-Website lässt sich nicht verbinden: Ihre Connectors laufen auf den Servern von OpenAI, die deinen Computer nicht sehen können. Die Schaltfläche oben ist für die Desktop-App, die ihre Einstellungen von diesem Computer liest. Für die Gemini-App gilt dasselbe wie für die Website – für ihre CLI gibt es eine Schaltfläche.';

  @override
  String get mcpCopyAddress => 'Adresse kopieren';

  @override
  String get mcpCopyConfiguration => 'Konfiguration kopieren';

  @override
  String get mcpOtherTools => 'Andere KI-Werkzeuge (erweitert)';

  @override
  String get mcpOtherToolsBody =>
      'Openote spricht MCP, den Standard, über den KI-Werkzeuge sich mit Apps verbinden. Jedes MCP-fähige Werkzeug kann das nutzen – der enthaltene Schlüssel ist ein Passwort, füge ihn also nur in Werkzeuge ein, denen du vertraust.';

  @override
  String mcpListening(String port) {
    return 'Wartet auf Port $port, nur auf diesem Computer.';
  }

  @override
  String get mcpNotListening => 'Wartet nicht.';

  @override
  String get mcpCopyConfig => 'Konfiguration kopieren';

  @override
  String get mcpCliIntro =>
      'Oder führ für Werkzeuge mit Befehlszeile einmalig aus:';

  @override
  String get mcpCopyCommand => 'Befehl kopieren';

  @override
  String get mcpCopied =>
      'Kopiert. Der enthaltene Schlüssel ist ein Passwort – füge ihn nur in deine eigenen Werkzeuge ein.';

  @override
  String get mcpChatGptUnreadable =>
      'Die Einstellungsdatei von ChatGPT konnte nicht gelesen werden, daher hat Openote sie nicht angerührt. Die Verbindungsdaten unter „Erweitert“ funktionieren weiterhin.';

  @override
  String get mcpChatGptUnparsable =>
      'Die Einstellungsdatei von ChatGPT enthält etwas, das Openote nicht versteht, daher wurde sie nicht angerührt. Kopiere die Konfiguration unter „Erweitert“ und füge sie von Hand hinzu.';

  @override
  String mcpSaveFailed(String error) {
    return 'Die Verbindung konnte nicht gespeichert werden: $error';
  }

  @override
  String get mcpChatGptSetUp =>
      'Eingerichtet. Starte die ChatGPT-Desktop-App neu, dann erscheint Openote unter ihren MCP-Servern. Die Website kann das nicht nutzen – nur eine App auf diesem Computer kann Openote sehen.';

  @override
  String get mcpChatGptSavedOnly =>
      'Gespeichert. Openote erscheint, sobald die ChatGPT-Desktop-App oder die Codex-CLI auf diesem Computer installiert ist.';

  @override
  String mcpClientUnreadable(String name) {
    return 'Die Einstellungsdatei von $name konnte nicht gelesen werden, daher hat Openote sie nicht angerührt. Die Verbindungsdaten unter „Erweitert“ funktionieren weiterhin in jedem MCP-fähigen Werkzeug.';
  }

  @override
  String mcpClientSetUp(String name) {
    return 'Eingerichtet. Wenn $name schon geöffnet ist, starte es neu – es sucht beim Start nach Openote. Frag es dann nach deinen Notizen, etwa: „Frag mich ab, was ich diese Woche geschrieben habe.“';
  }

  @override
  String mcpClientNotInstalled(String name) {
    return 'Openote ist bereit, aber $name scheint auf diesem Computer noch nicht installiert zu sein. Sobald es das ist, funktioniert die Verbindung von selbst.';
  }

  @override
  String get timeNow => 'jetzt';

  @override
  String timeMinutesShort(String n) {
    return '$n Min.';
  }

  @override
  String timeHoursShort(String n) {
    return '$n Std.';
  }

  @override
  String timeDaysShort(String n) {
    return '$n T.';
  }

  @override
  String timeMonthsShort(String n) {
    return '$n Mon.';
  }

  @override
  String timeYearsShort(String n) {
    return '$n J.';
  }

  @override
  String get countdownToday => 'heute';

  @override
  String get countdownTomorrow => 'morgen';

  @override
  String get countdownYesterday => 'gestern';

  @override
  String countdownDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String countdownDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Tagen',
      one: 'vor 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get countdownPassed => 'vorbei';

  @override
  String get monthsShort =>
      'Jan.,Feb.,März,Apr.,Mai,Juni,Juli,Aug.,Sept.,Okt.,Nov.,Dez.';

  @override
  String dateDayMonth(String day, String month) {
    return '$day. $month';
  }

  @override
  String dateDayMonthYear(String day, String month, String year) {
    return '$day. $month $year';
  }

  @override
  String get gradeAgain => 'Nochmal';

  @override
  String get gradeHard => 'Schwer';

  @override
  String get gradeGood => 'Gut';

  @override
  String get gradeEasy => 'Leicht';

  @override
  String get deckThisPage => 'Diese Seite';

  @override
  String get deckThisSection => 'Dieser Abschnitt';

  @override
  String get deckWholeNotebook => 'Ganzes Notizbuch';

  @override
  String get studyAnkiText => 'Anki-Text';

  @override
  String studyExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Karten exportiert – in Anki mit Datei ▸ Importieren einlesen',
      one: '1 Karte exportiert – in Anki mit Datei ▸ Importieren einlesen',
    );
    return '$_temp0';
  }

  @override
  String get studyForgetTitle => 'Zeitplan dieses Stapels vergessen?';

  @override
  String studyForgetBody(String scope) {
    String _temp0 = intl.Intl.selectLogic(
      scope,
      {
        'page':
            'Jede Karte auf dieser Seite wird wieder neu. Deine Notizen bleiben unberührt.',
        'section':
            'Jede Karte in diesem Abschnitt wird wieder neu. Deine Notizen bleiben unberührt.',
        'other':
            'Jede Karte im ganzen Notizbuch wird wieder neu. Deine Notizen bleiben unberührt.',
      },
    );
    return '$_temp0';
  }

  @override
  String get studyForget => 'Vergessen';

  @override
  String studyResetCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Karten zurückgesetzt',
      one: '1 Karte zurückgesetzt',
    );
    return '$_temp0';
  }

  @override
  String get studyEnd => 'Beenden';

  @override
  String get studyDeckActions => 'Stapelaktionen';

  @override
  String get studyExportAnki => 'Nach Anki exportieren…';

  @override
  String get studySetExam => 'Prüfungstermin festlegen…';

  @override
  String get studyChangeExam => 'Prüfungstermin ändern…';

  @override
  String get studyRemoveExam => 'Prüfungstermin entfernen';

  @override
  String get studyForgetSchedule => 'Zeitplan vergessen…';

  @override
  String get studyDue => 'fällig';

  @override
  String studyCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Karten',
      one: '1 Karte',
    );
    return '$_temp0';
  }

  @override
  String studyNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neu',
    );
    return '$_temp0';
  }

  @override
  String studyReview(String count) {
    return '$count wiederholen';
  }

  @override
  String get studyAllCaughtUp => 'Alles erledigt.';

  @override
  String studyAllCaughtUpNext(String delay) {
    return 'Alles erledigt – nächste Karte in $delay.';
  }

  @override
  String studyPracticeAll(String count) {
    return 'Alle $count üben';
  }

  @override
  String get studyPracticeNote => 'Üben ändert deinen Zeitplan nicht.';

  @override
  String get studyThisSection => 'Diesen Abschnitt lernen';

  @override
  String studyExamWhen(String when) {
    return 'Prüfung $when';
  }

  @override
  String get studyKeepSchedule => 'Diese Karten behalten ihren Zeitplan.';

  @override
  String get studyExamGoodLuck => 'Jede Karte gesehen. Viel Erfolg!';

  @override
  String studyExamUnseenToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hast du noch nicht gesehen.',
    );
    return '$_temp0';
  }

  @override
  String studyAllSeen(String count) {
    return 'Alle $count gesehen – bleib bei den Wiederholungen dran.';
  }

  @override
  String studyToLearn(String count, String perDay) {
    return '$count zu lernen · $perDay pro Tag schaffen das bis dahin';
  }

  @override
  String get studyExamToday => 'Prüfung heute';

  @override
  String get studySeen => 'GESEHEN';

  @override
  String studyNOfM(String n, String total) {
    return '$n von $total';
  }

  @override
  String get studyAddExam => 'Prüfungstermin hinzufügen';

  @override
  String studyReviewedToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count heute wiederholt',
    );
    return '$_temp0';
  }

  @override
  String get studyNothingToday => 'Heute noch nichts wiederholt';

  @override
  String studyStreakAtRisk(String days) {
    return '$days-Tage-Serie – halte sie heute am Laufen';
  }

  @override
  String studyStreak(String days, String today) {
    return '$days-Tage-Serie · $today heute';
  }

  @override
  String studyActivityTip(String days) {
    return 'Wiederholungen der letzten $days Tage';
  }

  @override
  String get studyDeck => 'Stapel';

  @override
  String get studyNoCards => 'Hier gibt es noch keine Karten.';

  @override
  String get studyRecipeQuestion =>
      'Markiere eine Frage. Die eingerückte Zeile darunter ist die Antwort.';

  @override
  String get studyRecipeDefinition =>
      'Markiere eine Definition in der Form „Begriff — Bedeutung“.';

  @override
  String get studyRecipeCloze =>
      'Hebe einen Teil einer markierten Zeile hervor, um stattdessen diesen auszublenden.';

  @override
  String get studyCardsAreNotes =>
      'Karten sind eine Ansicht deiner Notizen: Wenn du die Notiz bearbeitest, änderst du die Karte – es gibt nichts Separates zu pflegen.';

  @override
  String studyReviewedCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Karten wiederholt',
      one: '1 Karte wiederholt',
    );
    return '$_temp0';
  }

  @override
  String studyStillDue(String count) {
    return '$count in diesem Stapel noch fällig.';
  }

  @override
  String get studyNothingElseDue => 'Sonst ist nichts fällig.';

  @override
  String studyNextCardIn(String delay) {
    return 'Nächste Karte in $delay.';
  }

  @override
  String studyNeedAnotherLook(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count brauchen noch einen Blick.',
      one: '1 braucht noch einen Blick.',
    );
    return '$_temp0';
  }

  @override
  String get studyExamTodayDot => 'Prüfung heute.';

  @override
  String studyUntilExam(String countdown) {
    return '$countdown bis zur Prüfung.';
  }

  @override
  String studyUntilExamUnseen(String countdown, String count) {
    return '$countdown bis zur Prüfung · $count noch nicht gesehen.';
  }

  @override
  String studyReviewAgain(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Diese $count nochmal wiederholen',
      one: 'Diese eine nochmal wiederholen',
    );
    return '$_temp0';
  }

  @override
  String studyKeepGoing(String count) {
    return 'Weiter – $count fällig';
  }

  @override
  String get studyPracticeBadge => 'ÜBEN';

  @override
  String get studyShowAnswer => 'Antwort zeigen';

  @override
  String get studyOpenNote => 'Notiz öffnen';

  @override
  String get studyAnswerHidden => 'Antwort verborgen';

  @override
  String get studyAnswer => 'ANTWORT';

  @override
  String get studyFillBlank => 'LÜCKE FÜLLEN';

  @override
  String studyExamMenu(String when, String countdown) {
    return 'Prüfung $when · $countdown…';
  }

  @override
  String get examDateTitle => 'Prüfungstermin';

  @override
  String examTitleFor(String section) {
    return 'Prüfung – $section';
  }

  @override
  String examRemoved(String date) {
    return 'Prüfungstermin entfernt ($date). Deine Karten sind unverändert.';
  }

  @override
  String get examUseDate => 'Dieses Datum verwenden';

  @override
  String get examWhatTime => 'Wann beginnt sie?';

  @override
  String get examDate => 'Datum';

  @override
  String get examAddTime => 'Startzeit hinzufügen';

  @override
  String get examStarts => 'Beginn';

  @override
  String get examNoTime => 'Keine bestimmte Uhrzeit';

  @override
  String get examTimeOptional =>
      'Countdown und Lernplan rechnen in ganzen Tagen, eine Uhrzeit ist also optional.';

  @override
  String get examShownOnDay =>
      'Wird am Tag angezeigt. Der Countdown rechnet weiter in ganzen Tagen.';

  @override
  String get examSet => 'Festlegen';
}
