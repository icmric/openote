// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class LIt extends L {
  LIt([String locale = 'it']) : super(locale);

  @override
  String atomNewerVersion(String version) {
    return 'Creato con Openote $version';
  }

  @override
  String get atomNewerVersionUnknown =>
      'Creato con una versione più recente di Openote';

  @override
  String get atomUpdateToView => 'Aggiorna Openote per visualizzarlo';

  @override
  String get barBackToEquation => 'Torna agli strumenti per le equazioni';

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get barBlankOut => 'Nascondi la selezione';

  @override
  String get barBlankOutNeedsSelection =>
      'Seleziona prima le parole da nascondere.';

  @override
  String get barBold => 'Grassetto  (Ctrl+B)';

  @override
  String get barBulletList => 'Elenco puntato';

  @override
  String get barCheckbox => 'Casella';

  @override
  String get barClickIntoTextBox => 'Clicca in una casella di testo';

  @override
  String get barDefinitionCard => 'Scheda definizione';

  @override
  String get barDueDateChange => 'Cambia la scadenza…';

  @override
  String get barDueDateClear => 'Togli la scadenza';

  @override
  String get barDueDatePickerConfirm => 'Imposta';

  @override
  String get barDueDatePickerTitle => 'Scadenza';

  @override
  String get barDueDateSet => 'Scadenza…';

  @override
  String get barEquationBadge => 'Equazione';

  @override
  String get barEraserSplit => 'Spezza i tratti dove strofini';

  @override
  String get barEraserWhole => 'Toglie tutto il tratto che tocchi';

  @override
  String get barEscWhenDone => 'Premi Esc quando hai finito';

  @override
  String get barExport => 'Esporta';

  @override
  String get barExportCanvas => 'Per Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => 'Solo il disegno (.inkml)';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

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
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPdfPicture => 'PDF — immagine della pagina';

  @override
  String get barExportPrint => 'Stampa…';

  @override
  String get barExportTip => 'Esporta la pagina…';

  @override
  String barExportedTo(String path) {
    return 'Esportato in $path';
  }

  @override
  String get barFindOnPage => 'Cerca nella pagina';

  @override
  String get barFindOnPageTip => 'Cerca nella pagina  (Ctrl+F)';

  @override
  String get barFontSizeDefault => 'Predefinito';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barHeading1 => 'Titolo 1';

  @override
  String get barHighlight => 'Evidenzia';

  @override
  String get barInkColourTitle => 'Colore della penna';

  @override
  String get barInkDefaultColour => 'Inchiostro predefinito — segue la pagina';

  @override
  String get barInkHighlighterColourTitle => 'Colore dell’evidenziatore';

  @override
  String get barInkMoreColours => 'Altri colori…';

  @override
  String get barInkPickColour => 'Preleva un colore dalla pagina';

  @override
  String get barInkPickingHint =>
      'Fai clic su qualcosa nella pagina per usarne il colore';

  @override
  String get barInlineCode => 'Codice nel testo';

  @override
  String get barItalic => 'Corsivo  (Ctrl+I)';

  @override
  String get barLassoHint =>
      'Cerchia l\'inchiostro per selezionarlo — poi trascinalo o cancellalo';

  @override
  String get barMakeCardFromLine => 'Trasforma questa riga in una scheda';

  @override
  String get barNewCard => 'Nuova scheda';

  @override
  String get barNumberedList => 'Elenco numerato';

  @override
  String get barOpenStudyPanel => 'Apri il pannello di studio';

  @override
  String get barPageOverview => 'Panoramica della pagina';

  @override
  String get barPenProximity =>
      'Avvicinare la penna alla pagina passa all\'inchiostro.\nSe scegli un altro strumento mentre la penna è vicina, resta\nfinché la penna non si allontana e torna. La coda della penna\n(o il suo tasto, tenuto premuto) cancella.';

  @override
  String barPenSize(String size) {
    return 'Spessore $size';
  }

  @override
  String get barPenSizeExact => 'Dimensione esatta…';

  @override
  String get barPlanner => 'Agenda';

  @override
  String get barPlannerEmpty => 'Agenda — tutte le tue date in un posto solo';

  @override
  String barPlannerOverdue(int count) {
    return 'Agenda — $count per oggi o in ritardo';
  }

  @override
  String barPlannerToday(int count) {
    return 'Agenda — $count per oggi';
  }

  @override
  String get barQuestionCard => 'Scheda domanda';

  @override
  String get barQuote => 'Citazione';

  @override
  String get barRedo => 'Ripeti  (Ctrl+Y)';

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
  String barSaveFailed(String reason) {
    return 'Non è stato possibile salvare: $reason';
  }

  @override
  String get barSettings => 'Impostazioni';

  @override
  String get barSettingsTip => 'Impostazioni…';

  @override
  String get barStrikethrough => 'Barrato';

  @override
  String get barStudy => 'Studio';

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
  String get barStudyEmpty =>
      'Studio — etichetta una riga come Domanda o Definizione per farne una scheda';

  @override
  String barStudyExamCountdown(String when) {
    return ' · esame $when';
  }

  @override
  String get barTabDraw => 'Disegna';

  @override
  String get barTabHome => 'Home';

  @override
  String get barTabInsert => 'Inserisci';

  @override
  String get barTabPage => 'Pagina';

  @override
  String get barTagLine =>
      'Etichetta questa riga (Da fare, Importante, Domanda…)';

  @override
  String barTagged(String tags) {
    return 'Etichettata: $tags';
  }

  @override
  String get barTextColour => 'Colora il testo';

  @override
  String get barTextFont => 'Carattere del testo…';

  @override
  String get barTextSize => 'Dimensione del testo (punti)';

  @override
  String get barTextSizeDisabled =>
      'Clicca in una casella di testo per cambiarne la dimensione';

  @override
  String get barToolEraser => 'Gomma  (E)';

  @override
  String get barToolHighlighter => 'Evidenziatore  (H)';

  @override
  String get barToolLasso => 'Seleziona l\'inchiostro con il lazo';

  @override
  String get barToolPen => 'Penna  (P)';

  @override
  String get barToolSelect => 'Seleziona / sposta  (V)';

  @override
  String get barToolText => 'Testo  (T)';

  @override
  String get barUnderline => 'Sottolineato  (Ctrl+U)';

  @override
  String get barUndo => 'Annulla  (Ctrl+Z)';

  @override
  String barUpdateTo(String version) {
    return 'Aggiorna alla $version…';
  }

  @override
  String get canvasDeleteSelection => 'Elimina  (Canc)';

  @override
  String get canvasGroupSelection => 'Raggruppa  (Ctrl+G)';

  @override
  String get canvasUngroupSelection => 'Separa  (Ctrl+Maiusc+G)';

  @override
  String get commandNotInDemo => 'Non disponibile nella demo web';

  @override
  String get commonBack => 'Indietro';

  @override
  String get commonCancel => 'Annulla';

  @override
  String get commonClose => 'Chiudi';

  @override
  String get commonCopy => 'Copia';

  @override
  String get commonDelete => 'Elimina';

  @override
  String get commonDetailsAdvanced => 'Dettagli (avanzato)';

  @override
  String get commonDone => 'Fatto';

  @override
  String get commonNext => 'Avanti';

  @override
  String get commonOff => 'No';

  @override
  String get commonOn => 'Sì';

  @override
  String get commonOpen => 'Apri';

  @override
  String get commonOpenEllipsis => 'Apri…';

  @override
  String get commonSkip => 'Salta';

  @override
  String importBringingIn(String name, int done, int total) {
    return 'Sto portando «$name» — $done di $total pagine…';
  }

  @override
  String get importCancelledLabel => 'Importazione annullata.';

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine importate.',
      one: '1 pagina importata.',
    );
    return '$_temp0';
  }

  @override
  String importDoneButLost(int count, String detail) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count pagine importate, ma non è stato possibile portare $detail.',
      one: '1 pagina importata, ma non è stato possibile portare $detail.',
    );
    return '$_temp0';
  }

  @override
  String get importEmptyNotebook => 'Quel blocco appunti non aveva pagine.';

  @override
  String get importFailedGeneric =>
      'Non è stato possibile portare quel blocco appunti.';

  @override
  String importFoundPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine da portare. Si comincia…',
      one: '1 pagina da portare. Si comincia…',
    );
    return '$_temp0';
  }

  @override
  String importFoundSections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sezioni trovate — controllo del contenuto…',
      one: '1 sezione trovata — controllo del contenuto…',
    );
    return '$_temp0';
  }

  @override
  String get importLookingAround => 'Sto esaminando il tuo blocco appunti…';

  @override
  String importPartialBroke(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Qualcosa è andato storto a metà, ma le $count pagine già portate sono qui. Openote finirà il resto da solo più tardi.',
    );
    return '$_temp0';
  }

  @override
  String importPartialThrottled(String detail, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$detail Le $count pagine già portate sono qui. Openote finirà il resto da solo più tardi, oppure puoi ricominciare quando vuoi.',
    );
    return '$_temp0';
  }

  @override
  String get importReading => 'Lettura del blocco appunti…';

  @override
  String get importSigningIn => 'Accesso a OneNote…';

  @override
  String importStoppedKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Interrotto — le $count pagine già portate restano. Puoi finire quando vuoi.',
      one: 'Interrotto — la pagina già portata resta. Puoi finire quando vuoi.',
    );
    return '$_temp0';
  }

  @override
  String get importStopping => 'Interruzione…';

  @override
  String importThrottled(int seconds) {
    return 'Microsoft ha chiesto a Openote di rallentare — si riprende tra ${seconds}s. Niente di già portato va perso.';
  }

  @override
  String get importThrottledSoon =>
      'Microsoft ha chiesto a Openote di rallentare — si riprende tra un momento. Niente di già portato va perso.';

  @override
  String importWritingPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Importazione di $count pagine…',
      one: 'Importazione di 1 pagina…',
    );
    return '$_temp0';
  }

  @override
  String importWritingSection(String name) {
    return 'Importazione di «$name»…';
  }

  @override
  String get insertBoard => 'Bacheca';

  @override
  String get insertBoardTip => 'Colonne di schede che sposti avanti';

  @override
  String get insertCode => 'Codice';

  @override
  String get insertEquation => 'Equazione';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertFile => 'File';

  @override
  String get insertFlashcardItem => 'Scheda';

  @override
  String get insertGroupBringIn => 'Porta dentro';

  @override
  String get insertGroupLinkUp => 'Collega';

  @override
  String get insertGroupWrite => 'Scrivi';

  @override
  String get insertLinkToPage => 'Collega a una pagina';

  @override
  String get insertPageLink => 'Collegamento';

  @override
  String get insertPageWindow => 'Finestra';

  @override
  String get insertPdfAsCard => 'Come scheda — si apre in una finestra';

  @override
  String insertPdfFailed(String reason) {
    return 'Importazione del PDF fallita: $reason';
  }

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
  String get insertPdfPerSlide => 'Una pagina per diapositiva';

  @override
  String get insertPdfPrintout => 'Stampa su questa pagina';

  @override
  String get insertPdfSlides => 'PDF';

  @override
  String get insertPdfUnreadable => 'Non è stato possibile leggere quel PDF.';

  @override
  String get insertPickImages => 'Immagini';

  @override
  String get insertPickTables => 'Tabelle';

  @override
  String get insertPickVideo => 'Video e audio';

  @override
  String get insertPicture => 'Immagine';

  @override
  String get insertTable => 'Tabella';

  @override
  String get insertTableFromFile => 'Da un file';

  @override
  String get insertTableFromFileTip => 'CSV o Excel';

  @override
  String get insertTextBox => 'Casella';

  @override
  String get insertVideo => 'Video';

  @override
  String get insertVideoTip =>
      'La registrazione di una lezione, o un qualsiasi link';

  @override
  String get linkEdit => 'Modifica collegamento…';

  @override
  String mathSemanticLabel(String latex) {
    return 'Equazione: $latex';
  }

  @override
  String navAllCount(int total) {
    return 'Tutte e $total';
  }

  @override
  String get navBinEmpty => 'Niente di eliminato.';

  @override
  String get navBinItems => 'Elementi';

  @override
  String get navBinNotebooks => 'Quaderni';

  @override
  String navBinRetention(int days) {
    return 'Quello che sta qui viene eliminato per sempre dopo $days giorni.';
  }

  @override
  String get navClose => 'Chiudi';

  @override
  String get navCollapse => 'Chiudi il navigatore  (Ctrl+\\)';

  @override
  String get navColour => 'Colore';

  @override
  String get navColourDefault => 'Predefinito';

  @override
  String get navComingUp => 'IN ARRIVO';

  @override
  String get navDeleteForever => 'Elimina per sempre';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '«$title» e tutte le sue pagine saranno rimosse per sempre. Non si può annullare.$caveat';
  }

  @override
  String get navDeleteForeverTitle => 'Eliminare per sempre?';

  @override
  String get navDeletePermanently => 'Elimina per sempre';

  @override
  String navDeletedGroup(String title) {
    return 'Gruppo “$title” spostato nel cestino';
  }

  @override
  String navDeletedPage(String title) {
    return 'Pagina “$title” spostata nel cestino';
  }

  @override
  String navDeletedSection(String title) {
    return 'Sezione “$title” spostata nel cestino';
  }

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
  String get navDeletesSoon => 'Sta per essere eliminato';

  @override
  String navExamCountdown(String when, String countdown) {
    return 'Esame $when · $countdown…';
  }

  @override
  String get navExpand => 'Apri il navigatore  (Ctrl+\\)';

  @override
  String get navSectionsHeader => 'Sezioni';

  @override
  String get navNewSectionOrGroup => 'Nuova sezione o gruppo';

  @override
  String get dropMoveAbove => 'Sposta sopra';

  @override
  String get dropMoveBelow => 'Sposta sotto';

  @override
  String get dropMakeSubpage => 'Rendi sottopagina';

  @override
  String get dropGroupTogether => 'Raggruppa';

  @override
  String get dropMoveIntoGroup => 'Sposta nel gruppo';

  @override
  String get dropMoveToSection => 'Sposta in questa sezione';

  @override
  String get navBinEmptyAction => 'Svuota';

  @override
  String get navBinEmptyTitle => 'Svuotare il cestino?';

  @override
  String get navBinEmptyBody =>
      'Tutto il contenuto verrà rimosso per sempre. L’operazione non si può annullare.';

  @override
  String get navBinEmptySharedNote =>
      'I quaderni in una cartella condivisa vengono rimossi solo da questo computer.';

  @override
  String navBinDeleteOneBody(String title) {
    return '“$title” verrà rimosso per sempre. L’operazione non si può annullare.';
  }

  @override
  String get navBinKindPage => 'Pagina';

  @override
  String get navBinKindSection => 'Sezione';

  @override
  String get navBinKindGroup => 'Gruppo';

  @override
  String get navBinKindNotebook => 'Quaderno';

  @override
  String navBinItemLine(String kind, String when) {
    return '$kind · $when';
  }

  @override
  String get navBinWhenToday => 'oggi';

  @override
  String get navBinWhenYesterday => 'ieri';

  @override
  String navBinWhenDaysAgo(int days) {
    return '$days giorni fa';
  }

  @override
  String get reviewTitle => 'Rivedi la scrittura';

  @override
  String reviewChip(int count) {
    return '$count da rivedere';
  }

  @override
  String get reviewChipClear => 'Nessun problema di scrittura';

  @override
  String get reviewTooltip => 'Rivedi la scrittura (F7)';

  @override
  String get reviewChecking => 'Controllo della scrittura…';

  @override
  String fixNoticeRevert(String word) {
    return 'Ripristina «$word»';
  }

  @override
  String reviewSubtitle(int count, String language) {
    return 'In questa pagina · $count da rivedere · $language';
  }

  @override
  String get reviewSpelling => 'Ortografia';

  @override
  String get reviewGrammar => 'Grammatica';

  @override
  String get reviewPunctuation => 'Punteggiatura';

  @override
  String get reviewFixAll => 'Correggi tutto';

  @override
  String get reviewAccept => 'Accetta';

  @override
  String get reviewIgnore => 'Ignora';

  @override
  String get reviewAddToDictionary => 'Aggiungi al dizionario';

  @override
  String get reviewNotInDictionary => 'Non presente nel dizionario';

  @override
  String get reviewRemove => 'Rimuovi';

  @override
  String get reviewAllClear => 'Niente da rivedere in questa pagina.';

  @override
  String reviewFixedSpelling(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errori di ortografia corretti',
      one: '1 errore di ortografia corretto',
    );
    return '$_temp0';
  }

  @override
  String reviewFixedGrammar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errori di grammatica corretti',
      one: '1 errore di grammatica corretto',
    );
    return '$_temp0';
  }

  @override
  String reviewFixedPunctuation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errori di punteggiatura corretti',
      one: '1 errore di punteggiatura corretto',
    );
    return '$_temp0';
  }

  @override
  String get navHideSections => 'Nascondi l\'elenco delle sezioni';

  @override
  String get navRecent => 'Recenti';

  @override
  String get navHomeEmpty =>
      'Qui non c\'è ancora niente.\n\nClicca con il tasto destro su una pagina e scegli Preferita per fissarla; le pagine che apri finiscono in Recenti.';

  @override
  String get navRecentTip => 'Pagine recenti e preferiti';

  @override
  String get navInPageContent => 'Nel contenuto delle pagine';

  @override
  String get navLinkCopied =>
      'Collegamento copiato — incollalo in qualsiasi pagina';

  @override
  String navLockedCannotDelete(String title) {
    return '«$title» è bloccata. Togli il codice prima di eliminarla.';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '«$title» è bloccata. È nascosta dentro Openote, non cifrata nel file.';
  }

  @override
  String get navMenuAddFavourite => 'Aggiungi ai preferiti';

  @override
  String get navMenuCopyLink => 'Copia il collegamento alla pagina';

  @override
  String get navMenuDelete => 'Elimina';

  @override
  String get navMenuDuplicate => 'Duplica';

  @override
  String get navMenuExportSectionPdf => 'Esporta la sezione in PDF…';

  @override
  String get navMenuLock => 'Blocca con un codice…';

  @override
  String get navMenuMakeSubpage => 'Rendi sottopagina';

  @override
  String get navMenuMoveBackOut => 'Riportala fuori';

  @override
  String get navMenuMoveDown => 'Sposta giù';

  @override
  String get navMenuMoveToGroup => 'Sposta in un gruppo…';

  @override
  String get navMenuMoveUp => 'Sposta su';

  @override
  String get navMenuNewPage => 'Nuova pagina';

  @override
  String get navMenuPrint => 'Stampa…';

  @override
  String get navMenuPrintSection => 'Stampa la sezione…';

  @override
  String get navMenuRecentChanges => 'Modifiche recenti…';

  @override
  String get navMenuRemoveExam => 'Togli la data dell\'esame';

  @override
  String get navMenuRemoveFavourite => 'Togli dai preferiti';

  @override
  String get navMenuRemovePasscode => 'Togli il codice…';

  @override
  String get navMenuRename => 'Rinomina';

  @override
  String get navMenuSetExam => 'Imposta la data dell\'esame…';

  @override
  String get navMenuSharePdf => 'Condividi in PDF…';

  @override
  String get navMenuSortAZ => 'Ordina le pagine dalla A alla Z';

  @override
  String get navMenuSortEdited => 'Ordina per ultima modifica';

  @override
  String get navMoveSectionTo => 'Sposta la sezione in…';

  @override
  String navNewPageIn(String section) {
    return 'Nuova pagina in $section';
  }

  @override
  String get navNewSection => 'Nuova sezione';

  @override
  String get navNewSectionGroup => 'Nuovo gruppo';

  @override
  String get navNoGroupTopLevel => '(Nessun gruppo — primo livello)';

  @override
  String navNoMatches(String query) {
    return 'Nessun risultato per «$query»';
  }

  @override
  String get navNoPages => 'Ancora nessuna pagina';

  @override
  String get navNoSections =>
      'Ancora nessuna sezione.\nCreane una per iniziare.';

  @override
  String get navNotebooksTip => 'Quaderni — cambia, rinomina, duplica, importa';

  @override
  String get navOpen => 'Apri';

  @override
  String navPasscodeRemoved(String title) {
    return 'Codice rimosso da «$title».';
  }

  @override
  String get navRecycleBin => 'Cestino';

  @override
  String get navRestore => 'Ripristina';

  @override
  String get navSave => 'Salva';

  @override
  String navSavedTo(String path) {
    return 'Salvato in $path';
  }

  @override
  String get navSearchHint => 'Cerca o vai a…';

  @override
  String get navSection => 'Sezione';

  @override
  String get navShowSections => 'Mostra l\'elenco delle sezioni';

  @override
  String get navUndo => 'Annulla';

  @override
  String get navUntitled => 'Senza titolo';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return 'Controllo della pagina $done di $total…';
  }

  @override
  String get nbCheckingPages => 'Controllo delle pagine…';

  @override
  String get nbConfirmBin =>
      'Spostare nel cestino? Potrai ripristinarlo da qui.';

  @override
  String get nbConfirmBinShared =>
      'Questo quaderno è in una cartella condivisa. Rimuoverlo da questo computer lo lascia nella cartella e sugli altri tuoi dispositivi: puoi riaggiungerlo quando vuoi con Apri.';

  @override
  String get nbRemoveFromComputer => 'Rimuovi da questo computer';

  @override
  String get nbDeleteEverywhere => 'Elimina ovunque…';

  @override
  String nbDeleteEverywhereTitle(String title) {
    return 'Eliminare «$title» ovunque?';
  }

  @override
  String get nbDeleteEverywhereBody =>
      'Verrà eliminato dalla cartella condivisa e sparirà da ogni dispositivo che la usa. Non si può annullare.';

  @override
  String get nbDeleteEverywhereConfirm => 'Elimina ovunque';

  @override
  String nbRemoveSharedTitle(String title) {
    return 'Rimuovere «$title» da questo computer?';
  }

  @override
  String get nbRemoveSharedBody =>
      'Resta nella cartella condivisa e sugli altri tuoi dispositivi. Puoi riaggiungerlo quando vuoi con Apri.';

  @override
  String get nbCoreMissing =>
      'L\'importazione da OneNote richiede il nucleo Rust — compila onote_core.dll (vedi rust/onote_core/INTEGRATION.md).';

  @override
  String get nbCreate => 'Crea';

  @override
  String get nbDuplicate => 'Duplica';

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '$copies copie di «$title» · $pages pagine ciascuna · si recupererebbero $size';
  }

  @override
  String get nbDuplicates =>
      'Possibili doppioni · stesso titolo e stesso numero di pagine';

  @override
  String get nbDuplicatesHint =>
      'Tieni il più grande — il più piccolo di solito è un\'importazione interrotta a metà. Le copie eliminate finiscono nel cestino.';

  @override
  String get nbGetStarted => 'Inizia';

  @override
  String get nbImport => 'Importa';

  @override
  String get nbImportBusy =>
      'C\'è già un\'importazione in corso — una alla volta.';

  @override
  String get nbImportGit => 'Da un indirizzo git';

  @override
  String get nbImportDriveFolder => 'Apri da una cartella di Drive';

  @override
  String get nbImportInto => 'Importa in un nuovo quaderno';

  @override
  String get nbImportMarkdown => 'Cartella Markdown';

  @override
  String get nbImportOne => 'Sezione di OneNote (.one)';

  @override
  String get nbImportOnepkg => 'Quaderno di OneNote (.onepkg)';

  @override
  String get nbImportStarted =>
      'Importazione in corso in secondo piano — continua pure; la scheda nell\'angolo avviserà quando ha finito.';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return 'Importato $what da OneNote.$strokeNote';
  }

  @override
  String nbImportedNamed(String name) {
    return '$name importato';
  }

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
  String nbImportedProgress(String done) {
    return 'Importato $done';
  }

  @override
  String nbInBin(int days) {
    return 'Nel cestino · eliminato dopo $days giorni';
  }

  @override
  String get nbMoveToBin => 'Sposta nel cestino';

  @override
  String get nbNameHint => 'Nome del quaderno';

  @override
  String get nbNeedsNativeCore =>
      'L\'importazione da OneNote richiede il nucleo Rust — compila onote_core.dll e mettilo accanto all\'app.';

  @override
  String get nbNew => 'Nuovo';

  @override
  String get nbNewTitle => 'Nuovo quaderno';

  @override
  String get nbNoMarkdown =>
      'In quella cartella non c\'è nessun file Markdown.';

  @override
  String get nbNothingToRepair =>
      'Niente da riparare — tutte le pagine sono aggiornate.';

  @override
  String get nbOneFileEmpty =>
      'Non è stato possibile leggere niente da quel file .one.';

  @override
  String get nbOnePkgFileType => 'Pacchetto di quaderno OneNote';

  @override
  String nbOpenCount(int count) {
    return '$count aperti';
  }

  @override
  String get nbOpenThis => 'Apri questo quaderno';

  @override
  String nbReadFileFailed(String reason) {
    return 'Non è stato possibile leggere quel file: $reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return 'Non è stato possibile importare quella cartella: $reason';
  }

  @override
  String get nbReadingFolder => 'Lettura della cartella…';

  @override
  String get nbRename => 'Rinomina';

  @override
  String get nbRepair => 'Ripara';

  @override
  String nbRepairFailed(String reason) {
    return 'Riparazione fallita: $reason';
  }

  @override
  String nbRepaired(String boxes, String pages) {
    return 'Riparati $boxes in $pages.';
  }

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
  String get nbTitle => 'Quaderni';

  @override
  String objectRowBackground(String kind) {
    return 'Sfondo: $kind';
  }

  @override
  String get objectRowBackgroundBlank => 'bianco';

  @override
  String get objectRowBackgroundDotted => 'puntinato';

  @override
  String get objectRowBackgroundGrid => 'quadretti';

  @override
  String get objectRowBackgroundRuled => 'righe';

  @override
  String get objectRowCanvasMode =>
      'Modalità tela: senza confini — clicca per le pagine';

  @override
  String get objectRowCharacters => 'Caratteri';

  @override
  String get objectRowCharactersNoSpaces => 'Senza spazi';

  @override
  String get objectRowLandscape => 'Orizzontale';

  @override
  String get objectRowLandscapeSuffix => ' orizzontale';

  @override
  String objectRowMinutes(int n) {
    return '$n min';
  }

  @override
  String objectRowPageMode(String paper, String landscape) {
    return 'Modalità pagina: $paper$landscape — clicca per la tela';
  }

  @override
  String get objectRowPaperSize => 'Formato del foglio';

  @override
  String get objectRowReadingTime => 'Tempo di lettura';

  @override
  String get objectRowSnapOff => 'Aggancia alla griglia: NO — posizione libera';

  @override
  String get objectRowSnapOn =>
      'Aggancia alla griglia: SÌ (si vede mentre trascini)';

  @override
  String get objectRowWordCount =>
      'Parole in questa pagina — clicca per caratteri e tempo di lettura';

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
  String get objectRowWords => 'Parole';

  @override
  String get objectRowZoomFit => 'Adatta lo zoom al contenuto';

  @override
  String get objectRowZoomIn => 'Ingrandisci  (Ctrl+=)';

  @override
  String get objectRowZoomOut => 'Riduci  (Ctrl+-)';

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent%';
  }

  @override
  String get objectRowZoomReset =>
      'Torna al 100% e all\'inizio della pagina  (Ctrl+0)';

  @override
  String get onboardingCloudAction => 'Accedi';

  @override
  String get onboardingCloudBody =>
      'Accedi a Microsoft e scegli un blocco appunti. Non serve esportare nulla prima, e funziona su qualsiasi computer.';

  @override
  String get onboardingCloudTitle => 'Importa note da OneNote';

  @override
  String get onboardingExportMacNote =>
      'Su un Mac, o con la sola versione dello Store: esporta una sezione alla volta come .one, oppure fai creare il .onepkg a un computer Windows. Openote non accede mai al tuo account Microsoft — legge solo il file che gli dai.';

  @override
  String get onboardingExportSteps =>
      '1. Apri OneNote per Windows (l\'app desktop — le versioni Store e web non possono esportare).\n2. Lascia finire la sincronizzazione, così è tutto su questo computer.\n3. File ▸ Esporta ▸ Blocco appunti ▸ Pacchetto di OneNote (*.onepkg), poi Esporta.\n4. Torna qui e scegli quel file.';

  @override
  String get onboardingExportTitle => 'Esportare da OneNote';

  @override
  String get onboardingFreshAction => 'Inizia da zero';

  @override
  String get onboardingFreshBody =>
      'Un blocco appunti vuoto, pronto per scrivere. Potrai importare le tue note in qualsiasi momento.';

  @override
  String get onboardingFreshTitle => 'Inizia un nuovo blocco appunti';

  @override
  String get onboardingImportDone => 'Il tuo quaderno è pronto';

  @override
  String get onboardingImportRunning =>
      'Continua pure — questo va in secondo piano, e la scheda nell\'angolo avviserà quando ha finito.';

  @override
  String onboardingImportingFile(String fileName) {
    return 'Importazione di $fileName';
  }

  @override
  String get onboardingNoNativeCore =>
      'L\'importazione da OneNote richiede il nucleo nativo, che questa versione non contiene.';

  @override
  String get onboardingOneNoteAction => 'Scegli il file…';

  @override
  String get onboardingOneNoteBody =>
      'Pagine, formattazione, immagini, inchiostro ed etichette da un .onepkg. Va in secondo piano — tu continua pure.';

  @override
  String get onboardingOneNoteHideSteps => 'Nascondi i passaggi';

  @override
  String get onboardingOneNoteHowTo => 'Come si esporta?';

  @override
  String get onboardingOneNoteTitle => 'Porta gli appunti da OneNote';

  @override
  String get onboardingOnePkgFileType => 'Pacchetto di quaderno OneNote';

  @override
  String get onboardingOpenFailed =>
      'Openote non è riuscito ad aprire quel quaderno.';

  @override
  String onboardingReadFailed(String reason) {
    return 'Non è stato possibile leggere quel file: $reason';
  }

  @override
  String get onboardingStartWriting => 'Inizia a scrivere';

  @override
  String get onboardingStep1Body =>
      'Clicca dove vuoi e inizia a scrivere — la casella compare dove hai cliccato, e solo quando scrivi. La sposti dalla barra in alto, e le immagini le trascini da dove vuoi.';

  @override
  String get onboardingStep1Title => 'La pagina è una tela';

  @override
  String get onboardingStep2Body =>
      'Scrivi 1/2 o premi Alt+= e la notazione si costruisce davvero mentre scrivi, in una casella tutta sua o dentro la frase. La scheda Disegna accetta penna, dito o mouse.';

  @override
  String get onboardingStep2Title =>
      'Matematica e disegno, in mezzo alle parole';

  @override
  String get onboardingStep3Body =>
      'Un file aperto e leggibile per ogni quaderno — nessun account, nessun vincolo. Mettilo in una cartella che il tuo cloud già sincronizza e tutti i dispositivi restano allineati.';

  @override
  String get onboardingStep3Title => 'I tuoi appunti sono un file tuo';

  @override
  String get onboardingSyncAction => 'Configura…';

  @override
  String get onboardingSyncBodyAlso =>
      'Nessuno di questi? Scegli tu la cartella.';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive, OneDrive, iCloud, Dropbox, Syncthing, un NAS — o un repository GitHub.';

  @override
  String get onboardingSyncTitle => 'Sincronizza con un altro dispositivo';

  @override
  String get oneNoteCloudContinue => 'Continua con Microsoft';

  @override
  String get oneNoteCloudEmpty =>
      'Nessun blocco appunti trovato per questo account.';

  @override
  String get oneNoteCloudIntro =>
      'Openote leggerà i tuoi blocchi appunti da OneNote. Non può modificarli.';

  @override
  String get oneNoteCloudLoading => 'Ricerca dei tuoi blocchi appunti…';

  @override
  String get oneNoteCloudNoInk =>
      'Le tabelle vengono adattate alla pagina invece di mantenere la larghezza esatta, e il colore e il carattere del testo non vengono mantenuti.';

  @override
  String get oneNoteCloudOther => 'Usa un altro account';

  @override
  String get oneNoteCloudSignIn => 'Accedi a Microsoft';

  @override
  String get oneNoteCloudSigningIn => 'In attesa del browser…';

  @override
  String get oneNoteCloudTitle => 'Importa un blocco appunti da OneNote';

  @override
  String get oneNoteFileBody =>
      'Senza accedere, e la copia più fedele: le tabelle mantengono la larghezza esatta. Ti servirà OneNote su Windows per esportare prima il blocco appunti.';

  @override
  String get oneNoteFileTitle => 'Usa un file esportato';

  @override
  String get oneNotePickTitle => 'Quale blocco appunti?';

  @override
  String get oneNoteSignInBody =>
      'Scegli un blocco appunti e arriva direttamente, senza esportare nulla prima. Funziona su qualsiasi computer.';

  @override
  String get penButtonEraser => 'Gomma';

  @override
  String get penButtonLasso => 'Lazo';

  @override
  String get penButtonNothing => 'Niente';

  @override
  String get penButtonSelect => 'Seleziona';

  @override
  String get settingsAbout => 'Informazioni';

  @override
  String get settingsAi => 'Accesso dell\'IA';

  @override
  String get settingsAiOff => 'No — collega Claude o altri assistenti IA.';

  @override
  String get settingsAiOn =>
      'Sì — l’IA su questo computer può leggere i tuoi appunti.';

  @override
  String get settingsAppearance => 'Aspetto';

  @override
  String get settingsCheckUpdates => 'Cerca aggiornamenti';

  @override
  String get settingsConnections => 'Connessioni';

  @override
  String get settingsDiagnostics => 'Diagnostica';

  @override
  String get settingsHelp => 'Aiuto';

  @override
  String get settingsUiScale => 'Dimensione dell\'interfaccia';

  @override
  String get settingsUiScaleHint => 'Ingrandisce o riduce l\'intera finestra.';

  @override
  String settingsUiScaleLimited(String size) {
    return 'Mostrata al $size: questa finestra è troppo piccola per di più.';
  }

  @override
  String get settingsLanguage => 'Lingua';

  @override
  String get settingsLanguageAuto => 'Predefinito del sistema';

  @override
  String get settingsLanguageContribute =>
      'Come aggiungere o correggere una lingua';

  @override
  String get settingsPenAndTouch => 'Penna e tocco';

  @override
  String get settingsPenButton => 'Il pulsante laterale della penna';

  @override
  String get settingsPenButtonHint =>
      'Tienilo premuto per usare quello strumento.';

  @override
  String get settingsPenTest => 'Test di penna e tocco';

  @override
  String get settingsPenTestHint =>
      'Che cosa riportano la penna e i suoi pulsanti.';

  @override
  String get settingsShortcuts => 'Scorciatoie da tastiera';

  @override
  String get settingsShortcutsHint => 'Ctrl+/';

  @override
  String get settingsReportProblem => 'Segnala un problema o proponi un\'idea';

  @override
  String get settingsReportProblemHint =>
      'Apre GitHub. Serve un account GitHub gratuito.';

  @override
  String get settingsSpellCheck => 'Controllo ortografico';

  @override
  String get settingsSync => 'Sincronizzazione';

  @override
  String get settingsSyncHint =>
      'Salva questo quaderno su GitHub o in una cartella.';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeDark => 'Scuro';

  @override
  String get settingsThemeLight => 'Chiaro';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsTouchDrawing => 'Disegnare con il dito';

  @override
  String get settingsTouchDrawingHint =>
      'Due dita spostano e ingrandiscono sempre.';

  @override
  String settingsUpToDate(String version) {
    return 'Sei aggiornato ($version è la versione più recente).';
  }

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsWelcomeTour => 'Visita guidata';

  @override
  String get settingsWelcomeTourHint => 'Tre minuti su come funziona la tela.';

  @override
  String get settingsWhatsNew => 'Novità';

  @override
  String get settingsWriting => 'Scrittura e disegno';

  @override
  String get shellAlreadyUpToDate => 'Già aggiornato.';

  @override
  String get shellCheatSheet =>
      'V seleziona · T testo · P penna · H evidenzia · E cancella · Ctrl+Z annulla · Ctrl+rotella zoom';

  @override
  String get shellCloseEsc => 'Chiudi (Esc)';

  @override
  String get shellCreateFirstPage => 'Crea la tua prima pagina';

  @override
  String get shellDemoNothingSaved => 'Demo — non viene salvato nulla';

  @override
  String get shellEmptyBody =>
      'Tutto quello che fai qui resta sul tuo dispositivo,\nin un formato aperto che è tuo.';

  @override
  String get shellEmptyTitle => 'Una pagina aperta ti aspetta';

  @override
  String get shellFindOnThisPage => 'Cerca in questa pagina…';

  @override
  String get shellHeadingsHint =>
      'Inizia una riga con # per farne un titolo — la struttura si costruisce da sola mentre scrivi.';

  @override
  String get shellLinkedFrom => 'Collegata da';

  @override
  String get shellLinksTo => 'Rimanda a';

  @override
  String get shellNextMatch => 'Risultato successivo (Invio)';

  @override
  String get shellNoBacklinks => 'Nessuna pagina rimanda ancora qui.';

  @override
  String get shellNoHeadings => 'Non ci sono titoli in questa pagina.';

  @override
  String get shellNoLinks =>
      'Questa pagina non rimanda ancora da nessuna parte.';

  @override
  String get shellNoMatches => 'Nessun risultato';

  @override
  String get shellNoTags => 'In questo quaderno non ci sono ancora etichette.';

  @override
  String get shellNothingReplaced => 'Non è stato sostituito niente';

  @override
  String shellPageLocked(String title) {
    return '«$title» è bloccata';
  }

  @override
  String get shellPreviousMatch => 'Risultato precedente (Maiusc+Invio)';

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
  String get shellReplace => 'Sostituisci';

  @override
  String get shellReplaceAll => 'Tutte';

  @override
  String get shellReplaceWith => 'Sostituisci con…';

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
  String shellRustLinked(String build) {
    return 'Il nucleo Rust (onote-core) è collegato e calcola l\'impronta del contenuto di questa pagina al salvataggio.\n$build';
  }

  @override
  String get shellRustMissing =>
      'Sta girando il motore in puro Dart. Compila la libreria onote-core per collegare il nucleo Rust.';

  @override
  String get shellSavedLocally =>
      'Questa pagina è salvata nel tuo file .onote locale.';

  @override
  String get shellSavedOnDevice => 'Salvato su questo dispositivo';

  @override
  String get shellSaving => 'Salvataggio…';

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag  ($count)';
  }

  @override
  String get shellTagTheLine => 'Etichetta la riga su cui sei';

  @override
  String get shellTagsHint =>
      'Le etichette segnano una riga — da fare, importante, domanda, definizione — così la ritrovi, ci ripassi sopra o le dai una scadenza.';

  @override
  String get shellUnlock => 'Sblocca';

  @override
  String get tableColumnLeft => 'Inserisci colonna a sinistra';

  @override
  String get tableColumnRight => 'Inserisci colonna a destra';

  @override
  String get tableDeleteColumn => 'Elimina colonna';

  @override
  String get tableDeleteRow => 'Elimina riga';

  @override
  String get tableRowAbove => 'Inserisci riga sopra';

  @override
  String get tableRowBelow => 'Inserisci riga sotto';

  @override
  String get tagContact => 'Contatto';

  @override
  String get tagCritical => 'Urgente';

  @override
  String get tagCustom => 'Etichetta';

  @override
  String get tagDefinition => 'Definizione';

  @override
  String get tagIdea => 'Idea';

  @override
  String get tagImportant => 'Importante';

  @override
  String get tagQuestion => 'Domanda';

  @override
  String get tagRemember => 'Da ricordare';

  @override
  String get tagTodo => 'Da fare';

  @override
  String get touchDrawAlways => 'Sempre';

  @override
  String get touchDrawAuto => 'Auto (comanda la penna)';

  @override
  String get touchDrawNever => 'Mai';

  @override
  String updateAvailable(String version) {
    return 'Openote $version è disponibile';
  }

  @override
  String updateYouHave(String version) {
    return 'Hai la $version.';
  }

  @override
  String get updateDownloading => 'Download in corso…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Download in corso… $percent%';
  }

  @override
  String get updateSavedClosing =>
      'Le tue note sono salvate. Openote si chiuderà, si aggiornerà e si riaprirà.';

  @override
  String get updateWillRestart =>
      'Le tue note verranno salvate prima. Openote si chiude durante l’installazione e poi si riapre da solo.';

  @override
  String get updateInstallYourself => 'Dovrai scaricarla e installarla tu.';

  @override
  String get updateNotNow => 'Non ora';

  @override
  String get updateNow => 'Aggiorna ora';

  @override
  String get updateDownload => 'Scarica';

  @override
  String get settingsGrammarCheck => 'Controlla la grammatica';

  @override
  String get settingsAutoCorrect =>
      'Correggi i piccoli errori di battitura mentre scrivo';

  @override
  String get settingsAutoCapitalize => 'Maiuscola a inizio frase';

  @override
  String get settingsSpellLanguage => 'Lingua del controllo ortografico';

  @override
  String get settingsSpellLanguageSystem => 'Predefinito del sistema';

  @override
  String get settingsSpellLanguageOther => 'Altra lingua (non controllata)';

  @override
  String get settingsEnglishAU => 'Inglese (Australia)';

  @override
  String get settingsEnglishGB => 'Inglese (Regno Unito)';

  @override
  String get settingsEnglishUS => 'Inglese (Stati Uniti)';

  @override
  String get settingsEnglishCA => 'Inglese (Canada)';

  @override
  String get settingsEnglishIN => 'Inglese (India)';

  @override
  String get settingsWritingEnglishOnly =>
      'Per ora grammatica, correzione dei refusi e maiuscole funzionano solo in inglese. Nelle altre lingue restano disattivate.';

  @override
  String get barTabWrite => 'Scrivi';

  @override
  String get insertNotYet => 'Non ancora';

  @override
  String get barHideKeyboard => 'Nascondi la tastiera';

  @override
  String get pageSheetBlank => 'Vuota';

  @override
  String get pageSheetGrid => 'Griglia';

  @override
  String get pageSheetDots => 'Punti';

  @override
  String get pageSheetRuled => 'A righe';

  @override
  String get pageSheetPaper => 'Carta';

  @override
  String get pageSheetCanvas => 'Tela';

  @override
  String get pageSheetSnap => 'Aggancia';

  @override
  String get pageSheetFit => 'Adatta';

  @override
  String get navOpening => 'Apertura del quaderno…';

  @override
  String get openFolderTitle => 'Apri un quaderno da una cartella';

  @override
  String get openFolderBody =>
      'Scegli la cartella in cui tieni i quaderni, per esempio una di Google Drive, OneDrive o Dropbox. Openote cerca i quaderni al suo interno.';

  @override
  String get openFolderChoose => 'Scegli una cartella…';

  @override
  String get openFolderNone =>
      'Nessun quaderno trovato lì. Scegli la cartella che contiene i tuoi quaderni, oppure la cartella del quaderno stesso (il nome termina con .onotebook).';

  @override
  String get openFolderLooking => 'Ricerca dei quaderni…';

  @override
  String get openFolderAndroidHint =>
      'Scegli la cartella dei tuoi quaderni. In Google Drive di solito è quella chiamata “Openote”. Poi tocca “Usa questa cartella”.';

  @override
  String get openFolderFound => 'Quaderni trovati';

  @override
  String protectLockTitle(String title) {
    return 'Blocca «$title»';
  }

  @override
  String protectLockedTitle(String title) {
    return '«$title» è bloccata';
  }

  @override
  String get protectBetaHeadline =>
      'Beta: questo nasconde la pagina in Openote, ma non la cifra ancora.';

  @override
  String get protectBetaBody =>
      'Per ora, chiunque abbia il file del tuo blocco appunti può comunque leggere la pagina, e un codice dimenticato non si può recuperare. È prevista una vera cifratura.';

  @override
  String get protectPasscode => 'Codice';

  @override
  String get protectPasscodeAgain => 'Ripeti il codice';

  @override
  String get protectAskAgain => 'Richiedilo di nuovo…';

  @override
  String get protectLock => 'Blocca';

  @override
  String get protectEnterPasscode => 'Inserisci un codice.';

  @override
  String get protectMismatch => 'I due codici non coincidono.';

  @override
  String get protectWrong => 'Non è il codice giusto.';

  @override
  String get protectPolicyAlways => 'Ogni volta che si apre';

  @override
  String get protectPolicyTenMinutes => 'Per 10 minuti';

  @override
  String get protectPolicyOneHour => 'Per 1 ora';

  @override
  String get protectPolicySession => 'Finché Openote resta aperto';

  @override
  String get linkTitleNew => 'Link';

  @override
  String get linkTitleEdit => 'Modifica link';

  @override
  String get linkTextToShow => 'Testo da mostrare';

  @override
  String get linkNothingSelected =>
      'Non c’era niente di selezionato da trasformare in link';

  @override
  String get linkAddress => 'Indirizzo';

  @override
  String get linkOrPage => 'oppure collega a una pagina';

  @override
  String get linkRemove => 'Rimuovi link';

  @override
  String get linkUpdate => 'Aggiorna';

  @override
  String get linkInsert => 'Inserisci';

  @override
  String get linkNeedWords => 'Dai al link un testo da mostrare.';

  @override
  String get linkBadAddress =>
      'Non sembra un indirizzo che Openote possa aprire. Prova qualcosa come https://example.com';

  @override
  String get linkNoCaret => 'Metti prima il cursore dove deve andare il link.';

  @override
  String get linkOneLine =>
      'Un link deve stare su una sola riga. Seleziona parole su una sola riga.';

  @override
  String get linkOnObject =>
      'Un’immagine, una tabella o una scheda non può avere un link. Mettilo su delle parole.';

  @override
  String get linkOnMaths =>
      'Un’equazione non può avere un link: le parentesi appartengono alla matematica.';

  @override
  String get linkBrackets =>
      'Il testo di un link non può contenere parentesi quadre. Seleziona qualcosa senza.';

  @override
  String get linkNested =>
      'Quel testo è già formattato o collegato. Seleziona parole semplici, oppure fai clic nel link per modificarlo.';

  @override
  String get alertsTitle => 'Avvisi prima delle lezioni';

  @override
  String get alertsIntro =>
      'Openote può avvisarti prima che inizi qualcosa del tuo orario. Capisce il tipo di ogni evento dal nome, quindi scegli i tipi per cui vuoi davvero essere interrotto.';

  @override
  String get alertsPreset => 'Avvisami 10 minuti prima delle lezioni';

  @override
  String get alertsAllOff => 'Disattiva tutti';

  @override
  String get alertsWhileRunning =>
      'Gli avvisi compaiono dentro Openote, quindi ti raggiungono solo mentre è aperto. Quello che ti sei perso ti aspetta in questo pannello la prossima volta che lo apri.';

  @override
  String get alertsAtStart => 'All’inizio';

  @override
  String alertsMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get eventKindLecture => 'Lezione';

  @override
  String get eventKindTutorial => 'Esercitazione';

  @override
  String get eventKindLab => 'Laboratorio / pratica';

  @override
  String get eventKindWorkshop => 'Workshop';

  @override
  String get eventKindSeminar => 'Seminario';

  @override
  String get eventKindExam => 'Esame / verifica';

  @override
  String get eventKindMeeting => 'Riunione';

  @override
  String get eventKindOther => 'Tutto il resto';

  @override
  String get commonOk => 'OK';

  @override
  String get saveProblemNotAddedShort => 'Non è stato aggiunto';

  @override
  String get saveProblemNotAdded =>
      'Openote non è riuscito a salvare l’immagine o il file che hai appena aggiunto, quindi non è nel tuo quaderno.\n\nControlla che il disco non sia pieno e che la cartella del quaderno non sia di sola lettura, poi incollalo o trascinalo di nuovo.';

  @override
  String get saveProblemNotOnDriveShort => 'Non ancora su Drive';

  @override
  String get saveProblemNotOnDrive =>
      'Le tue modifiche sono salvate su questo telefono. Non è stato possibile inviarle alla cartella di Drive in questo momento (nessuna connessione, o cartella non raggiungibile) e verranno inviate appena sarà raggiungibile.';

  @override
  String get saveProblemNotRecordedShort => 'Salvato, ma non registrato';

  @override
  String get saveProblemNotRecorded =>
      'Openote ha salvato le tue note su questo computer, ma non è riuscito ad aggiungere la modifica alla cronologia di questo quaderno.\n\nLa cronologia è la copia da cui leggono gli altri tuoi dispositivi, i tuoi backup e le tue cartelle condivise, quindi potrebbero restare indietro finché il problema non si risolve. Niente di quello che hai scritto è andato perso.\n\nControlla che il disco non sia pieno, che la cartella del quaderno non sia di sola lettura e che un’app cloud come OneDrive o Google Drive abbia finito di usarla. Openote riprova ogni volta che salvi.';

  @override
  String get saveProblemPageShort => 'Non salvato: modifiche in memoria';

  @override
  String get saveProblemPage =>
      'Openote non è riuscito a salvare questa pagina sul tuo computer.\n\nLe tue modifiche sono ancora sullo schermo e Openote riproverà la prossima volta che scrivi o chiudi la finestra. La prima volta che chiudi la finestra resta aperta, così puoi risolvere il problema; se la chiudi di nuovo, Openote esce senza queste modifiche.\n\nControlla che il disco non sia pieno e che il quaderno non sia aperto in un altro programma.';

  @override
  String get saveProblemPicturesShort => 'Alcune immagini potrebbero mancare';

  @override
  String saveProblemPictures(int count) {
    return 'Openote conserva una seconda copia di ogni immagine e disegno nella cartella di questo quaderno, così anche gli altri tuoi dispositivi e i tuoi backup possono mostrarli.\n\nPer $count di essi, Openote non ha trovato dati integri da nessuna parte su questo computer: né in quella seconda copia, né nel file di lavoro del quaderno. Finché non ricompaiono (da un altro dispositivo, da un backup o aggiungendo di nuovo l’immagine), resteranno vuoti ovunque siano usati, su questo computer come su qualsiasi altro.\n\nControlla che il disco non sia pieno e che la cartella non sia di sola lettura, poi chiudi il quaderno e riaprilo. Openote riprova ogni volta che lo apri.';
  }

  @override
  String get saveProblemListLockedShort => 'L’elenco dei quaderni è bloccato';

  @override
  String get saveProblemNewerShort => 'Sola lettura: da un Openote più recente';

  @override
  String get saveProblemNewer =>
      'Questo quaderno contiene modifiche fatte con una versione più recente di Openote, che questa versione non riesce a leggere.\n\nPer questo Openote ti mostra il quaderno senza modificarlo. Tutto il contenuto è al sicuro e niente di quello che fai qui può danneggiarlo, ma quello che scrivi adesso non verrà conservato.\n\nAggiornando Openote all’ultima versione potrai modificarlo di nuovo.';

  @override
  String get saveProblemListShort => 'Elenco dei quaderni non salvato';

  @override
  String get saveProblemList =>
      'Openote non è riuscito a salvare l’elenco dei quaderni e le impostazioni. La prima volta che chiudi la finestra resterà aperta. Controlla il disco e riprova, oppure chiudi di nuovo la finestra per uscire comunque.';

  @override
  String get mcpTitle => 'Accesso IA';

  @override
  String get mcpIntro =>
      'Permetti a un assistente IA, come Claude, di leggere le tue note, cercarle, interrogarti e creare flashcard. Funziona solo mentre Openote è aperto, solo su questo computer, e tutto ciò che aggiunge è una normale modifica: Ctrl+Z la annulla.';

  @override
  String get mcpPasscodeNote =>
      'Tutto ciò che ha un codice resta privato: un assistente IA non può vederlo né modificarlo, nemmeno mentre l’hai sbloccato. Un codice blocca Openote, non il file in sé, quindi uno strumento IA che può aprire file sul tuo computer potrebbe comunque leggerlo.';

  @override
  String mcpCouldNotStart(String error) {
    return 'Impossibile avviare: $error';
  }

  @override
  String mcpReady(String lastUsed) {
    return 'Pronto. $lastUsed';
  }

  @override
  String get mcpNeverUsed =>
      'Nessun assistente IA l’ha usato da quando Openote è stato aperto.';

  @override
  String get mcpUsedJustNow => 'Usato da un assistente IA proprio ora.';

  @override
  String mcpUsedMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Usato da un assistente IA $minutes minuti fa.',
      one: 'Usato da un assistente IA 1 minuto fa.',
    );
    return '$_temp0';
  }

  @override
  String mcpUsedHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Usato da un assistente IA $hours ore fa.',
      one: 'Usato da un assistente IA 1 ora fa.',
    );
    return '$_temp0';
  }

  @override
  String get mcpUsedOverADay =>
      'Usato da un assistente IA più di un giorno fa.';

  @override
  String get mcpRestartHint =>
      'Un assistente IA cerca Openote quando si avvia. Se il tuo era già aperto, riavvialo.';

  @override
  String mcpClientIsSetUp(String name) {
    return '$name: configurato';
  }

  @override
  String mcpSetUpClient(String name) {
    return 'Configura $name';
  }

  @override
  String get mcpClaudeApp => 'App Claude';

  @override
  String get mcpChatGptApp => 'App ChatGPT';

  @override
  String get mcpWebsiteNote =>
      'Il sito web di ChatGPT non si può collegare: i suoi connettori girano sui server di OpenAI, che non vedono il tuo computer. Il pulsante qui sopra è per l’app desktop, che legge le impostazioni da questo computer. L’app Gemini è nello stesso caso del sito: la sua CLI ha un pulsante.';

  @override
  String get mcpCopyAddress => 'Copia indirizzo';

  @override
  String get mcpCopyConfiguration => 'Copia configurazione';

  @override
  String get mcpOtherTools => 'Altri strumenti IA (avanzate)';

  @override
  String get mcpOtherToolsBody =>
      'Openote parla MCP, lo standard che gli strumenti IA usano per collegarsi alle app. Qualsiasi strumento compatibile con MCP può usarlo: la chiave contenuta è una password, quindi incollala solo in strumenti di cui ti fidi.';

  @override
  String mcpListening(String port) {
    return 'In ascolto sulla porta $port, solo su questo computer.';
  }

  @override
  String get mcpNotListening => 'Non in ascolto.';

  @override
  String get mcpCopyConfig => 'Copia config';

  @override
  String get mcpCliIntro =>
      'Oppure, per gli strumenti a riga di comando, esegui una volta:';

  @override
  String get mcpCopyCommand => 'Copia comando';

  @override
  String get mcpCopied =>
      'Copiato. La chiave contenuta è una password: incollala solo nei tuoi strumenti.';

  @override
  String get mcpChatGptUnreadable =>
      'Non è stato possibile leggere il file di impostazioni di ChatGPT, quindi Openote non l’ha toccato. I dati di connessione in Avanzate funzionano comunque.';

  @override
  String get mcpChatGptUnparsable =>
      'Il file di impostazioni di ChatGPT contiene qualcosa che Openote non capisce, quindi non l’ha toccato. Copia la configurazione in Avanzate e aggiungila a mano.';

  @override
  String mcpSaveFailed(String error) {
    return 'Impossibile salvare la connessione: $error';
  }

  @override
  String get mcpChatGptSetUp =>
      'Configurato. Riavvia l’app desktop di ChatGPT e Openote comparirà tra i suoi server MCP. Il sito web non può usarlo: solo un’app su questo computer può vedere Openote.';

  @override
  String get mcpChatGptSavedOnly =>
      'Salvato. Openote comparirà appena l’app desktop di ChatGPT o la CLI di Codex saranno installate su questo computer.';

  @override
  String mcpClientUnreadable(String name) {
    return 'Non è stato possibile leggere il file di impostazioni di $name, quindi Openote non l’ha toccato. I dati di connessione in Avanzate funzionano comunque in qualsiasi strumento compatibile con MCP.';
  }

  @override
  String mcpClientSetUp(String name) {
    return 'Configurato. Se $name è già aperto, riavvialo: cerca Openote quando si avvia. Poi chiedigli delle tue note; prova con «interrogami su quello che ho scritto questa settimana».';
  }

  @override
  String mcpClientNotInstalled(String name) {
    return 'Openote è pronto, ma $name non sembra ancora installato su questo computer. Appena lo sarà, la connessione funzionerà da sola.';
  }

  @override
  String get timeNow => 'ora';

  @override
  String timeMinutesShort(String n) {
    return '$n min';
  }

  @override
  String timeHoursShort(String n) {
    return '$n h';
  }

  @override
  String timeDaysShort(String n) {
    return '$n g';
  }

  @override
  String timeMonthsShort(String n) {
    return '$n mesi';
  }

  @override
  String timeYearsShort(String n) {
    return '$n a';
  }

  @override
  String get countdownToday => 'oggi';

  @override
  String get countdownTomorrow => 'domani';

  @override
  String get countdownYesterday => 'ieri';

  @override
  String countdownDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni',
      one: '1 giorno',
    );
    return '$_temp0';
  }

  @override
  String countdownDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni fa',
      one: '1 giorno fa',
    );
    return '$_temp0';
  }

  @override
  String get countdownPassed => 'passato';

  @override
  String get monthsShort => 'gen,feb,mar,apr,mag,giu,lug,ago,set,ott,nov,dic';

  @override
  String dateDayMonth(String day, String month) {
    return '$day $month';
  }

  @override
  String dateDayMonthYear(String day, String month, String year) {
    return '$day $month $year';
  }

  @override
  String get gradeAgain => 'Di nuovo';

  @override
  String get gradeHard => 'Difficile';

  @override
  String get gradeGood => 'Bene';

  @override
  String get gradeEasy => 'Facile';

  @override
  String get deckThisPage => 'Questa pagina';

  @override
  String get deckThisSection => 'Questa sezione';

  @override
  String get deckWholeNotebook => 'Tutto il quaderno';

  @override
  String get studyAnkiText => 'Testo Anki';

  @override
  String studyExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count schede esportate: importale in Anki con File ▸ Importa',
      one: '1 scheda esportata: importala in Anki con File ▸ Importa',
    );
    return '$_temp0';
  }

  @override
  String get studyForgetTitle =>
      'Dimenticare la programmazione di questo mazzo?';

  @override
  String studyForgetBody(String scope) {
    String _temp0 = intl.Intl.selectLogic(
      scope,
      {
        'page':
            'Ogni scheda di questa pagina torna nuova. Le tue note non vengono toccate.',
        'section':
            'Ogni scheda di questa sezione torna nuova. Le tue note non vengono toccate.',
        'other':
            'Ogni scheda dell’intero quaderno torna nuova. Le tue note non vengono toccate.',
      },
    );
    return '$_temp0';
  }

  @override
  String get studyForget => 'Dimentica';

  @override
  String studyResetCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count schede reimpostate',
      one: '1 scheda reimpostata',
    );
    return '$_temp0';
  }

  @override
  String get studyEnd => 'Termina';

  @override
  String get studyDeckActions => 'Azioni del mazzo';

  @override
  String get studyExportAnki => 'Esporta in Anki…';

  @override
  String get studySetExam => 'Imposta data dell’esame…';

  @override
  String get studyChangeExam => 'Cambia data dell’esame…';

  @override
  String get studyRemoveExam => 'Rimuovi data dell’esame';

  @override
  String get studyForgetSchedule => 'Dimentica programmazione…';

  @override
  String get studyDue => 'da ripassare';

  @override
  String studyCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count schede',
      one: '1 scheda',
    );
    return '$_temp0';
  }

  @override
  String studyNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuove',
      one: '1 nuova',
    );
    return '$_temp0';
  }

  @override
  String studyReview(String count) {
    return 'Ripassa $count';
  }

  @override
  String get studyAllCaughtUp => 'Tutto in pari.';

  @override
  String studyAllCaughtUpNext(String delay) {
    return 'Tutto in pari: prossima scheda tra $delay.';
  }

  @override
  String studyPracticeAll(String count) {
    return 'Esercitati su tutte le $count';
  }

  @override
  String get studyPracticeNote =>
      'Esercitarsi non cambia la tua programmazione.';

  @override
  String get studyThisSection => 'Studia questa sezione';

  @override
  String studyExamWhen(String when) {
    return 'Esame $when';
  }

  @override
  String get studyKeepSchedule =>
      'Queste schede mantengono la loro programmazione.';

  @override
  String get studyExamGoodLuck => 'Tutte le schede viste. In bocca al lupo!';

  @override
  String studyExamUnseenToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count che non hai ancora visto.',
    );
    return '$_temp0';
  }

  @override
  String studyAllSeen(String count) {
    return 'Tutte le $count viste: continua con i ripassi.';
  }

  @override
  String studyToLearn(String count, String perDay) {
    return '$count da imparare · $perDay al giorno bastano per arrivarci';
  }

  @override
  String get studyExamToday => 'Esame oggi';

  @override
  String get studySeen => 'VISTE';

  @override
  String studyNOfM(String n, String total) {
    return '$n di $total';
  }

  @override
  String get studyAddExam => 'Aggiungi una data d’esame';

  @override
  String studyReviewedToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ripassate oggi',
      one: '1 ripassata oggi',
    );
    return '$_temp0';
  }

  @override
  String get studyNothingToday => 'Niente ripassato oggi';

  @override
  String studyStreakAtRisk(String days) {
    return 'Serie di $days giorni: continuala oggi';
  }

  @override
  String studyStreak(String days, String today) {
    return 'Serie di $days giorni · $today oggi';
  }

  @override
  String studyActivityTip(String days) {
    return 'Ripassi degli ultimi $days giorni';
  }

  @override
  String get studyDeck => 'Mazzo';

  @override
  String get studyNoCards => 'Ancora nessuna scheda qui.';

  @override
  String get studyRecipeQuestion =>
      'Etichetta una domanda. La riga rientrata sotto è la risposta.';

  @override
  String get studyRecipeDefinition =>
      'Etichetta una definizione scritta come «termine — significato».';

  @override
  String get studyRecipeCloze =>
      'Evidenzia parte di una riga etichettata per nasconderla invece.';

  @override
  String get studyCardsAreNotes =>
      'Le schede sono una vista delle tue note, quindi modificare la nota modifica la scheda: non c’è niente di separato da mantenere.';

  @override
  String studyReviewedCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count schede ripassate',
      one: '1 scheda ripassata',
    );
    return '$_temp0';
  }

  @override
  String studyStillDue(String count) {
    return '$count ancora da ripassare in questo mazzo.';
  }

  @override
  String get studyNothingElseDue => 'Nient’altro da ripassare.';

  @override
  String studyNextCardIn(String delay) {
    return 'Prossima scheda tra $delay.';
  }

  @override
  String studyNeedAnotherLook(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count meritano un’altra occhiata.',
      one: '1 merita un’altra occhiata.',
    );
    return '$_temp0';
  }

  @override
  String get studyExamTodayDot => 'Esame oggi.';

  @override
  String studyUntilExam(String countdown) {
    return '$countdown all’esame.';
  }

  @override
  String studyUntilExamUnseen(String countdown, String count) {
    return '$countdown all’esame · $count ancora da vedere.';
  }

  @override
  String studyReviewAgain(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ripassa quelle $count di nuovo',
      one: 'Ripassa quella di nuovo',
    );
    return '$_temp0';
  }

  @override
  String studyKeepGoing(String count) {
    return 'Continua: $count da ripassare';
  }

  @override
  String get studyPracticeBadge => 'ESERCIZIO';

  @override
  String get studyShowAnswer => 'Mostra risposta';

  @override
  String get studyOpenNote => 'Apri la nota';

  @override
  String get studyAnswerHidden => 'Risposta nascosta';

  @override
  String get studyAnswer => 'RISPOSTA';

  @override
  String get studyFillBlank => 'COMPLETA LO SPAZIO';

  @override
  String studyExamMenu(String when, String countdown) {
    return 'Esame $when · $countdown…';
  }

  @override
  String get examDateTitle => 'Data dell’esame';

  @override
  String examTitleFor(String section) {
    return 'Esame: $section';
  }

  @override
  String examRemoved(String date) {
    return 'Data dell’esame rimossa ($date). Le tue schede non cambiano.';
  }

  @override
  String get examUseDate => 'Usa questa data';

  @override
  String get examWhatTime => 'A che ora inizia?';

  @override
  String get examDate => 'Data';

  @override
  String get examAddTime => 'Aggiungi un orario di inizio';

  @override
  String get examStarts => 'Inizio';

  @override
  String get examNoTime => 'Nessun orario preciso';

  @override
  String get examTimeOptional =>
      'Il conto alla rovescia e il piano di ripasso funzionano a giorni interi, quindi l’orario è facoltativo.';

  @override
  String get examShownOnDay =>
      'Mostrato quel giorno. Il conto alla rovescia funziona sempre a giorni interi.';

  @override
  String get examSet => 'Imposta';

  @override
  String get weekdaysShort => 'lun,mar,mer,gio,ven,sab,dom';

  @override
  String get weekdayInitials => 'L,M,M,G,V,S,D';

  @override
  String dateDayFull(String weekday, String day, String month) {
    return '$weekday $day $month';
  }

  @override
  String planMonthYear(String month, String year) {
    return '$month $year';
  }

  @override
  String whenInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tra $count giorni',
      one: 'tra 1 giorno',
    );
    return '$_temp0';
  }

  @override
  String get agendaOverdue => 'In ritardo';

  @override
  String get agendaToday => 'Oggi';

  @override
  String get agendaTomorrow => 'Domani';

  @override
  String get agendaThisWeek => 'Questa settimana';

  @override
  String get agendaLater => 'Più avanti';

  @override
  String get agendaDone => 'Fatto';

  @override
  String get planShowList => 'Mostra l’elenco';

  @override
  String get planShowMonth => 'Mostra il mese';

  @override
  String planRemindersAway(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count promemoria mentre eri via',
      one: '1 promemoria mentre eri via',
    );
    return '$_temp0';
  }

  @override
  String planRemindersHeading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count promemoria',
      one: 'Un promemoria',
    );
    return '$_temp0';
  }

  @override
  String get planDoneAll => 'Fatto con tutti';

  @override
  String planTimetableError(String error) {
    return 'Orario: $error. Viene mostrata l’ultima copia.';
  }

  @override
  String planCalendarNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count note su questo calendario',
      one: '1 nota su questo calendario',
    );
    return '$_temp0';
  }

  @override
  String get planShowAll => 'Mostra tutto';

  @override
  String get planNothingOnDay => 'Niente in questo giorno.';

  @override
  String get planDoneReminder => 'Fatto con questo promemoria';

  @override
  String get planEmptyHeadline => 'Ancora niente con una data.';

  @override
  String get planEmptyBody =>
      'Tutto ciò che ha una data compare qui: date d’esame, attività con scadenza, promemoria e il tuo orario se ti iscrivi a uno.';

  @override
  String get planSetExam => 'Imposta una data d’esame';

  @override
  String get planAddReminder => 'Aggiungi un promemoria';

  @override
  String get planSubscribe => 'Iscriviti a un orario';

  @override
  String get planAddDate => 'Aggiungi una data';

  @override
  String get planAddDateMenu => 'Aggiungi una data…';

  @override
  String get planMenuReminder => 'Promemoria…';

  @override
  String get planMenuExam => 'Data dell’esame…';

  @override
  String get planMenuTask => 'Scadenza su questa pagina…';

  @override
  String get planMenuSubscribe => 'Iscriviti a un orario…';

  @override
  String get planSettings => 'Impostazioni del planner';

  @override
  String get planChangeTimetable => 'Cambia l’orario…';

  @override
  String get planAlerts => 'Avvisi prima delle lezioni…';

  @override
  String get planRemoveTimetable => 'Rimuovi l’orario';

  @override
  String get planCalendarNotesMenu => 'Note su questo calendario…';

  @override
  String get planTimetable => 'Orario';

  @override
  String planRefreshError(String name, String error) {
    return '$name: $error. Aggiorna';
  }

  @override
  String planRefresh(String name) {
    return 'Aggiorna $name';
  }

  @override
  String planRefreshUpdated(String name, String when) {
    return 'Aggiorna $name (aggiornato $when)';
  }

  @override
  String get planGoToNote => 'Vai alla nota';

  @override
  String get planMoveToday => 'Sposta a oggi';

  @override
  String get planMoveTomorrow => 'Sposta a domani';

  @override
  String get planMoveWeek => 'Sposta di una settimana';

  @override
  String get planPickDateMenu => 'Scegli una data…';

  @override
  String get planDeleteReminder => 'Elimina promemoria';

  @override
  String get planClearDate => 'Rimuovi la data';

  @override
  String get planReadOnly => 'Dal tuo calendario: sola lettura';

  @override
  String get planWhichSection => 'Quale sezione?';

  @override
  String get planTagFirst =>
      'Prima etichetta una riga di questa pagina: poi potrà avere una scadenza.';

  @override
  String get planWhichLine => 'Quale riga riceve la scadenza?';

  @override
  String get planEmptyLine => '(riga vuota)';

  @override
  String get planDueDate => 'Scadenza';

  @override
  String planReminderSet(String time, String when) {
    return 'Promemoria alle $time $when. Openote ti avviserà se è aperto, e ti dirà se non lo era.';
  }

  @override
  String get planTimetableAdded =>
      'Orario aggiunto. Si aggiorna quando Openote si apre.';

  @override
  String planCouldNotLoad(String error) {
    return 'Impossibile caricare quel calendario: $error';
  }

  @override
  String get planAboutCalendar => 'Informazioni su questo calendario';

  @override
  String get planAboutCalendarBody =>
      'Openote legge le parti comuni di un file di calendario. Quello che non è riuscito a leggere, o non esattamente, è elencato qui invece di essere scartato in silenzio. Gli orari sono mostrati nel fuso orario del tuo computer.';

  @override
  String get planPickDate => 'Scegli una data';

  @override
  String get planSnooze => 'Posticipa';

  @override
  String get planSnooze10 => '10 minuti';

  @override
  String get planSnoozeHour => 'Un’ora';

  @override
  String get planSnoozeEvening => 'Stasera (3 ore)';

  @override
  String get planSnoozeTomorrow => 'Domani';

  @override
  String get planRemindMe => 'Ricordamelo';

  @override
  String get planReminderHint => 'Riprendere la dimostrazione del 2.7';

  @override
  String get planIn30 => 'Tra 30 min';

  @override
  String get planInHour => 'Tra un’ora';

  @override
  String get planThisEvening => 'Stasera';

  @override
  String get planTomorrowMorning => 'Domani mattina';

  @override
  String get planNudgeNote =>
      'Openote ti avvisa mentre è aperto. Se era chiuso all’ora stabilita, il promemoria ti aspetta alla prossima apertura.';

  @override
  String get planSubscribeTitle => 'Iscriviti a un calendario';

  @override
  String get planSubscribeBody =>
      'Incolla l’indirizzo del calendario del tuo orario universitario, di Google Calendar, Outlook o Calendario di Apple. Di solito finisce con .ics ed è l’unica cosa che Openote vede: nessun accesso e nessun permesso sul tuo account.';

  @override
  String get planReadOnlyNote =>
      'Sola lettura, in una sola direzione: Openote mostra il tuo orario accanto alle note e non vi scrive mai nulla.';

  @override
  String get planSubscribeButton => 'Iscriviti';

  @override
  String get planNow => 'Ora';

  @override
  String get planNext => 'Poi';

  @override
  String get planThen => 'Dopo';

  @override
  String get planUntitledEvent => '(evento senza titolo)';

  @override
  String planJoin(String provider) {
    return 'Partecipa su $provider';
  }

  @override
  String planInMinutes(String minutes) {
    return 'tra $minutes min';
  }

  @override
  String planAtTime(String time) {
    return 'alle $time';
  }

  @override
  String planUntil(String time) {
    return 'fino alle $time';
  }

  @override
  String planCouldNotOpenLink(String url) {
    return 'Impossibile aprire quel link: $url';
  }

  @override
  String get planPrevMonth => 'Mese precedente';

  @override
  String get planNextMonth => 'Mese successivo';

  @override
  String alertWaiting(String count) {
    return '$count in attesa';
  }

  @override
  String alertWaitingMore(String count, String hidden) {
    return '$count in attesa · altri $hidden sotto';
  }

  @override
  String alertWhileAway(String count) {
    return '$count mentre eri via';
  }

  @override
  String get alertDismissAll => 'Chiudi tutto';

  @override
  String get alertDismiss => 'Chiudi';

  @override
  String get alertStartingNow => 'inizia ora';

  @override
  String alertInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tra $count minuti',
      one: 'tra 1 minuto',
    );
    return '$_temp0';
  }

  @override
  String alertWasDue(String time) {
    return 'Era previsto alle $time';
  }
}
