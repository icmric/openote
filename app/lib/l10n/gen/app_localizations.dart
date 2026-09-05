import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_zh.dart';

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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('pt'),
    Locale('zh')
  ];

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

  /// Tooltip on the four page-background buttons in the object row. {kind} is one of objectRowBackgroundBlank/Grid/Dotted/Ruled.
  ///
  /// In en, this message translates to:
  /// **'Background: {kind}'**
  String objectRowBackground(String kind);

  /// A page with no printed background at all. Lower case: it is substituted into objectRowBackground.
  ///
  /// In en, this message translates to:
  /// **'blank'**
  String get objectRowBackgroundBlank;

  /// A page printed with squared paper. Lower case: substituted into objectRowBackground.
  ///
  /// In en, this message translates to:
  /// **'grid'**
  String get objectRowBackgroundGrid;

  /// A page printed with a grid of dots. Lower case: substituted into objectRowBackground.
  ///
  /// In en, this message translates to:
  /// **'dotted'**
  String get objectRowBackgroundDotted;

  /// A page printed with horizontal lines to write on. Lower case: substituted into objectRowBackground.
  ///
  /// In en, this message translates to:
  /// **'ruled'**
  String get objectRowBackgroundRuled;

  /// Tooltip when the page is set to a fixed paper size. {paper} is a paper name like A4 or Letter; {landscape} is either empty or objectRowLandscapeSuffix.
  ///
  /// In en, this message translates to:
  /// **'Page mode: {paper}{landscape} — click for canvas'**
  String objectRowPageMode(String paper, String landscape);

  /// Appended to the paper name when the page is rotated. Keep the leading space — it follows the paper name inside objectRowPageMode.
  ///
  /// In en, this message translates to:
  /// **' landscape'**
  String get objectRowLandscapeSuffix;

  /// Tooltip when the page has no fixed size and simply extends in every direction.
  ///
  /// In en, this message translates to:
  /// **'Canvas mode: boundless — click for pages'**
  String get objectRowCanvasMode;

  /// Tooltip on the menu that picks A4, Letter and so on.
  ///
  /// In en, this message translates to:
  /// **'Paper size'**
  String get objectRowPaperSize;

  /// Menu item: rotate the page so it is wider than it is tall.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get objectRowLandscape;

  /// Tooltip when dragged boxes line up to an invisible grid.
  ///
  /// In en, this message translates to:
  /// **'Snap to grid: ON (grid shows while dragging)'**
  String get objectRowSnapOn;

  /// Tooltip when boxes can be dropped anywhere.
  ///
  /// In en, this message translates to:
  /// **'Snap to grid: OFF — free placement'**
  String get objectRowSnapOff;

  /// Tooltip. Keep the shortcut in brackets as typed; the two spaces before it separate it from the words.
  ///
  /// In en, this message translates to:
  /// **'Zoom out  (Ctrl+-)'**
  String get objectRowZoomOut;

  /// Tooltip. Keep the shortcut in brackets as typed.
  ///
  /// In en, this message translates to:
  /// **'Zoom in  (Ctrl+=)'**
  String get objectRowZoomIn;

  /// Tooltip on the zoom percentage, which is itself a button.
  ///
  /// In en, this message translates to:
  /// **'Back to 100% and the top of the page  (Ctrl+0)'**
  String get objectRowZoomReset;

  /// Tooltip: choose the zoom that puts everything written on the page on screen at once.
  ///
  /// In en, this message translates to:
  /// **'Zoom to fit content'**
  String get objectRowZoomFit;

  /// Tooltip on the word count.
  ///
  /// In en, this message translates to:
  /// **'Words on this page — click for characters and reading time'**
  String get objectRowWordCount;

  /// Row label in the word-count menu.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get objectRowWords;

  /// Row label in the word-count menu: every character including spaces.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get objectRowCharacters;

  /// Row label in the word-count menu: characters not counting spaces.
  ///
  /// In en, this message translates to:
  /// **'Without spaces'**
  String get objectRowCharactersNoSpaces;

  /// Row label in the word-count menu: roughly how long the page takes to read.
  ///
  /// In en, this message translates to:
  /// **'Reading time'**
  String get objectRowReadingTime;

  /// A duration in minutes, abbreviated. Shown beside objectRowReadingTime.
  ///
  /// In en, this message translates to:
  /// **'{n} min'**
  String objectRowMinutes(int n);

  /// The word count shown in the object row itself. {formatted} is the same number already grouped for this language (1,234 in English) — use it rather than {count} wherever the number is printed; {count} is only there to choose the plural form.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no words} =1{1 word} other{{formatted} words}}'**
  String objectRowWordTally(int count, String formatted);

  /// The zoom level, shown on a button between the zoom-out and zoom-in controls. Some languages put a space before the percent sign, or the sign first.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String objectRowZoomPercent(int percent);

  /// Toolbar tab: writing and formatting.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get barTabHome;

  /// Toolbar tab: adding things to the page.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get barTabInsert;

  /// Toolbar tab: pens, highlighters and erasers.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get barTabDraw;

  /// A label, not a button: it appears in the tab row while an equation is being written, to say what the row below is about.
  ///
  /// In en, this message translates to:
  /// **'Equation'**
  String get barEquationBadge;

  /// Button and tooltip shown only when a newer release of Openote exists.
  ///
  /// In en, this message translates to:
  /// **'Update to {version}…'**
  String barUpdateTo(String version);

  /// Button that puts the pen or eraser down and goes back to selecting.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get barDone;

  /// Opens the flashcard revision panel.
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get barStudy;

  /// Opens the panel listing every date in the notebook.
  ///
  /// In en, this message translates to:
  /// **'Planner'**
  String get barPlanner;

  /// Opens the panel that lists lines marked To Do, Important and so on.
  ///
  /// In en, this message translates to:
  /// **'Find tags'**
  String get barFindTags;

  /// Opens the panel listing the headings on this page.
  ///
  /// In en, this message translates to:
  /// **'Page outline'**
  String get barPageOutline;

  /// Opens the panel showing what this page links to and what links to it.
  ///
  /// In en, this message translates to:
  /// **'Links & backlinks'**
  String get barLinks;

  /// Opens the search bar for the open page.
  ///
  /// In en, this message translates to:
  /// **'Find on page'**
  String get barFindOnPage;

  /// Tooltip. Keep the shortcut in brackets as typed; the two spaces separate it from the words.
  ///
  /// In en, this message translates to:
  /// **'Find on page  (Ctrl+F)'**
  String get barFindOnPageTip;

  /// Opens the menu of ways to save a copy elsewhere.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get barExport;

  /// Tooltip on the export menu.
  ///
  /// In en, this message translates to:
  /// **'Export page…'**
  String get barExportTip;

  /// Menu item. Markdown is a format name and .md a file extension; neither is translated.
  ///
  /// In en, this message translates to:
  /// **'Markdown (.md)'**
  String get barExportMarkdown;

  /// Menu item. Not translated.
  ///
  /// In en, this message translates to:
  /// **'PDF (.pdf)'**
  String get barExportPdf;

  /// Menu item: send the page to a printer.
  ///
  /// In en, this message translates to:
  /// **'Print…'**
  String get barExportPrint;

  /// Menu item: a PDF that is an image of the page rather than selectable text.
  ///
  /// In en, this message translates to:
  /// **'PDF — picture of the page'**
  String get barExportPdfPicture;

  /// Menu item. Obsidian is another notes app and .canvas its file extension; neither is translated.
  ///
  /// In en, this message translates to:
  /// **'For Obsidian Canvas (.canvas)'**
  String get barExportCanvas;

  /// Menu item: only the handwriting, as an InkML file. The extension is not translated.
  ///
  /// In en, this message translates to:
  /// **'Just the drawing (.inkml)'**
  String get barExportInk;

  /// Menu item: write the entire notebook out as ordinary folders and files on disk.
  ///
  /// In en, this message translates to:
  /// **'Save the whole notebook as folders and files…'**
  String get barExportNotebook;

  /// Progress message while that runs.
  ///
  /// In en, this message translates to:
  /// **'Saving the notebook…'**
  String get barExportNotebookBusy;

  /// Progress message during a notebook export.
  ///
  /// In en, this message translates to:
  /// **'Page {done} of {total}…'**
  String barExportPageProgress(int done, int total);

  /// Confirmation after an export, naming where the file landed.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String barExportedTo(String path);

  /// Opens the settings dialog.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get barSettings;

  /// Tooltip on the settings button.
  ///
  /// In en, this message translates to:
  /// **'Settings…'**
  String get barSettingsTip;

  /// Tooltip. Keep the shortcut in brackets as typed.
  ///
  /// In en, this message translates to:
  /// **'Undo  (Ctrl+Z)'**
  String get barUndo;

  /// Tooltip. Keep the shortcut in brackets as typed.
  ///
  /// In en, this message translates to:
  /// **'Redo  (Ctrl+Y)'**
  String get barRedo;

  /// Tooltip on the bold button. Keep the shortcut as typed.
  ///
  /// In en, this message translates to:
  /// **'Bold  (Ctrl+B)'**
  String get barBold;

  /// Tooltip. Keep the shortcut as typed.
  ///
  /// In en, this message translates to:
  /// **'Italic  (Ctrl+I)'**
  String get barItalic;

  /// Tooltip. Keep the shortcut as typed.
  ///
  /// In en, this message translates to:
  /// **'Underline  (Ctrl+U)'**
  String get barUnderline;

  /// Tooltip: a line drawn through the words.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get barStrikethrough;

  /// Tooltip: format the selected words as computer code, in a monospaced face.
  ///
  /// In en, this message translates to:
  /// **'Inline code'**
  String get barInlineCode;

  /// Tooltip: mark the words as if with a highlighter pen.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get barHighlight;

  /// Tooltip: make this line a top-level heading.
  ///
  /// In en, this message translates to:
  /// **'Heading 1'**
  String get barHeading1;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Bullet list'**
  String get barBulletList;

  /// Tooltip.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get barNumberedList;

  /// Tooltip: a list where each line can be ticked off.
  ///
  /// In en, this message translates to:
  /// **'Checkbox'**
  String get barCheckbox;

  /// Tooltip: set the line off as a quotation.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get barQuote;

  /// Tooltip on the button that colours the selected words.
  ///
  /// In en, this message translates to:
  /// **'Apply text colour'**
  String get barTextColour;

  /// Tooltip on the button that opens the font picker.
  ///
  /// In en, this message translates to:
  /// **'Text font…'**
  String get barTextFont;

  /// Shown in place of the formatting controls when nothing is being written, to say why they are greyed out. **Keep it short** — it sits at the end of a row that scrolls sideways, so a long translation simply ends up off the edge of the window where nobody reads it. The English is 31 characters; treat that as the budget.
  ///
  /// In en, this message translates to:
  /// **'Click into a text box to format'**
  String get barClickIntoTextBox;

  /// Tooltip. The letter in brackets is the key that picks this tool — keep it as typed unless the shortcut itself differs in this language.
  ///
  /// In en, this message translates to:
  /// **'Select / move  (V)'**
  String get barToolSelect;

  /// Tooltip. Keep the key in brackets as typed.
  ///
  /// In en, this message translates to:
  /// **'Text  (T)'**
  String get barToolText;

  /// Tooltip. Keep the key in brackets as typed.
  ///
  /// In en, this message translates to:
  /// **'Pen  (P)'**
  String get barToolPen;

  /// Tooltip. Keep the key in brackets as typed.
  ///
  /// In en, this message translates to:
  /// **'Highlighter  (H)'**
  String get barToolHighlighter;

  /// Tooltip. Keep the key in brackets as typed.
  ///
  /// In en, this message translates to:
  /// **'Eraser  (E)'**
  String get barToolEraser;

  /// Tooltip: draw a loop around handwriting to select it.
  ///
  /// In en, this message translates to:
  /// **'Lasso-select ink'**
  String get barToolLasso;

  /// Tooltip: the eraser takes out only the part of a pen stroke it touches.
  ///
  /// In en, this message translates to:
  /// **'Splits strokes where you rub'**
  String get barEraserSplit;

  /// Tooltip: the eraser removes a whole pen stroke at once.
  ///
  /// In en, this message translates to:
  /// **'Removes any stroke you touch'**
  String get barEraserWhole;

  /// Hint shown in the Draw row while the lasso tool is picked.
  ///
  /// In en, this message translates to:
  /// **'Draw a loop around ink to select it — then drag or delete'**
  String get barLassoHint;

  /// Hint shown in the Draw row when no drawing tool is picked.
  ///
  /// In en, this message translates to:
  /// **'Pick the pen or highlighter to draw'**
  String get barPickPenHint;

  /// Tooltip on the finger-drawing setting. 'pans' means moves the page around. Keep the line breaks.
  ///
  /// In en, this message translates to:
  /// **'Draw with your finger.\nAuto: a finger draws until you use the pen, then touch pans so your palm can\'t mark the page.\nTwo fingers always pan and zoom.'**
  String get barTouchDrawing;

  /// Tooltip on the pen-proximity setting. 'tail' is the blunt end of a stylus; 'barrel button' the button on its side. Keep the line breaks.
  ///
  /// In en, this message translates to:
  /// **'Bringing the pen near the page switches to inking.\nPick another tool while the pen hovers and it sticks until the\npen leaves and comes back. The pen\'s tail (or its barrel\nbutton, held while drawing) erases.'**
  String get barPenProximity;

  /// Tooltip on the font-size field. Points are the printer's unit type is measured in.
  ///
  /// In en, this message translates to:
  /// **'Text size (points)'**
  String get barTextSize;

  /// Tooltip on the font-size field when nothing is being written.
  ///
  /// In en, this message translates to:
  /// **'Click into a text box to change its size'**
  String get barTextSizeDisabled;

  /// Menu item: go back to whatever size the page normally uses.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get barFontSizeDefault;

  /// A font size in points, e.g. '11 pt'.
  ///
  /// In en, this message translates to:
  /// **'{size} pt'**
  String barFontSizePt(String size);

  /// Tooltip on the tag button when the line carries no tag yet. The three words in brackets are examples of tags.
  ///
  /// In en, this message translates to:
  /// **'Tag this line (To Do, Important, Question…)'**
  String get barTagLine;

  /// Tooltip on the tag button when the line is already tagged. {tags} is a comma-separated list of tag names.
  ///
  /// In en, this message translates to:
  /// **'Tagged: {tags}'**
  String barTagged(String tags);

  /// Menu item: give this line a deadline.
  ///
  /// In en, this message translates to:
  /// **'Due date…'**
  String get barDueDateSet;

  /// Menu item: alter the deadline this line already has.
  ///
  /// In en, this message translates to:
  /// **'Change due date…'**
  String get barDueDateChange;

  /// Menu item: remove the deadline.
  ///
  /// In en, this message translates to:
  /// **'Clear the due date'**
  String get barDueDateClear;

  /// Heading of the calendar that picks a deadline.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get barDueDatePickerTitle;

  /// Button that confirms the picked deadline.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get barDueDatePickerConfirm;

  /// Tooltip: turn the line the caret is on into a revision card.
  ///
  /// In en, this message translates to:
  /// **'Make this line a flashcard'**
  String get barMakeCardFromLine;

  /// Tooltip: add a revision card in a box of its own.
  ///
  /// In en, this message translates to:
  /// **'New flashcard'**
  String get barNewCard;

  /// Menu item: a card whose front is a question.
  ///
  /// In en, this message translates to:
  /// **'Question card'**
  String get barQuestionCard;

  /// Menu item: a card whose front is a term to define.
  ///
  /// In en, this message translates to:
  /// **'Definition card'**
  String get barDefinitionCard;

  /// Menu item: hide the selected words so they have to be recalled.
  ///
  /// In en, this message translates to:
  /// **'Blank out selection'**
  String get barBlankOut;

  /// Message when that is pressed with nothing selected.
  ///
  /// In en, this message translates to:
  /// **'Select the words to blank out first.'**
  String get barBlankOutNeedsSelection;

  /// Menu item.
  ///
  /// In en, this message translates to:
  /// **'Open study panel'**
  String get barOpenStudyPanel;

  /// Tooltip on the study badge when the section has no cards. 'Question' and 'Definition' are the names of two tags and should match barQuestionCard/barDefinitionCard.
  ///
  /// In en, this message translates to:
  /// **'Study — tag a line Question or Definition to make a card'**
  String get barStudyEmpty;

  /// Tooltip on the study badge. {countdown} is either empty or barStudyExamCountdown.
  ///
  /// In en, this message translates to:
  /// **'{due} of {total, plural, =1{1 card} other{{total} cards}} due in this section{countdown}'**
  String barStudyDue(int due, int total, String countdown);

  /// Appended to barStudyDue when the section has an exam date. Keep the leading space and the separator.
  ///
  /// In en, this message translates to:
  /// **' · exam {when}'**
  String barStudyExamCountdown(String when);

  /// Tooltip on the planner badge when nothing is due.
  ///
  /// In en, this message translates to:
  /// **'Planner — every date you have, in one place'**
  String get barPlannerEmpty;

  /// Tooltip on the planner badge.
  ///
  /// In en, this message translates to:
  /// **'Planner — {count} today'**
  String barPlannerToday(int count);

  /// Tooltip on the planner badge when some of the count is already late.
  ///
  /// In en, this message translates to:
  /// **'Planner — {count} today or overdue'**
  String barPlannerOverdue(int count);

  /// Tooltip on the planner badge when reminders have fired and not been dealt with.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 reminder} other{{count} reminders}} waiting'**
  String barRemindersWaiting(int count);

  /// Tooltip on the badge shown while an equation is open. 'Esc' is the Escape key.
  ///
  /// In en, this message translates to:
  /// **'Esc when you are done'**
  String get barEscWhenDone;

  /// Message after an export or print that did not work. {reason} is the underlying error, in English, from the operating system.
  ///
  /// In en, this message translates to:
  /// **'That couldn\'t be saved: {reason}'**
  String barSaveFailed(String reason);

  /// A small number printed on a toolbar badge — cards due, or reminders waiting. Its own message so the digits are grouped and shaped for this language rather than printed as raw ASCII.
  ///
  /// In en, this message translates to:
  /// **'{count}'**
  String barBadgeCount(int count);

  /// Placeholder in the navigator's search box.
  ///
  /// In en, this message translates to:
  /// **'Search or jump to…'**
  String get navSearchHint;

  /// Shown when a search found nothing. The quotation marks are curly ones — use whatever this language uses.
  ///
  /// In en, this message translates to:
  /// **'No matches for “{query}”'**
  String navNoMatches(String query);

  /// Heading over search results found in the words ON pages, as opposed to in page titles.
  ///
  /// In en, this message translates to:
  /// **'In page content'**
  String get navInPageContent;

  /// Stands in for the name of a page that has none yet.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get navUntitled;

  /// Shown when a notebook has no sections. A section is a divider in a notebook, holding pages. Keep the line break.
  ///
  /// In en, this message translates to:
  /// **'No sections yet.\nCreate one to get started.'**
  String get navNoSections;

  /// Button that adds a section.
  ///
  /// In en, this message translates to:
  /// **'New section'**
  String get navNewSection;

  /// Tooltip on the + beside a section.
  ///
  /// In en, this message translates to:
  /// **'New page in {section}'**
  String navNewPageIn(String section);

  /// Shown when a section holds no pages.
  ///
  /// In en, this message translates to:
  /// **'No pages yet'**
  String get navNoPages;

  /// Column heading over the list of sections.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get navSection;

  /// Tooltip. A section group is a folder holding several sections.
  ///
  /// In en, this message translates to:
  /// **'New section group'**
  String get navNewSectionGroup;

  /// Where deleted pages and notebooks wait before being removed for good.
  ///
  /// In en, this message translates to:
  /// **'Recycle bin'**
  String get navRecycleBin;

  /// The navigator's first pane: favourites, recent pages and what is coming up.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Tooltip on the Home button.
  ///
  /// In en, this message translates to:
  /// **'Home — favourites & recents'**
  String get navHomeTip;

  /// Shown on the Home pane before anything has been favourited or visited. 'Favourite' and 'Recent' name things elsewhere in this file — keep them consistent. Keep the blank line.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.\n\nRight-click a page and choose Favourite to pin it; pages you visit show up under Recent.'**
  String get navHomeEmpty;

  /// Heading over the next few dated things. Capitals are a style choice: match whatever reads as a small heading in this language.
  ///
  /// In en, this message translates to:
  /// **'COMING UP'**
  String get navComingUp;

  /// Link opening the full planner when more is dated than fits.
  ///
  /// In en, this message translates to:
  /// **'All {total}'**
  String navAllCount(int total);

  /// Link opening the planner when everything dated already fits.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get navOpen;

  /// Tooltip. Keep the shortcut in brackets as typed — the character is a backslash.
  ///
  /// In en, this message translates to:
  /// **'Expand the navigator  (Ctrl+\\)'**
  String get navExpand;

  /// Tooltip. Keep the shortcut in brackets as typed.
  ///
  /// In en, this message translates to:
  /// **'Collapse the navigator  (Ctrl+\\)'**
  String get navCollapse;

  /// Tooltip on the notebook button.
  ///
  /// In en, this message translates to:
  /// **'Notebooks — switch, rename, duplicate, import'**
  String get navNotebooksTip;

  /// Shown on a recycle-bin row whose 30 days are up.
  ///
  /// In en, this message translates to:
  /// **'Deletes soon'**
  String get navDeletesSoon;

  /// How long a deleted thing has left in the recycle bin.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Deletes in 1 day} other{Deletes in {days} days}}'**
  String navDeletesInDays(int days);

  /// Shown when the recycle bin holds nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing deleted.'**
  String get navBinEmpty;

  /// Explains the recycle bin's 30-day rule.
  ///
  /// In en, this message translates to:
  /// **'Items here are permanently deleted after {days} days.'**
  String navBinRetention(int days);

  /// Heading in the recycle bin over deleted notebooks.
  ///
  /// In en, this message translates to:
  /// **'Notebooks'**
  String get navBinNotebooks;

  /// Heading in the recycle bin over deleted pages and sections.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get navBinItems;

  /// Button that puts a deleted thing back.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get navRestore;

  /// Tooltip on the button that removes something for good.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get navDeletePermanently;

  /// Button that closes the recycle bin.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get navClose;

  /// Title of the dialog confirming a permanent deletion.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently?'**
  String get navDeleteForeverTitle;

  /// Body of that dialog. {caveat} is either empty or an extra paragraph, already beginning with two line breaks.
  ///
  /// In en, this message translates to:
  /// **'“{title}” and all its pages will be removed for good. This can\'t be undone.{caveat}'**
  String navDeleteForeverBody(String title, String caveat);

  /// The button that does it.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get navDeleteForever;

  /// Message when someone tries to delete a page they have locked.
  ///
  /// In en, this message translates to:
  /// **'“{title}” is locked. Remove its passcode before deleting it.'**
  String navLockedCannotDelete(String title);

  /// Confirmation after deleting a page.
  ///
  /// In en, this message translates to:
  /// **'Deleted “{title}” — restore it from the recycle bin.'**
  String navDeletedRestorable(String title);

  /// Said plainly after locking a page, so nobody mistakes a passcode for encryption.
  ///
  /// In en, this message translates to:
  /// **'“{title}” is locked. It is hidden inside Openote, not encrypted in the file.'**
  String navLockedNotEncrypted(String title);

  /// Confirmation after unlocking a page.
  ///
  /// In en, this message translates to:
  /// **'Passcode removed from “{title}”.'**
  String navPasscodeRemoved(String title);

  /// Confirmation naming where an exported file landed.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String navSavedTo(String path);

  /// Confirmation after copying a link to a page.
  ///
  /// In en, this message translates to:
  /// **'Link copied — paste it into any page'**
  String get navLinkCopied;

  /// Title of the dialog picking which group a section goes into.
  ///
  /// In en, this message translates to:
  /// **'Move section to…'**
  String get navMoveSectionTo;

  /// The choice in that dialog meaning 'not inside any group'.
  ///
  /// In en, this message translates to:
  /// **'(No group — top level)'**
  String get navNoGroupTopLevel;

  /// Title of the dialog that saves this page's layout for reuse.
  ///
  /// In en, this message translates to:
  /// **'Save as template'**
  String get navSaveTemplateTitle;

  /// Confirm button in that dialog.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get navSave;

  /// Placeholder in that dialog's text box.
  ///
  /// In en, this message translates to:
  /// **'Template name'**
  String get navTemplateNameHint;

  /// Confirmation after saving a template.
  ///
  /// In en, this message translates to:
  /// **'Template \"{name}\" saved'**
  String navTemplateSaved(String name);

  /// Shown when there is nothing to apply. The quoted phrase must match navSaveTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'No templates yet — \"Save as template…\" first.'**
  String get navNoTemplates;

  /// Title of the dialog that lays a saved template over this page.
  ///
  /// In en, this message translates to:
  /// **'Apply template'**
  String get navApplyTemplate;

  /// Label beside the row of colours a section can be given.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get navColour;

  /// Tooltip on the swatch meaning 'no colour of its own'.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get navColourDefault;

  /// Shown on a section that has an exam date.
  ///
  /// In en, this message translates to:
  /// **'Exam {when} · {countdown}…'**
  String navExamCountdown(String when, String countdown);

  /// Context-menu item: move this page or section one place earlier.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get navMenuMoveUp;

  /// Context-menu item: move it one place later.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get navMenuMoveDown;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'New page'**
  String get navMenuNewPage;

  /// Context-menu item: put this section inside a group.
  ///
  /// In en, this message translates to:
  /// **'Move to group…'**
  String get navMenuMoveToGroup;

  /// Context-menu item: order the pages by title. Use this language's own alphabet in the arrow, e.g. А→Я.
  ///
  /// In en, this message translates to:
  /// **'Sort pages A→Z'**
  String get navMenuSortAZ;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Sort pages by last edited'**
  String get navMenuSortEdited;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Export section as PDF…'**
  String get navMenuExportSectionPdf;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Print section…'**
  String get navMenuPrintSection;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Remove exam date'**
  String get navMenuRemoveExam;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Set exam date…'**
  String get navMenuSetExam;

  /// Context-menu item: nest this page under the one above it.
  ///
  /// In en, this message translates to:
  /// **'Make subpage'**
  String get navMenuMakeSubpage;

  /// Context-menu item: undo that nesting.
  ///
  /// In en, this message translates to:
  /// **'Move back out'**
  String get navMenuMoveBackOut;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get navMenuRemoveFavourite;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get navMenuAddFavourite;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Share as PDF…'**
  String get navMenuSharePdf;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Print…'**
  String get navMenuPrint;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Copy link to page'**
  String get navMenuCopyLink;

  /// Context-menu item: the page's own history.
  ///
  /// In en, this message translates to:
  /// **'Recent changes…'**
  String get navMenuRecentChanges;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Save as template…'**
  String get navMenuSaveTemplate;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Apply a template…'**
  String get navMenuApplyTemplate;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Remove passcode…'**
  String get navMenuRemovePasscode;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Lock with a passcode…'**
  String get navMenuLock;

  /// Context-menu item.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get navMenuDelete;

  /// One half of an on/off pair, shown as a highlighted segment rather than a switch.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get commonOn;

  /// The other half of that pair.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get commonOff;

  /// Button that dismisses a dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Button that finishes with a dialog.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// Button or menu item that removes something (to the recycle bin, not for good).
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Button on a settings row that opens a dialog of its own.
  ///
  /// In en, this message translates to:
  /// **'Open…'**
  String get commonOpenEllipsis;

  /// Title of the settings dialog.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Section heading.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// Row label: light, dark, or follow the computer.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// Theme choice: follow whatever the computer is set to.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// Theme choice: dark text on a pale page.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme choice: pale text on a dark page.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Section heading.
  ///
  /// In en, this message translates to:
  /// **'Writing and drawing'**
  String get settingsWriting;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Spell check'**
  String get settingsSpellCheck;

  /// Row label: bringing a stylus close to the screen picks the pen tool.
  ///
  /// In en, this message translates to:
  /// **'Pen near the page switches to inking'**
  String get settingsPenProximity;

  /// Section heading.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get settingsConnections;

  /// Row label for the backup-and-share settings.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get settingsSync;

  /// Supporting line under settingsSync. GitHub is a product name.
  ///
  /// In en, this message translates to:
  /// **'Back up and share this notebook — GitHub or a folder.'**
  String get settingsSyncHint;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'AI access'**
  String get settingsAi;

  /// Supporting line when AI access is enabled.
  ///
  /// In en, this message translates to:
  /// **'On — AI helpers on this computer can use your notes.'**
  String get settingsAiOn;

  /// Supporting line when it is not. Claude is a product name.
  ///
  /// In en, this message translates to:
  /// **'Off — connect Claude or other AI helpers.'**
  String get settingsAiOff;

  /// Section heading.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get settingsHelp;

  /// Row label: reopens the three-step welcome flow.
  ///
  /// In en, this message translates to:
  /// **'Welcome tour'**
  String get settingsWelcomeTour;

  /// Supporting line naming the flow's three steps.
  ///
  /// In en, this message translates to:
  /// **'The three-minute version: the canvas, maths and ink, and where your notes live.'**
  String get settingsWelcomeTourHint;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get settingsShortcuts;

  /// Supporting line. Keep the shortcut in brackets as typed.
  ///
  /// In en, this message translates to:
  /// **'Everything has a key — the full list.  (Ctrl+/)'**
  String get settingsShortcutsHint;

  /// Section heading.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// Row label naming the installed version. Openote is the product name.
  ///
  /// In en, this message translates to:
  /// **'Openote {version}'**
  String settingsVersion(String version);

  /// Button.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsCheckUpdates;

  /// Shown after checking, when nothing newer exists.
  ///
  /// In en, this message translates to:
  /// **'You\'re up to date ({version} is the newest version).'**
  String settingsUpToDate(String version);

  /// Link opening the release notes in a browser.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get settingsWhatsNew;

  /// Title of the notebook manager.
  ///
  /// In en, this message translates to:
  /// **'Notebooks'**
  String get nbTitle;

  /// Subtitle counting how many notebooks are in the workspace.
  ///
  /// In en, this message translates to:
  /// **'{count} open'**
  String nbOpenCount(int count);

  /// Heading over deleted notebooks.
  ///
  /// In en, this message translates to:
  /// **'In the recycle bin · deleted after {days} days'**
  String nbInBin(int days);

  /// Heading over the list of things that can be imported.
  ///
  /// In en, this message translates to:
  /// **'Import into a new notebook'**
  String get nbImportInto;

  /// Button that creates an empty notebook.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get nbNew;

  /// Title of the dialog that names it.
  ///
  /// In en, this message translates to:
  /// **'New notebook'**
  String get nbNewTitle;

  /// Confirm button in that dialog.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get nbCreate;

  /// Placeholder in that dialog.
  ///
  /// In en, this message translates to:
  /// **'Notebook name'**
  String get nbNameHint;

  /// Button opening the import choices.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get nbImport;

  /// Button that checks every page and fixes what it can.
  ///
  /// In en, this message translates to:
  /// **'Repair'**
  String get nbRepair;

  /// Button that opens the welcome flow.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get nbGetStarted;

  /// Import choice. OneNote is a product name and .onepkg a file extension.
  ///
  /// In en, this message translates to:
  /// **'OneNote notebook (.onepkg)'**
  String get nbImportOnepkg;

  /// Import choice. Not translated.
  ///
  /// In en, this message translates to:
  /// **'OneNote section (.one)'**
  String get nbImportOne;

  /// Import choice: a folder of .md files. Markdown is a format name.
  ///
  /// In en, this message translates to:
  /// **'Markdown folder'**
  String get nbImportMarkdown;

  /// Import choice: clone a notebook from a git repository.
  ///
  /// In en, this message translates to:
  /// **'From a git address'**
  String get nbImportGit;

  /// Heading over notebooks that look like copies of each other.
  ///
  /// In en, this message translates to:
  /// **'Possible duplicates · same title and same page count'**
  String get nbDuplicates;

  /// Advice under that heading, said explicitly because "delete the duplicates" is a frightening sentence unless the safest choice is named.
  ///
  /// In en, this message translates to:
  /// **'Keep the largest — an import interrupted part way through is the smaller one. Deleted copies go to the recycle bin.'**
  String get nbDuplicatesHint;

  /// Menu item.
  ///
  /// In en, this message translates to:
  /// **'Open this notebook'**
  String get nbOpenThis;

  /// Menu item.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get nbRename;

  /// Menu item: make a copy.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get nbDuplicate;

  /// Menu item.
  ///
  /// In en, this message translates to:
  /// **'Move to recycle bin'**
  String get nbMoveToBin;

  /// Confirmation question before deleting a notebook.
  ///
  /// In en, this message translates to:
  /// **'Move to the recycle bin? You can restore it from here.'**
  String get nbConfirmBin;

  /// File-type name shown in the operating system's own file picker beside .onepkg.
  ///
  /// In en, this message translates to:
  /// **'OneNote notebook package'**
  String get nbOnePkgFileType;

  /// Message when a second import is started while one is running.
  ///
  /// In en, this message translates to:
  /// **'An import is already running — one at a time.'**
  String get nbImportBusy;

  /// Message when an import starts.
  ///
  /// In en, this message translates to:
  /// **'Importing in the background — keep working, the card in the corner will say when it\'s done.'**
  String get nbImportStarted;

  /// Confirmation after importing one file.
  ///
  /// In en, this message translates to:
  /// **'Imported {name}'**
  String nbImportedNamed(String name);

  /// Progress message while a folder of Markdown is being scanned.
  ///
  /// In en, this message translates to:
  /// **'Reading the folder…'**
  String get nbReadingFolder;

  /// Progress message naming the file just read.
  ///
  /// In en, this message translates to:
  /// **'Imported {done}'**
  String nbImportedProgress(String done);

  /// Message when a Markdown import found nothing to read.
  ///
  /// In en, this message translates to:
  /// **'No Markdown files found in that folder.'**
  String get nbNoMarkdown;

  /// Confirmation after importing a folder.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 page} other{Imported {count} pages}}'**
  String nbImportedPages(int count);

  /// Error for a build without the native library. 'the Rust core' and the file name are Openote's own components.
  ///
  /// In en, this message translates to:
  /// **'OneNote import needs the Rust core — build onote_core.dll and put it beside the app.'**
  String get nbNeedsNativeCore;

  /// Progress message while Repair runs.
  ///
  /// In en, this message translates to:
  /// **'Checking pages…'**
  String get nbCheckingPages;

  /// Progress message during Repair.
  ///
  /// In en, this message translates to:
  /// **'Checking page {done} of {total}…'**
  String nbCheckingPageProgress(int done, int total);

  /// Result when Repair found nothing wrong.
  ///
  /// In en, this message translates to:
  /// **'Nothing to repair — every page is already up to date.'**
  String get nbNothingToRepair;

  /// How much Repair fixed. A 'box' is one block of content on a page. Substituted into nbRepaired.
  ///
  /// In en, this message translates to:
  /// **'{blocks, plural, =1{1 box} other{{blocks} boxes}}'**
  String nbRepairedBoxes(int blocks);

  /// How many pages Repair touched. Substituted into nbRepaired.
  ///
  /// In en, this message translates to:
  /// **'{pages, plural, =1{1 page} other{{pages} pages}}'**
  String nbRepairedPages(int pages);

  /// Result when Repair fixed something — e.g. 'Repaired 3 boxes across 2 pages.' {boxes} is nbRepairedBoxes and {pages} is nbRepairedPages, each already in its right plural form.
  ///
  /// In en, this message translates to:
  /// **'Repaired {boxes} across {pages}.'**
  String nbRepaired(String boxes, String pages);

  /// Shown when Repair itself could not run.
  ///
  /// In en, this message translates to:
  /// **'Repair failed: {reason}'**
  String nbRepairFailed(String reason);

  /// One row in the duplicate-notebooks list. {size} is already-formatted disk space, e.g. '4.2 MB'.
  ///
  /// In en, this message translates to:
  /// **'{copies} copies of \"{title}\" · {pages} pages each · {size} would come back'**
  String nbDuplicateGroup(int copies, String title, int pages, String size);

  /// Error for a build without the native library. The file name and the path are literal and must not be translated.
  ///
  /// In en, this message translates to:
  /// **'OneNote import needs the Rust core — build onote_core.dll (see rust/onote_core/INTEGRATION.md).'**
  String get nbCoreMissing;

  /// Error when a chosen file could not be opened at all.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that file: {reason}'**
  String nbReadFileFailed(String reason);

  /// Error when a folder of Markdown could not be read.
  ///
  /// In en, this message translates to:
  /// **'That folder couldn\'t be imported: {reason}'**
  String nbReadFolderFailed(String reason);

  /// Shown when a OneNote section file parsed but held nothing. '.one' is a file extension.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read any content from that .one file.'**
  String get nbOneFileEmpty;

  /// Result of importing a OneNote section. {what} is a phrase like '12 pages, 4 pictures' and {strokeNote} an optional sentence about undecodable handwriting — both are still assembled in English elsewhere in the code and are on the list to convert.
  ///
  /// In en, this message translates to:
  /// **'Imported {what} from OneNote.{strokeNote}'**
  String nbImportedFromOneNote(String what, String strokeNote);

  /// Progress while a Markdown folder is read.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 page…} other{Imported {count} pages…}}'**
  String nbImportedPagesProgress(int count);

  /// What a screen reader says for a rendered equation. {latex} is the equation's own LaTeX source — not translated, because it is what the student typed. Only the word before it is yours.
  ///
  /// In en, this message translates to:
  /// **'Equation: {latex}'**
  String mathSemanticLabel(String latex);

  /// Heading over the Insert items that make something to fill in — a text box, an equation, a table.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get insertGroupWrite;

  /// Heading over the Insert items that bring something in from elsewhere — a picture, a video, a file.
  ///
  /// In en, this message translates to:
  /// **'Bring in'**
  String get insertGroupBringIn;

  /// Heading over the Insert items that point at something that already exists — a page link, a template.
  ///
  /// In en, this message translates to:
  /// **'Link up'**
  String get insertGroupLinkUp;

  /// Insert item: a box to type in. One noun, the one a fifteen-year-old would use.
  ///
  /// In en, this message translates to:
  /// **'Text box'**
  String get insertTextBox;

  /// Insert item: a mathematical equation.
  ///
  /// In en, this message translates to:
  /// **'Equation'**
  String get insertEquation;

  /// The keyboard shortcut, shown as the item's tooltip. Not translated unless the shortcut itself differs in this language.
  ///
  /// In en, this message translates to:
  /// **'Alt+='**
  String get insertEquationTip;

  /// Insert item: a grid of rows and columns.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get insertTable;

  /// Insert item, under Table: build the table from a spreadsheet.
  ///
  /// In en, this message translates to:
  /// **'From a file'**
  String get insertTableFromFile;

  /// Tooltip naming the file kinds accepted. Both are product/format names.
  ///
  /// In en, this message translates to:
  /// **'CSV or Excel'**
  String get insertTableFromFileTip;

  /// Insert item: a box of computer code that can be run.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get insertCode;

  /// Insert item: a kanban board.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get insertBoard;

  /// Tooltip explaining what a board is, for someone who has not met the word.
  ///
  /// In en, this message translates to:
  /// **'Columns of cards you move along'**
  String get insertBoardTip;

  /// Insert item: an image.
  ///
  /// In en, this message translates to:
  /// **'Picture'**
  String get insertPicture;

  /// Insert item: a PDF, usually a lecture slide deck. PDF is not translated.
  ///
  /// In en, this message translates to:
  /// **'PDF slides'**
  String get insertPdfSlides;

  /// Insert choice: lay the PDF's pages onto this page to write over, the way a paper printout would be.
  ///
  /// In en, this message translates to:
  /// **'Printout on this page'**
  String get insertPdfPrintout;

  /// Insert choice: give each slide a page of its own.
  ///
  /// In en, this message translates to:
  /// **'One page per slide'**
  String get insertPdfPerSlide;

  /// Insert choice: a small card on the page that opens the PDF in a window when clicked.
  ///
  /// In en, this message translates to:
  /// **'As a card — open in a popup'**
  String get insertPdfAsCard;

  /// Insert item: a video or audio recording.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get insertVideo;

  /// Tooltip: it takes a file from this computer or a link to one online.
  ///
  /// In en, this message translates to:
  /// **'A lecture recording, or any web link'**
  String get insertVideoTip;

  /// Insert item: attach any file to the page.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get insertFile;

  /// Insert item: a revision card with a question on one side.
  ///
  /// In en, this message translates to:
  /// **'Flashcard'**
  String get insertFlashcardItem;

  /// Insert item: a link to another page in the notebook.
  ///
  /// In en, this message translates to:
  /// **'Page link'**
  String get insertPageLink;

  /// Insert item: a live window showing another page inside this one.
  ///
  /// In en, this message translates to:
  /// **'Page window'**
  String get insertPageWindow;

  /// Insert item: a saved page layout to lay over this page.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get insertTemplate;

  /// File-type name in the operating system's own picker, beside png/jpg/gif/webp.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get insertPickImages;

  /// File-type name in the OS file picker, beside csv/tsv/xlsx.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get insertPickTables;

  /// File-type name in the OS file picker, beside the video and audio extensions.
  ///
  /// In en, this message translates to:
  /// **'Video and audio'**
  String get insertPickVideo;

  /// Tag name: something that still has to be done. Title case as a proper label.
  ///
  /// In en, this message translates to:
  /// **'To Do'**
  String get tagTodo;

  /// Tag name.
  ///
  /// In en, this message translates to:
  /// **'Important'**
  String get tagImportant;

  /// Tag name. Also the front of a flashcard — keep it consistent with barQuestionCard.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get tagQuestion;

  /// Tag name: worth committing to memory.
  ///
  /// In en, this message translates to:
  /// **'Remember'**
  String get tagRemember;

  /// Tag name. Also a flashcard kind — keep it consistent with barDefinitionCard.
  ///
  /// In en, this message translates to:
  /// **'Definition'**
  String get tagDefinition;

  /// Tag name.
  ///
  /// In en, this message translates to:
  /// **'Idea'**
  String get tagIdea;

  /// Tag name: more urgent than Important.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get tagCritical;

  /// Tag name: a person to get in touch with.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get tagContact;

  /// The fallback name for a tag with no kind of its own — the generic word.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tagCustom;

  /// Setting: a finger draws until a stylus is used, then touch moves the page instead so a resting palm cannot mark it.
  ///
  /// In en, this message translates to:
  /// **'Auto (pen takes over)'**
  String get touchDrawAuto;

  /// Setting: a finger always draws, even when a stylus is present. Shown in a small dropdown, so keep it to one word if the language allows.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get touchDrawAlways;

  /// Setting: fingers only move and zoom the page; drawing needs a stylus or the mouse. Shown in a small dropdown — one word if the language allows.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get touchDrawNever;

  /// Title of the dialog that picks which page to link to.
  ///
  /// In en, this message translates to:
  /// **'Link to page'**
  String get insertLinkToPage;

  /// Error when a chosen PDF could not be opened at all.
  ///
  /// In en, this message translates to:
  /// **'That PDF couldn\'t be read.'**
  String get insertPdfUnreadable;

  /// Confirmation after importing a PDF. {where} is either empty or insertPdfOntoThisPage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 slide} other{Imported {count} slides}}{where} — pick the pen and write on them. The slide text is searchable.'**
  String insertPdfImported(int count, String where);

  /// Appended when the slides landed on the page already open rather than on new pages. Keep the leading space.
  ///
  /// In en, this message translates to:
  /// **' onto this page'**
  String get insertPdfOntoThisPage;

  /// Error when the import itself broke.
  ///
  /// In en, this message translates to:
  /// **'PDF import failed: {reason}'**
  String insertPdfFailed(String reason);

  /// Row label in Settings for choosing the interface language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// The default language choice: follow whatever the operating system is set to. Chosen over the word 'Automatic', which does not say what it will do.
  ///
  /// In en, this message translates to:
  /// **'Same as my computer'**
  String get settingsLanguageAuto;

  /// Supporting line under the language picker, inviting corrections. 'one file' means one .arb translation file.
  ///
  /// In en, this message translates to:
  /// **'Openote is translated by the people who use it. If yours is missing or wrong, it is one file — the link says how.'**
  String get settingsLanguageHelp;

  /// Link opening the contributing guide in a browser.
  ///
  /// In en, this message translates to:
  /// **'How to add or fix a language'**
  String get settingsLanguageContribute;

  /// Result of Replace All when the search text was not on the page.
  ///
  /// In en, this message translates to:
  /// **'Nothing replaced'**
  String get shellNothingReplaced;

  /// Result of Replace All.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Replaced 1 occurrence} other{Replaced {count} occurrences}}'**
  String shellReplaced(int count);

  /// Placeholder in the replacement box of the find bar.
  ///
  /// In en, this message translates to:
  /// **'Replace with…'**
  String get shellReplaceWith;

  /// Button: replace the match the caret is on.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get shellReplace;

  /// Button beside Replace: replace every match at once. Short, because it sits in a narrow bar.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get shellReplaceAll;

  /// Placeholder in the find box.
  ///
  /// In en, this message translates to:
  /// **'Find on this page…'**
  String get shellFindOnThisPage;

  /// Shown in the find bar when the search text is not on the page.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get shellNoMatches;

  /// Tooltip. Keep the keys as typed.
  ///
  /// In en, this message translates to:
  /// **'Previous match (Shift+Enter)'**
  String get shellPreviousMatch;

  /// Tooltip. Keep the key as typed.
  ///
  /// In en, this message translates to:
  /// **'Next match (Enter)'**
  String get shellNextMatch;

  /// Tooltip on the find bar's close button. Esc is the Escape key.
  ///
  /// In en, this message translates to:
  /// **'Close (Esc)'**
  String get shellCloseEsc;

  /// Empty state of the tags panel.
  ///
  /// In en, this message translates to:
  /// **'No tags in this notebook yet.'**
  String get shellNoTags;

  /// Explains what tags are, under shellNoTags. The four words are tag names: keep them consistent with tagTodo, tagImportant, tagQuestion, tagDefinition.
  ///
  /// In en, this message translates to:
  /// **'Tags mark a line — to do, important, question, definition — so you can find it again, revise from it, or give it a deadline.'**
  String get shellTagsHint;

  /// Button in the empty tags panel.
  ///
  /// In en, this message translates to:
  /// **'Tag the line you are on'**
  String get shellTagTheLine;

  /// Empty state of the page-outline panel.
  ///
  /// In en, this message translates to:
  /// **'No headings on this page.'**
  String get shellNoHeadings;

  /// Explains how to make a heading. The # is the Markdown character and must stay.
  ///
  /// In en, this message translates to:
  /// **'Start a line with # to make a heading — the outline builds itself as you write.'**
  String get shellHeadingsHint;

  /// Heading in the links panel: pages that point AT this one.
  ///
  /// In en, this message translates to:
  /// **'Linked from'**
  String get shellLinkedFrom;

  /// Empty state under shellLinkedFrom.
  ///
  /// In en, this message translates to:
  /// **'No pages link here yet.'**
  String get shellNoBacklinks;

  /// Heading in the links panel: pages this one points at.
  ///
  /// In en, this message translates to:
  /// **'Links to'**
  String get shellLinksTo;

  /// Empty state under shellLinksTo.
  ///
  /// In en, this message translates to:
  /// **'This page links nowhere yet.'**
  String get shellNoLinks;

  /// Tooltip on the save indicator. '.onote' is the file extension.
  ///
  /// In en, this message translates to:
  /// **'This page is saved to your local .onote file.'**
  String get shellSavedLocally;

  /// Shown while a page is being written to disk.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get shellSaving;

  /// Status-bar text when everything is written and the notebook is not synced anywhere.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device'**
  String get shellSavedOnDevice;

  /// Tooltip on the engine indicator. 'onote-core' is a component name. {build} is a line naming when the native library was built, already assembled.
  ///
  /// In en, this message translates to:
  /// **'The Rust core (onote-core) is linked and computing this page\'s content hash on save.\n{build}'**
  String shellRustLinked(String build);

  /// Tooltip when the native library is absent. 'onote-core' is a component name.
  ///
  /// In en, this message translates to:
  /// **'Running the pure-Dart engine. Build the onote-core library to link the Rust core.'**
  String get shellRustMissing;

  /// The one-line keyboard cheat sheet along the bottom. Each item is a key followed by what it does; the separator is a middle dot. It is dropped whole when the window is too narrow, never truncated, so a longer translation costs nothing but its own visibility on small windows.
  ///
  /// In en, this message translates to:
  /// **'V select · T text · P pen · H highlight · E erase · Ctrl+Z undo · Ctrl+scroll zoom'**
  String get shellCheatSheet;

  /// Heading shown when no page is open.
  ///
  /// In en, this message translates to:
  /// **'An open page awaits'**
  String get shellEmptyTitle;

  /// Under shellEmptyTitle. Keep the line break.
  ///
  /// In en, this message translates to:
  /// **'Everything you make here lives on your device,\nin an open format you own.'**
  String get shellEmptyBody;

  /// Button in the empty state.
  ///
  /// In en, this message translates to:
  /// **'Create your first page'**
  String get shellCreateFirstPage;

  /// Result of a manual sync that found nothing new.
  ///
  /// In en, this message translates to:
  /// **'Already up to date.'**
  String get shellAlreadyUpToDate;

  /// Result of a manual sync.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Pulled 1 change} other{Pulled {count} changes}}'**
  String shellPulled(int count);

  /// Shown in place of a page that has a passcode on it.
  ///
  /// In en, this message translates to:
  /// **'“{title}” is locked'**
  String shellPageLocked(String title);

  /// Heading over one tag's group in the tags panel — the tag's name and how many lines carry it.
  ///
  /// In en, this message translates to:
  /// **'{tag}  ({count})'**
  String shellTagGroup(String tag, int count);

  /// Button that asks for the passcode on a locked page.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get shellUnlock;

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

  /// Welcome flow: begin with an empty notebook rather than importing or syncing.
  ///
  /// In en, this message translates to:
  /// **'Start a fresh notebook'**
  String get onboardingFreshTitle;

  /// Body for the start-fresh option in the welcome flow.
  ///
  /// In en, this message translates to:
  /// **'An empty notebook, ready to write in. You can always bring notes over later.'**
  String get onboardingFreshBody;

  /// Button creating an empty notebook and closing the welcome flow.
  ///
  /// In en, this message translates to:
  /// **'Start fresh'**
  String get onboardingFreshAction;

  /// Welcome flow: import straight from Microsoft OneNote over the internet. 'OneNote' is a product name.
  ///
  /// In en, this message translates to:
  /// **'Bring notes over from OneNote'**
  String get onboardingCloudTitle;

  /// Body for the sign-in-to-Microsoft import option.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Microsoft and pick a notebook. Nothing to export first, and it works on any computer.'**
  String get onboardingCloudBody;

  /// Button starting the Microsoft sign-in.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get onboardingCloudAction;

  /// Dialog title for importing from OneNote over the internet.
  ///
  /// In en, this message translates to:
  /// **'Bring a notebook over from OneNote'**
  String get oneNoteCloudTitle;

  /// Reassurance shown before signing in: the import is read-only.
  ///
  /// In en, this message translates to:
  /// **'Openote will read your notebooks from OneNote. It cannot change them.'**
  String get oneNoteCloudIntro;

  /// Button opening the browser to sign in.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Microsoft'**
  String get oneNoteCloudSignIn;

  /// Shown while the browser sign-in is open.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your browser…'**
  String get oneNoteCloudSigningIn;

  /// Shown while the notebook list is being fetched.
  ///
  /// In en, this message translates to:
  /// **'Looking for your notebooks…'**
  String get oneNoteCloudLoading;

  /// Shown when the signed-in account has no OneNote notebooks.
  ///
  /// In en, this message translates to:
  /// **'No notebooks were found on this account.'**
  String get oneNoteCloudEmpty;

  /// Button signing out and starting the sign-in again.
  ///
  /// In en, this message translates to:
  /// **'Use a different account'**
  String get oneNoteCloudOther;

  /// Honest note that page nesting is not available over the internet import. Handwriting IS imported.
  ///
  /// In en, this message translates to:
  /// **'Subpages arrive as ordinary pages: OneNote does not send how they were nested.'**
  String get oneNoteCloudNoInk;

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

  /// Import route that needs no Microsoft sign-in, using an exported .onepkg file.
  ///
  /// In en, this message translates to:
  /// **'Use a file you exported'**
  String get oneNoteFileTitle;

  /// Body for the file import route. 'OneNote' is a product name.
  ///
  /// In en, this message translates to:
  /// **'No signing in, and subpages keep their nesting. You will need OneNote on Windows to export the notebook first.'**
  String get oneNoteFileBody;

  /// Body for the Microsoft sign-in import route.
  ///
  /// In en, this message translates to:
  /// **'Pick a notebook and it comes straight over, with nothing to export first. Works on any computer.'**
  String get oneNoteSignInBody;

  /// Heading above the list of notebooks found in the signed-in account.
  ///
  /// In en, this message translates to:
  /// **'Which notebook?'**
  String get oneNotePickTitle;

  /// Button reusing a remembered Microsoft sign-in, so no browser is needed.
  ///
  /// In en, this message translates to:
  /// **'Continue with Microsoft'**
  String get oneNoteCloudContinue;
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'de',
        'en',
        'es',
        'fr',
        'it',
        'pt',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return LDe();
    case 'en':
      return LEn();
    case 'es':
      return LEs();
    case 'fr':
      return LFr();
    case 'it':
      return LIt();
    case 'pt':
      return LPt();
    case 'zh':
      return LZh();
  }

  throw FlutterError(
      'L.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
