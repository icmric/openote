// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class LZh extends L {
  LZh([String locale = 'zh']) : super(locale);

  @override
  String get commonBack => '上一步';

  @override
  String get commonSkip => '跳过';

  @override
  String get commonNext => '下一步';

  @override
  String get commonOpen => '打开';

  @override
  String get commonCancel => '取消';

  @override
  String get commonDetailsAdvanced => '详细信息（进阶）';

  @override
  String objectRowBackground(String kind) {
    return '背景：$kind';
  }

  @override
  String get objectRowBackgroundBlank => '空白';

  @override
  String get objectRowBackgroundGrid => '方格';

  @override
  String get objectRowBackgroundDotted => '点阵';

  @override
  String get objectRowBackgroundRuled => '横线';

  @override
  String objectRowPageMode(String paper, String landscape) {
    return '分页模式：$paper$landscape — 点击切换到画布';
  }

  @override
  String get objectRowLandscapeSuffix => ' 横向';

  @override
  String get objectRowCanvasMode => '画布模式：无边界 — 点击切换到分页';

  @override
  String get objectRowPaperSize => '纸张大小';

  @override
  String get objectRowLandscape => '横向';

  @override
  String get objectRowSnapOn => '对齐网格：开（拖动时显示网格）';

  @override
  String get objectRowSnapOff => '对齐网格：关 — 自由摆放';

  @override
  String get objectRowZoomOut => '缩小  (Ctrl+-)';

  @override
  String get objectRowZoomIn => '放大  (Ctrl+=)';

  @override
  String get objectRowZoomReset => '回到 100% 并回到页首  (Ctrl+0)';

  @override
  String get objectRowZoomFit => '缩放以显示全部内容';

  @override
  String get objectRowWordCount => '本页字数 — 点击查看字符数和阅读时间';

  @override
  String get objectRowWords => '字数';

  @override
  String get objectRowCharacters => '字符';

  @override
  String get objectRowCharactersNoSpaces => '不含空格';

  @override
  String get objectRowReadingTime => '阅读时间';

  @override
  String objectRowMinutes(int n) {
    return '$n 分钟';
  }

  @override
  String objectRowWordTally(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted 字',
      zero: '暂无文字',
    );
    return '$_temp0';
  }

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent%';
  }

  @override
  String get barTabHome => '开始';

  @override
  String get barTabInsert => '插入';

  @override
  String get barTabDraw => '绘图';

  @override
  String get barEquationBadge => '公式';

  @override
  String barUpdateTo(String version) {
    return '更新到 $version…';
  }

  @override
  String get barDone => '完成';

  @override
  String get barStudy => '复习';

  @override
  String get barPlanner => '日程';

  @override
  String get barFindTags => '查找标记';

  @override
  String get barPageOutline => '页面大纲';

  @override
  String get barLinks => '链接与反向链接';

  @override
  String get barFindOnPage => '在页面中查找';

  @override
  String get barFindOnPageTip => '在页面中查找  (Ctrl+F)';

  @override
  String get barExport => '导出';

  @override
  String get barExportTip => '导出页面…';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

  @override
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPrint => '打印…';

  @override
  String get barExportPdfPicture => 'PDF — 页面图像';

  @override
  String get barExportCanvas => '用于 Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => '只导出手写 (.inkml)';

  @override
  String get barExportNotebook => '把整个笔记本保存为文件夹和文件…';

  @override
  String get barExportNotebookBusy => '正在保存笔记本…';

  @override
  String barExportPageProgress(int done, int total) {
    return '第 $done 页，共 $total 页…';
  }

  @override
  String barExportedTo(String path) {
    return '已导出到 $path';
  }

  @override
  String get barSettings => '设置';

  @override
  String get barSettingsTip => '设置…';

  @override
  String get barUndo => '撤销  (Ctrl+Z)';

  @override
  String get barRedo => '重做  (Ctrl+Y)';

  @override
  String get barBold => '加粗  (Ctrl+B)';

  @override
  String get barItalic => '斜体  (Ctrl+I)';

  @override
  String get barUnderline => '下划线  (Ctrl+U)';

  @override
  String get barStrikethrough => '删除线';

  @override
  String get barInlineCode => '行内代码';

  @override
  String get barHighlight => '高亮';

  @override
  String get barHeading1 => '标题 1';

  @override
  String get barBulletList => '项目符号列表';

  @override
  String get barNumberedList => '编号列表';

  @override
  String get barCheckbox => '复选框';

  @override
  String get barQuote => '引用';

  @override
  String get barTextColour => '设置文字颜色';

  @override
  String get barTextFont => '文字字体…';

  @override
  String get barClickIntoTextBox => '点进文本框才能设置格式';

  @override
  String get barToolSelect => '选择／移动  (V)';

  @override
  String get barToolText => '文字  (T)';

  @override
  String get barToolPen => '钢笔  (P)';

  @override
  String get barToolHighlighter => '荧光笔  (H)';

  @override
  String get barToolEraser => '橡皮擦  (E)';

  @override
  String get barToolLasso => '套索选择手写内容';

  @override
  String get barEraserSplit => '从擦过的地方把笔画断开';

  @override
  String get barEraserWhole => '碰到哪一笔就整笔擦掉';

  @override
  String get barLassoHint => '圈住手写内容即可选中 — 然后拖动或删除';

  @override
  String get barPickPenHint => '选择钢笔或荧光笔开始绘制';

  @override
  String get barTouchDrawing =>
      '用手指绘制。\n自动：手指可以画，直到你拿起触控笔；之后手指改为拖动页面，手掌就不会留下痕迹。\n两根手指始终用于拖动和缩放。';

  @override
  String get barPenProximity =>
      '触控笔靠近页面时自动切换到手写。\n笔悬停时若改选其他工具，会一直保持，直到笔离开\n再回来。笔的尾端（或绘制时按住的笔杆按键）用来擦除。';

  @override
  String get barTextSize => '文字大小（磅）';

  @override
  String get barTextSizeDisabled => '点进文本框才能改字号';

  @override
  String get barFontSizeDefault => '默认';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barTagLine => '标记这一行（待办、重要、问题…）';

  @override
  String barTagged(String tags) {
    return '已标记：$tags';
  }

  @override
  String get barDueDateSet => '截止日期…';

  @override
  String get barDueDateChange => '修改截止日期…';

  @override
  String get barDueDateClear => '清除截止日期';

  @override
  String get barDueDatePickerTitle => '截止日期';

  @override
  String get barDueDatePickerConfirm => '设定';

  @override
  String get barMakeCardFromLine => '把这一行做成记忆卡';

  @override
  String get barNewCard => '新建记忆卡';

  @override
  String get barQuestionCard => '问题卡';

  @override
  String get barDefinitionCard => '定义卡';

  @override
  String get barBlankOut => '把选中的内容挖空';

  @override
  String get barBlankOutNeedsSelection => '请先选中要挖空的文字。';

  @override
  String get barOpenStudyPanel => '打开复习面板';

  @override
  String get barStudyEmpty => '复习 — 把某一行标记为问题或定义，就能做成卡片';

  @override
  String barStudyDue(int due, int total, String countdown) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total 张卡片',
    );
    return '本节共 $_temp0，其中 $due 张待复习$countdown';
  }

  @override
  String barStudyExamCountdown(String when) {
    return ' · 考试 $when';
  }

  @override
  String get barPlannerEmpty => '日程 — 所有日期集中在一处';

  @override
  String barPlannerToday(int count) {
    return '日程 — 今天 $count 项';
  }

  @override
  String barPlannerOverdue(int count) {
    return '日程 — 今天或已逾期 $count 项';
  }

  @override
  String barRemindersWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条提醒',
    );
    return '$_temp0等待处理';
  }

  @override
  String get barEscWhenDone => '完成后按 Esc';

  @override
  String barSaveFailed(String reason) {
    return '无法保存：$reason';
  }

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get navSearchHint => '搜索或跳转到…';

  @override
  String navNoMatches(String query) {
    return '没有找到“$query”';
  }

  @override
  String get navInPageContent => '在页面内容中';

  @override
  String get navUntitled => '无标题';

  @override
  String get navNoSections => '还没有分区。\n新建一个即可开始。';

  @override
  String get navNewSection => '新建分区';

  @override
  String navNewPageIn(String section) {
    return '在 $section 中新建页面';
  }

  @override
  String get navNoPages => '还没有页面';

  @override
  String get navSection => '分区';

  @override
  String get navNewSectionGroup => '新建分区组';

  @override
  String get navRecycleBin => '回收站';

  @override
  String get navHome => '主页';

  @override
  String get navHomeTip => '主页 — 收藏与最近';

  @override
  String get navHomeEmpty => '这里还什么都没有。\n\n右键点击页面并选择「收藏」即可固定；你打开过的页面会出现在「最近」里。';

  @override
  String get navComingUp => '即将到来';

  @override
  String navAllCount(int total) {
    return '全部 $total 项';
  }

  @override
  String get navOpen => '打开';

  @override
  String get navExpand => '展开导航栏  (Ctrl+\\)';

  @override
  String get navCollapse => '收起导航栏  (Ctrl+\\)';

  @override
  String get navNotebooksTip => '笔记本 — 切换、重命名、复制、导入';

  @override
  String get navDeletesSoon => '即将删除';

  @override
  String navDeletesInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days 天后删除',
    );
    return '$_temp0';
  }

  @override
  String get navBinEmpty => '没有已删除的内容。';

  @override
  String navBinRetention(int days) {
    return '这里的内容会在 $days 天后被彻底删除。';
  }

  @override
  String get navBinNotebooks => '笔记本';

  @override
  String get navBinItems => '项目';

  @override
  String get navRestore => '还原';

  @override
  String get navDeletePermanently => '彻底删除';

  @override
  String get navClose => '关闭';

  @override
  String get navDeleteForeverTitle => '彻底删除？';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '“$title”及其所有页面都将被永久删除，无法撤销。$caveat';
  }

  @override
  String get navDeleteForever => '永久删除';

  @override
  String navLockedCannotDelete(String title) {
    return '“$title”已锁定。请先移除密码再删除。';
  }

  @override
  String navDeletedRestorable(String title) {
    return '已删除“$title” — 可以从回收站还原。';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '“$title”已锁定。它只是在 Openote 里被隐藏，文件本身并未加密。';
  }

  @override
  String navPasscodeRemoved(String title) {
    return '已移除“$title”的密码。';
  }

  @override
  String navSavedTo(String path) {
    return '已保存到 $path';
  }

  @override
  String get navLinkCopied => '链接已复制 — 可以粘贴到任何页面';

  @override
  String get navMoveSectionTo => '把分区移动到…';

  @override
  String get navNoGroupTopLevel => '（不属于任何组 — 顶层）';

  @override
  String get navSaveTemplateTitle => '保存为模板';

  @override
  String get navSave => '保存';

  @override
  String get navTemplateNameHint => '模板名称';

  @override
  String navTemplateSaved(String name) {
    return '模板“$name”已保存';
  }

  @override
  String get navNoTemplates => '还没有模板 — 请先用「保存为模板…」。';

  @override
  String get navApplyTemplate => '应用模板';

  @override
  String get navColour => '颜色';

  @override
  String get navColourDefault => '默认';

  @override
  String navExamCountdown(String when, String countdown) {
    return '考试 $when · $countdown…';
  }

  @override
  String get navMenuMoveUp => '上移';

  @override
  String get navMenuMoveDown => '下移';

  @override
  String get navMenuNewPage => '新建页面';

  @override
  String get navMenuMoveToGroup => '移动到分区组…';

  @override
  String get navMenuSortAZ => '按标题排序';

  @override
  String get navMenuSortEdited => '按最后修改时间排序';

  @override
  String get navMenuExportSectionPdf => '把分区导出为 PDF…';

  @override
  String get navMenuPrintSection => '打印分区…';

  @override
  String get navMenuRemoveExam => '移除考试日期';

  @override
  String get navMenuSetExam => '设置考试日期…';

  @override
  String get navMenuMakeSubpage => '设为子页面';

  @override
  String get navMenuMoveBackOut => '取消子页面';

  @override
  String get navMenuRemoveFavourite => '取消收藏';

  @override
  String get navMenuAddFavourite => '加入收藏';

  @override
  String get navMenuSharePdf => '以 PDF 分享…';

  @override
  String get navMenuPrint => '打印…';

  @override
  String get navMenuCopyLink => '复制页面链接';

  @override
  String get navMenuRecentChanges => '最近的修改…';

  @override
  String get navMenuSaveTemplate => '保存为模板…';

  @override
  String get navMenuApplyTemplate => '应用模板…';

  @override
  String get navMenuRemovePasscode => '移除密码…';

  @override
  String get navMenuLock => '用密码锁定…';

  @override
  String get navMenuDelete => '删除';

  @override
  String get commonOn => '开';

  @override
  String get commonOff => '关';

  @override
  String get commonClose => '关闭';

  @override
  String get commonDone => '完成';

  @override
  String get commonDelete => '删除';

  @override
  String get commonOpenEllipsis => '打开…';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsWriting => '书写与绘图';

  @override
  String get settingsSpellCheck => '拼写检查';

  @override
  String get settingsPenProximity => '触控笔靠近页面时切换到手写';

  @override
  String get settingsConnections => '连接';

  @override
  String get settingsSync => '同步';

  @override
  String get settingsSyncHint => '备份并分享这个笔记本 — 用 GitHub 或一个文件夹。';

  @override
  String get settingsAi => 'AI 访问';

  @override
  String get settingsAiOn => '开 — 这台电脑上的 AI 助手可以读取你的笔记。';

  @override
  String get settingsAiOff => '关 — 可连接 Claude 或其他 AI 助手。';

  @override
  String get settingsHelp => '帮助';

  @override
  String get settingsWelcomeTour => '新手导览';

  @override
  String get settingsWelcomeTourHint => '三分钟版：画布、公式与手写，以及笔记存放在哪里。';

  @override
  String get settingsShortcuts => '键盘快捷键';

  @override
  String get settingsShortcutsHint => '每个功能都有快捷键 — 这是完整列表。  (Ctrl+/)';

  @override
  String get settingsAbout => '关于';

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsCheckUpdates => '检查更新';

  @override
  String settingsUpToDate(String version) {
    return '已是最新版本（$version 就是最新版）。';
  }

  @override
  String get settingsWhatsNew => '更新内容';

  @override
  String get nbTitle => '笔记本';

  @override
  String nbOpenCount(int count) {
    return '已打开 $count 个';
  }

  @override
  String nbInBin(int days) {
    return '在回收站中 · $days 天后删除';
  }

  @override
  String get nbImportInto => '导入到新的笔记本';

  @override
  String get nbNew => '新建';

  @override
  String get nbNewTitle => '新建笔记本';

  @override
  String get nbCreate => '创建';

  @override
  String get nbNameHint => '笔记本名称';

  @override
  String get nbImport => '导入';

  @override
  String get nbRepair => '修复';

  @override
  String get nbGetStarted => '开始使用';

  @override
  String get nbImportOnepkg => 'OneNote 笔记本 (.onepkg)';

  @override
  String get nbImportOne => 'OneNote 分区 (.one)';

  @override
  String get nbImportMarkdown => 'Markdown 文件夹';

  @override
  String get nbImportGit => '从 git 地址导入';

  @override
  String get nbDuplicates => '可能重复 · 标题相同且页数相同';

  @override
  String get nbDuplicatesHint => '保留最大的那个 — 较小的通常是中途中断的导入。删除的副本会进入回收站。';

  @override
  String get nbOpenThis => '打开这个笔记本';

  @override
  String get nbRename => '重命名';

  @override
  String get nbDuplicate => '复制';

  @override
  String get nbMoveToBin => '移到回收站';

  @override
  String get nbConfirmBin => '移到回收站？之后可以从这里还原。';

  @override
  String get nbOnePkgFileType => 'OneNote 笔记本包';

  @override
  String get nbImportBusy => '已经有一个导入在进行 — 一次只能导入一个。';

  @override
  String get nbImportStarted => '正在后台导入 — 你可以继续做别的，完成后角落的卡片会提示。';

  @override
  String nbImportedNamed(String name) {
    return '已导入 $name';
  }

  @override
  String get nbReadingFolder => '正在读取文件夹…';

  @override
  String nbImportedProgress(String done) {
    return '已导入 $done';
  }

  @override
  String get nbNoMarkdown => '那个文件夹里没有找到 Markdown 文件。';

  @override
  String nbImportedPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导入 $count 页',
    );
    return '$_temp0';
  }

  @override
  String get nbNeedsNativeCore =>
      'OneNote 导入需要 Rust 内核 — 请编译 onote_core.dll 并放在程序旁边。';

  @override
  String get nbCheckingPages => '正在检查页面…';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return '正在检查第 $done 页，共 $total 页…';
  }

  @override
  String get nbNothingToRepair => '没有需要修复的内容 — 所有页面都是最新的。';

  @override
  String nbRepairedBoxes(int blocks) {
    String _temp0 = intl.Intl.pluralLogic(
      blocks,
      locale: localeName,
      other: '$blocks 个框',
    );
    return '$_temp0';
  }

  @override
  String nbRepairedPages(int pages) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages 页',
    );
    return '$_temp0';
  }

  @override
  String nbRepaired(String boxes, String pages) {
    return '已在 $pages 中修复 $boxes。';
  }

  @override
  String nbRepairFailed(String reason) {
    return '修复失败：$reason';
  }

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '“$title”有 $copies 份副本 · 每份 $pages 页 · 可释放 $size';
  }

  @override
  String get nbCoreMissing =>
      'OneNote 导入需要 Rust 内核 — 请编译 onote_core.dll（见 rust/onote_core/INTEGRATION.md）。';

  @override
  String nbReadFileFailed(String reason) {
    return '无法读取该文件：$reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return '无法导入该文件夹：$reason';
  }

  @override
  String get nbOneFileEmpty => '没能从那个 .one 文件里读出任何内容。';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return '已从 OneNote 导入 $what。$strokeNote';
  }

  @override
  String nbImportedPagesProgress(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导入 $count 页…',
    );
    return '$_temp0';
  }

  @override
  String mathSemanticLabel(String latex) {
    return '公式：$latex';
  }

  @override
  String get insertGroupWrite => '书写';

  @override
  String get insertGroupBringIn => '引入';

  @override
  String get insertGroupLinkUp => '关联';

  @override
  String get insertTextBox => '文本框';

  @override
  String get insertEquation => '公式';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertTable => '表格';

  @override
  String get insertTableFromFile => '来自文件';

  @override
  String get insertTableFromFileTip => 'CSV 或 Excel';

  @override
  String get insertCode => '代码';

  @override
  String get insertBoard => '看板';

  @override
  String get insertBoardTip => '一列列可以拖动的卡片';

  @override
  String get insertPicture => '图片';

  @override
  String get insertPdfSlides => 'PDF 幻灯片';

  @override
  String get insertPdfPrintout => '作为讲义放在本页';

  @override
  String get insertPdfPerSlide => '每张幻灯片一页';

  @override
  String get insertPdfAsCard => '作为卡片 — 在弹窗中打开';

  @override
  String get insertVideo => '视频';

  @override
  String get insertVideoTip => '课堂录像，或任意网页链接';

  @override
  String get insertFile => '文件';

  @override
  String get insertFlashcardItem => '记忆卡';

  @override
  String get insertPageLink => '页面链接';

  @override
  String get insertPageWindow => '页面窗口';

  @override
  String get insertTemplate => '模板';

  @override
  String get insertPickImages => '图片';

  @override
  String get insertPickTables => '表格';

  @override
  String get insertPickVideo => '视频和音频';

  @override
  String get tagTodo => '待办';

  @override
  String get tagImportant => '重要';

  @override
  String get tagQuestion => '问题';

  @override
  String get tagRemember => '记住';

  @override
  String get tagDefinition => '定义';

  @override
  String get tagIdea => '想法';

  @override
  String get tagCritical => '紧急';

  @override
  String get tagContact => '联系人';

  @override
  String get tagCustom => '标记';

  @override
  String get touchDrawAuto => '自动（以笔为准）';

  @override
  String get touchDrawAlways => '总是';

  @override
  String get touchDrawNever => '从不';

  @override
  String get insertLinkToPage => '链接到页面';

  @override
  String get insertPdfUnreadable => '无法读取该 PDF。';

  @override
  String insertPdfImported(int count, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导入 $count 张幻灯片',
    );
    return '$_temp0$where — 拿起笔就能在上面写。幻灯片里的文字可以搜索。';
  }

  @override
  String get insertPdfOntoThisPage => '到本页';

  @override
  String insertPdfFailed(String reason) {
    return 'PDF 导入失败：$reason';
  }

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageAuto => '与电脑一致';

  @override
  String get settingsLanguageHelp =>
      'Openote 由使用者自己翻译。如果缺少你的语言或哪里译得不好，只需要改一个文件 — 链接里有说明。';

  @override
  String get settingsLanguageContribute => '如何添加或修正一种语言';

  @override
  String get shellNothingReplaced => '没有替换任何内容';

  @override
  String shellReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已替换 $count 处',
    );
    return '$_temp0';
  }

  @override
  String get shellReplaceWith => '替换为…';

  @override
  String get shellReplace => '替换';

  @override
  String get shellReplaceAll => '全部';

  @override
  String get shellFindOnThisPage => '在本页中查找…';

  @override
  String get shellNoMatches => '没有匹配项';

  @override
  String get shellPreviousMatch => '上一个匹配 (Shift+Enter)';

  @override
  String get shellNextMatch => '下一个匹配 (Enter)';

  @override
  String get shellCloseEsc => '关闭 (Esc)';

  @override
  String get shellNoTags => '这个笔记本里还没有标记。';

  @override
  String get shellTagsHint =>
      '标记用来标注某一行 — 待办、重要、问题、定义 — 方便你以后找回、复习，或者给它加个截止日期。';

  @override
  String get shellTagTheLine => '标记当前所在的行';

  @override
  String get shellNoHeadings => '本页没有标题。';

  @override
  String get shellHeadingsHint => '在行首输入 # 就能变成标题 — 大纲会在你书写时自动生成。';

  @override
  String get shellLinkedFrom => '被链接自';

  @override
  String get shellNoBacklinks => '还没有页面链接到这里。';

  @override
  String get shellLinksTo => '链接到';

  @override
  String get shellNoLinks => '这个页面还没有链接到任何地方。';

  @override
  String get shellSavedLocally => '这一页已保存到你本地的 .onote 文件中。';

  @override
  String get shellSaving => '正在保存…';

  @override
  String get shellSavedOnDevice => '已保存在本机';

  @override
  String shellRustLinked(String build) {
    return 'Rust 内核（onote-core）已链接，保存时会计算本页内容的哈希值。\n$build';
  }

  @override
  String get shellRustMissing => '正在使用纯 Dart 引擎。编译 onote-core 库即可链接 Rust 内核。';

  @override
  String get shellCheatSheet =>
      'V 选择 · T 文字 · P 钢笔 · H 荧光笔 · E 擦除 · Ctrl+Z 撤销 · Ctrl+滚轮 缩放';

  @override
  String get shellEmptyTitle => '一页空白，等你来写';

  @override
  String get shellEmptyBody => '你在这里做的一切都留在自己的设备上，\n用的是属于你自己的开放格式。';

  @override
  String get shellCreateFirstPage => '创建第一页';

  @override
  String get shellAlreadyUpToDate => '已经是最新的了。';

  @override
  String shellPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已获取 $count 处改动',
    );
    return '$_temp0';
  }

  @override
  String shellPageLocked(String title) {
    return '“$title”已锁定';
  }

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag（$count）';
  }

  @override
  String get shellUnlock => '解锁';

  @override
  String get onboardingStep1Title => '页面就是一块画布';

  @override
  String get onboardingStep1Body =>
      '在任意位置点击就能开始写 — 文本框出现在你点击的地方，而且只有你开始输入时才出现。用顶部的横条移动它，图片可以从任何地方拖进来。';

  @override
  String get onboardingStep2Title => '公式和手写，就在文字中间';

  @override
  String get onboardingStep2Body =>
      '输入 1/2 或按 Alt+=，边写边生成真正的数学排版，既可以单独成框，也可以写在句子中间。「绘图」标签支持触控笔、手指和鼠标。';

  @override
  String get onboardingStep3Title => '笔记是属于你自己的文件';

  @override
  String get onboardingStep3Body =>
      '每个笔记本就是一个开放、可读的文件 — 不用账号，也不会被绑定。把它放进云盘已经在同步的文件夹里，所有设备就能保持一致。';

  @override
  String get onboardingStartWriting => '开始书写';

  @override
  String get onboardingSyncTitle => '与另一台设备同步';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive、OneDrive、iCloud、Dropbox、Syncthing、NAS — 或者一个 GitHub 仓库。';

  @override
  String get onboardingSyncBodyAlso => '都不是？那就自己选一个文件夹。';

  @override
  String get onboardingSyncAction => '去设置…';

  @override
  String get onboardingOneNoteTitle => '把笔记从 OneNote 搬过来';

  @override
  String get onboardingOneNoteBody =>
      '从 .onepkg 导入页面、格式、图片、手写和标记。在后台进行 — 你可以继续做别的。';

  @override
  String get onboardingOneNoteAction => '选择文件…';

  @override
  String get onboardingFreshTitle => '新建笔记本';

  @override
  String get onboardingFreshBody => '一个空白笔记本，可以直接开始写。之后随时可以导入笔记。';

  @override
  String get onboardingFreshAction => '从空白开始';

  @override
  String get onboardingCloudTitle => '从 OneNote 导入笔记';

  @override
  String get onboardingCloudBody => '登录 Microsoft 并选择一个笔记本。无需先导出，任何电脑都能用。';

  @override
  String get onboardingCloudAction => '登录';

  @override
  String get oneNoteCloudTitle => '从 OneNote 导入笔记本';

  @override
  String get oneNoteCloudIntro => 'Openote 将读取你在 OneNote 中的笔记本，不会修改它们。';

  @override
  String get oneNoteCloudSignIn => '登录 Microsoft';

  @override
  String get oneNoteCloudSigningIn => '正在等待浏览器…';

  @override
  String get oneNoteCloudLoading => '正在查找你的笔记本…';

  @override
  String get oneNoteCloudEmpty => '此账户下未找到任何笔记本。';

  @override
  String get oneNoteCloudOther => '使用其他账户';

  @override
  String get oneNoteCloudNoInk => '手写内容无法通过这种方式导入，其余内容都可以。';

  @override
  String get onboardingOnePkgFileType => 'OneNote 笔记本包';

  @override
  String get onboardingOneNoteHowTo => '怎么导出？';

  @override
  String get onboardingOneNoteHideSteps => '隐藏步骤';

  @override
  String get onboardingExportTitle => '从 OneNote 导出';

  @override
  String get onboardingExportSteps =>
      '1. 打开 Windows 版 OneNote（桌面版 — 商店版和网页版无法导出）。\n2. 等笔记本同步完成，确保内容都在这台电脑上。\n3. 文件 ▸ 导出 ▸ 笔记本 ▸ OneNote 程序包 (*.onepkg)，然后点导出。\n4. 回到这里选择那个文件。';

  @override
  String get onboardingExportMacNote =>
      '如果用的是 Mac，或者只有商店版：可以一个分区一个分区地导出为 .one，或者找一台 Windows 电脑生成 .onepkg。Openote 从不登录你的 Microsoft 账号 — 它只读取你交给它的文件。';

  @override
  String onboardingImportingFile(String fileName) {
    return '正在导入 $fileName';
  }

  @override
  String get onboardingImportRunning => '继续做你的事 — 这在后台进行，完成后角落的卡片会提示。';

  @override
  String get onboardingImportDone => '你的笔记本准备好了';

  @override
  String get onboardingOpenFailed => 'Openote 无法打开那个笔记本。';

  @override
  String get onboardingNoNativeCore => 'OneNote 导入需要原生内核，而这个版本没有包含它。';

  @override
  String onboardingReadFailed(String reason) {
    return '无法读取该文件：$reason';
  }
}
