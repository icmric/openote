// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class LIt extends L {
  LIt([String locale = 'it']) : super(locale);

  @override
  String get commonBack => 'Indietro';

  @override
  String get commonSkip => 'Salta';

  @override
  String get commonNext => 'Avanti';

  @override
  String get commonOpen => 'Apri';

  @override
  String get commonCancel => 'Annulla';

  @override
  String get commonDetailsAdvanced => 'Dettagli (avanzato)';

  @override
  String objectRowBackground(String kind) {
    return 'Sfondo: $kind';
  }

  @override
  String get objectRowBackgroundBlank => 'bianco';

  @override
  String get objectRowBackgroundGrid => 'quadretti';

  @override
  String get objectRowBackgroundDotted => 'puntinato';

  @override
  String get objectRowBackgroundRuled => 'righe';

  @override
  String objectRowPageMode(String paper, String landscape) {
    return 'Modalità pagina: $paper$landscape — clicca per la tela';
  }

  @override
  String get objectRowLandscapeSuffix => ' orizzontale';

  @override
  String get objectRowCanvasMode =>
      'Modalità tela: senza confini — clicca per le pagine';

  @override
  String get objectRowPaperSize => 'Formato del foglio';

  @override
  String get objectRowLandscape => 'Orizzontale';

  @override
  String get objectRowSnapOn =>
      'Aggancia alla griglia: SÌ (si vede mentre trascini)';

  @override
  String get objectRowSnapOff => 'Aggancia alla griglia: NO — posizione libera';

  @override
  String get objectRowZoomOut => 'Riduci  (Ctrl+-)';

  @override
  String get objectRowZoomIn => 'Ingrandisci  (Ctrl+=)';

  @override
  String get objectRowZoomReset =>
      'Torna al 100% e all\'inizio della pagina  (Ctrl+0)';

  @override
  String get objectRowZoomFit => 'Adatta lo zoom al contenuto';

  @override
  String get objectRowWordCount =>
      'Parole in questa pagina — clicca per caratteri e tempo di lettura';

  @override
  String get objectRowWords => 'Parole';

  @override
  String get objectRowCharacters => 'Caratteri';

  @override
  String get objectRowCharactersNoSpaces => 'Senza spazi';

  @override
  String get objectRowReadingTime => 'Tempo di lettura';

  @override
  String objectRowMinutes(int n) {
    return '$n min';
  }

  @override
  String objectRowWordTally(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted parole',
      one: '1 parola',
      zero: 'nessuna parola',
    );
    return '$_temp0';
  }

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent%';
  }

  @override
  String get barTabHome => 'Home';

  @override
  String get barTabInsert => 'Inserisci';

  @override
  String get barTabDraw => 'Disegna';

  @override
  String get barEquationBadge => 'Equazione';

  @override
  String barUpdateTo(String version) {
    return 'Aggiorna alla $version…';
  }

  @override
  String get barDone => 'Fatto';

  @override
  String get barStudy => 'Studio';

  @override
  String get barPlanner => 'Agenda';

  @override
  String get barFindTags => 'Cerca etichette';

  @override
  String get barPageOutline => 'Struttura della pagina';

  @override
  String get barLinks => 'Collegamenti e rimandi';

  @override
  String get barFindOnPage => 'Cerca nella pagina';

  @override
  String get barFindOnPageTip => 'Cerca nella pagina  (Ctrl+F)';

  @override
  String get barExport => 'Esporta';

  @override
  String get barExportTip => 'Esporta la pagina…';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

  @override
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPrint => 'Stampa…';

  @override
  String get barExportPdfPicture => 'PDF — immagine della pagina';

  @override
  String get barExportCanvas => 'Per Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => 'Solo il disegno (.inkml)';

  @override
  String get barExportNotebook =>
      'Salva tutto il quaderno come cartelle e file…';

  @override
  String get barExportNotebookBusy => 'Salvataggio del quaderno…';

  @override
  String barExportPageProgress(int done, int total) {
    return 'Pagina $done di $total…';
  }

  @override
  String barExportedTo(String path) {
    return 'Esportato in $path';
  }

  @override
  String get barSettings => 'Impostazioni';

  @override
  String get barSettingsTip => 'Impostazioni…';

  @override
  String get barUndo => 'Annulla  (Ctrl+Z)';

  @override
  String get barRedo => 'Ripeti  (Ctrl+Y)';

  @override
  String get barBold => 'Grassetto  (Ctrl+B)';

  @override
  String get barItalic => 'Corsivo  (Ctrl+I)';

  @override
  String get barUnderline => 'Sottolineato  (Ctrl+U)';

  @override
  String get barStrikethrough => 'Barrato';

  @override
  String get barInlineCode => 'Codice nel testo';

  @override
  String get barHighlight => 'Evidenzia';

  @override
  String get barHeading1 => 'Titolo 1';

  @override
  String get barBulletList => 'Elenco puntato';

  @override
  String get barNumberedList => 'Elenco numerato';

  @override
  String get barCheckbox => 'Casella';

  @override
  String get barQuote => 'Citazione';

  @override
  String get barTextColour => 'Colora il testo';

  @override
  String get barTextFont => 'Carattere del testo…';

  @override
  String get barClickIntoTextBox => 'Clicca in una casella di testo';

  @override
  String get barToolSelect => 'Seleziona / sposta  (V)';

  @override
  String get barToolText => 'Testo  (T)';

  @override
  String get barToolPen => 'Penna  (P)';

  @override
  String get barToolHighlighter => 'Evidenziatore  (H)';

  @override
  String get barToolEraser => 'Gomma  (E)';

  @override
  String get barToolLasso => 'Seleziona l\'inchiostro con il lazo';

  @override
  String get barEraserSplit => 'Spezza i tratti dove strofini';

  @override
  String get barEraserWhole => 'Toglie tutto il tratto che tocchi';

  @override
  String get barLassoHint =>
      'Cerchia l\'inchiostro per selezionarlo — poi trascinalo o cancellalo';

  @override
  String get barPickPenHint =>
      'Scegli la penna o l\'evidenziatore per disegnare';

  @override
  String get barTouchDrawing =>
      'Disegna con il dito.\nAuto: il dito disegna finché non usi la penna; poi il dito sposta la pagina, così il palmo non lascia segni.\nDue dita spostano e ingrandiscono sempre.';

  @override
  String get barPenProximity =>
      'Avvicinare la penna alla pagina passa all\'inchiostro.\nSe scegli un altro strumento mentre la penna è vicina, resta\nfinché la penna non si allontana e torna. La coda della penna\n(o il suo tasto, tenuto premuto) cancella.';

  @override
  String get barTextSize => 'Dimensione del testo (punti)';

  @override
  String get barTextSizeDisabled =>
      'Clicca in una casella di testo per cambiarne la dimensione';

  @override
  String get barFontSizeDefault => 'Predefinito';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barTagLine =>
      'Etichetta questa riga (Da fare, Importante, Domanda…)';

  @override
  String barTagged(String tags) {
    return 'Etichettata: $tags';
  }

  @override
  String get barDueDateSet => 'Scadenza…';

  @override
  String get barDueDateChange => 'Cambia la scadenza…';

  @override
  String get barDueDateClear => 'Togli la scadenza';

  @override
  String get barDueDatePickerTitle => 'Scadenza';

  @override
  String get barDueDatePickerConfirm => 'Imposta';

  @override
  String get barMakeCardFromLine => 'Trasforma questa riga in una scheda';

  @override
  String get barNewCard => 'Nuova scheda';

  @override
  String get barQuestionCard => 'Scheda domanda';

  @override
  String get barDefinitionCard => 'Scheda definizione';

  @override
  String get barBlankOut => 'Nascondi la selezione';

  @override
  String get barBlankOutNeedsSelection =>
      'Seleziona prima le parole da nascondere.';

  @override
  String get barOpenStudyPanel => 'Apri il pannello di studio';

  @override
  String get barStudyEmpty =>
      'Studio — etichetta una riga come Domanda o Definizione per farne una scheda';

  @override
  String barStudyDue(int due, int total, String countdown) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total schede',
      one: '1 scheda',
    );
    return '$due di $_temp0 da ripassare in questa sezione$countdown';
  }

  @override
  String barStudyExamCountdown(String when) {
    return ' · esame $when';
  }

  @override
  String get barPlannerEmpty => 'Agenda — tutte le tue date in un posto solo';

  @override
  String barPlannerToday(int count) {
    return 'Agenda — $count per oggi';
  }

  @override
  String barPlannerOverdue(int count) {
    return 'Agenda — $count per oggi o in ritardo';
  }

  @override
  String barRemindersWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count promemoria',
      one: '1 promemoria',
    );
    return '$_temp0 in attesa';
  }

  @override
  String get barEscWhenDone => 'Premi Esc quando hai finito';

  @override
  String barSaveFailed(String reason) {
    return 'Non è stato possibile salvare: $reason';
  }

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get navSearchHint => 'Cerca o vai a…';

  @override
  String navNoMatches(String query) {
    return 'Nessun risultato per «$query»';
  }

  @override
  String get navInPageContent => 'Nel contenuto delle pagine';

  @override
  String get navUntitled => 'Senza titolo';

  @override
  String get navNoSections =>
      'Ancora nessuna sezione.\nCreane una per iniziare.';

  @override
  String get navNewSection => 'Nuova sezione';

  @override
  String navNewPageIn(String section) {
    return 'Nuova pagina in $section';
  }

  @override
  String get navNoPages => 'Ancora nessuna pagina';

  @override
  String get navSection => 'Sezione';

  @override
  String get navNewSectionGroup => 'Nuovo gruppo di sezioni';

  @override
  String get navRecycleBin => 'Cestino';

  @override
  String get navHome => 'Home';

  @override
  String get navHomeTip => 'Home — preferiti e recenti';

  @override
  String get navHomeEmpty =>
      'Qui non c\'è ancora niente.\n\nClicca con il tasto destro su una pagina e scegli Preferita per fissarla; le pagine che apri finiscono in Recenti.';

  @override
  String get navComingUp => 'IN ARRIVO';

  @override
  String navAllCount(int total) {
    return 'Tutte e $total';
  }

  @override
  String get navOpen => 'Apri';

  @override
  String get navExpand => 'Apri il navigatore  (Ctrl+\\)';

  @override
  String get navCollapse => 'Chiudi il navigatore  (Ctrl+\\)';

  @override
  String get navNotebooksTip => 'Quaderni — cambia, rinomina, duplica, importa';

  @override
  String get navDeletesSoon => 'Sta per essere eliminato';

  @override
  String navDeletesInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Eliminato fra $days giorni',
      one: 'Eliminato fra 1 giorno',
    );
    return '$_temp0';
  }

  @override
  String get navBinEmpty => 'Niente di eliminato.';

  @override
  String navBinRetention(int days) {
    return 'Quello che sta qui viene eliminato per sempre dopo $days giorni.';
  }

  @override
  String get navBinNotebooks => 'Quaderni';

  @override
  String get navBinItems => 'Elementi';

  @override
  String get navRestore => 'Ripristina';

  @override
  String get navDeletePermanently => 'Elimina per sempre';

  @override
  String get navClose => 'Chiudi';

  @override
  String get navDeleteForeverTitle => 'Eliminare per sempre?';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '«$title» e tutte le sue pagine saranno rimosse per sempre. Non si può annullare.$caveat';
  }

  @override
  String get navDeleteForever => 'Elimina per sempre';

  @override
  String navLockedCannotDelete(String title) {
    return '«$title» è bloccata. Togli il codice prima di eliminarla.';
  }

  @override
  String navDeletedRestorable(String title) {
    return '«$title» eliminata — puoi ripristinarla dal cestino.';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '«$title» è bloccata. È nascosta dentro Openote, non cifrata nel file.';
  }

  @override
  String navPasscodeRemoved(String title) {
    return 'Codice rimosso da «$title».';
  }

  @override
  String navSavedTo(String path) {
    return 'Salvato in $path';
  }

  @override
  String get navLinkCopied =>
      'Collegamento copiato — incollalo in qualsiasi pagina';

  @override
  String get navMoveSectionTo => 'Sposta la sezione in…';

  @override
  String get navNoGroupTopLevel => '(Nessun gruppo — primo livello)';

  @override
  String get navSaveTemplateTitle => 'Salva come modello';

  @override
  String get navSave => 'Salva';

  @override
  String get navTemplateNameHint => 'Nome del modello';

  @override
  String navTemplateSaved(String name) {
    return 'Modello «$name» salvato';
  }

  @override
  String get navNoTemplates =>
      'Ancora nessun modello — usa prima «Salva come modello…».';

  @override
  String get navApplyTemplate => 'Applica un modello';

  @override
  String get navColour => 'Colore';

  @override
  String get navColourDefault => 'Predefinito';

  @override
  String navExamCountdown(String when, String countdown) {
    return 'Esame $when · $countdown…';
  }

  @override
  String get navMenuMoveUp => 'Sposta su';

  @override
  String get navMenuMoveDown => 'Sposta giù';

  @override
  String get navMenuNewPage => 'Nuova pagina';

  @override
  String get navMenuMoveToGroup => 'Sposta in un gruppo…';

  @override
  String get navMenuSortAZ => 'Ordina le pagine dalla A alla Z';

  @override
  String get navMenuSortEdited => 'Ordina per ultima modifica';

  @override
  String get navMenuExportSectionPdf => 'Esporta la sezione in PDF…';

  @override
  String get navMenuPrintSection => 'Stampa la sezione…';

  @override
  String get navMenuRemoveExam => 'Togli la data dell\'esame';

  @override
  String get navMenuSetExam => 'Imposta la data dell\'esame…';

  @override
  String get navMenuMakeSubpage => 'Rendi sottopagina';

  @override
  String get navMenuMoveBackOut => 'Riportala fuori';

  @override
  String get navMenuRemoveFavourite => 'Togli dai preferiti';

  @override
  String get navMenuAddFavourite => 'Aggiungi ai preferiti';

  @override
  String get navMenuSharePdf => 'Condividi in PDF…';

  @override
  String get navMenuPrint => 'Stampa…';

  @override
  String get navMenuCopyLink => 'Copia il collegamento alla pagina';

  @override
  String get navMenuRecentChanges => 'Modifiche recenti…';

  @override
  String get navMenuSaveTemplate => 'Salva come modello…';

  @override
  String get navMenuApplyTemplate => 'Applica un modello…';

  @override
  String get navMenuRemovePasscode => 'Togli il codice…';

  @override
  String get navMenuLock => 'Blocca con un codice…';

  @override
  String get navMenuDelete => 'Elimina';

  @override
  String get commonOn => 'Sì';

  @override
  String get commonOff => 'No';

  @override
  String get commonClose => 'Chiudi';

  @override
  String get commonDone => 'Fatto';

  @override
  String get commonDelete => 'Elimina';

  @override
  String get commonOpenEllipsis => 'Apri…';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsAppearance => 'Aspetto';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsThemeLight => 'Chiaro';

  @override
  String get settingsThemeDark => 'Scuro';

  @override
  String get settingsWriting => 'Scrittura e disegno';

  @override
  String get settingsSpellCheck => 'Controllo ortografico';

  @override
  String get settingsPenProximity =>
      'La penna vicino alla pagina passa all\'inchiostro';

  @override
  String get settingsConnections => 'Connessioni';

  @override
  String get settingsSync => 'Sincronizzazione';

  @override
  String get settingsSyncHint =>
      'Fai una copia di questo quaderno e condividilo — GitHub o una cartella.';

  @override
  String get settingsAi => 'Accesso dell\'IA';

  @override
  String get settingsAiOn =>
      'Sì — gli assistenti IA su questo computer possono leggere i tuoi appunti.';

  @override
  String get settingsAiOff => 'No — collega Claude o altri assistenti IA.';

  @override
  String get settingsHelp => 'Aiuto';

  @override
  String get settingsWelcomeTour => 'Visita guidata';

  @override
  String get settingsWelcomeTourHint =>
      'La versione in tre minuti: la tela, la matematica e l\'inchiostro, e dove stanno i tuoi appunti.';

  @override
  String get settingsShortcuts => 'Scorciatoie da tastiera';

  @override
  String get settingsShortcutsHint =>
      'Ogni cosa ha un tasto — l\'elenco completo.  (Ctrl+/)';

  @override
  String get settingsAbout => 'Informazioni';

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsCheckUpdates => 'Cerca aggiornamenti';

  @override
  String settingsUpToDate(String version) {
    return 'Sei aggiornato ($version è la versione più recente).';
  }

  @override
  String get settingsWhatsNew => 'Novità';

  @override
  String get nbTitle => 'Quaderni';

  @override
  String nbOpenCount(int count) {
    return '$count aperti';
  }

  @override
  String nbInBin(int days) {
    return 'Nel cestino · eliminato dopo $days giorni';
  }

  @override
  String get nbImportInto => 'Importa in un nuovo quaderno';

  @override
  String get nbNew => 'Nuovo';

  @override
  String get nbNewTitle => 'Nuovo quaderno';

  @override
  String get nbCreate => 'Crea';

  @override
  String get nbNameHint => 'Nome del quaderno';

  @override
  String get nbImport => 'Importa';

  @override
  String get nbRepair => 'Ripara';

  @override
  String get nbGetStarted => 'Inizia';

  @override
  String get nbImportOnepkg => 'Quaderno di OneNote (.onepkg)';

  @override
  String get nbImportOne => 'Sezione di OneNote (.one)';

  @override
  String get nbImportMarkdown => 'Cartella Markdown';

  @override
  String get nbImportGit => 'Da un indirizzo git';

  @override
  String get nbDuplicates =>
      'Possibili doppioni · stesso titolo e stesso numero di pagine';

  @override
  String get nbDuplicatesHint =>
      'Tieni il più grande — il più piccolo di solito è un\'importazione interrotta a metà. Le copie eliminate finiscono nel cestino.';

  @override
  String get nbOpenThis => 'Apri questo quaderno';

  @override
  String get nbRename => 'Rinomina';

  @override
  String get nbDuplicate => 'Duplica';

  @override
  String get nbMoveToBin => 'Sposta nel cestino';

  @override
  String get nbConfirmBin =>
      'Spostare nel cestino? Potrai ripristinarlo da qui.';

  @override
  String get nbOnePkgFileType => 'Pacchetto di quaderno OneNote';

  @override
  String get nbImportBusy =>
      'C\'è già un\'importazione in corso — una alla volta.';

  @override
  String get nbImportStarted =>
      'Importazione in corso in secondo piano — continua pure; la scheda nell\'angolo avviserà quando ha finito.';

  @override
  String nbImportedNamed(String name) {
    return '$name importato';
  }

  @override
  String get nbReadingFolder => 'Lettura della cartella…';

  @override
  String nbImportedProgress(String done) {
    return 'Importato $done';
  }

  @override
  String get nbNoMarkdown =>
      'In quella cartella non c\'è nessun file Markdown.';

  @override
  String nbImportedPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine importate',
      one: '1 pagina importata',
    );
    return '$_temp0';
  }

  @override
  String get nbNeedsNativeCore =>
      'L\'importazione da OneNote richiede il nucleo Rust — compila onote_core.dll e mettilo accanto all\'app.';

  @override
  String get nbCheckingPages => 'Controllo delle pagine…';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return 'Controllo della pagina $done di $total…';
  }

  @override
  String get nbNothingToRepair =>
      'Niente da riparare — tutte le pagine sono aggiornate.';

  @override
  String nbRepairedBoxes(int blocks) {
    String _temp0 = intl.Intl.pluralLogic(
      blocks,
      locale: localeName,
      other: '$blocks riquadri',
      one: '1 riquadro',
    );
    return '$_temp0';
  }

  @override
  String nbRepairedPages(int pages) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages pagine',
      one: '1 pagina',
    );
    return '$_temp0';
  }

  @override
  String nbRepaired(String boxes, String pages) {
    return 'Riparati $boxes in $pages.';
  }

  @override
  String nbRepairFailed(String reason) {
    return 'Riparazione fallita: $reason';
  }

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '$copies copie di «$title» · $pages pagine ciascuna · si recupererebbero $size';
  }

  @override
  String get nbCoreMissing =>
      'L\'importazione da OneNote richiede il nucleo Rust — compila onote_core.dll (vedi rust/onote_core/INTEGRATION.md).';

  @override
  String nbReadFileFailed(String reason) {
    return 'Non è stato possibile leggere quel file: $reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return 'Non è stato possibile importare quella cartella: $reason';
  }

  @override
  String get nbOneFileEmpty =>
      'Non è stato possibile leggere niente da quel file .one.';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return 'Importato $what da OneNote.$strokeNote';
  }

  @override
  String nbImportedPagesProgress(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine importate…',
      one: '1 pagina importata…',
    );
    return '$_temp0';
  }

  @override
  String mathSemanticLabel(String latex) {
    return 'Equazione: $latex';
  }

  @override
  String get insertGroupWrite => 'Scrivi';

  @override
  String get insertGroupBringIn => 'Porta dentro';

  @override
  String get insertGroupLinkUp => 'Collega';

  @override
  String get insertTextBox => 'Casella';

  @override
  String get insertEquation => 'Equazione';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertTable => 'Tabella';

  @override
  String get insertTableFromFile => 'Da un file';

  @override
  String get insertTableFromFileTip => 'CSV o Excel';

  @override
  String get insertCode => 'Codice';

  @override
  String get insertBoard => 'Bacheca';

  @override
  String get insertBoardTip => 'Colonne di schede che sposti avanti';

  @override
  String get insertPicture => 'Immagine';

  @override
  String get insertPdfSlides => 'PDF';

  @override
  String get insertPdfPrintout => 'Stampa su questa pagina';

  @override
  String get insertPdfPerSlide => 'Una pagina per diapositiva';

  @override
  String get insertPdfAsCard => 'Come scheda — si apre in una finestra';

  @override
  String get insertVideo => 'Video';

  @override
  String get insertVideoTip =>
      'La registrazione di una lezione, o un qualsiasi link';

  @override
  String get insertFile => 'File';

  @override
  String get insertFlashcardItem => 'Scheda';

  @override
  String get insertPageLink => 'Collegamento';

  @override
  String get insertPageWindow => 'Finestra';

  @override
  String get insertTemplate => 'Modello';

  @override
  String get insertPickImages => 'Immagini';

  @override
  String get insertPickTables => 'Tabelle';

  @override
  String get insertPickVideo => 'Video e audio';

  @override
  String get tagTodo => 'Da fare';

  @override
  String get tagImportant => 'Importante';

  @override
  String get tagQuestion => 'Domanda';

  @override
  String get tagRemember => 'Da ricordare';

  @override
  String get tagDefinition => 'Definizione';

  @override
  String get tagIdea => 'Idea';

  @override
  String get tagCritical => 'Urgente';

  @override
  String get tagContact => 'Contatto';

  @override
  String get tagCustom => 'Etichetta';

  @override
  String get touchDrawAuto => 'Auto (comanda la penna)';

  @override
  String get touchDrawAlways => 'Sempre';

  @override
  String get touchDrawNever => 'Mai';

  @override
  String get insertLinkToPage => 'Collega a una pagina';

  @override
  String get insertPdfUnreadable => 'Non è stato possibile leggere quel PDF.';

  @override
  String insertPdfImported(int count, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count diapositive importate',
      one: '1 diapositiva importata',
    );
    return '$_temp0$where — prendi la penna e scrivici sopra. Il testo delle diapositive è cercabile.';
  }

  @override
  String get insertPdfOntoThisPage => ' in questa pagina';

  @override
  String insertPdfFailed(String reason) {
    return 'Importazione del PDF fallita: $reason';
  }

  @override
  String get settingsLanguage => 'Lingua';

  @override
  String get settingsLanguageAuto => 'Come il computer';

  @override
  String get settingsLanguageHelp =>
      'Openote è tradotto da chi lo usa. Se la tua manca o è sbagliata, è un file solo — il collegamento spiega come.';

  @override
  String get settingsLanguageContribute =>
      'Come aggiungere o correggere una lingua';

  @override
  String get shellNothingReplaced => 'Non è stato sostituito niente';

  @override
  String shellReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count occorrenze sostituite',
      one: '1 occorrenza sostituita',
    );
    return '$_temp0';
  }

  @override
  String get shellReplaceWith => 'Sostituisci con…';

  @override
  String get shellReplace => 'Sostituisci';

  @override
  String get shellReplaceAll => 'Tutte';

  @override
  String get shellFindOnThisPage => 'Cerca in questa pagina…';

  @override
  String get shellNoMatches => 'Nessun risultato';

  @override
  String get shellPreviousMatch => 'Risultato precedente (Maiusc+Invio)';

  @override
  String get shellNextMatch => 'Risultato successivo (Invio)';

  @override
  String get shellCloseEsc => 'Chiudi (Esc)';

  @override
  String get shellNoTags => 'In questo quaderno non ci sono ancora etichette.';

  @override
  String get shellTagsHint =>
      'Le etichette segnano una riga — da fare, importante, domanda, definizione — così la ritrovi, ci ripassi sopra o le dai una scadenza.';

  @override
  String get shellTagTheLine => 'Etichetta la riga su cui sei';

  @override
  String get shellNoHeadings => 'Non ci sono titoli in questa pagina.';

  @override
  String get shellHeadingsHint =>
      'Inizia una riga con # per farne un titolo — la struttura si costruisce da sola mentre scrivi.';

  @override
  String get shellLinkedFrom => 'Collegata da';

  @override
  String get shellNoBacklinks => 'Nessuna pagina rimanda ancora qui.';

  @override
  String get shellLinksTo => 'Rimanda a';

  @override
  String get shellNoLinks =>
      'Questa pagina non rimanda ancora da nessuna parte.';

  @override
  String get shellSavedLocally =>
      'Questa pagina è salvata nel tuo file .onote locale.';

  @override
  String get shellSaving => 'Salvataggio…';

  @override
  String get shellSavedOnDevice => 'Salvato su questo dispositivo';

  @override
  String shellRustLinked(String build) {
    return 'Il nucleo Rust (onote-core) è collegato e calcola l\'impronta del contenuto di questa pagina al salvataggio.\n$build';
  }

  @override
  String get shellRustMissing =>
      'Sta girando il motore in puro Dart. Compila la libreria onote-core per collegare il nucleo Rust.';

  @override
  String get shellCheatSheet =>
      'V seleziona · T testo · P penna · H evidenzia · E cancella · Ctrl+Z annulla · Ctrl+rotella zoom';

  @override
  String get shellEmptyTitle => 'Una pagina aperta ti aspetta';

  @override
  String get shellEmptyBody =>
      'Tutto quello che fai qui resta sul tuo dispositivo,\nin un formato aperto che è tuo.';

  @override
  String get shellCreateFirstPage => 'Crea la tua prima pagina';

  @override
  String get shellAlreadyUpToDate => 'Già aggiornato.';

  @override
  String shellPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifiche scaricate',
      one: '1 modifica scaricata',
    );
    return '$_temp0';
  }

  @override
  String shellPageLocked(String title) {
    return '«$title» è bloccata';
  }

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag  ($count)';
  }

  @override
  String get shellUnlock => 'Sblocca';

  @override
  String get onboardingStep1Title => 'La pagina è una tela';

  @override
  String get onboardingStep1Body =>
      'Clicca dove vuoi e inizia a scrivere — la casella compare dove hai cliccato, e solo quando scrivi. La sposti dalla barra in alto, e le immagini le trascini da dove vuoi.';

  @override
  String get onboardingStep2Title =>
      'Matematica e disegno, in mezzo alle parole';

  @override
  String get onboardingStep2Body =>
      'Scrivi 1/2 o premi Alt+= e la notazione si costruisce davvero mentre scrivi, in una casella tutta sua o dentro la frase. La scheda Disegna accetta penna, dito o mouse.';

  @override
  String get onboardingStep3Title => 'I tuoi appunti sono un file tuo';

  @override
  String get onboardingStep3Body =>
      'Un file aperto e leggibile per ogni quaderno — nessun account, nessun vincolo. Mettilo in una cartella che il tuo cloud già sincronizza e tutti i dispositivi restano allineati.';

  @override
  String get onboardingStartWriting => 'Inizia a scrivere';

  @override
  String get onboardingSyncTitle => 'Sincronizza con un altro dispositivo';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive, OneDrive, iCloud, Dropbox, Syncthing, un NAS — o un repository GitHub.';

  @override
  String get onboardingSyncBodyAlso =>
      'Nessuno di questi? Scegli tu la cartella.';

  @override
  String get onboardingSyncAction => 'Configura…';

  @override
  String get onboardingOneNoteTitle => 'Porta gli appunti da OneNote';

  @override
  String get onboardingOneNoteBody =>
      'Pagine, formattazione, immagini, inchiostro ed etichette da un .onepkg. Va in secondo piano — tu continua pure.';

  @override
  String get onboardingOneNoteAction => 'Scegli il file…';

  @override
  String get onboardingFreshTitle => 'Inizia un nuovo blocco appunti';

  @override
  String get onboardingFreshBody =>
      'Un blocco appunti vuoto, pronto per scrivere. Potrai importare le tue note in qualsiasi momento.';

  @override
  String get onboardingFreshAction => 'Inizia da zero';

  @override
  String get onboardingCloudTitle => 'Importa note da OneNote';

  @override
  String get onboardingCloudBody =>
      'Accedi a Microsoft e scegli un blocco appunti. Non serve esportare nulla prima, e funziona su qualsiasi computer.';

  @override
  String get onboardingCloudAction => 'Accedi';

  @override
  String get oneNoteCloudTitle => 'Importa un blocco appunti da OneNote';

  @override
  String get oneNoteCloudIntro =>
      'Openote leggerà i tuoi blocchi appunti da OneNote. Non può modificarli.';

  @override
  String get oneNoteCloudSignIn => 'Accedi a Microsoft';

  @override
  String get oneNoteCloudSigningIn => 'In attesa del browser…';

  @override
  String get oneNoteCloudLoading => 'Ricerca dei tuoi blocchi appunti…';

  @override
  String get oneNoteCloudEmpty =>
      'Nessun blocco appunti trovato per questo account.';

  @override
  String get oneNoteCloudOther => 'Usa un altro account';

  @override
  String get oneNoteCloudNoInk =>
      'Le tabelle vengono adattate alla pagina invece di mantenere la larghezza esatta, e il colore e il carattere del testo non vengono mantenuti.';

  @override
  String get onboardingOnePkgFileType => 'Pacchetto di quaderno OneNote';

  @override
  String get onboardingOneNoteHowTo => 'Come si esporta?';

  @override
  String get onboardingOneNoteHideSteps => 'Nascondi i passaggi';

  @override
  String get onboardingExportTitle => 'Esportare da OneNote';

  @override
  String get onboardingExportSteps =>
      '1. Apri OneNote per Windows (l\'app desktop — le versioni Store e web non possono esportare).\n2. Lascia finire la sincronizzazione, così è tutto su questo computer.\n3. File ▸ Esporta ▸ Blocco appunti ▸ Pacchetto di OneNote (*.onepkg), poi Esporta.\n4. Torna qui e scegli quel file.';

  @override
  String get onboardingExportMacNote =>
      'Su un Mac, o con la sola versione dello Store: esporta una sezione alla volta come .one, oppure fai creare il .onepkg a un computer Windows. Openote non accede mai al tuo account Microsoft — legge solo il file che gli dai.';

  @override
  String onboardingImportingFile(String fileName) {
    return 'Importazione di $fileName';
  }

  @override
  String get onboardingImportRunning =>
      'Continua pure — questo va in secondo piano, e la scheda nell\'angolo avviserà quando ha finito.';

  @override
  String get onboardingImportDone => 'Il tuo quaderno è pronto';

  @override
  String get onboardingOpenFailed =>
      'Openote non è riuscito ad aprire quel quaderno.';

  @override
  String get onboardingNoNativeCore =>
      'L\'importazione da OneNote richiede il nucleo nativo, che questa versione non contiene.';

  @override
  String onboardingReadFailed(String reason) {
    return 'Non è stato possibile leggere quel file: $reason';
  }

  @override
  String get oneNoteFileTitle => 'Usa un file esportato';

  @override
  String get oneNoteFileBody =>
      'Senza accedere, e la copia più fedele: le tabelle mantengono la larghezza esatta. Ti servirà OneNote su Windows per esportare prima il blocco appunti.';

  @override
  String get oneNoteSignInBody =>
      'Scegli un blocco appunti e arriva direttamente, senza esportare nulla prima. Funziona su qualsiasi computer.';

  @override
  String get oneNotePickTitle => 'Quale blocco appunti?';

  @override
  String get oneNoteCloudContinue => 'Continua con Microsoft';
}
