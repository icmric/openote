// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String atomNewerVersion(String version) {
    return 'Made in Openote $version';
  }

  @override
  String get atomNewerVersionUnknown => 'Made in a newer version of Openote';

  @override
  String get atomUpdateToView => 'Update Openote to view it';

  @override
  String get barBackToEquation => 'Back to the equation tools';

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get barBlankOut => 'Blank out selection';

  @override
  String get barBlankOutNeedsSelection =>
      'Select the words to blank out first.';

  @override
  String get barBold => 'Bold  (Ctrl+B)';

  @override
  String get barBulletList => 'Bullet list';

  @override
  String get barCheckbox => 'Checkbox';

  @override
  String get barClickIntoTextBox => 'Click into a text box to format';

  @override
  String get barDefinitionCard => 'Definition card';

  @override
  String get barDueDateChange => 'Change due date…';

  @override
  String get barDueDateClear => 'Clear the due date';

  @override
  String get barDueDatePickerConfirm => 'Set';

  @override
  String get barDueDatePickerTitle => 'Due date';

  @override
  String get barDueDateSet => 'Due date…';

  @override
  String get barEquationBadge => 'Equation';

  @override
  String get barEraserSplit => 'Splits strokes where you rub';

  @override
  String get barEraserWhole => 'Removes any stroke you touch';

  @override
  String get barEscWhenDone => 'Esc when you are done';

  @override
  String get barExport => 'Export';

  @override
  String get barExportCanvas => 'For Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => 'Just the drawing (.inkml)';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

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
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPdfPicture => 'PDF — picture of the page';

  @override
  String get barExportPrint => 'Print…';

  @override
  String get barExportTip => 'Export page…';

  @override
  String barExportedTo(String path) {
    return 'Exported to $path';
  }

  @override
  String get barFindOnPage => 'Find on page';

  @override
  String get barFindOnPageTip => 'Find on page  (Ctrl+F)';

  @override
  String get barFontSizeDefault => 'Default';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barHeading1 => 'Heading 1';

  @override
  String get barHighlight => 'Highlight';

  @override
  String get barInkColourTitle => 'Pen colour';

  @override
  String get barInkDefaultColour => 'Default ink — follows the page';

  @override
  String get barInkHighlighterColourTitle => 'Highlighter colour';

  @override
  String get barInkMoreColours => 'More colours…';

  @override
  String get barInkPickColour => 'Pick a colour off the page';

  @override
  String get barInkPickingHint =>
      'Click anything on the page to use its colour';

  @override
  String get barInlineCode => 'Inline code';

  @override
  String get barItalic => 'Italic  (Ctrl+I)';

  @override
  String get barLassoHint =>
      'Draw a loop around ink to select it — then drag or delete';

  @override
  String get barMakeCardFromLine => 'Make this line a flashcard';

  @override
  String get barNewCard => 'New flashcard';

  @override
  String get barNumberedList => 'Numbered list';

  @override
  String get barOpenStudyPanel => 'Open study panel';

  @override
  String get barPageOverview => 'Page overview';

  @override
  String get barPenProximity =>
      'Bringing the pen near the page switches to inking.\nPick another tool while the pen hovers and it sticks until the\npen leaves and comes back. The pen\'s tail (or its barrel\nbutton, held while drawing) erases.';

  @override
  String barPenSize(String size) {
    return 'Pen size $size';
  }

  @override
  String get barPenSizeExact => 'Exact size…';

  @override
  String get barPlanner => 'Planner';

  @override
  String get barPlannerEmpty => 'Planner — every date you have, in one place';

  @override
  String barPlannerOverdue(int count) {
    return 'Planner — $count today or overdue';
  }

  @override
  String barPlannerToday(int count) {
    return 'Planner — $count today';
  }

  @override
  String get barQuestionCard => 'Question card';

  @override
  String get barQuote => 'Quote';

  @override
  String get barRedo => 'Redo  (Ctrl+Y)';

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
  String barSaveFailed(String reason) {
    return 'That couldn\'t be saved: $reason';
  }

  @override
  String get barSettings => 'Settings';

  @override
  String get barSettingsTip => 'Settings…';

  @override
  String get barStrikethrough => 'Strikethrough';

  @override
  String get barStudy => 'Study';

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
  String get barStudyEmpty =>
      'Study — tag a line Question or Definition to make a card';

  @override
  String barStudyExamCountdown(String when) {
    return ' · exam $when';
  }

  @override
  String get barTabDraw => 'Draw';

  @override
  String get barTabHome => 'Home';

  @override
  String get barTabInsert => 'Insert';

  @override
  String get barTabPage => 'Page';

  @override
  String get barTagLine => 'Tag this line (To Do, Important, Question…)';

  @override
  String barTagged(String tags) {
    return 'Tagged: $tags';
  }

  @override
  String get barTextColour => 'Apply text colour';

  @override
  String get barTextFont => 'Text font…';

  @override
  String get barTextSize => 'Text size (points)';

  @override
  String get barTextSizeDisabled => 'Click into a text box to change its size';

  @override
  String get barToolEraser => 'Eraser  (E)';

  @override
  String get barToolHighlighter => 'Highlighter  (H)';

  @override
  String get barToolLasso => 'Lasso-select ink';

  @override
  String get barToolPen => 'Pen  (P)';

  @override
  String get barToolSelect => 'Select / move  (V)';

  @override
  String get barToolText => 'Text  (T)';

  @override
  String get barUnderline => 'Underline  (Ctrl+U)';

  @override
  String get barUndo => 'Undo  (Ctrl+Z)';

  @override
  String barUpdateTo(String version) {
    return 'Update to $version…';
  }

  @override
  String get canvasDeleteSelection => 'Delete  (Del)';

  @override
  String get canvasGroupSelection => 'Group  (Ctrl+G)';

  @override
  String get canvasUngroupSelection => 'Ungroup  (Ctrl+Shift+G)';

  @override
  String get commandNotInDemo => 'Not in the web demo';

  @override
  String get commonBack => 'Back';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonDetailsAdvanced => 'Details (advanced)';

  @override
  String get commonDone => 'Done';

  @override
  String get commonNext => 'Next';

  @override
  String get commonOff => 'Off';

  @override
  String get commonOn => 'On';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonOpenEllipsis => 'Open…';

  @override
  String get commonSkip => 'Skip';

  @override
  String importBringingIn(String name, int done, int total) {
    return 'Bringing in \"$name\" — $done of $total pages…';
  }

  @override
  String get importCancelledLabel => 'Import cancelled.';

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count pages.',
      one: 'Imported 1 page.',
    );
    return '$_temp0';
  }

  @override
  String importDoneButLost(int count, String detail) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count pages, but could not bring $detail.',
      one: 'Imported 1 page, but could not bring $detail.',
    );
    return '$_temp0';
  }

  @override
  String get importEmptyNotebook => 'That notebook had no pages in it.';

  @override
  String get importFailedGeneric => 'That notebook could not be brought over.';

  @override
  String importFoundPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages to bring over. Starting now…',
      one: '1 page to bring over. Starting now…',
    );
    return '$_temp0';
  }

  @override
  String importFoundSections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $count sections — seeing what is in them…',
      one: 'Found 1 section — seeing what is in it…',
    );
    return '$_temp0';
  }

  @override
  String get importLookingAround => 'Looking through your notebook…';

  @override
  String importPartialBroke(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Something went wrong partway through, but the $count pages already brought over are here. Openote will finish the rest on its own later.',
      one:
          'Something went wrong partway through, but the 1 page already brought over is here. Openote will finish the rest on its own later.',
    );
    return '$_temp0';
  }

  @override
  String importPartialThrottled(String detail, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$detail The $count pages already brought over are here. Openote will finish the rest on its own later, or you can start it again whenever you like.',
      one:
          '$detail The 1 page already brought over is here. Openote will finish the rest on its own later, or you can start it again whenever you like.',
    );
    return '$_temp0';
  }

  @override
  String get importReading => 'Reading the notebook…';

  @override
  String get importSigningIn => 'Signing in to OneNote…';

  @override
  String importStoppedKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Stopped — kept the $count pages already brought in. You can finish it whenever you like.',
      one:
          'Stopped — kept the 1 page already brought in. You can finish it whenever you like.',
    );
    return '$_temp0';
  }

  @override
  String get importStopping => 'Stopping…';

  @override
  String importThrottled(int seconds) {
    return 'Microsoft has asked Openote to slow down — carrying on in ${seconds}s. Nothing already brought in is lost.';
  }

  @override
  String get importThrottledSoon =>
      'Microsoft has asked Openote to slow down — carrying on in a moment. Nothing already brought in is lost.';

  @override
  String importWritingPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Importing $count pages…',
      one: 'Importing 1 page…',
    );
    return '$_temp0';
  }

  @override
  String importWritingSection(String name) {
    return 'Importing \"$name\"…';
  }

  @override
  String get insertBoard => 'Board';

  @override
  String get insertBoardTip => 'Columns of cards you move along';

  @override
  String get insertCode => 'Code';

  @override
  String get insertEquation => 'Equation';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertFile => 'File';

  @override
  String get insertFlashcardItem => 'Flashcard';

  @override
  String get insertGroupBringIn => 'Bring in';

  @override
  String get insertGroupLinkUp => 'Link up';

  @override
  String get insertGroupWrite => 'Write';

  @override
  String get insertLinkToPage => 'Link to page';

  @override
  String get insertPageLink => 'Link…';

  @override
  String get insertPageWindow => 'Page window';

  @override
  String get insertPdfAsCard => 'As a card — open in a popup';

  @override
  String insertPdfFailed(String reason) {
    return 'PDF import failed: $reason';
  }

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
  String get insertPdfPerSlide => 'One page per slide';

  @override
  String get insertPdfPrintout => 'Printout on this page';

  @override
  String get insertPdfSlides => 'PDF slides';

  @override
  String get insertPdfUnreadable => 'That PDF couldn\'t be read.';

  @override
  String get insertPickImages => 'Images';

  @override
  String get insertPickTables => 'Tables';

  @override
  String get insertPickVideo => 'Video and audio';

  @override
  String get insertPicture => 'Picture';

  @override
  String get insertTable => 'Table';

  @override
  String get insertTableFromFile => 'From a file';

  @override
  String get insertTableFromFileTip => 'CSV or Excel';

  @override
  String get insertTextBox => 'Text box';

  @override
  String get insertVideo => 'Video';

  @override
  String get insertVideoTip => 'A lecture recording, or any web link';

  @override
  String get linkEdit => 'Edit link…';

  @override
  String mathSemanticLabel(String latex) {
    return 'Equation: $latex';
  }

  @override
  String navAllCount(int total) {
    return 'All $total';
  }

  @override
  String get navBinEmpty => 'Nothing deleted.';

  @override
  String get navBinItems => 'Items';

  @override
  String get navBinNotebooks => 'Notebooks';

  @override
  String navBinRetention(int days) {
    return 'Items here are permanently deleted after $days days.';
  }

  @override
  String get navClose => 'Close';

  @override
  String get navCollapse => 'Collapse the navigator  (Ctrl+\\)';

  @override
  String get navColour => 'Colour';

  @override
  String get navColourDefault => 'Default';

  @override
  String get navComingUp => 'COMING UP';

  @override
  String get navDeleteForever => 'Delete forever';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '“$title” and all its pages will be removed for good. This can\'t be undone.$caveat';
  }

  @override
  String get navDeleteForeverTitle => 'Delete permanently?';

  @override
  String get navDeletePermanently => 'Delete permanently';

  @override
  String navDeletedGroup(String title) {
    return 'Moved group “$title” to the bin';
  }

  @override
  String navDeletedPage(String title) {
    return 'Moved page “$title” to the bin';
  }

  @override
  String navDeletedSection(String title) {
    return 'Moved section “$title” to the bin';
  }

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
  String get navDeletesSoon => 'Deletes soon';

  @override
  String navExamCountdown(String when, String countdown) {
    return 'Exam $when · $countdown…';
  }

  @override
  String get navExpand => 'Expand the navigator  (Ctrl+\\)';

  @override
  String get navSectionsHeader => 'Sections';

  @override
  String get navNewSectionOrGroup => 'New section or group';

  @override
  String get dropMoveAbove => 'Move above';

  @override
  String get dropMoveBelow => 'Move below';

  @override
  String get dropMakeSubpage => 'Make a subpage';

  @override
  String get dropGroupTogether => 'Group together';

  @override
  String get dropMoveIntoGroup => 'Move into group';

  @override
  String get dropMoveToSection => 'Move to this section';

  @override
  String get navBinEmptyAction => 'Empty';

  @override
  String get navBinEmptyTitle => 'Empty the recycle bin?';

  @override
  String get navBinEmptyBody =>
      'Everything in it will be removed for good. This can\'t be undone.';

  @override
  String get navBinEmptySharedNote =>
      'Notebooks in a shared folder are only removed from this computer.';

  @override
  String navBinDeleteOneBody(String title) {
    return '“$title” will be removed for good. This can\'t be undone.';
  }

  @override
  String get navBinKindPage => 'Page';

  @override
  String get navBinKindSection => 'Section';

  @override
  String get navBinKindGroup => 'Group';

  @override
  String get navBinKindNotebook => 'Notebook';

  @override
  String navBinItemLine(String kind, String when) {
    return '$kind · $when';
  }

  @override
  String get navBinWhenToday => 'today';

  @override
  String get navBinWhenYesterday => 'yesterday';

  @override
  String navBinWhenDaysAgo(int days) {
    return '$days days ago';
  }

  @override
  String get reviewTitle => 'Review writing';

  @override
  String reviewChip(int count) {
    return '$count to review';
  }

  @override
  String get reviewChipClear => 'No writing issues';

  @override
  String get reviewTooltip => 'Review writing (F7)';

  @override
  String get reviewChecking => 'Checking your writing…';

  @override
  String fixNoticeRevert(String word) {
    return 'Put back “$word”';
  }

  @override
  String reviewSubtitle(int count, String language) {
    return 'On this page · $count to review · $language';
  }

  @override
  String get reviewSpelling => 'Spelling';

  @override
  String get reviewGrammar => 'Grammar';

  @override
  String get reviewPunctuation => 'Punctuation';

  @override
  String get reviewFixAll => 'Fix all';

  @override
  String get reviewAccept => 'Accept';

  @override
  String get reviewIgnore => 'Ignore';

  @override
  String get reviewAddToDictionary => 'Add to dictionary';

  @override
  String get reviewNotInDictionary => 'Not in the dictionary';

  @override
  String get reviewRemove => 'Remove';

  @override
  String get reviewAllClear => 'Nothing to review on this page.';

  @override
  String reviewFixedSpelling(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fixed $count spelling mistakes',
      one: 'Fixed 1 spelling mistake',
    );
    return '$_temp0';
  }

  @override
  String reviewFixedGrammar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fixed $count grammar mistakes',
      one: 'Fixed 1 grammar mistake',
    );
    return '$_temp0';
  }

  @override
  String reviewFixedPunctuation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fixed $count punctuation mistakes',
      one: 'Fixed 1 punctuation mistake',
    );
    return '$_temp0';
  }

  @override
  String get navHideSections => 'Hide the section list';

  @override
  String get navRecent => 'Recent';

  @override
  String get navHomeEmpty =>
      'Nothing here yet.\n\nRight-click a page and choose Favourite to pin it; pages you visit show up under Recent.';

  @override
  String get navRecentTip => 'Recent pages and favourites';

  @override
  String get navInPageContent => 'In page content';

  @override
  String get navLinkCopied => 'Link copied — paste it into any page';

  @override
  String navLockedCannotDelete(String title) {
    return '“$title” is locked. Remove its passcode before deleting it.';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '“$title” is locked. It is hidden inside Openote, not encrypted in the file.';
  }

  @override
  String get navMenuAddFavourite => 'Add to favourites';

  @override
  String get navMenuCopyLink => 'Copy link to page';

  @override
  String get navMenuDelete => 'Delete';

  @override
  String get navMenuDuplicate => 'Duplicate';

  @override
  String get navMenuExportSectionPdf => 'Export section as PDF…';

  @override
  String get navMenuLock => 'Lock with a passcode…';

  @override
  String get navMenuMakeSubpage => 'Make subpage';

  @override
  String get navMenuMoveBackOut => 'Move back out';

  @override
  String get navMenuMoveDown => 'Move down';

  @override
  String get navMenuMoveToGroup => 'Move to group…';

  @override
  String get navMenuMoveUp => 'Move up';

  @override
  String get navMenuNewPage => 'New page';

  @override
  String get navMenuPrint => 'Print…';

  @override
  String get navMenuPrintSection => 'Print section…';

  @override
  String get navMenuRecentChanges => 'Recent changes…';

  @override
  String get navMenuRemoveExam => 'Remove exam date';

  @override
  String get navMenuRemoveFavourite => 'Remove from favourites';

  @override
  String get navMenuRemovePasscode => 'Remove passcode…';

  @override
  String get navMenuRename => 'Rename';

  @override
  String get navMenuSetExam => 'Set exam date…';

  @override
  String get navMenuSharePdf => 'Share as PDF…';

  @override
  String get navMenuSortAZ => 'Sort pages A→Z';

  @override
  String get navMenuSortEdited => 'Sort pages by last edited';

  @override
  String get navMoveSectionTo => 'Move section to…';

  @override
  String navNewPageIn(String section) {
    return 'New page in $section';
  }

  @override
  String get navNewSection => 'New section';

  @override
  String get navNewSectionGroup => 'New group';

  @override
  String get navNoGroupTopLevel => '(No group — top level)';

  @override
  String navNoMatches(String query) {
    return 'No matches for “$query”';
  }

  @override
  String get navNoPages => 'No pages yet';

  @override
  String get navNoSections => 'No sections yet.\nCreate one to get started.';

  @override
  String get navNotebooksTip => 'Notebooks — switch, rename, duplicate, import';

  @override
  String get navOpen => 'Open';

  @override
  String navPasscodeRemoved(String title) {
    return 'Passcode removed from “$title”.';
  }

  @override
  String get navRecycleBin => 'Recycle bin';

  @override
  String get navRestore => 'Restore';

  @override
  String get navSave => 'Save';

  @override
  String navSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get navSearchHint => 'Search or jump to…';

  @override
  String get navSection => 'Section';

  @override
  String get navShowSections => 'Show the section list';

  @override
  String get navUndo => 'Undo';

  @override
  String get navUntitled => 'Untitled';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return 'Checking page $done of $total…';
  }

  @override
  String get nbCheckingPages => 'Checking pages…';

  @override
  String get nbConfirmBin =>
      'Move to the recycle bin? You can restore it from here.';

  @override
  String get nbConfirmBinShared =>
      'This notebook is in a shared folder. Removing it from this computer leaves it in the folder and on your other devices — add it back any time with Open.';

  @override
  String get nbRemoveFromComputer => 'Remove from this computer';

  @override
  String get nbDeleteEverywhere => 'Delete everywhere…';

  @override
  String nbDeleteEverywhereTitle(String title) {
    return 'Delete “$title” everywhere?';
  }

  @override
  String get nbDeleteEverywhereBody =>
      'This deletes it from the shared folder, so it is gone from every device that uses it. This can\'t be undone.';

  @override
  String get nbDeleteEverywhereConfirm => 'Delete everywhere';

  @override
  String nbRemoveSharedTitle(String title) {
    return 'Remove “$title” from this computer?';
  }

  @override
  String get nbRemoveSharedBody =>
      'It stays in the shared folder and on your other devices. Add it back any time with Open.';

  @override
  String get nbCoreMissing =>
      'OneNote import needs the Rust core — build onote_core.dll (see rust/onote_core/INTEGRATION.md).';

  @override
  String get nbCreate => 'Create';

  @override
  String get nbDuplicate => 'Duplicate';

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '$copies copies of \"$title\" · $pages pages each · $size would come back';
  }

  @override
  String get nbDuplicates =>
      'Possible duplicates · same title and same page count';

  @override
  String get nbDuplicatesHint =>
      'Keep the largest — an import interrupted part way through is the smaller one. Deleted copies go to the recycle bin.';

  @override
  String get nbGetStarted => 'Get started';

  @override
  String get nbImport => 'Import';

  @override
  String get nbImportBusy => 'An import is already running — one at a time.';

  @override
  String get nbImportGit => 'From a git address';

  @override
  String get nbImportDriveFolder => 'Open from a Drive folder';

  @override
  String get nbImportInto => 'Import into a new notebook';

  @override
  String get nbImportMarkdown => 'Markdown folder';

  @override
  String get nbImportOne => 'OneNote section (.one)';

  @override
  String get nbImportOnepkg => 'OneNote notebook (.onepkg)';

  @override
  String get nbImportStarted =>
      'Importing in the background — keep working, the card in the corner will say when it\'s done.';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return 'Imported $what from OneNote.$strokeNote';
  }

  @override
  String nbImportedNamed(String name) {
    return 'Imported $name';
  }

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
  String nbImportedProgress(String done) {
    return 'Imported $done';
  }

  @override
  String nbInBin(int days) {
    return 'In the recycle bin · deleted after $days days';
  }

  @override
  String get nbMoveToBin => 'Move to recycle bin';

  @override
  String get nbNameHint => 'Notebook name';

  @override
  String get nbNeedsNativeCore =>
      'OneNote import needs the Rust core — build onote_core.dll and put it beside the app.';

  @override
  String get nbNew => 'New';

  @override
  String get nbNewTitle => 'New notebook';

  @override
  String get nbNoMarkdown => 'No Markdown files found in that folder.';

  @override
  String get nbNothingToRepair =>
      'Nothing to repair — every page is already up to date.';

  @override
  String get nbOneFileEmpty =>
      'Couldn\'t read any content from that .one file.';

  @override
  String get nbOnePkgFileType => 'OneNote notebook package';

  @override
  String nbOpenCount(int count) {
    return '$count open';
  }

  @override
  String get nbOpenThis => 'Open this notebook';

  @override
  String nbReadFileFailed(String reason) {
    return 'Couldn\'t read that file: $reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return 'That folder couldn\'t be imported: $reason';
  }

  @override
  String get nbReadingFolder => 'Reading the folder…';

  @override
  String get nbRename => 'Rename';

  @override
  String get nbRepair => 'Repair';

  @override
  String nbRepairFailed(String reason) {
    return 'Repair failed: $reason';
  }

  @override
  String nbRepaired(String boxes, String pages) {
    return 'Repaired $boxes across $pages.';
  }

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
  String get nbTitle => 'Notebooks';

  @override
  String objectRowBackground(String kind) {
    return 'Background: $kind';
  }

  @override
  String get objectRowBackgroundBlank => 'blank';

  @override
  String get objectRowBackgroundDotted => 'dotted';

  @override
  String get objectRowBackgroundGrid => 'grid';

  @override
  String get objectRowBackgroundRuled => 'ruled';

  @override
  String get objectRowCanvasMode => 'Canvas mode: boundless — click for pages';

  @override
  String get objectRowCharacters => 'Characters';

  @override
  String get objectRowCharactersNoSpaces => 'Without spaces';

  @override
  String get objectRowLandscape => 'Landscape';

  @override
  String get objectRowLandscapeSuffix => ' landscape';

  @override
  String objectRowMinutes(int n) {
    return '$n min';
  }

  @override
  String objectRowPageMode(String paper, String landscape) {
    return 'Page mode: $paper$landscape — click for canvas';
  }

  @override
  String get objectRowPaperSize => 'Paper size';

  @override
  String get objectRowReadingTime => 'Reading time';

  @override
  String get objectRowSnapOff => 'Snap to grid: OFF — free placement';

  @override
  String get objectRowSnapOn => 'Snap to grid: ON (grid shows while dragging)';

  @override
  String get objectRowWordCount =>
      'Words on this page — click for characters and reading time';

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
  String get objectRowWords => 'Words';

  @override
  String get objectRowZoomFit => 'Zoom to fit content';

  @override
  String get objectRowZoomIn => 'Zoom in  (Ctrl+=)';

  @override
  String get objectRowZoomOut => 'Zoom out  (Ctrl+-)';

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent%';
  }

  @override
  String get objectRowZoomReset =>
      'Back to 100% and the top of the page  (Ctrl+0)';

  @override
  String get onboardingCloudAction => 'Sign in';

  @override
  String get onboardingCloudBody =>
      'Sign in to Microsoft and pick a notebook. Nothing to export first, and it works on any computer.';

  @override
  String get onboardingCloudTitle => 'Bring notes over from OneNote';

  @override
  String get onboardingExportMacNote =>
      'On a Mac, or with only the Store version: export one section at a time as .one, or ask a Windows machine to make the .onepkg. Openote never signs into your Microsoft account — it only reads the file you hand it.';

  @override
  String get onboardingExportSteps =>
      '1. Open OneNote for Windows (the desktop app — the Store and web versions cannot export).\n2. Let the notebook finish syncing, so everything is on this machine.\n3. File ▸ Export ▸ Notebook ▸ OneNote Package (*.onepkg), then Export.\n4. Come back here and choose that file.';

  @override
  String get onboardingExportTitle => 'Exporting from OneNote';

  @override
  String get onboardingFreshAction => 'Start fresh';

  @override
  String get onboardingFreshBody =>
      'An empty notebook, ready to write in. You can always bring notes over later.';

  @override
  String get onboardingFreshTitle => 'Start a fresh notebook';

  @override
  String get onboardingImportDone => 'Your notebook is ready';

  @override
  String get onboardingImportRunning =>
      'Keep going — this runs in the background, and the card in the corner will say when it\'s done.';

  @override
  String onboardingImportingFile(String fileName) {
    return 'Importing $fileName';
  }

  @override
  String get onboardingNoNativeCore =>
      'OneNote import needs the native core, which this build does not include.';

  @override
  String get onboardingOneNoteAction => 'Choose file…';

  @override
  String get onboardingOneNoteBody =>
      'Pages, formatting, images, ink and tags from a .onepkg. Runs in the background — keep going while it works.';

  @override
  String get onboardingOneNoteHideSteps => 'Hide steps';

  @override
  String get onboardingOneNoteHowTo => 'How do I export?';

  @override
  String get onboardingOneNoteTitle => 'Bring notes over from OneNote';

  @override
  String get onboardingOnePkgFileType => 'OneNote notebook package';

  @override
  String get onboardingOpenFailed => 'Openote couldn\'t open that notebook.';

  @override
  String onboardingReadFailed(String reason) {
    return 'Couldn\'t read that file: $reason';
  }

  @override
  String get onboardingStartWriting => 'Start writing';

  @override
  String get onboardingStep1Body =>
      'Click anywhere and start typing — a box appears where you clicked, and only once you type. Move one by the bar along its top, and drag pictures in from anywhere.';

  @override
  String get onboardingStep1Title => 'The page is a canvas';

  @override
  String get onboardingStep2Body =>
      'Type 1/2 or press Alt+= and it builds up as real notation as you write, in a box of its own or mid-sentence. The Draw tab takes a pen, a finger or the mouse.';

  @override
  String get onboardingStep2Title => 'Maths and drawing, in with the words';

  @override
  String get onboardingStep3Body =>
      'One open, readable file per notebook — no account, no lock-in. Put it in a folder your cloud already keeps in step and every device stays together.';

  @override
  String get onboardingStep3Title => 'Your notes are a file you own';

  @override
  String get onboardingSyncAction => 'Set up…';

  @override
  String get onboardingSyncBodyAlso =>
      'Not one of the above? Choose the folder yourself.';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive, OneDrive, iCloud, Dropbox, Syncthing, a NAS — or a GitHub repository.';

  @override
  String get onboardingSyncTitle => 'Sync with another device';

  @override
  String get oneNoteCloudContinue => 'Continue with Microsoft';

  @override
  String get oneNoteCloudEmpty => 'No notebooks were found on this account.';

  @override
  String get oneNoteCloudIntro =>
      'Openote will read your notebooks from OneNote. It cannot change them.';

  @override
  String get oneNoteCloudLoading => 'Looking for your notebooks…';

  @override
  String get oneNoteCloudNoInk =>
      'Tables are fitted to the page rather than kept at their exact widths, and text colour and font are not carried over.';

  @override
  String get oneNoteCloudOther => 'Use a different account';

  @override
  String get oneNoteCloudSignIn => 'Sign in to Microsoft';

  @override
  String get oneNoteCloudSigningIn => 'Waiting for your browser…';

  @override
  String get oneNoteCloudTitle => 'Bring a notebook over from OneNote';

  @override
  String get oneNoteFileBody =>
      'No signing in, and the closest copy: tables keep their exact widths. You will need OneNote on Windows to export the notebook first.';

  @override
  String get oneNoteFileTitle => 'Use a file you exported';

  @override
  String get oneNotePickTitle => 'Which notebook?';

  @override
  String get oneNoteSignInBody =>
      'Pick a notebook and it comes straight over, with nothing to export first. Works on any computer.';

  @override
  String get penButtonEraser => 'Eraser';

  @override
  String get penButtonLasso => 'Lasso';

  @override
  String get penButtonNothing => 'Nothing';

  @override
  String get penButtonSelect => 'Select';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAi => 'AI access';

  @override
  String get settingsAiOff => 'Off — connect Claude or other AI helpers.';

  @override
  String get settingsAiOn => 'On — AI on this computer can read your notes.';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsCheckUpdates => 'Check for updates';

  @override
  String get settingsConnections => 'Connections';

  @override
  String get settingsDiagnostics => 'Diagnostics';

  @override
  String get settingsHelp => 'Help';

  @override
  String get settingsUiScale => 'Interface size';

  @override
  String get settingsUiScaleHint => 'Makes the whole window bigger or smaller.';

  @override
  String settingsUiScaleLimited(String size) {
    return 'Showing $size: this window is too small for more.';
  }

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageAuto => 'System default';

  @override
  String get settingsLanguageContribute => 'How to add or fix a language';

  @override
  String get settingsPenAndTouch => 'Pen and touch';

  @override
  String get settingsPenButton => 'The pen\'s side button';

  @override
  String get settingsPenButtonHint => 'Held down, it borrows that tool.';

  @override
  String get settingsPenTest => 'Pen and touch test';

  @override
  String get settingsPenTestHint => 'What your pen and its buttons report.';

  @override
  String get settingsShortcuts => 'Keyboard shortcuts';

  @override
  String get settingsShortcutsHint => 'Ctrl+/';

  @override
  String get settingsReportProblem => 'Report a problem or share an idea';

  @override
  String get settingsReportProblemHint =>
      'Opens GitHub. You need a free GitHub account.';

  @override
  String get settingsSpellCheck => 'Spell check';

  @override
  String get settingsSync => 'Sync';

  @override
  String get settingsSyncHint => 'Back up this notebook to GitHub or a folder.';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTouchDrawing => 'Draw with your finger';

  @override
  String get settingsTouchDrawingHint => 'Two fingers always pan and zoom.';

  @override
  String settingsUpToDate(String version) {
    return 'You\'re up to date ($version is the newest version).';
  }

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsWelcomeTour => 'Welcome tour';

  @override
  String get settingsWelcomeTourHint =>
      'Three minutes on how the canvas works.';

  @override
  String get settingsWhatsNew => 'What\'s new';

  @override
  String get settingsWriting => 'Writing and drawing';

  @override
  String get shellAlreadyUpToDate => 'Already up to date.';

  @override
  String get shellCheatSheet =>
      'V select · T text · P pen · H highlight · E erase · Ctrl+Z undo · Ctrl+scroll zoom';

  @override
  String get shellCloseEsc => 'Close (Esc)';

  @override
  String get shellCreateFirstPage => 'Create your first page';

  @override
  String get shellDemoNothingSaved => 'Demo — nothing is saved';

  @override
  String get shellEmptyBody =>
      'Everything you make here lives on your device,\nin an open format you own.';

  @override
  String get shellEmptyTitle => 'An open page awaits';

  @override
  String get shellFindOnThisPage => 'Find on this page…';

  @override
  String get shellHeadingsHint =>
      'Start a line with # to make a heading — the outline builds itself as you write.';

  @override
  String get shellLinkedFrom => 'Linked from';

  @override
  String get shellLinksTo => 'Links to';

  @override
  String get shellNextMatch => 'Next match (Enter)';

  @override
  String get shellNoBacklinks => 'No pages link here yet.';

  @override
  String get shellNoHeadings => 'No headings on this page.';

  @override
  String get shellNoLinks => 'This page links nowhere yet.';

  @override
  String get shellNoMatches => 'No matches';

  @override
  String get shellNoTags => 'No tags in this notebook yet.';

  @override
  String get shellNothingReplaced => 'Nothing replaced';

  @override
  String shellPageLocked(String title) {
    return '“$title” is locked';
  }

  @override
  String get shellPreviousMatch => 'Previous match (Shift+Enter)';

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
  String get shellReplace => 'Replace';

  @override
  String get shellReplaceAll => 'All';

  @override
  String get shellReplaceWith => 'Replace with…';

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
  String shellRustLinked(String build) {
    return 'The Rust core (onote-core) is linked and computing this page\'s content hash on save.\n$build';
  }

  @override
  String get shellRustMissing =>
      'Running the pure-Dart engine. Build the onote-core library to link the Rust core.';

  @override
  String get shellSavedLocally =>
      'This page is saved to your local .onote file.';

  @override
  String get shellSavedOnDevice => 'Saved on this device';

  @override
  String get shellSaving => 'Saving…';

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag  ($count)';
  }

  @override
  String get shellTagTheLine => 'Tag the line you are on';

  @override
  String get shellTagsHint =>
      'Tags mark a line — to do, important, question, definition — so you can find it again, revise from it, or give it a deadline.';

  @override
  String get shellUnlock => 'Unlock';

  @override
  String get tableColumnLeft => 'Insert column left';

  @override
  String get tableColumnRight => 'Insert column right';

  @override
  String get tableDeleteColumn => 'Delete column';

  @override
  String get tableDeleteRow => 'Delete row';

  @override
  String get tableRowAbove => 'Insert row above';

  @override
  String get tableRowBelow => 'Insert row below';

  @override
  String get tagContact => 'Contact';

  @override
  String get tagCritical => 'Critical';

  @override
  String get tagCustom => 'Tag';

  @override
  String get tagDefinition => 'Definition';

  @override
  String get tagIdea => 'Idea';

  @override
  String get tagImportant => 'Important';

  @override
  String get tagQuestion => 'Question';

  @override
  String get tagRemember => 'Remember';

  @override
  String get tagTodo => 'To Do';

  @override
  String get touchDrawAlways => 'Always';

  @override
  String get touchDrawAuto => 'Auto (pen takes over)';

  @override
  String get touchDrawNever => 'Never';

  @override
  String updateAvailable(String version) {
    return 'Openote $version is available';
  }

  @override
  String updateYouHave(String version) {
    return 'You have $version.';
  }

  @override
  String get updateDownloading => 'Downloading…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateSavedClosing =>
      'Your notes are saved. Openote will close, update itself, and reopen.';

  @override
  String get updateWillRestart =>
      'Your notes will be saved first. Openote closes while the update installs, then reopens by itself.';

  @override
  String get updateInstallYourself =>
      'You’ll need to download and install it yourself.';

  @override
  String get updateNotNow => 'Not now';

  @override
  String get updateNow => 'Update now';

  @override
  String get updateDownload => 'Download';

  @override
  String get settingsGrammarCheck => 'Check grammar';

  @override
  String get settingsAutoCorrect => 'Fix small typos as I type';

  @override
  String get settingsAutoCapitalize => 'Capitalise sentences';

  @override
  String get settingsSpellLanguage => 'Spelling language';

  @override
  String get settingsSpellLanguageSystem => 'System default';

  @override
  String get settingsSpellLanguageOther => 'Other language (not checked)';

  @override
  String get settingsEnglishAU => 'English (Australia)';

  @override
  String get settingsEnglishGB => 'English (United Kingdom)';

  @override
  String get settingsEnglishUS => 'English (United States)';

  @override
  String get settingsEnglishCA => 'English (Canada)';

  @override
  String get settingsEnglishIN => 'English (India)';

  @override
  String get settingsWritingEnglishOnly =>
      'Grammar, typo fixes and capital letters work in English for now. In any other language they stay off.';

  @override
  String get barTabWrite => 'Write';

  @override
  String get insertNotYet => 'Not yet';

  @override
  String get barHideKeyboard => 'Put the keyboard away';

  @override
  String get pageSheetBlank => 'Blank';

  @override
  String get pageSheetGrid => 'Grid';

  @override
  String get pageSheetDots => 'Dots';

  @override
  String get pageSheetRuled => 'Ruled';

  @override
  String get pageSheetPaper => 'Paper';

  @override
  String get pageSheetCanvas => 'Canvas';

  @override
  String get pageSheetSnap => 'Snap';

  @override
  String get pageSheetFit => 'Fit';

  @override
  String get navOpening => 'Opening this notebook…';

  @override
  String get openFolderTitle => 'Open a notebook from a folder';

  @override
  String get openFolderBody =>
      'Choose the folder your notebooks are kept in, such as one in Google Drive, OneDrive or Dropbox. Openote looks inside it for notebooks.';

  @override
  String get openFolderChoose => 'Choose a folder…';

  @override
  String get openFolderNone =>
      'No notebooks were found there. Choose the folder that holds your notebooks, or a notebook’s own folder (its name ends in .onotebook).';

  @override
  String get openFolderLooking => 'Looking for notebooks…';

  @override
  String get openFolderAndroidHint =>
      'Choose the folder your notebooks are in. In Google Drive that is usually the one called “Openote”. Then tap “Use this folder”.';

  @override
  String get openFolderFound => 'Notebooks found';

  @override
  String protectLockTitle(String title) {
    return 'Lock “$title”';
  }

  @override
  String protectLockedTitle(String title) {
    return '“$title” is locked';
  }

  @override
  String get protectBetaHeadline =>
      'Beta: this hides the page in Openote, it does not encrypt it yet.';

  @override
  String get protectBetaBody =>
      'For now, anyone with your notebook file can still read the page, and a forgotten passcode cannot be recovered. Real encryption is planned.';

  @override
  String get protectPasscode => 'Passcode';

  @override
  String get protectPasscodeAgain => 'Passcode again';

  @override
  String get protectAskAgain => 'Ask for it again…';

  @override
  String get protectLock => 'Lock';

  @override
  String get protectEnterPasscode => 'Enter a passcode.';

  @override
  String get protectMismatch => 'The two entries do not match.';

  @override
  String get protectWrong => 'That is not the passcode.';

  @override
  String get protectPolicyAlways => 'Every time it is opened';

  @override
  String get protectPolicyTenMinutes => 'For 10 minutes';

  @override
  String get protectPolicyOneHour => 'For 1 hour';

  @override
  String get protectPolicySession => 'Until Openote is closed';

  @override
  String get linkTitleNew => 'Link';

  @override
  String get linkTitleEdit => 'Edit link';

  @override
  String get linkTextToShow => 'Text to show';

  @override
  String get linkNothingSelected =>
      'There was nothing selected to turn into a link';

  @override
  String get linkAddress => 'Address';

  @override
  String get linkOrPage => 'or link to a page';

  @override
  String get linkRemove => 'Remove link';

  @override
  String get linkUpdate => 'Update';

  @override
  String get linkInsert => 'Insert';

  @override
  String get linkNeedWords => 'Give the link some words to show.';

  @override
  String get linkBadAddress =>
      'That doesn\'t look like an address Openote can open. Try something like https://example.com';

  @override
  String get linkNoCaret => 'Put the cursor where the link should go first.';

  @override
  String get linkOneLine =>
      'A link has to sit on one line. Select some words on a single line.';

  @override
  String get linkOnObject =>
      'A picture, a table or a card can\'t carry a link. Put it on some words instead.';

  @override
  String get linkOnMaths =>
      'An equation can\'t carry a link — the brackets belong to the maths.';

  @override
  String get linkBrackets =>
      'A link\'s words can\'t contain square brackets. Select something without them.';

  @override
  String get linkNested =>
      'That text is already formatted or linked. Select some plain words, or click inside the link to edit it.';

  @override
  String get alertsTitle => 'Alerts before classes';

  @override
  String get alertsIntro =>
      'Openote can pop up before something in your timetable starts. It works out what each event is from its name, so pick the kinds you actually want interrupting for.';

  @override
  String get alertsPreset => 'Remind me 10 minutes before classes';

  @override
  String get alertsAllOff => 'Turn all off';

  @override
  String get alertsWhileRunning =>
      'Alerts appear inside Openote, so they only reach you while it is running. Anything you missed is waiting in this panel next time you open it.';

  @override
  String get alertsAtStart => 'At start';

  @override
  String alertsMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String get eventKindLecture => 'Lecture';

  @override
  String get eventKindTutorial => 'Tutorial';

  @override
  String get eventKindLab => 'Lab / practical';

  @override
  String get eventKindWorkshop => 'Workshop';

  @override
  String get eventKindSeminar => 'Seminar';

  @override
  String get eventKindExam => 'Exam / test';

  @override
  String get eventKindMeeting => 'Meeting';

  @override
  String get eventKindOther => 'Everything else';

  @override
  String get commonOk => 'OK';

  @override
  String get saveProblemNotAddedShort => 'That didn\'t get added';

  @override
  String get saveProblemNotAdded =>
      'Openote could not save the picture or file you just added, so it is not in your notebook.\n\nCheck that the disk is not full and that the notebook\'s folder is not set to read-only, then paste or drop it again.';

  @override
  String get saveProblemNotOnDriveShort => 'Not on Drive yet';

  @override
  String get saveProblemNotOnDrive =>
      'Your changes are saved on this phone. They could not be sent to the Drive folder just now (no connection, or the folder is not reachable), and will be sent when it can be reached.';

  @override
  String get saveProblemNotRecordedShort => 'Saved, but not recorded';

  @override
  String get saveProblemNotRecorded =>
      'Openote saved your notes on this computer, but it could not add the change to this notebook\'s history.\n\nThe history is the copy your other devices, your backups and your shared folders read from, so those may fall behind until this works again. Nothing you have written has been lost.\n\nCheck that the disk is not full, that the notebook\'s folder is not set to read-only, and that a cloud app such as OneDrive or Google Drive has finished with it. Openote tries again every time you save.';

  @override
  String get saveProblemPageShort => 'Couldn\'t save — changes kept in memory';

  @override
  String get saveProblemPage =>
      'Openote could not save this page to your computer.\n\nYour changes are still on screen and Openote will try again the next time you type or close the window. The first time you close the window it stays open so you can fix this; if you close the window again, Openote leaves without these changes.\n\nCheck that the disk is not full and that the notebook is not open in another program.';

  @override
  String get saveProblemPicturesShort => 'Some pictures may be missing';

  @override
  String saveProblemPictures(int count) {
    return 'Openote keeps a second copy of every picture and drawing inside this notebook\'s own folder, so your other devices and your backups can show them too.\n\nFor $count of them, Openote could not find good bytes anywhere on this computer — not in that second copy, and not in the notebook\'s own working file either. Until they turn up (from another device, a backup, or by adding the picture again), it will show blank wherever it is used, on this computer as well as any other.\n\nCheck that the disk is not full and that the folder is not set to read-only, then close the notebook and open it again. Openote tries again every time you open it.';
  }

  @override
  String get saveProblemListLockedShort => 'Your notebook list is locked';

  @override
  String get saveProblemNewerShort => 'Read-only — made by a newer Openote';

  @override
  String get saveProblemNewer =>
      'This notebook has changes in it that were made by a newer version of Openote, and this version cannot read them.\n\nSo Openote is showing you this notebook without changing it. Everything in it is safe, and nothing you do here can damage it — but anything you type now will not be kept.\n\nUpdating Openote to the latest version lets you edit it again.';

  @override
  String get saveProblemListShort => 'Couldn\'t save the notebook list';

  @override
  String get saveProblemList =>
      'Openote could not save your notebook list and settings. The window will stay open the first time you close it. Check the disk and try again, or close the window again to leave anyway.';

  @override
  String get mcpTitle => 'AI access';

  @override
  String get mcpIntro =>
      'Let an AI helper — like Claude — read your notes, search them, quiz you, and make flashcards from them. It only works while Openote is open, only on this computer, and anything it adds is a normal edit: Ctrl+Z undoes it.';

  @override
  String get mcpPasscodeNote =>
      'Anything with a passcode stays private: an AI helper can\'t see it or change it, even while you have it unlocked. A passcode locks Openote, not the file itself, so an AI tool that can open files on your computer could still read it.';

  @override
  String mcpCouldNotStart(String error) {
    return 'Could not start: $error';
  }

  @override
  String mcpReady(String lastUsed) {
    return 'Ready. $lastUsed';
  }

  @override
  String get mcpNeverUsed => 'No AI helper has used it since Openote opened.';

  @override
  String get mcpUsedJustNow => 'Last used by an AI helper just now.';

  @override
  String mcpUsedMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Last used by an AI helper $minutes minutes ago.',
      one: 'Last used by an AI helper 1 minute ago.',
    );
    return '$_temp0';
  }

  @override
  String mcpUsedHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Last used by an AI helper $hours hours ago.',
      one: 'Last used by an AI helper 1 hour ago.',
    );
    return '$_temp0';
  }

  @override
  String get mcpUsedOverADay =>
      'Last used by an AI helper more than a day ago.';

  @override
  String get mcpRestartHint =>
      'An AI helper looks for Openote when it starts. If yours was already open, restart it.';

  @override
  String mcpClientIsSetUp(String name) {
    return '$name — set up';
  }

  @override
  String mcpSetUpClient(String name) {
    return 'Set up $name';
  }

  @override
  String get mcpClaudeApp => 'Claude app';

  @override
  String get mcpChatGptApp => 'ChatGPT app';

  @override
  String get mcpWebsiteNote =>
      'The ChatGPT website can\'t be connected: its connectors run on OpenAI\'s servers, which can\'t see your computer. The button above is for the desktop app, which reads its settings from this computer. The Gemini app is the website case too — its CLI has a button.';

  @override
  String get mcpCopyAddress => 'Copy address';

  @override
  String get mcpCopyConfiguration => 'Copy configuration';

  @override
  String get mcpOtherTools => 'Other AI tools (advanced)';

  @override
  String get mcpOtherToolsBody =>
      'Openote speaks MCP, the standard AI tools use to connect to apps. Any MCP-capable tool can use this — the key inside is a password, so paste it only into tools you trust.';

  @override
  String mcpListening(String port) {
    return 'Listening on port $port, on this computer only.';
  }

  @override
  String get mcpNotListening => 'Not listening.';

  @override
  String get mcpCopyConfig => 'Copy config';

  @override
  String get mcpCliIntro => 'Or, for tools with a command line, run once:';

  @override
  String get mcpCopyCommand => 'Copy command';

  @override
  String get mcpCopied =>
      'Copied. The key inside is a password — paste it only into your own tools.';

  @override
  String get mcpChatGptUnreadable =>
      'ChatGPT\'s settings file couldn\'t be read, so Openote left it alone. The connection details under Advanced still work.';

  @override
  String get mcpChatGptUnparsable =>
      'ChatGPT\'s settings file has something in it Openote doesn\'t understand, so it was left alone. Copy the configuration under Advanced and add it by hand.';

  @override
  String mcpSaveFailed(String error) {
    return 'Couldn\'t save the connection: $error';
  }

  @override
  String get mcpChatGptSetUp =>
      'Set up. Restart the ChatGPT desktop app and Openote will be there under its MCP servers. The website cannot use this — only an app on this computer can see Openote.';

  @override
  String get mcpChatGptSavedOnly =>
      'Saved. Openote will appear once the ChatGPT desktop app or the Codex CLI is installed on this computer.';

  @override
  String mcpClientUnreadable(String name) {
    return '$name\'s settings file couldn\'t be read, so Openote left it alone. The connection details under Advanced still work in any MCP-capable tool.';
  }

  @override
  String mcpClientSetUp(String name) {
    return 'Set up. If $name is already open, restart it — it looks for Openote when it starts. Then ask it about your notes: try \"quiz me on what I wrote this week\".';
  }

  @override
  String mcpClientNotInstalled(String name) {
    return 'Openote is ready, but $name doesn\'t look installed on this computer yet. Once it is, the connection will just work.';
  }

  @override
  String get timeNow => 'now';

  @override
  String timeMinutesShort(String n) {
    return '${n}m';
  }

  @override
  String timeHoursShort(String n) {
    return '${n}h';
  }

  @override
  String timeDaysShort(String n) {
    return '${n}d';
  }

  @override
  String timeMonthsShort(String n) {
    return '${n}mo';
  }

  @override
  String timeYearsShort(String n) {
    return '${n}y';
  }

  @override
  String get countdownToday => 'today';

  @override
  String get countdownTomorrow => 'tomorrow';

  @override
  String get countdownYesterday => 'yesterday';

  @override
  String countdownDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String countdownDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get countdownPassed => 'passed';

  @override
  String get monthsShort => 'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec';

  @override
  String dateDayMonth(String day, String month) {
    return '$day $month';
  }

  @override
  String dateDayMonthYear(String day, String month, String year) {
    return '$day $month $year';
  }

  @override
  String get gradeAgain => 'Again';

  @override
  String get gradeHard => 'Hard';

  @override
  String get gradeGood => 'Good';

  @override
  String get gradeEasy => 'Easy';

  @override
  String get deckThisPage => 'This page';

  @override
  String get deckThisSection => 'This section';

  @override
  String get deckWholeNotebook => 'Whole notebook';

  @override
  String get studyAnkiText => 'Anki text';

  @override
  String studyExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Exported $count cards — import into Anki with File ▸ Import',
      one: 'Exported 1 card — import into Anki with File ▸ Import',
    );
    return '$_temp0';
  }

  @override
  String get studyForgetTitle => 'Forget this deck’s schedule?';

  @override
  String studyForgetBody(String scope) {
    String _temp0 = intl.Intl.selectLogic(
      scope,
      {
        'page':
            'Every card on this page becomes new again. Your notes are not touched.',
        'section':
            'Every card in this section becomes new again. Your notes are not touched.',
        'other':
            'Every card in the whole notebook becomes new again. Your notes are not touched.',
      },
    );
    return '$_temp0';
  }

  @override
  String get studyForget => 'Forget';

  @override
  String studyResetCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Reset $count cards',
      one: 'Reset 1 card',
    );
    return '$_temp0';
  }

  @override
  String get studyEnd => 'End';

  @override
  String get studyDeckActions => 'Deck actions';

  @override
  String get studyExportAnki => 'Export to Anki…';

  @override
  String get studySetExam => 'Set exam date…';

  @override
  String get studyChangeExam => 'Change exam date…';

  @override
  String get studyRemoveExam => 'Remove exam date';

  @override
  String get studyForgetSchedule => 'Forget schedule…';

  @override
  String get studyDue => 'due';

  @override
  String studyCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cards',
      one: '1 card',
    );
    return '$_temp0';
  }

  @override
  String studyNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new',
    );
    return '$_temp0';
  }

  @override
  String studyReview(String count) {
    return 'Review $count';
  }

  @override
  String get studyAllCaughtUp => 'All caught up.';

  @override
  String studyAllCaughtUpNext(String delay) {
    return 'All caught up — next card in $delay.';
  }

  @override
  String studyPracticeAll(String count) {
    return 'Practice all $count';
  }

  @override
  String get studyPracticeNote => 'Practice doesn\'t change your schedule.';

  @override
  String get studyThisSection => 'Study this section';

  @override
  String studyExamWhen(String when) {
    return 'Exam $when';
  }

  @override
  String get studyKeepSchedule => 'These cards keep their schedule.';

  @override
  String get studyExamGoodLuck => 'Every card seen. Good luck.';

  @override
  String studyExamUnseenToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count you haven\'t seen yet.',
    );
    return '$_temp0';
  }

  @override
  String studyAllSeen(String count) {
    return 'All $count seen — keep the reviews up.';
  }

  @override
  String studyToLearn(String count, String perDay) {
    return '$count to learn · $perDay a day covers them by then';
  }

  @override
  String get studyExamToday => 'Exam today';

  @override
  String get studySeen => 'SEEN';

  @override
  String studyNOfM(String n, String total) {
    return '$n of $total';
  }

  @override
  String get studyAddExam => 'Add an exam date';

  @override
  String studyReviewedToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reviewed today',
    );
    return '$_temp0';
  }

  @override
  String get studyNothingToday => 'Nothing reviewed today';

  @override
  String studyStreakAtRisk(String days) {
    return '$days-day streak — keep it going today';
  }

  @override
  String studyStreak(String days, String today) {
    return '$days-day streak · $today today';
  }

  @override
  String studyActivityTip(String days) {
    return 'Reviews in the last $days days';
  }

  @override
  String get studyDeck => 'Deck';

  @override
  String get studyNoCards => 'No cards here yet.';

  @override
  String get studyRecipeQuestion =>
      'Tag a question. The indented line below it is the answer.';

  @override
  String get studyRecipeDefinition =>
      'Tag a definition written as “term — meaning”.';

  @override
  String get studyRecipeCloze =>
      'Highlight part of a tagged line to blank it out instead.';

  @override
  String get studyCardsAreNotes =>
      'Cards are a view of your notes, so editing the note edits the card — there is nothing separate to maintain.';

  @override
  String studyReviewedCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Reviewed $count cards',
      one: 'Reviewed 1 card',
    );
    return '$_temp0';
  }

  @override
  String studyStillDue(String count) {
    return '$count still due in this deck.';
  }

  @override
  String get studyNothingElseDue => 'Nothing else due.';

  @override
  String studyNextCardIn(String delay) {
    return 'Next card in $delay.';
  }

  @override
  String studyNeedAnotherLook(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count need another look.',
      one: '1 needs another look.',
    );
    return '$_temp0';
  }

  @override
  String get studyExamTodayDot => 'Exam today.';

  @override
  String studyUntilExam(String countdown) {
    return '$countdown until the exam.';
  }

  @override
  String studyUntilExamUnseen(String countdown, String count) {
    return '$countdown until the exam · $count still unseen.';
  }

  @override
  String studyReviewAgain(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Review those $count again',
      one: 'Review that one again',
    );
    return '$_temp0';
  }

  @override
  String studyKeepGoing(String count) {
    return 'Keep going — $count due';
  }

  @override
  String get studyPracticeBadge => 'PRACTICE';

  @override
  String get studyShowAnswer => 'Show answer';

  @override
  String get studyOpenNote => 'Open the note';

  @override
  String get studyAnswerHidden => 'Answer hidden';

  @override
  String get studyAnswer => 'ANSWER';

  @override
  String get studyFillBlank => 'FILL IN THE BLANK';

  @override
  String studyExamMenu(String when, String countdown) {
    return 'Exam $when · $countdown…';
  }

  @override
  String get examDateTitle => 'Exam date';

  @override
  String examTitleFor(String section) {
    return 'Exam — $section';
  }

  @override
  String examRemoved(String date) {
    return 'Exam date removed ($date). Your cards are unchanged.';
  }

  @override
  String get examUseDate => 'Use this date';

  @override
  String get examWhatTime => 'What time does it start?';

  @override
  String get examDate => 'Date';

  @override
  String get examAddTime => 'Add a start time';

  @override
  String get examStarts => 'Starts';

  @override
  String get examNoTime => 'No particular time';

  @override
  String get examTimeOptional =>
      'The countdown and the revision plan work in whole days, so a time is optional.';

  @override
  String get examShownOnDay =>
      'Shown on the day. The countdown still works in whole days.';

  @override
  String get examSet => 'Set';
}
