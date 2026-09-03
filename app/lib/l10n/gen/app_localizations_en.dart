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
  String objectRowBackground(String kind) {
    return 'Background: $kind';
  }

  @override
  String get objectRowBackgroundBlank => 'blank';

  @override
  String get objectRowBackgroundGrid => 'grid';

  @override
  String get objectRowBackgroundDotted => 'dotted';

  @override
  String get objectRowBackgroundRuled => 'ruled';

  @override
  String objectRowPageMode(String paper, String landscape) {
    return 'Page mode: $paper$landscape — click for canvas';
  }

  @override
  String get objectRowLandscapeSuffix => ' landscape';

  @override
  String get objectRowCanvasMode => 'Canvas mode: boundless — click for pages';

  @override
  String get objectRowPaperSize => 'Paper size';

  @override
  String get objectRowLandscape => 'Landscape';

  @override
  String get objectRowSnapOn => 'Snap to grid: ON (grid shows while dragging)';

  @override
  String get objectRowSnapOff => 'Snap to grid: OFF — free placement';

  @override
  String get objectRowZoomOut => 'Zoom out  (Ctrl+-)';

  @override
  String get objectRowZoomIn => 'Zoom in  (Ctrl+=)';

  @override
  String get objectRowZoomReset =>
      'Back to 100% and the top of the page  (Ctrl+0)';

  @override
  String get objectRowZoomFit => 'Zoom to fit content';

  @override
  String get objectRowWordCount =>
      'Words on this page — click for characters and reading time';

  @override
  String get objectRowWords => 'Words';

  @override
  String get objectRowCharacters => 'Characters';

  @override
  String get objectRowCharactersNoSpaces => 'Without spaces';

  @override
  String get objectRowReadingTime => 'Reading time';

  @override
  String objectRowMinutes(int n) {
    return '$n min';
  }

  @override
  String objectRowWordTally(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted words',
      one: '1 word',
      zero: 'no words',
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
  String get barTabInsert => 'Insert';

  @override
  String get barTabDraw => 'Draw';

  @override
  String get barEquationBadge => 'Equation';

  @override
  String barUpdateTo(String version) {
    return 'Update to $version…';
  }

  @override
  String get barDone => 'Done';

  @override
  String get barStudy => 'Study';

  @override
  String get barPlanner => 'Planner';

  @override
  String get barFindTags => 'Find tags';

  @override
  String get barPageOutline => 'Page outline';

  @override
  String get barLinks => 'Links & backlinks';

  @override
  String get barFindOnPage => 'Find on page';

  @override
  String get barFindOnPageTip => 'Find on page  (Ctrl+F)';

  @override
  String get barExport => 'Export';

  @override
  String get barExportTip => 'Export page…';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

  @override
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPrint => 'Print…';

  @override
  String get barExportPdfPicture => 'PDF — picture of the page';

  @override
  String get barExportCanvas => 'For Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => 'Just the drawing (.inkml)';

  @override
  String get barExportNotebook =>
      'Save the whole notebook as folders and files…';

  @override
  String get barExportNotebookBusy => 'Saving the notebook…';

  @override
  String barExportPageProgress(int done, int total) {
    return 'Page $done of $total…';
  }

  @override
  String barExportedTo(String path) {
    return 'Exported to $path';
  }

  @override
  String get barSettings => 'Settings';

  @override
  String get barSettingsTip => 'Settings…';

  @override
  String get barUndo => 'Undo  (Ctrl+Z)';

  @override
  String get barRedo => 'Redo  (Ctrl+Y)';

  @override
  String get barBold => 'Bold  (Ctrl+B)';

  @override
  String get barItalic => 'Italic  (Ctrl+I)';

  @override
  String get barUnderline => 'Underline  (Ctrl+U)';

  @override
  String get barStrikethrough => 'Strikethrough';

  @override
  String get barInlineCode => 'Inline code';

  @override
  String get barHighlight => 'Highlight';

  @override
  String get barHeading1 => 'Heading 1';

  @override
  String get barBulletList => 'Bullet list';

  @override
  String get barNumberedList => 'Numbered list';

  @override
  String get barCheckbox => 'Checkbox';

  @override
  String get barQuote => 'Quote';

  @override
  String get barTextColour => 'Apply text colour';

  @override
  String get barTextFont => 'Text font…';

  @override
  String get barClickIntoTextBox => 'Click into a text box to format';

  @override
  String get barToolSelect => 'Select / move  (V)';

  @override
  String get barToolText => 'Text  (T)';

  @override
  String get barToolPen => 'Pen  (P)';

  @override
  String get barToolHighlighter => 'Highlighter  (H)';

  @override
  String get barToolEraser => 'Eraser  (E)';

  @override
  String get barToolLasso => 'Lasso-select ink';

  @override
  String get barEraserSplit => 'Splits strokes where you rub';

  @override
  String get barEraserWhole => 'Removes any stroke you touch';

  @override
  String get barLassoHint =>
      'Draw a loop around ink to select it — then drag or delete';

  @override
  String get barPickPenHint => 'Pick the pen or highlighter to draw';

  @override
  String get barTouchDrawing =>
      'Draw with your finger.\nAuto: a finger draws until you use the pen, then touch pans so your palm can\'t mark the page.\nTwo fingers always pan and zoom.';

  @override
  String get barPenProximity =>
      'Bringing the pen near the page switches to inking.\nPick another tool while the pen hovers and it sticks until the\npen leaves and comes back. The pen\'s tail (or its barrel\nbutton, held while drawing) erases.';

  @override
  String get barTextSize => 'Text size (points)';

  @override
  String get barTextSizeDisabled => 'Click into a text box to change its size';

  @override
  String get barFontSizeDefault => 'Default';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barTagLine => 'Tag this line (To Do, Important, Question…)';

  @override
  String barTagged(String tags) {
    return 'Tagged: $tags';
  }

  @override
  String get barDueDateSet => 'Due date…';

  @override
  String get barDueDateChange => 'Change due date…';

  @override
  String get barDueDateClear => 'Clear the due date';

  @override
  String get barDueDatePickerTitle => 'Due date';

  @override
  String get barDueDatePickerConfirm => 'Set';

  @override
  String get barMakeCardFromLine => 'Make this line a flashcard';

  @override
  String get barNewCard => 'New flashcard';

  @override
  String get barQuestionCard => 'Question card';

  @override
  String get barDefinitionCard => 'Definition card';

  @override
  String get barBlankOut => 'Blank out selection';

  @override
  String get barBlankOutNeedsSelection =>
      'Select the words to blank out first.';

  @override
  String get barOpenStudyPanel => 'Open study panel';

  @override
  String get barStudyEmpty =>
      'Study — tag a line Question or Definition to make a card';

  @override
  String barStudyDue(int due, int total, String countdown) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total cards',
      one: '1 card',
    );
    return '$due of $_temp0 due in this section$countdown';
  }

  @override
  String barStudyExamCountdown(String when) {
    return ' · exam $when';
  }

  @override
  String get barPlannerEmpty => 'Planner — every date you have, in one place';

  @override
  String barPlannerToday(int count) {
    return 'Planner — $count today';
  }

  @override
  String barPlannerOverdue(int count) {
    return 'Planner — $count today or overdue';
  }

  @override
  String barRemindersWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reminders',
      one: '1 reminder',
    );
    return '$_temp0 waiting';
  }

  @override
  String get barEscWhenDone => 'Esc when you are done';

  @override
  String barSaveFailed(String reason) {
    return 'That couldn\'t be saved: $reason';
  }

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get navSearchHint => 'Search or jump to…';

  @override
  String navNoMatches(String query) {
    return 'No matches for “$query”';
  }

  @override
  String get navInPageContent => 'In page content';

  @override
  String get navUntitled => 'Untitled';

  @override
  String get navNoSections => 'No sections yet.\nCreate one to get started.';

  @override
  String get navNewSection => 'New section';

  @override
  String navNewPageIn(String section) {
    return 'New page in $section';
  }

  @override
  String get navNoPages => 'No pages yet';

  @override
  String get navSection => 'Section';

  @override
  String get navNewSectionGroup => 'New section group';

  @override
  String get navRecycleBin => 'Recycle bin';

  @override
  String get navHome => 'Home';

  @override
  String get navHomeTip => 'Home — favourites & recents';

  @override
  String get navHomeEmpty =>
      'Nothing here yet.\n\nRight-click a page and choose Favourite to pin it; pages you visit show up under Recent.';

  @override
  String get navComingUp => 'COMING UP';

  @override
  String navAllCount(int total) {
    return 'All $total';
  }

  @override
  String get navOpen => 'Open';

  @override
  String get navExpand => 'Expand the navigator  (Ctrl+\\)';

  @override
  String get navCollapse => 'Collapse the navigator  (Ctrl+\\)';

  @override
  String get navNotebooksTip => 'Notebooks — switch, rename, duplicate, import';

  @override
  String get navDeletesSoon => 'Deletes soon';

  @override
  String navDeletesInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Deletes in $days days',
      one: 'Deletes in 1 day',
    );
    return '$_temp0';
  }

  @override
  String get navBinEmpty => 'Nothing deleted.';

  @override
  String navBinRetention(int days) {
    return 'Items here are permanently deleted after $days days.';
  }

  @override
  String get navBinNotebooks => 'Notebooks';

  @override
  String get navBinItems => 'Items';

  @override
  String get navRestore => 'Restore';

  @override
  String get navDeletePermanently => 'Delete permanently';

  @override
  String get navClose => 'Close';

  @override
  String get navDeleteForeverTitle => 'Delete permanently?';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '“$title” and all its pages will be removed for good. This can\'t be undone.$caveat';
  }

  @override
  String get navDeleteForever => 'Delete forever';

  @override
  String navLockedCannotDelete(String title) {
    return '“$title” is locked. Remove its passcode before deleting it.';
  }

  @override
  String navDeletedRestorable(String title) {
    return 'Deleted “$title” — restore it from the recycle bin.';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '“$title” is locked. It is hidden inside Openote, not encrypted in the file.';
  }

  @override
  String navPasscodeRemoved(String title) {
    return 'Passcode removed from “$title”.';
  }

  @override
  String navSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get navLinkCopied => 'Link copied — paste it into any page';

  @override
  String get navMoveSectionTo => 'Move section to…';

  @override
  String get navNoGroupTopLevel => '(No group — top level)';

  @override
  String get navSaveTemplateTitle => 'Save as template';

  @override
  String get navSave => 'Save';

  @override
  String get navTemplateNameHint => 'Template name';

  @override
  String navTemplateSaved(String name) {
    return 'Template \"$name\" saved';
  }

  @override
  String get navNoTemplates =>
      'No templates yet — \"Save as template…\" first.';

  @override
  String get navApplyTemplate => 'Apply template';

  @override
  String get navColour => 'Colour';

  @override
  String get navColourDefault => 'Default';

  @override
  String navExamCountdown(String when, String countdown) {
    return 'Exam $when · $countdown…';
  }

  @override
  String get navMenuMoveUp => 'Move up';

  @override
  String get navMenuMoveDown => 'Move down';

  @override
  String get navMenuNewPage => 'New page';

  @override
  String get navMenuMoveToGroup => 'Move to group…';

  @override
  String get navMenuSortAZ => 'Sort pages A→Z';

  @override
  String get navMenuSortEdited => 'Sort pages by last edited';

  @override
  String get navMenuExportSectionPdf => 'Export section as PDF…';

  @override
  String get navMenuPrintSection => 'Print section…';

  @override
  String get navMenuRemoveExam => 'Remove exam date';

  @override
  String get navMenuSetExam => 'Set exam date…';

  @override
  String get navMenuMakeSubpage => 'Make subpage';

  @override
  String get navMenuMoveBackOut => 'Move back out';

  @override
  String get navMenuRemoveFavourite => 'Remove from favourites';

  @override
  String get navMenuAddFavourite => 'Add to favourites';

  @override
  String get navMenuSharePdf => 'Share as PDF…';

  @override
  String get navMenuPrint => 'Print…';

  @override
  String get navMenuCopyLink => 'Copy link to page';

  @override
  String get navMenuRecentChanges => 'Recent changes…';

  @override
  String get navMenuSaveTemplate => 'Save as template…';

  @override
  String get navMenuApplyTemplate => 'Apply a template…';

  @override
  String get navMenuRemovePasscode => 'Remove passcode…';

  @override
  String get navMenuLock => 'Lock with a passcode…';

  @override
  String get navMenuDelete => 'Delete';

  @override
  String get commonOn => 'On';

  @override
  String get commonOff => 'Off';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDone => 'Done';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonOpenEllipsis => 'Open…';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsWriting => 'Writing and drawing';

  @override
  String get settingsSpellCheck => 'Spell check';

  @override
  String get settingsPenProximity => 'Pen near the page switches to inking';

  @override
  String get settingsConnections => 'Connections';

  @override
  String get settingsSync => 'Sync';

  @override
  String get settingsSyncHint =>
      'Back up and share this notebook — GitHub or a folder.';

  @override
  String get settingsAi => 'AI access';

  @override
  String get settingsAiOn =>
      'On — AI helpers on this computer can use your notes.';

  @override
  String get settingsAiOff => 'Off — connect Claude or other AI helpers.';

  @override
  String get settingsHelp => 'Help';

  @override
  String get settingsWelcomeTour => 'Welcome tour';

  @override
  String get settingsWelcomeTourHint =>
      'The three-minute version: the canvas, maths and ink, and where your notes live.';

  @override
  String get settingsShortcuts => 'Keyboard shortcuts';

  @override
  String get settingsShortcutsHint =>
      'Everything has a key — the full list.  (Ctrl+/)';

  @override
  String get settingsAbout => 'About';

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsCheckUpdates => 'Check for updates';

  @override
  String settingsUpToDate(String version) {
    return 'You\'re up to date ($version is the newest version).';
  }

  @override
  String get settingsWhatsNew => 'What\'s new';

  @override
  String get nbTitle => 'Notebooks';

  @override
  String nbOpenCount(int count) {
    return '$count open';
  }

  @override
  String nbInBin(int days) {
    return 'In the recycle bin · deleted after $days days';
  }

  @override
  String get nbImportInto => 'Import into a new notebook';

  @override
  String get nbNew => 'New';

  @override
  String get nbNewTitle => 'New notebook';

  @override
  String get nbCreate => 'Create';

  @override
  String get nbNameHint => 'Notebook name';

  @override
  String get nbImport => 'Import';

  @override
  String get nbRepair => 'Repair';

  @override
  String get nbGetStarted => 'Get started';

  @override
  String get nbImportOnepkg => 'OneNote notebook (.onepkg)';

  @override
  String get nbImportOne => 'OneNote section (.one)';

  @override
  String get nbImportMarkdown => 'Markdown folder';

  @override
  String get nbImportGit => 'From a git address';

  @override
  String get nbDuplicates =>
      'Possible duplicates · same title and same page count';

  @override
  String get nbDuplicatesHint =>
      'Keep the largest — an import interrupted part way through is the smaller one. Deleted copies go to the recycle bin.';

  @override
  String get nbOpenThis => 'Open this notebook';

  @override
  String get nbRename => 'Rename';

  @override
  String get nbDuplicate => 'Duplicate';

  @override
  String get nbMoveToBin => 'Move to recycle bin';

  @override
  String get nbConfirmBin =>
      'Move to the recycle bin? You can restore it from here.';

  @override
  String get nbOnePkgFileType => 'OneNote notebook package';

  @override
  String get nbImportBusy => 'An import is already running — one at a time.';

  @override
  String get nbImportStarted =>
      'Importing in the background — keep working, the card in the corner will say when it\'s done.';

  @override
  String nbImportedNamed(String name) {
    return 'Imported $name';
  }

  @override
  String get nbReadingFolder => 'Reading the folder…';

  @override
  String nbImportedProgress(String done) {
    return 'Imported $done';
  }

  @override
  String get nbNoMarkdown => 'No Markdown files found in that folder.';

  @override
  String nbImportedPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count pages',
      one: 'Imported 1 page',
    );
    return '$_temp0';
  }

  @override
  String get nbNeedsNativeCore =>
      'OneNote import needs the Rust core — build onote_core.dll and put it beside the app.';

  @override
  String get nbCheckingPages => 'Checking pages…';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return 'Checking page $done of $total…';
  }

  @override
  String get nbNothingToRepair =>
      'Nothing to repair — every page is already up to date.';

  @override
  String nbRepairedBoxes(int blocks) {
    String _temp0 = intl.Intl.pluralLogic(
      blocks,
      locale: localeName,
      other: '$blocks boxes',
      one: '1 box',
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
    return 'Repaired $boxes across $pages.';
  }

  @override
  String nbRepairFailed(String reason) {
    return 'Repair failed: $reason';
  }

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '$copies copies of \"$title\" · $pages pages each · $size would come back';
  }

  @override
  String get nbCoreMissing =>
      'OneNote import needs the Rust core — build onote_core.dll (see rust/onote_core/INTEGRATION.md).';

  @override
  String nbReadFileFailed(String reason) {
    return 'Couldn\'t read that file: $reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return 'That folder couldn\'t be imported: $reason';
  }

  @override
  String get nbOneFileEmpty =>
      'Couldn\'t read any content from that .one file.';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return 'Imported $what from OneNote.$strokeNote';
  }

  @override
  String nbImportedPagesProgress(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count pages…',
      one: 'Imported 1 page…',
    );
    return '$_temp0';
  }

  @override
  String mathSemanticLabel(String latex) {
    return 'Equation: $latex';
  }

  @override
  String get insertGroupWrite => 'Write';

  @override
  String get insertGroupBringIn => 'Bring in';

  @override
  String get insertGroupLinkUp => 'Link up';

  @override
  String get insertTextBox => 'Text box';

  @override
  String get insertEquation => 'Equation';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertTable => 'Table';

  @override
  String get insertTableFromFile => 'From a file';

  @override
  String get insertTableFromFileTip => 'CSV or Excel';

  @override
  String get insertCode => 'Code';

  @override
  String get insertBoard => 'Board';

  @override
  String get insertBoardTip => 'Columns of cards you move along';

  @override
  String get insertPicture => 'Picture';

  @override
  String get insertPdfSlides => 'PDF slides';

  @override
  String get insertPdfPrintout => 'Printout on this page';

  @override
  String get insertPdfPerSlide => 'One page per slide';

  @override
  String get insertPdfAsCard => 'As a card — open in a popup';

  @override
  String get insertVideo => 'Video';

  @override
  String get insertVideoTip => 'A lecture recording, or any web link';

  @override
  String get insertFile => 'File';

  @override
  String get insertFlashcardItem => 'Flashcard';

  @override
  String get insertPageLink => 'Page link';

  @override
  String get insertPageWindow => 'Page window';

  @override
  String get insertTemplate => 'Template';

  @override
  String get insertPickImages => 'Images';

  @override
  String get insertPickTables => 'Tables';

  @override
  String get insertPickVideo => 'Video and audio';

  @override
  String get tagTodo => 'To Do';

  @override
  String get tagImportant => 'Important';

  @override
  String get tagQuestion => 'Question';

  @override
  String get tagRemember => 'Remember';

  @override
  String get tagDefinition => 'Definition';

  @override
  String get tagIdea => 'Idea';

  @override
  String get tagCritical => 'Critical';

  @override
  String get tagContact => 'Contact';

  @override
  String get tagCustom => 'Tag';

  @override
  String get touchDrawAuto => 'Auto (pen takes over)';

  @override
  String get touchDrawAlways => 'Always';

  @override
  String get touchDrawNever => 'Never';

  @override
  String get insertLinkToPage => 'Link to page';

  @override
  String get insertPdfUnreadable => 'That PDF couldn\'t be read.';

  @override
  String insertPdfImported(int count, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count slides',
      one: 'Imported 1 slide',
    );
    return '$_temp0$where — pick the pen and write on them. The slide text is searchable.';
  }

  @override
  String get insertPdfOntoThisPage => ' onto this page';

  @override
  String insertPdfFailed(String reason) {
    return 'PDF import failed: $reason';
  }

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageAuto => 'Same as my computer';

  @override
  String get settingsLanguageHelp =>
      'Openote is translated by the people who use it. If yours is missing or wrong, it is one file — the link says how.';

  @override
  String get settingsLanguageContribute => 'How to add or fix a language';

  @override
  String get shellNothingReplaced => 'Nothing replaced';

  @override
  String shellReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Replaced $count occurrences',
      one: 'Replaced 1 occurrence',
    );
    return '$_temp0';
  }

  @override
  String get shellReplaceWith => 'Replace with…';

  @override
  String get shellReplace => 'Replace';

  @override
  String get shellReplaceAll => 'All';

  @override
  String get shellFindOnThisPage => 'Find on this page…';

  @override
  String get shellNoMatches => 'No matches';

  @override
  String get shellPreviousMatch => 'Previous match (Shift+Enter)';

  @override
  String get shellNextMatch => 'Next match (Enter)';

  @override
  String get shellCloseEsc => 'Close (Esc)';

  @override
  String get shellNoTags => 'No tags in this notebook yet.';

  @override
  String get shellTagsHint =>
      'Tags mark a line — to do, important, question, definition — so you can find it again, revise from it, or give it a deadline.';

  @override
  String get shellTagTheLine => 'Tag the line you are on';

  @override
  String get shellNoHeadings => 'No headings on this page.';

  @override
  String get shellHeadingsHint =>
      'Start a line with # to make a heading — the outline builds itself as you write.';

  @override
  String get shellLinkedFrom => 'Linked from';

  @override
  String get shellNoBacklinks => 'No pages link here yet.';

  @override
  String get shellLinksTo => 'Links to';

  @override
  String get shellNoLinks => 'This page links nowhere yet.';

  @override
  String get shellSavedLocally =>
      'This page is saved to your local .onote file.';

  @override
  String get shellSaving => 'Saving…';

  @override
  String get shellSavedOnDevice => 'Saved on this device';

  @override
  String shellRustLinked(String build) {
    return 'The Rust core (onote-core) is linked and computing this page\'s content hash on save.\n$build';
  }

  @override
  String get shellRustMissing =>
      'Running the pure-Dart engine. Build the onote-core library to link the Rust core.';

  @override
  String get shellCheatSheet =>
      'V select · T text · P pen · H highlight · E erase · Ctrl+Z undo · Ctrl+scroll zoom';

  @override
  String get shellEmptyTitle => 'An open page awaits';

  @override
  String get shellEmptyBody =>
      'Everything you make here lives on your device,\nin an open format you own.';

  @override
  String get shellCreateFirstPage => 'Create your first page';

  @override
  String get shellAlreadyUpToDate => 'Already up to date.';

  @override
  String shellPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pulled $count changes',
      one: 'Pulled 1 change',
    );
    return '$_temp0';
  }

  @override
  String shellPageLocked(String title) {
    return '“$title” is locked';
  }

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag  ($count)';
  }

  @override
  String get shellUnlock => 'Unlock';

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
