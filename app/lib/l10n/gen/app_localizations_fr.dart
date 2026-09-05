// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class LFr extends L {
  LFr([String locale = 'fr']) : super(locale);

  @override
  String get commonBack => 'Retour';

  @override
  String get commonSkip => 'Passer';

  @override
  String get commonNext => 'Suivant';

  @override
  String get commonOpen => 'Ouvrir';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonDetailsAdvanced => 'Détails (avancé)';

  @override
  String objectRowBackground(String kind) {
    return 'Fond : $kind';
  }

  @override
  String get objectRowBackgroundBlank => 'blanc';

  @override
  String get objectRowBackgroundGrid => 'quadrillé';

  @override
  String get objectRowBackgroundDotted => 'pointillé';

  @override
  String get objectRowBackgroundRuled => 'ligné';

  @override
  String objectRowPageMode(String paper, String landscape) {
    return 'Mode page : $paper$landscape — cliquez pour le canevas';
  }

  @override
  String get objectRowLandscapeSuffix => ' paysage';

  @override
  String get objectRowCanvasMode =>
      'Mode canevas : sans limites — cliquez pour les pages';

  @override
  String get objectRowPaperSize => 'Format du papier';

  @override
  String get objectRowLandscape => 'Paysage';

  @override
  String get objectRowSnapOn =>
      'Aligner sur la grille : OUI (visible pendant le déplacement)';

  @override
  String get objectRowSnapOff =>
      'Aligner sur la grille : NON — placement libre';

  @override
  String get objectRowZoomOut => 'Dézoomer  (Ctrl+-)';

  @override
  String get objectRowZoomIn => 'Zoomer  (Ctrl+=)';

  @override
  String get objectRowZoomReset =>
      'Revenir à 100 % et en haut de la page  (Ctrl+0)';

  @override
  String get objectRowZoomFit => 'Ajuster le zoom au contenu';

  @override
  String get objectRowWordCount =>
      'Mots sur cette page — cliquez pour les caractères et le temps de lecture';

  @override
  String get objectRowWords => 'Mots';

  @override
  String get objectRowCharacters => 'Caractères';

  @override
  String get objectRowCharactersNoSpaces => 'Sans les espaces';

  @override
  String get objectRowReadingTime => 'Temps de lecture';

  @override
  String objectRowMinutes(int n) {
    return '$n min';
  }

  @override
  String objectRowWordTally(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted mots',
      one: '1 mot',
      zero: 'aucun mot',
    );
    return '$_temp0';
  }

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent %';
  }

  @override
  String get barTabHome => 'Accueil';

  @override
  String get barTabInsert => 'Insérer';

  @override
  String get barTabDraw => 'Dessiner';

  @override
  String get barEquationBadge => 'Équation';

  @override
  String barUpdateTo(String version) {
    return 'Mettre à jour vers $version…';
  }

  @override
  String get barDone => 'Terminé';

  @override
  String get barStudy => 'Révisions';

  @override
  String get barPlanner => 'Agenda';

  @override
  String get barFindTags => 'Chercher les étiquettes';

  @override
  String get barPageOutline => 'Plan de la page';

  @override
  String get barLinks => 'Liens et rétroliens';

  @override
  String get barFindOnPage => 'Chercher dans la page';

  @override
  String get barFindOnPageTip => 'Chercher dans la page  (Ctrl+F)';

  @override
  String get barExport => 'Exporter';

  @override
  String get barExportTip => 'Exporter la page…';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

  @override
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPrint => 'Imprimer…';

  @override
  String get barExportPdfPicture => 'PDF — image de la page';

  @override
  String get barExportCanvas => 'Pour Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => 'Le dessin seul (.inkml)';

  @override
  String get barExportNotebook =>
      'Enregistrer tout le carnet en dossiers et fichiers…';

  @override
  String get barExportNotebookBusy => 'Enregistrement du carnet…';

  @override
  String barExportPageProgress(int done, int total) {
    return 'Page $done sur $total…';
  }

  @override
  String barExportedTo(String path) {
    return 'Exporté vers $path';
  }

  @override
  String get barSettings => 'Réglages';

  @override
  String get barSettingsTip => 'Réglages…';

  @override
  String get barUndo => 'Annuler  (Ctrl+Z)';

  @override
  String get barRedo => 'Rétablir  (Ctrl+Y)';

  @override
  String get barBold => 'Gras  (Ctrl+B)';

  @override
  String get barItalic => 'Italique  (Ctrl+I)';

  @override
  String get barUnderline => 'Souligné  (Ctrl+U)';

  @override
  String get barStrikethrough => 'Barré';

  @override
  String get barInlineCode => 'Code en ligne';

  @override
  String get barHighlight => 'Surlignage';

  @override
  String get barHeading1 => 'Titre 1';

  @override
  String get barBulletList => 'Liste à puces';

  @override
  String get barNumberedList => 'Liste numérotée';

  @override
  String get barCheckbox => 'Case à cocher';

  @override
  String get barQuote => 'Citation';

  @override
  String get barTextColour => 'Colorer le texte';

  @override
  String get barTextFont => 'Police du texte…';

  @override
  String get barClickIntoTextBox => 'Cliquez dans une zone de texte';

  @override
  String get barToolSelect => 'Sélectionner / déplacer  (V)';

  @override
  String get barToolText => 'Texte  (T)';

  @override
  String get barToolPen => 'Stylo  (P)';

  @override
  String get barToolHighlighter => 'Surligneur  (H)';

  @override
  String get barToolEraser => 'Gomme  (E)';

  @override
  String get barToolLasso => 'Sélectionner l\'encre au lasso';

  @override
  String get barEraserSplit => 'Coupe les traits à l\'endroit frotté';

  @override
  String get barEraserWhole => 'Enlève tout trait que vous touchez';

  @override
  String get barLassoHint =>
      'Entourez l\'encre pour la sélectionner — puis déplacez-la ou supprimez-la';

  @override
  String get barPickPenHint => 'Prenez le stylo ou le surligneur pour dessiner';

  @override
  String get barTouchDrawing =>
      'Dessinez au doigt.\nAuto : le doigt dessine jusqu\'à ce que vous preniez le stylet ; ensuite le doigt fait glisser la page, pour que la paume ne marque rien.\nDeux doigts font toujours glisser et zoomer.';

  @override
  String get barPenProximity =>
      'Approcher le stylet de la page passe à l\'encre.\nSi vous choisissez un autre outil pendant que le stylet est là, il\nreste jusqu\'à ce que le stylet s\'éloigne et revienne. Le bout\narrière du stylet (ou son bouton, maintenu) efface.';

  @override
  String get barTextSize => 'Taille du texte (points)';

  @override
  String get barTextSizeDisabled =>
      'Cliquez dans une zone de texte pour changer sa taille';

  @override
  String get barFontSizeDefault => 'Par défaut';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barTagLine =>
      'Étiqueter cette ligne (À faire, Important, Question…)';

  @override
  String barTagged(String tags) {
    return 'Étiquetée : $tags';
  }

  @override
  String get barDueDateSet => 'Échéance…';

  @override
  String get barDueDateChange => 'Changer l\'échéance…';

  @override
  String get barDueDateClear => 'Enlever l\'échéance';

  @override
  String get barDueDatePickerTitle => 'Échéance';

  @override
  String get barDueDatePickerConfirm => 'Définir';

  @override
  String get barMakeCardFromLine => 'Faire une fiche de cette ligne';

  @override
  String get barNewCard => 'Nouvelle fiche';

  @override
  String get barQuestionCard => 'Fiche question';

  @override
  String get barDefinitionCard => 'Fiche définition';

  @override
  String get barBlankOut => 'Masquer la sélection';

  @override
  String get barBlankOutNeedsSelection =>
      'Sélectionnez d\'abord les mots à masquer.';

  @override
  String get barOpenStudyPanel => 'Ouvrir le panneau de révisions';

  @override
  String get barStudyEmpty =>
      'Révisions — étiquetez une ligne Question ou Définition pour en faire une fiche';

  @override
  String barStudyDue(int due, int total, String countdown) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total fiches',
      one: '1 fiche',
    );
    return '$due sur $_temp0 à revoir dans cette section$countdown';
  }

  @override
  String barStudyExamCountdown(String when) {
    return ' · examen $when';
  }

  @override
  String get barPlannerEmpty => 'Agenda — toutes vos dates au même endroit';

  @override
  String barPlannerToday(int count) {
    return 'Agenda — $count pour aujourd\'hui';
  }

  @override
  String barPlannerOverdue(int count) {
    return 'Agenda — $count pour aujourd\'hui ou en retard';
  }

  @override
  String barRemindersWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rappels',
      one: '1 rappel',
    );
    return '$_temp0 en attente';
  }

  @override
  String get barEscWhenDone => 'Échap quand vous avez fini';

  @override
  String barSaveFailed(String reason) {
    return 'Impossible d\'enregistrer : $reason';
  }

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get navSearchHint => 'Chercher ou aller à…';

  @override
  String navNoMatches(String query) {
    return 'Aucun résultat pour « $query »';
  }

  @override
  String get navInPageContent => 'Dans le contenu des pages';

  @override
  String get navUntitled => 'Sans titre';

  @override
  String get navNoSections =>
      'Pas encore de section.\nCréez-en une pour commencer.';

  @override
  String get navNewSection => 'Nouvelle section';

  @override
  String navNewPageIn(String section) {
    return 'Nouvelle page dans $section';
  }

  @override
  String get navNoPages => 'Pas encore de page';

  @override
  String get navSection => 'Section';

  @override
  String get navNewSectionGroup => 'Nouveau groupe de sections';

  @override
  String get navRecycleBin => 'Corbeille';

  @override
  String get navHome => 'Accueil';

  @override
  String get navHomeTip => 'Accueil — favoris et récents';

  @override
  String get navHomeEmpty =>
      'Rien ici pour l\'instant.\n\nFaites un clic droit sur une page et choisissez Favori pour l\'épingler ; les pages que vous visitez apparaissent dans Récents.';

  @override
  String get navComingUp => 'À VENIR';

  @override
  String navAllCount(int total) {
    return 'Voir les $total';
  }

  @override
  String get navOpen => 'Ouvrir';

  @override
  String get navExpand => 'Déplier le navigateur  (Ctrl+\\)';

  @override
  String get navCollapse => 'Replier le navigateur  (Ctrl+\\)';

  @override
  String get navNotebooksTip =>
      'Carnets — changer, renommer, dupliquer, importer';

  @override
  String get navDeletesSoon => 'Bientôt supprimé';

  @override
  String navDeletesInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Supprimé dans $days jours',
      one: 'Supprimé dans 1 jour',
    );
    return '$_temp0';
  }

  @override
  String get navBinEmpty => 'Rien de supprimé.';

  @override
  String navBinRetention(int days) {
    return 'Ce qui est ici est supprimé définitivement au bout de $days jours.';
  }

  @override
  String get navBinNotebooks => 'Carnets';

  @override
  String get navBinItems => 'Éléments';

  @override
  String get navRestore => 'Restaurer';

  @override
  String get navDeletePermanently => 'Supprimer définitivement';

  @override
  String get navClose => 'Fermer';

  @override
  String get navDeleteForeverTitle => 'Supprimer définitivement ?';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '« $title » et toutes ses pages seront supprimées pour de bon. C\'est irréversible.$caveat';
  }

  @override
  String get navDeleteForever => 'Supprimer pour de bon';

  @override
  String navLockedCannotDelete(String title) {
    return '« $title » est verrouillée. Enlevez son code avant de la supprimer.';
  }

  @override
  String navDeletedRestorable(String title) {
    return '« $title » supprimée — vous pouvez la restaurer depuis la corbeille.';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '« $title » est verrouillée. Elle est cachée dans Openote, pas chiffrée dans le fichier.';
  }

  @override
  String navPasscodeRemoved(String title) {
    return 'Code enlevé de « $title ».';
  }

  @override
  String navSavedTo(String path) {
    return 'Enregistré dans $path';
  }

  @override
  String get navLinkCopied =>
      'Lien copié — collez-le dans n\'importe quelle page';

  @override
  String get navMoveSectionTo => 'Déplacer la section vers…';

  @override
  String get navNoGroupTopLevel => '(Aucun groupe — premier niveau)';

  @override
  String get navSaveTemplateTitle => 'Enregistrer comme modèle';

  @override
  String get navSave => 'Enregistrer';

  @override
  String get navTemplateNameHint => 'Nom du modèle';

  @override
  String navTemplateSaved(String name) {
    return 'Modèle « $name » enregistré';
  }

  @override
  String get navNoTemplates =>
      'Pas encore de modèle — utilisez d\'abord « Enregistrer comme modèle… ».';

  @override
  String get navApplyTemplate => 'Appliquer un modèle';

  @override
  String get navColour => 'Couleur';

  @override
  String get navColourDefault => 'Par défaut';

  @override
  String navExamCountdown(String when, String countdown) {
    return 'Examen $when · $countdown…';
  }

  @override
  String get navMenuMoveUp => 'Monter';

  @override
  String get navMenuMoveDown => 'Descendre';

  @override
  String get navMenuNewPage => 'Nouvelle page';

  @override
  String get navMenuMoveToGroup => 'Déplacer vers un groupe…';

  @override
  String get navMenuSortAZ => 'Trier les pages de A à Z';

  @override
  String get navMenuSortEdited => 'Trier par dernière modification';

  @override
  String get navMenuExportSectionPdf => 'Exporter la section en PDF…';

  @override
  String get navMenuPrintSection => 'Imprimer la section…';

  @override
  String get navMenuRemoveExam => 'Enlever la date d\'examen';

  @override
  String get navMenuSetExam => 'Définir la date d\'examen…';

  @override
  String get navMenuMakeSubpage => 'Mettre en sous-page';

  @override
  String get navMenuMoveBackOut => 'Sortir de la sous-page';

  @override
  String get navMenuRemoveFavourite => 'Retirer des favoris';

  @override
  String get navMenuAddFavourite => 'Ajouter aux favoris';

  @override
  String get navMenuSharePdf => 'Partager en PDF…';

  @override
  String get navMenuPrint => 'Imprimer…';

  @override
  String get navMenuCopyLink => 'Copier le lien vers la page';

  @override
  String get navMenuRecentChanges => 'Modifications récentes…';

  @override
  String get navMenuSaveTemplate => 'Enregistrer comme modèle…';

  @override
  String get navMenuApplyTemplate => 'Appliquer un modèle…';

  @override
  String get navMenuRemovePasscode => 'Enlever le code…';

  @override
  String get navMenuLock => 'Verrouiller avec un code…';

  @override
  String get navMenuDelete => 'Supprimer';

  @override
  String get commonOn => 'Oui';

  @override
  String get commonOff => 'Non';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonDone => 'Terminé';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get commonOpenEllipsis => 'Ouvrir…';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsAppearance => 'Apparence';

  @override
  String get settingsTheme => 'Thème';

  @override
  String get settingsThemeSystem => 'Système';

  @override
  String get settingsThemeLight => 'Clair';

  @override
  String get settingsThemeDark => 'Sombre';

  @override
  String get settingsWriting => 'Écriture et dessin';

  @override
  String get settingsSpellCheck => 'Correcteur orthographique';

  @override
  String get settingsPenProximity =>
      'Approcher le stylet de la page passe à l\'encre';

  @override
  String get settingsConnections => 'Connexions';

  @override
  String get settingsSync => 'Synchronisation';

  @override
  String get settingsSyncHint =>
      'Sauvegardez ce carnet et partagez-le — GitHub ou un dossier.';

  @override
  String get settingsAi => 'Accès de l\'IA';

  @override
  String get settingsAiOn =>
      'Oui — les assistants IA de cet ordinateur peuvent lire vos notes.';

  @override
  String get settingsAiOff =>
      'Non — connectez Claude ou d\'autres assistants IA.';

  @override
  String get settingsHelp => 'Aide';

  @override
  String get settingsWelcomeTour => 'Visite guidée';

  @override
  String get settingsWelcomeTourHint =>
      'La version en trois minutes : le canevas, les maths et l\'encre, et où vivent vos notes.';

  @override
  String get settingsShortcuts => 'Raccourcis clavier';

  @override
  String get settingsShortcutsHint =>
      'Tout a une touche — la liste complète.  (Ctrl+/)';

  @override
  String get settingsAbout => 'À propos';

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsCheckUpdates => 'Rechercher les mises à jour';

  @override
  String settingsUpToDate(String version) {
    return 'Vous êtes à jour ($version est la version la plus récente).';
  }

  @override
  String get settingsWhatsNew => 'Nouveautés';

  @override
  String get nbTitle => 'Carnets';

  @override
  String nbOpenCount(int count) {
    return '$count ouverts';
  }

  @override
  String nbInBin(int days) {
    return 'Dans la corbeille · supprimé au bout de $days jours';
  }

  @override
  String get nbImportInto => 'Importer dans un nouveau carnet';

  @override
  String get nbNew => 'Nouveau';

  @override
  String get nbNewTitle => 'Nouveau carnet';

  @override
  String get nbCreate => 'Créer';

  @override
  String get nbNameHint => 'Nom du carnet';

  @override
  String get nbImport => 'Importer';

  @override
  String get nbRepair => 'Réparer';

  @override
  String get nbGetStarted => 'Commencer';

  @override
  String get nbImportOnepkg => 'Carnet OneNote (.onepkg)';

  @override
  String get nbImportOne => 'Section OneNote (.one)';

  @override
  String get nbImportMarkdown => 'Dossier Markdown';

  @override
  String get nbImportGit => 'Depuis une adresse git';

  @override
  String get nbDuplicates =>
      'Doublons possibles · même titre et même nombre de pages';

  @override
  String get nbDuplicatesHint =>
      'Gardez le plus gros — le plus petit vient en général d\'une importation interrompue. Les copies supprimées vont à la corbeille.';

  @override
  String get nbOpenThis => 'Ouvrir ce carnet';

  @override
  String get nbRename => 'Renommer';

  @override
  String get nbDuplicate => 'Dupliquer';

  @override
  String get nbMoveToBin => 'Mettre à la corbeille';

  @override
  String get nbConfirmBin =>
      'Mettre à la corbeille ? Vous pourrez le restaurer d\'ici.';

  @override
  String get nbOnePkgFileType => 'Paquet de carnet OneNote';

  @override
  String get nbImportBusy =>
      'Une importation est déjà en cours — une à la fois.';

  @override
  String get nbImportStarted =>
      'Importation en arrière-plan — continuez ; la carte dans le coin préviendra quand ce sera fini.';

  @override
  String nbImportedNamed(String name) {
    return '$name importé';
  }

  @override
  String get nbReadingFolder => 'Lecture du dossier…';

  @override
  String nbImportedProgress(String done) {
    return 'Importé $done';
  }

  @override
  String get nbNoMarkdown => 'Aucun fichier Markdown trouvé dans ce dossier.';

  @override
  String nbImportedPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages importées',
      one: '1 page importée',
    );
    return '$_temp0';
  }

  @override
  String get nbNeedsNativeCore =>
      'L\'import OneNote a besoin du cœur Rust — compilez onote_core.dll et placez-le à côté de l\'application.';

  @override
  String get nbCheckingPages => 'Vérification des pages…';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return 'Vérification de la page $done sur $total…';
  }

  @override
  String get nbNothingToRepair =>
      'Rien à réparer — toutes les pages sont à jour.';

  @override
  String nbRepairedBoxes(int blocks) {
    String _temp0 = intl.Intl.pluralLogic(
      blocks,
      locale: localeName,
      other: '$blocks blocs',
      one: '1 bloc',
    );
    return '$_temp0';
  }

  @override
  String nbRepairedPages(int pages) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String nbRepaired(String boxes, String pages) {
    return '$boxes réparés sur $pages.';
  }

  @override
  String nbRepairFailed(String reason) {
    return 'La réparation a échoué : $reason';
  }

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '$copies copies de « $title » · $pages pages chacune · $size récupérés';
  }

  @override
  String get nbCoreMissing =>
      'L\'import OneNote a besoin du cœur Rust — compilez onote_core.dll (voir rust/onote_core/INTEGRATION.md).';

  @override
  String nbReadFileFailed(String reason) {
    return 'Impossible de lire ce fichier : $reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return 'Impossible d\'importer ce dossier : $reason';
  }

  @override
  String get nbOneFileEmpty =>
      'Impossible de lire quoi que ce soit dans ce fichier .one.';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return 'Importé $what depuis OneNote.$strokeNote';
  }

  @override
  String nbImportedPagesProgress(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages importées…',
      one: '1 page importée…',
    );
    return '$_temp0';
  }

  @override
  String mathSemanticLabel(String latex) {
    return 'Équation : $latex';
  }

  @override
  String get insertGroupWrite => 'Écrire';

  @override
  String get insertGroupBringIn => 'Apporter';

  @override
  String get insertGroupLinkUp => 'Relier';

  @override
  String get insertTextBox => 'Zone';

  @override
  String get insertEquation => 'Équation';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertTable => 'Tableau';

  @override
  String get insertTableFromFile => 'D\'un fichier';

  @override
  String get insertTableFromFileTip => 'CSV ou Excel';

  @override
  String get insertCode => 'Code';

  @override
  String get insertBoard => 'Tableau';

  @override
  String get insertBoardTip => 'Des colonnes de cartes que vous faites avancer';

  @override
  String get insertPicture => 'Image';

  @override
  String get insertPdfSlides => 'PDF';

  @override
  String get insertPdfPrintout => 'Imprimé sur cette page';

  @override
  String get insertPdfPerSlide => 'Une page par diapositive';

  @override
  String get insertPdfAsCard => 'En carte — s\'ouvre dans une fenêtre';

  @override
  String get insertVideo => 'Vidéo';

  @override
  String get insertVideoTip =>
      'Un enregistrement de cours, ou n\'importe quel lien web';

  @override
  String get insertFile => 'Fichier';

  @override
  String get insertFlashcardItem => 'Fiche';

  @override
  String get insertPageLink => 'Lien';

  @override
  String get insertPageWindow => 'Fenêtre';

  @override
  String get insertTemplate => 'Modèle';

  @override
  String get insertPickImages => 'Images';

  @override
  String get insertPickTables => 'Tableaux';

  @override
  String get insertPickVideo => 'Vidéo et audio';

  @override
  String get tagTodo => 'À faire';

  @override
  String get tagImportant => 'Important';

  @override
  String get tagQuestion => 'Question';

  @override
  String get tagRemember => 'À retenir';

  @override
  String get tagDefinition => 'Définition';

  @override
  String get tagIdea => 'Idée';

  @override
  String get tagCritical => 'Urgent';

  @override
  String get tagContact => 'Contact';

  @override
  String get tagCustom => 'Étiquette';

  @override
  String get touchDrawAuto => 'Auto (le stylet prend la main)';

  @override
  String get touchDrawAlways => 'Toujours';

  @override
  String get touchDrawNever => 'Jamais';

  @override
  String get insertLinkToPage => 'Lier à une page';

  @override
  String get insertPdfUnreadable => 'Ce PDF n\'a pas pu être lu.';

  @override
  String insertPdfImported(int count, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count diapositives importées',
      one: '1 diapositive importée',
    );
    return '$_temp0$where — prenez le stylo et écrivez dessus. Le texte des diapositives est cherchable.';
  }

  @override
  String get insertPdfOntoThisPage => ' sur cette page';

  @override
  String insertPdfFailed(String reason) {
    return 'L\'import du PDF a échoué : $reason';
  }

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguageAuto => 'La même que mon ordinateur';

  @override
  String get settingsLanguageHelp =>
      'Openote est traduit par ceux qui l\'utilisent. Si la vôtre manque ou est fausse, c\'est un seul fichier — le lien explique comment.';

  @override
  String get settingsLanguageContribute =>
      'Comment ajouter ou corriger une langue';

  @override
  String get shellNothingReplaced => 'Rien n\'a été remplacé';

  @override
  String shellReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count occurrences remplacées',
      one: '1 occurrence remplacée',
    );
    return '$_temp0';
  }

  @override
  String get shellReplaceWith => 'Remplacer par…';

  @override
  String get shellReplace => 'Remplacer';

  @override
  String get shellReplaceAll => 'Tout';

  @override
  String get shellFindOnThisPage => 'Chercher dans cette page…';

  @override
  String get shellNoMatches => 'Aucun résultat';

  @override
  String get shellPreviousMatch => 'Résultat précédent (Maj+Entrée)';

  @override
  String get shellNextMatch => 'Résultat suivant (Entrée)';

  @override
  String get shellCloseEsc => 'Fermer (Échap)';

  @override
  String get shellNoTags => 'Pas encore d\'étiquette dans ce carnet.';

  @override
  String get shellTagsHint =>
      'Les étiquettes marquent une ligne — à faire, important, question, définition — pour la retrouver, la réviser ou lui donner une échéance.';

  @override
  String get shellTagTheLine => 'Étiqueter la ligne où vous êtes';

  @override
  String get shellNoHeadings => 'Aucun titre sur cette page.';

  @override
  String get shellHeadingsHint =>
      'Commencez une ligne par # pour en faire un titre — le plan se construit tout seul pendant que vous écrivez.';

  @override
  String get shellLinkedFrom => 'Liée depuis';

  @override
  String get shellNoBacklinks => 'Aucune page ne pointe encore ici.';

  @override
  String get shellLinksTo => 'Pointe vers';

  @override
  String get shellNoLinks => 'Cette page ne pointe encore nulle part.';

  @override
  String get shellSavedLocally =>
      'Cette page est enregistrée dans votre fichier .onote local.';

  @override
  String get shellSaving => 'Enregistrement…';

  @override
  String get shellSavedOnDevice => 'Enregistré sur cet appareil';

  @override
  String shellRustLinked(String build) {
    return 'Le cœur Rust (onote-core) est relié et calcule l\'empreinte du contenu de cette page à l\'enregistrement.\n$build';
  }

  @override
  String get shellRustMissing =>
      'Fonctionne avec le moteur Dart pur. Compilez la bibliothèque onote-core pour relier le cœur Rust.';

  @override
  String get shellCheatSheet =>
      'V sélection · T texte · P stylo · H surligneur · E gomme · Ctrl+Z annuler · Ctrl+molette zoom';

  @override
  String get shellEmptyTitle => 'Une page ouverte vous attend';

  @override
  String get shellEmptyBody =>
      'Tout ce que vous faites ici reste sur votre appareil,\ndans un format ouvert qui vous appartient.';

  @override
  String get shellCreateFirstPage => 'Créez votre première page';

  @override
  String get shellAlreadyUpToDate => 'Déjà à jour.';

  @override
  String shellPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifications récupérées',
      one: '1 modification récupérée',
    );
    return '$_temp0';
  }

  @override
  String shellPageLocked(String title) {
    return '« $title » est verrouillée';
  }

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag  ($count)';
  }

  @override
  String get shellUnlock => 'Déverrouiller';

  @override
  String get onboardingStep1Title => 'La page est un canevas';

  @override
  String get onboardingStep1Body =>
      'Cliquez n\'importe où et écrivez — la zone apparaît là où vous avez cliqué, et seulement quand vous tapez. Déplacez-la par la barre du haut, et faites glisser des images d\'où vous voulez.';

  @override
  String get onboardingStep2Title =>
      'Les maths et le dessin, au milieu des mots';

  @override
  String get onboardingStep2Body =>
      'Tapez 1/2 ou appuyez sur Alt+= : la vraie notation se construit à mesure que vous écrivez, dans sa propre zone ou en pleine phrase. L\'onglet Dessiner accepte le stylet, le doigt ou la souris.';

  @override
  String get onboardingStep3Title =>
      'Vos notes sont un fichier qui vous appartient';

  @override
  String get onboardingStep3Body =>
      'Un fichier ouvert et lisible par carnet — sans compte, sans enfermement. Mettez-le dans un dossier que votre cloud synchronise déjà et tous vos appareils resteront d\'accord.';

  @override
  String get onboardingStartWriting => 'Commencer à écrire';

  @override
  String get onboardingSyncTitle => 'Synchroniser avec un autre appareil';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive, OneDrive, iCloud, Dropbox, Syncthing, un NAS — ou un dépôt GitHub.';

  @override
  String get onboardingSyncBodyAlso =>
      'Aucun de ceux-là ? Choisissez le dossier vous-même.';

  @override
  String get onboardingSyncAction => 'Configurer…';

  @override
  String get onboardingOneNoteTitle => 'Récupérer des notes depuis OneNote';

  @override
  String get onboardingOneNoteBody =>
      'Pages, mise en forme, images, encre et étiquettes depuis un .onepkg. Tourne en arrière-plan — continuez pendant ce temps.';

  @override
  String get onboardingOneNoteAction => 'Choisir un fichier…';

  @override
  String get onboardingFreshTitle => 'Commencer un nouveau carnet';

  @override
  String get onboardingFreshBody =>
      'Un carnet vide, prêt à l\'emploi. Vous pourrez importer vos notes plus tard.';

  @override
  String get onboardingFreshAction => 'Commencer à zéro';

  @override
  String get onboardingCloudTitle => 'Importer des notes depuis OneNote';

  @override
  String get onboardingCloudBody =>
      'Connectez-vous à Microsoft et choisissez un carnet. Rien à exporter au préalable, et cela fonctionne sur n\'importe quel ordinateur.';

  @override
  String get onboardingCloudAction => 'Se connecter';

  @override
  String get oneNoteCloudTitle => 'Importer un carnet depuis OneNote';

  @override
  String get oneNoteCloudIntro =>
      'Openote lira vos carnets OneNote. Il ne peut pas les modifier.';

  @override
  String get oneNoteCloudSignIn => 'Se connecter à Microsoft';

  @override
  String get oneNoteCloudSigningIn => 'En attente de votre navigateur…';

  @override
  String get oneNoteCloudLoading => 'Recherche de vos carnets…';

  @override
  String get oneNoteCloudEmpty => 'Aucun carnet trouvé sur ce compte.';

  @override
  String get oneNoteCloudOther => 'Utiliser un autre compte';

  @override
  String get oneNoteCloudNoInk =>
      'Les tableaux sont ajustés à la page plutôt que conservés à leur largeur exacte, et la couleur et la police du texte ne sont pas reprises.';

  @override
  String get onboardingOnePkgFileType => 'Paquet de carnet OneNote';

  @override
  String get onboardingOneNoteHowTo => 'Comment exporter ?';

  @override
  String get onboardingOneNoteHideSteps => 'Masquer les étapes';

  @override
  String get onboardingExportTitle => 'Exporter depuis OneNote';

  @override
  String get onboardingExportSteps =>
      '1. Ouvrez OneNote pour Windows (l\'application de bureau — les versions Store et web ne peuvent pas exporter).\n2. Laissez le carnet finir de se synchroniser, pour tout avoir sur cette machine.\n3. Fichier ▸ Exporter ▸ Bloc-notes ▸ Package OneNote (*.onepkg), puis Exporter.\n4. Revenez ici et choisissez ce fichier.';

  @override
  String get onboardingExportMacNote =>
      'Sur un Mac, ou avec seulement la version du Store : exportez section par section en .one, ou demandez à une machine Windows de faire le .onepkg. Openote ne se connecte jamais à votre compte Microsoft — il lit seulement le fichier que vous lui donnez.';

  @override
  String onboardingImportingFile(String fileName) {
    return 'Importation de $fileName';
  }

  @override
  String get onboardingImportRunning =>
      'Continuez — cela tourne en arrière-plan, et la carte dans le coin préviendra quand ce sera fini.';

  @override
  String get onboardingImportDone => 'Votre carnet est prêt';

  @override
  String get onboardingOpenFailed => 'Openote n\'a pas pu ouvrir ce carnet.';

  @override
  String get onboardingNoNativeCore =>
      'L\'import OneNote a besoin du cœur natif, que cette version ne contient pas.';

  @override
  String onboardingReadFailed(String reason) {
    return 'Impossible de lire ce fichier : $reason';
  }

  @override
  String get oneNoteFileTitle => 'Utiliser un fichier exporté';

  @override
  String get oneNoteFileBody =>
      'Sans connexion, et la copie la plus fidèle : les tableaux conservent leur largeur exacte. Il vous faudra OneNote sous Windows pour exporter le carnet au préalable.';

  @override
  String get oneNoteSignInBody =>
      'Choisissez un carnet et il arrive directement, sans rien exporter. Fonctionne sur n\'importe quel ordinateur.';

  @override
  String get oneNotePickTitle => 'Quel carnet ?';

  @override
  String get oneNoteCloudContinue => 'Continuer avec Microsoft';
}
