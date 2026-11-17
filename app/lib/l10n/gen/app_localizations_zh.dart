// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class LZh extends L {
  LZh([String locale = 'zh']) : super(locale);

  @override
  String atomNewerVersion(String version) {
    return '由 Openote $version 创建';
  }

  @override
  String get atomNewerVersionUnknown => '由较新版本的 Openote 创建';

  @override
  String get atomUpdateToView => '请更新 Openote 以查看';

  @override
  String get barBackToEquation => '返回公式工具';

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get barBlankOut => '把选中的内容挖空';

  @override
  String get barBlankOutNeedsSelection => '请先选中要挖空的文字。';

  @override
  String get barBold => '加粗  (Ctrl+B)';

  @override
  String get barBulletList => '项目符号列表';

  @override
  String get barCheckbox => '复选框';

  @override
  String get barClickIntoTextBox => '点进文本框才能设置格式';

  @override
  String get barDefinitionCard => '定义卡';

  @override
  String get barDueDateChange => '修改截止日期…';

  @override
  String get barDueDateClear => '清除截止日期';

  @override
  String get barDueDatePickerConfirm => '设定';

  @override
  String get barDueDatePickerTitle => '截止日期';

  @override
  String get barDueDateSet => '截止日期…';

  @override
  String get barEquationBadge => '公式';

  @override
  String get barEraserSplit => '从擦过的地方把笔画断开';

  @override
  String get barEraserWhole => '碰到哪一笔就整笔擦掉';

  @override
  String get barEscWhenDone => '完成后按 Esc';

  @override
  String get barExport => '导出';

  @override
  String get barExportCanvas => '用于 Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => '只导出手写 (.inkml)';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

  @override
  String get barExportNotebook => '把整个笔记本保存为文件夹和文件…';

  @override
  String get barExportNotebookBusy => '正在保存笔记本…';

  @override
  String barExportPageProgress(int done, int total) {
    return '第 $done 页，共 $total 页…';
  }

  @override
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPdfPicture => 'PDF — 页面图像';

  @override
  String get barExportPrint => '打印…';

  @override
  String get barExportTip => '导出页面…';

  @override
  String barExportedTo(String path) {
    return '已导出到 $path';
  }

  @override
  String get barFindOnPage => '在页面中查找';

  @override
  String get barFindOnPageTip => '在页面中查找  (Ctrl+F)';

  @override
  String get barFontSizeDefault => '默认';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barHeading1 => '标题 1';

  @override
  String get barHighlight => '高亮';

  @override
  String get barInkColourTitle => '笔的颜色';

  @override
  String get barInkDefaultColour => '默认墨迹 — 跟随页面';

  @override
  String get barInkHighlighterColourTitle => '荧光笔的颜色';

  @override
  String get barInkMoreColours => '更多颜色…';

  @override
  String get barInkPickColour => '从页面上拾取颜色';

  @override
  String get barInkPickingHint => '点击页面上的任意内容以使用它的颜色';

  @override
  String get barInlineCode => '行内代码';

  @override
  String get barItalic => '斜体  (Ctrl+I)';

  @override
  String get barLassoHint => '圈住手写内容即可选中 — 然后拖动或删除';

  @override
  String get barMakeCardFromLine => '把这一行做成记忆卡';

  @override
  String get barNewCard => '新建记忆卡';

  @override
  String get barNumberedList => '编号列表';

  @override
  String get barOpenStudyPanel => '打开复习面板';

  @override
  String get barPageOverview => '页面总览';

  @override
  String get barPenProximity =>
      '触控笔靠近页面时自动切换到手写。\n笔悬停时若改选其他工具，会一直保持，直到笔离开\n再回来。笔的尾端（或绘制时按住的笔杆按键）用来擦除。';

  @override
  String barPenSize(String size) {
    return '笔迹粗细 $size';
  }

  @override
  String get barPenSizeExact => '精确大小…';

  @override
  String get barPlanner => '日程';

  @override
  String get barPlannerEmpty => '日程 — 所有日期集中在一处';

  @override
  String barPlannerOverdue(int count) {
    return '日程 — 今天或已逾期 $count 项';
  }

  @override
  String barPlannerToday(int count) {
    return '日程 — 今天 $count 项';
  }

  @override
  String get barQuestionCard => '问题卡';

  @override
  String get barQuote => '引用';

  @override
  String get barRedo => '重做  (Ctrl+Y)';

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
  String barSaveFailed(String reason) {
    return '无法保存：$reason';
  }

  @override
  String get barSettings => '设置';

  @override
  String get barSettingsTip => '设置…';

  @override
  String get barStrikethrough => '删除线';

  @override
  String get barStudy => '复习';

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
  String get barStudyEmpty => '复习 — 把某一行标记为问题或定义，就能做成卡片';

  @override
  String barStudyExamCountdown(String when) {
    return ' · 考试 $when';
  }

  @override
  String get barTabDraw => '绘图';

  @override
  String get barTabHome => '开始';

  @override
  String get barTabInsert => '插入';

  @override
  String get barTabPage => '页面';

  @override
  String get barTagLine => '标记这一行（待办、重要、问题…）';

  @override
  String barTagged(String tags) {
    return '已标记：$tags';
  }

  @override
  String get barTextColour => '设置文字颜色';

  @override
  String get barTextFont => '文字字体…';

  @override
  String get barTextSize => '文字大小（磅）';

  @override
  String get barTextSizeDisabled => '点进文本框才能改字号';

  @override
  String get barToolEraser => '橡皮擦  (E)';

  @override
  String get barToolHighlighter => '荧光笔  (H)';

  @override
  String get barToolLasso => '套索选择手写内容';

  @override
  String get barToolPen => '钢笔  (P)';

  @override
  String get barToolSelect => '选择／移动  (V)';

  @override
  String get barToolText => '文字  (T)';

  @override
  String get barUnderline => '下划线  (Ctrl+U)';

  @override
  String get barUndo => '撤销  (Ctrl+Z)';

  @override
  String barUpdateTo(String version) {
    return '更新到 $version…';
  }

  @override
  String get canvasDeleteSelection => '删除  (Del)';

  @override
  String get canvasGroupSelection => '组合  (Ctrl+G)';

  @override
  String get canvasUngroupSelection => '取消组合  (Ctrl+Shift+G)';

  @override
  String get commandNotInDemo => '网页演示版中不可用';

  @override
  String get commonBack => '上一步';

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '关闭';

  @override
  String get commonCopy => '复制';

  @override
  String get commonDelete => '删除';

  @override
  String get commonDetailsAdvanced => '详细信息（进阶）';

  @override
  String get commonDone => '完成';

  @override
  String get commonNext => '下一步';

  @override
  String get commonOff => '关';

  @override
  String get commonOn => '开';

  @override
  String get commonOpen => '打开';

  @override
  String get commonOpenEllipsis => '打开…';

  @override
  String get commonSkip => '跳过';

  @override
  String importBringingIn(String name, int done, int total) {
    return '正在导入“$name” — $total 页中的第 $done 页…';
  }

  @override
  String get importCancelledLabel => '导入已取消。';

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导入 $count 页。',
    );
    return '$_temp0';
  }

  @override
  String importDoneButLost(int count, String detail) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导入 $count 页，但无法导入 $detail。',
    );
    return '$_temp0';
  }

  @override
  String get importEmptyNotebook => '该笔记本中没有页面。';

  @override
  String get importFailedGeneric => '无法导入该笔记本。';

  @override
  String importFoundPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '共 $count 页要导入。开始…',
    );
    return '$_temp0';
  }

  @override
  String importFoundSections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '找到 $count 个分区 — 正在查看内容…',
    );
    return '$_temp0';
  }

  @override
  String get importLookingAround => '正在查看您的笔记本…';

  @override
  String importPartialBroke(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '中途出了点问题，但已导入的 $count 页在这里。Openote 稍后会自行完成其余部分。',
    );
    return '$_temp0';
  }

  @override
  String importPartialThrottled(String detail, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$detail 已导入的 $count 页在这里。Openote 稍后会自行完成其余部分，您也可以随时重新开始。',
    );
    return '$_temp0';
  }

  @override
  String get importReading => '正在读取笔记本…';

  @override
  String get importSigningIn => '正在登录 OneNote…';

  @override
  String importStoppedKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已停止 — 保留了已导入的 $count 页。您可以随时完成。',
    );
    return '$_temp0';
  }

  @override
  String get importStopping => '正在停止…';

  @override
  String importThrottled(int seconds) {
    return 'Microsoft 要求 Openote 放慢速度 — $seconds 秒后继续。已导入的内容不会丢失。';
  }

  @override
  String get importThrottledSoon =>
      'Microsoft 要求 Openote 放慢速度 — 稍后继续。已导入的内容不会丢失。';

  @override
  String importWritingPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '正在导入 $count 页…',
    );
    return '$_temp0';
  }

  @override
  String importWritingSection(String name) {
    return '正在导入“$name”…';
  }

  @override
  String get insertBoard => '看板';

  @override
  String get insertBoardTip => '一列列可以拖动的卡片';

  @override
  String get insertCode => '代码';

  @override
  String get insertEquation => '公式';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertFile => '文件';

  @override
  String get insertFlashcardItem => '记忆卡';

  @override
  String get insertGroupBringIn => '引入';

  @override
  String get insertGroupLinkUp => '关联';

  @override
  String get insertGroupWrite => '书写';

  @override
  String get insertLinkToPage => '链接到页面';

  @override
  String get insertPageLink => '页面链接';

  @override
  String get insertPageWindow => '页面窗口';

  @override
  String get insertPdfAsCard => '作为卡片 — 在弹窗中打开';

  @override
  String insertPdfFailed(String reason) {
    return 'PDF 导入失败：$reason';
  }

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
  String get insertPdfPerSlide => '每张幻灯片一页';

  @override
  String get insertPdfPrintout => '作为讲义放在本页';

  @override
  String get insertPdfSlides => 'PDF 幻灯片';

  @override
  String get insertPdfUnreadable => '无法读取该 PDF。';

  @override
  String get insertPickImages => '图片';

  @override
  String get insertPickTables => '表格';

  @override
  String get insertPickVideo => '视频和音频';

  @override
  String get insertPicture => '图片';

  @override
  String get insertTable => '表格';

  @override
  String get insertTableFromFile => '来自文件';

  @override
  String get insertTableFromFileTip => 'CSV 或 Excel';

  @override
  String get insertTextBox => '文本框';

  @override
  String get insertVideo => '视频';

  @override
  String get insertVideoTip => '课堂录像，或任意网页链接';

  @override
  String get linkEdit => '编辑链接…';

  @override
  String mathSemanticLabel(String latex) {
    return '公式：$latex';
  }

  @override
  String navAllCount(int total) {
    return '全部 $total 项';
  }

  @override
  String get navBinEmpty => '没有已删除的内容。';

  @override
  String get navBinItems => '项目';

  @override
  String get navBinNotebooks => '笔记本';

  @override
  String navBinRetention(int days) {
    return '这里的内容会在 $days 天后被彻底删除。';
  }

  @override
  String get navClose => '关闭';

  @override
  String get navCollapse => '收起导航栏  (Ctrl+\\)';

  @override
  String get navColour => '颜色';

  @override
  String get navColourDefault => '默认';

  @override
  String get navComingUp => '即将到来';

  @override
  String get navDeleteForever => '永久删除';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '“$title”及其所有页面都将被永久删除，无法撤销。$caveat';
  }

  @override
  String get navDeleteForeverTitle => '彻底删除？';

  @override
  String get navDeletePermanently => '彻底删除';

  @override
  String navDeletedGroup(String title) {
    return '已将分区组“$title”移至回收站';
  }

  @override
  String navDeletedPage(String title) {
    return '已将页面“$title”移至回收站';
  }

  @override
  String navDeletedSection(String title) {
    return '已将分区“$title”移至回收站';
  }

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
  String get navDeletesSoon => '即将删除';

  @override
  String navExamCountdown(String when, String countdown) {
    return '考试 $when · $countdown…';
  }

  @override
  String get navExpand => '展开导航栏  (Ctrl+\\)';

  @override
  String get navSectionsHeader => '分区';

  @override
  String get navNewSectionOrGroup => '新建分区或分区组';

  @override
  String get dropMoveAbove => '移到上方';

  @override
  String get dropMoveBelow => '移到下方';

  @override
  String get dropMakeSubpage => '设为子页面';

  @override
  String get dropGroupTogether => '归为一组';

  @override
  String get dropMoveIntoGroup => '移入该组';

  @override
  String get dropMoveToSection => '移到此分区';

  @override
  String get navBinEmptyAction => '清空';

  @override
  String get navBinEmptyTitle => '清空回收站？';

  @override
  String get navBinEmptyBody => '里面的所有内容都将被永久删除，且无法撤销。';

  @override
  String get navBinEmptySharedNote => '共享文件夹中的笔记本只会从这台电脑上移除。';

  @override
  String navBinDeleteOneBody(String title) {
    return '“$title”将被永久删除，且无法撤销。';
  }

  @override
  String get navBinKindPage => '页面';

  @override
  String get navBinKindSection => '分区';

  @override
  String get navBinKindGroup => '分组';

  @override
  String get navBinKindNotebook => '笔记本';

  @override
  String navBinItemLine(String kind, String when) {
    return '$kind · $when';
  }

  @override
  String get navBinWhenToday => '今天';

  @override
  String get navBinWhenYesterday => '昨天';

  @override
  String navBinWhenDaysAgo(int days) {
    return '$days 天前';
  }

  @override
  String get reviewTitle => '检查文字';

  @override
  String reviewChip(int count) {
    return '$count 项待检查';
  }

  @override
  String get reviewChipClear => '没有写作问题';

  @override
  String get reviewTooltip => '检查文字（F7）';

  @override
  String get reviewChecking => '正在检查文字…';

  @override
  String fixNoticeRevert(String word) {
    return '还原为“$word”';
  }

  @override
  String reviewSubtitle(int count, String language) {
    return '本页 · $count 项待检查 · $language';
  }

  @override
  String get reviewSpelling => '拼写';

  @override
  String get reviewGrammar => '语法';

  @override
  String get reviewPunctuation => '标点';

  @override
  String get reviewFixAll => '全部修正';

  @override
  String get reviewAccept => '接受';

  @override
  String get reviewIgnore => '忽略';

  @override
  String get reviewAddToDictionary => '添加到词典';

  @override
  String get reviewNotInDictionary => '不在词典中';

  @override
  String get reviewRemove => '删除';

  @override
  String get reviewAllClear => '本页没有需要检查的内容。';

  @override
  String reviewFixedSpelling(int count) {
    return '已修正 $count 处拼写错误';
  }

  @override
  String reviewFixedGrammar(int count) {
    return '已修正 $count 处语法错误';
  }

  @override
  String reviewFixedPunctuation(int count) {
    return '已修正 $count 处标点错误';
  }

  @override
  String get navHideSections => '隐藏分区列表';

  @override
  String get navRecent => '最近';

  @override
  String get navHomeEmpty => '这里还什么都没有。\n\n右键点击页面并选择「收藏」即可固定；你打开过的页面会出现在「最近」里。';

  @override
  String get navRecentTip => '最近的页面和收藏';

  @override
  String get navInPageContent => '在页面内容中';

  @override
  String get navLinkCopied => '链接已复制 — 可以粘贴到任何页面';

  @override
  String navLockedCannotDelete(String title) {
    return '“$title”已锁定。请先移除密码再删除。';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '“$title”已锁定。它只是在 Openote 里被隐藏，文件本身并未加密。';
  }

  @override
  String get navMenuAddFavourite => '加入收藏';

  @override
  String get navMenuCopyLink => '复制页面链接';

  @override
  String get navMenuDelete => '删除';

  @override
  String get navMenuDuplicate => '复制';

  @override
  String get navMenuExportSectionPdf => '把分区导出为 PDF…';

  @override
  String get navMenuLock => '用密码锁定…';

  @override
  String get navMenuMakeSubpage => '设为子页面';

  @override
  String get navMenuMoveBackOut => '取消子页面';

  @override
  String get navMenuMoveDown => '下移';

  @override
  String get navMenuMoveToGroup => '移动到分区组…';

  @override
  String get navMenuMoveUp => '上移';

  @override
  String get navMenuNewPage => '新建页面';

  @override
  String get navMenuPrint => '打印…';

  @override
  String get navMenuPrintSection => '打印分区…';

  @override
  String get navMenuRecentChanges => '最近的修改…';

  @override
  String get navMenuRemoveExam => '移除考试日期';

  @override
  String get navMenuRemoveFavourite => '取消收藏';

  @override
  String get navMenuRemovePasscode => '移除密码…';

  @override
  String get navMenuRename => '重命名';

  @override
  String get navMenuSetExam => '设置考试日期…';

  @override
  String get navMenuSharePdf => '以 PDF 分享…';

  @override
  String get navMenuSortAZ => '按标题排序';

  @override
  String get navMenuSortEdited => '按最后修改时间排序';

  @override
  String get navMoveSectionTo => '把分区移动到…';

  @override
  String navNewPageIn(String section) {
    return '在 $section 中新建页面';
  }

  @override
  String get navNewSection => '新建分区';

  @override
  String get navNewSectionGroup => '新建分组';

  @override
  String get navNoGroupTopLevel => '（不属于任何组 — 顶层）';

  @override
  String navNoMatches(String query) {
    return '没有找到“$query”';
  }

  @override
  String get navNoPages => '还没有页面';

  @override
  String get navNoSections => '还没有分区。\n新建一个即可开始。';

  @override
  String get navNotebooksTip => '笔记本 — 切换、重命名、复制、导入';

  @override
  String get navOpen => '打开';

  @override
  String navPasscodeRemoved(String title) {
    return '已移除“$title”的密码。';
  }

  @override
  String get navRecycleBin => '回收站';

  @override
  String get navRestore => '还原';

  @override
  String get navSave => '保存';

  @override
  String navSavedTo(String path) {
    return '已保存到 $path';
  }

  @override
  String get navSearchHint => '搜索或跳转到…';

  @override
  String get navSection => '分区';

  @override
  String get navShowSections => '显示分区列表';

  @override
  String get navUndo => '撤销';

  @override
  String get navUntitled => '无标题';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return '正在检查第 $done 页，共 $total 页…';
  }

  @override
  String get nbCheckingPages => '正在检查页面…';

  @override
  String get nbConfirmBin => '移到回收站？之后可以从这里还原。';

  @override
  String get nbConfirmBinShared =>
      '这个笔记本在共享文件夹里。从这台电脑上移除它，它仍会留在文件夹和你的其他设备上——随时可以用“打开”再添加回来。';

  @override
  String get nbRemoveFromComputer => '从这台电脑移除';

  @override
  String get nbDeleteEverywhere => '到处删除…';

  @override
  String nbDeleteEverywhereTitle(String title) {
    return '到处删除“$title”？';
  }

  @override
  String get nbDeleteEverywhereBody => '这会把它从共享文件夹里删掉，所有使用该文件夹的设备都会失去它。无法撤销。';

  @override
  String get nbDeleteEverywhereConfirm => '到处删除';

  @override
  String nbRemoveSharedTitle(String title) {
    return '从这台电脑移除“$title”？';
  }

  @override
  String get nbRemoveSharedBody => '它仍留在共享文件夹和你的其他设备上。随时可以用“打开”再添加回来。';

  @override
  String get nbCoreMissing =>
      'OneNote 导入需要 Rust 内核 — 请编译 onote_core.dll（见 rust/onote_core/INTEGRATION.md）。';

  @override
  String get nbCreate => '创建';

  @override
  String get nbDuplicate => '复制';

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '“$title”有 $copies 份副本 · 每份 $pages 页 · 可释放 $size';
  }

  @override
  String get nbDuplicates => '可能重复 · 标题相同且页数相同';

  @override
  String get nbDuplicatesHint => '保留最大的那个 — 较小的通常是中途中断的导入。删除的副本会进入回收站。';

  @override
  String get nbGetStarted => '开始使用';

  @override
  String get nbImport => '导入';

  @override
  String get nbImportBusy => '已经有一个导入在进行 — 一次只能导入一个。';

  @override
  String get nbImportGit => '从 git 地址导入';

  @override
  String get nbImportDriveFolder => '从 Drive 文件夹打开';

  @override
  String get nbImportInto => '导入到新的笔记本';

  @override
  String get nbImportMarkdown => 'Markdown 文件夹';

  @override
  String get nbImportOne => 'OneNote 分区 (.one)';

  @override
  String get nbImportOnepkg => 'OneNote 笔记本 (.onepkg)';

  @override
  String get nbImportStarted => '正在后台导入 — 你可以继续做别的，完成后角落的卡片会提示。';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return '已从 OneNote 导入 $what。$strokeNote';
  }

  @override
  String nbImportedNamed(String name) {
    return '已导入 $name';
  }

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
  String nbImportedPagesProgress(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导入 $count 页…',
    );
    return '$_temp0';
  }

  @override
  String nbImportedProgress(String done) {
    return '已导入 $done';
  }

  @override
  String nbInBin(int days) {
    return '在回收站中 · $days 天后删除';
  }

  @override
  String get nbMoveToBin => '移到回收站';

  @override
  String get nbNameHint => '笔记本名称';

  @override
  String get nbNeedsNativeCore =>
      'OneNote 导入需要 Rust 内核 — 请编译 onote_core.dll 并放在程序旁边。';

  @override
  String get nbNew => '新建';

  @override
  String get nbNewTitle => '新建笔记本';

  @override
  String get nbNoMarkdown => '那个文件夹里没有找到 Markdown 文件。';

  @override
  String get nbNothingToRepair => '没有需要修复的内容 — 所有页面都是最新的。';

  @override
  String get nbOneFileEmpty => '没能从那个 .one 文件里读出任何内容。';

  @override
  String get nbOnePkgFileType => 'OneNote 笔记本包';

  @override
  String nbOpenCount(int count) {
    return '已打开 $count 个';
  }

  @override
  String get nbOpenThis => '打开这个笔记本';

  @override
  String nbReadFileFailed(String reason) {
    return '无法读取该文件：$reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return '无法导入该文件夹：$reason';
  }

  @override
  String get nbReadingFolder => '正在读取文件夹…';

  @override
  String get nbRename => '重命名';

  @override
  String get nbRepair => '修复';

  @override
  String nbRepairFailed(String reason) {
    return '修复失败：$reason';
  }

  @override
  String nbRepaired(String boxes, String pages) {
    return '已在 $pages 中修复 $boxes。';
  }

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
  String get nbTitle => '笔记本';

  @override
  String objectRowBackground(String kind) {
    return '背景：$kind';
  }

  @override
  String get objectRowBackgroundBlank => '空白';

  @override
  String get objectRowBackgroundDotted => '点阵';

  @override
  String get objectRowBackgroundGrid => '方格';

  @override
  String get objectRowBackgroundRuled => '横线';

  @override
  String get objectRowCanvasMode => '画布模式：无边界 — 点击切换到分页';

  @override
  String get objectRowCharacters => '字符';

  @override
  String get objectRowCharactersNoSpaces => '不含空格';

  @override
  String get objectRowLandscape => '横向';

  @override
  String get objectRowLandscapeSuffix => ' 横向';

  @override
  String objectRowMinutes(int n) {
    return '$n 分钟';
  }

  @override
  String objectRowPageMode(String paper, String landscape) {
    return '分页模式：$paper$landscape — 点击切换到画布';
  }

  @override
  String get objectRowPaperSize => '纸张大小';

  @override
  String get objectRowReadingTime => '阅读时间';

  @override
  String get objectRowSnapOff => '对齐网格：关 — 自由摆放';

  @override
  String get objectRowSnapOn => '对齐网格：开（拖动时显示网格）';

  @override
  String get objectRowWordCount => '本页字数 — 点击查看字符数和阅读时间';

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
  String get objectRowWords => '字数';

  @override
  String get objectRowZoomFit => '缩放以显示全部内容';

  @override
  String get objectRowZoomIn => '放大  (Ctrl+=)';

  @override
  String get objectRowZoomOut => '缩小  (Ctrl+-)';

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent%';
  }

  @override
  String get objectRowZoomReset => '回到 100% 并回到页首  (Ctrl+0)';

  @override
  String get onboardingCloudAction => '登录';

  @override
  String get onboardingCloudBody => '登录 Microsoft 并选择一个笔记本。无需先导出，任何电脑都能用。';

  @override
  String get onboardingCloudTitle => '从 OneNote 导入笔记';

  @override
  String get onboardingExportMacNote =>
      '如果用的是 Mac，或者只有商店版：可以一个分区一个分区地导出为 .one，或者找一台 Windows 电脑生成 .onepkg。Openote 从不登录你的 Microsoft 账号 — 它只读取你交给它的文件。';

  @override
  String get onboardingExportSteps =>
      '1. 打开 Windows 版 OneNote（桌面版 — 商店版和网页版无法导出）。\n2. 等笔记本同步完成，确保内容都在这台电脑上。\n3. 文件 ▸ 导出 ▸ 笔记本 ▸ OneNote 程序包 (*.onepkg)，然后点导出。\n4. 回到这里选择那个文件。';

  @override
  String get onboardingExportTitle => '从 OneNote 导出';

  @override
  String get onboardingFreshAction => '从空白开始';

  @override
  String get onboardingFreshBody => '一个空白笔记本，可以直接开始写。之后随时可以导入笔记。';

  @override
  String get onboardingFreshTitle => '新建笔记本';

  @override
  String get onboardingImportDone => '你的笔记本准备好了';

  @override
  String get onboardingImportRunning => '继续做你的事 — 这在后台进行，完成后角落的卡片会提示。';

  @override
  String onboardingImportingFile(String fileName) {
    return '正在导入 $fileName';
  }

  @override
  String get onboardingNoNativeCore => 'OneNote 导入需要原生内核，而这个版本没有包含它。';

  @override
  String get onboardingOneNoteAction => '选择文件…';

  @override
  String get onboardingOneNoteBody =>
      '从 .onepkg 导入页面、格式、图片、手写和标记。在后台进行 — 你可以继续做别的。';

  @override
  String get onboardingOneNoteHideSteps => '隐藏步骤';

  @override
  String get onboardingOneNoteHowTo => '怎么导出？';

  @override
  String get onboardingOneNoteTitle => '把笔记从 OneNote 搬过来';

  @override
  String get onboardingOnePkgFileType => 'OneNote 笔记本包';

  @override
  String get onboardingOpenFailed => 'Openote 无法打开那个笔记本。';

  @override
  String onboardingReadFailed(String reason) {
    return '无法读取该文件：$reason';
  }

  @override
  String get onboardingStartWriting => '开始书写';

  @override
  String get onboardingStep1Body =>
      '在任意位置点击就能开始写 — 文本框出现在你点击的地方，而且只有你开始输入时才出现。用顶部的横条移动它，图片可以从任何地方拖进来。';

  @override
  String get onboardingStep1Title => '页面就是一块画布';

  @override
  String get onboardingStep2Body =>
      '输入 1/2 或按 Alt+=，边写边生成真正的数学排版，既可以单独成框，也可以写在句子中间。「绘图」标签支持触控笔、手指和鼠标。';

  @override
  String get onboardingStep2Title => '公式和手写，就在文字中间';

  @override
  String get onboardingStep3Body =>
      '每个笔记本就是一个开放、可读的文件 — 不用账号，也不会被绑定。把它放进云盘已经在同步的文件夹里，所有设备就能保持一致。';

  @override
  String get onboardingStep3Title => '笔记是属于你自己的文件';

  @override
  String get onboardingSyncAction => '去设置…';

  @override
  String get onboardingSyncBodyAlso => '都不是？那就自己选一个文件夹。';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive、OneDrive、iCloud、Dropbox、Syncthing、NAS — 或者一个 GitHub 仓库。';

  @override
  String get onboardingSyncTitle => '与另一台设备同步';

  @override
  String get oneNoteCloudContinue => '继续使用 Microsoft';

  @override
  String get oneNoteCloudEmpty => '此账户下未找到任何笔记本。';

  @override
  String get oneNoteCloudIntro => 'Openote 将读取你在 OneNote 中的笔记本，不会修改它们。';

  @override
  String get oneNoteCloudLoading => '正在查找你的笔记本…';

  @override
  String get oneNoteCloudNoInk => '表格会适应页面宽度，而不是保留原有宽度；文字颜色和字体也不会导入。';

  @override
  String get oneNoteCloudOther => '使用其他账户';

  @override
  String get oneNoteCloudSignIn => '登录 Microsoft';

  @override
  String get oneNoteCloudSigningIn => '正在等待浏览器…';

  @override
  String get oneNoteCloudTitle => '从 OneNote 导入笔记本';

  @override
  String get oneNoteFileBody =>
      '无需登录，且最为完整：表格会保留原有宽度。需要先在 Windows 版 OneNote 中导出笔记本。';

  @override
  String get oneNoteFileTitle => '使用导出的文件';

  @override
  String get oneNotePickTitle => '选择哪个笔记本？';

  @override
  String get oneNoteSignInBody => '选择一个笔记本即可直接导入，无需事先导出。任何电脑都能用。';

  @override
  String get penButtonEraser => '橡皮擦';

  @override
  String get penButtonLasso => '套索';

  @override
  String get penButtonNothing => '无';

  @override
  String get penButtonSelect => '选择';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsAi => 'AI 访问';

  @override
  String get settingsAiOff => '关 — 可连接 Claude 或其他 AI 助手。';

  @override
  String get settingsAiOn => '已开启 — 本机上的 AI 可以读取你的笔记。';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsCheckUpdates => '检查更新';

  @override
  String get settingsConnections => '连接';

  @override
  String get settingsDiagnostics => '诊断';

  @override
  String get settingsHelp => '帮助';

  @override
  String get settingsUiScale => '界面大小';

  @override
  String get settingsUiScaleHint => '放大或缩小整个窗口。';

  @override
  String settingsUiScaleLimited(String size) {
    return '当前显示为 $size：此窗口太小，无法再放大。';
  }

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageAuto => '系统默认';

  @override
  String get settingsLanguageContribute => '如何添加或修正一种语言';

  @override
  String get settingsPenAndTouch => '触控笔与触摸';

  @override
  String get settingsPenButton => '触控笔侧键';

  @override
  String get settingsPenButtonHint => '按住即可临时使用该工具。';

  @override
  String get settingsPenTest => '触控笔与触摸测试';

  @override
  String get settingsPenTestHint => '你的触控笔及其按键汇报的内容。';

  @override
  String get settingsShortcuts => '键盘快捷键';

  @override
  String get settingsShortcutsHint => 'Ctrl+/';

  @override
  String get settingsReportProblem => '报告问题或提出想法';

  @override
  String get settingsReportProblemHint => '打开 GitHub，需要一个免费的 GitHub 账号。';

  @override
  String get settingsSpellCheck => '拼写检查';

  @override
  String get settingsSync => '同步';

  @override
  String get settingsSyncHint => '将此笔记本备份到 GitHub 或文件夹。';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsTouchDrawing => '用手指绘图';

  @override
  String get settingsTouchDrawingHint => '双指始终用于平移和缩放。';

  @override
  String settingsUpToDate(String version) {
    return '已是最新版本（$version 就是最新版）。';
  }

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsWelcomeTour => '新手导览';

  @override
  String get settingsWelcomeTourHint => '三分钟了解画布的用法。';

  @override
  String get settingsWhatsNew => '更新内容';

  @override
  String get settingsWriting => '书写与绘图';

  @override
  String get shellAlreadyUpToDate => '已经是最新的了。';

  @override
  String get shellCheatSheet =>
      'V 选择 · T 文字 · P 钢笔 · H 荧光笔 · E 擦除 · Ctrl+Z 撤销 · Ctrl+滚轮 缩放';

  @override
  String get shellCloseEsc => '关闭 (Esc)';

  @override
  String get shellCreateFirstPage => '创建第一页';

  @override
  String get shellDemoNothingSaved => '演示版 — 内容不会保存';

  @override
  String get shellEmptyBody => '你在这里做的一切都留在自己的设备上，\n用的是属于你自己的开放格式。';

  @override
  String get shellEmptyTitle => '一页空白，等你来写';

  @override
  String get shellFindOnThisPage => '在本页中查找…';

  @override
  String get shellHeadingsHint => '在行首输入 # 就能变成标题 — 大纲会在你书写时自动生成。';

  @override
  String get shellLinkedFrom => '被链接自';

  @override
  String get shellLinksTo => '链接到';

  @override
  String get shellNextMatch => '下一个匹配 (Enter)';

  @override
  String get shellNoBacklinks => '还没有页面链接到这里。';

  @override
  String get shellNoHeadings => '本页没有标题。';

  @override
  String get shellNoLinks => '这个页面还没有链接到任何地方。';

  @override
  String get shellNoMatches => '没有匹配项';

  @override
  String get shellNoTags => '这个笔记本里还没有标记。';

  @override
  String get shellNothingReplaced => '没有替换任何内容';

  @override
  String shellPageLocked(String title) {
    return '“$title”已锁定';
  }

  @override
  String get shellPreviousMatch => '上一个匹配 (Shift+Enter)';

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
  String get shellReplace => '替换';

  @override
  String get shellReplaceAll => '全部';

  @override
  String get shellReplaceWith => '替换为…';

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
  String shellRustLinked(String build) {
    return 'Rust 内核（onote-core）已链接，保存时会计算本页内容的哈希值。\n$build';
  }

  @override
  String get shellRustMissing => '正在使用纯 Dart 引擎。编译 onote-core 库即可链接 Rust 内核。';

  @override
  String get shellSavedLocally => '这一页已保存到你本地的 .onote 文件中。';

  @override
  String get shellSavedOnDevice => '已保存在本机';

  @override
  String get shellSaving => '正在保存…';

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag（$count）';
  }

  @override
  String get shellTagTheLine => '标记当前所在的行';

  @override
  String get shellTagsHint =>
      '标记用来标注某一行 — 待办、重要、问题、定义 — 方便你以后找回、复习，或者给它加个截止日期。';

  @override
  String get shellUnlock => '解锁';

  @override
  String get tableColumnLeft => '在左侧插入列';

  @override
  String get tableColumnRight => '在右侧插入列';

  @override
  String get tableDeleteColumn => '删除列';

  @override
  String get tableDeleteRow => '删除行';

  @override
  String get tableRowAbove => '在上方插入行';

  @override
  String get tableRowBelow => '在下方插入行';

  @override
  String get tagContact => '联系人';

  @override
  String get tagCritical => '紧急';

  @override
  String get tagCustom => '标记';

  @override
  String get tagDefinition => '定义';

  @override
  String get tagIdea => '想法';

  @override
  String get tagImportant => '重要';

  @override
  String get tagQuestion => '问题';

  @override
  String get tagRemember => '记住';

  @override
  String get tagTodo => '待办';

  @override
  String get touchDrawAlways => '总是';

  @override
  String get touchDrawAuto => '自动（以笔为准）';

  @override
  String get touchDrawNever => '从不';

  @override
  String updateAvailable(String version) {
    return 'Openote $version 已发布';
  }

  @override
  String updateYouHave(String version) {
    return '你当前的版本是 $version。';
  }

  @override
  String get updateDownloading => '正在下载…';

  @override
  String updateDownloadingPercent(int percent) {
    return '正在下载… $percent%';
  }

  @override
  String get updateSavedClosing => '你的笔记已保存。Openote 会关闭、完成更新，然后自动重新打开。';

  @override
  String get updateWillRestart => '系统会先保存你的笔记。安装更新时 Openote 会关闭，完成后自动重新打开。';

  @override
  String get updateInstallYourself => '你需要自己下载并安装。';

  @override
  String get updateNotNow => '暂不更新';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateDownload => '前往下载';

  @override
  String get settingsGrammarCheck => '检查语法';

  @override
  String get settingsAutoCorrect => '输入时自动更正小的拼写错误';

  @override
  String get settingsAutoCapitalize => '句首自动大写';

  @override
  String get settingsSpellLanguage => '拼写检查语言';

  @override
  String get settingsSpellLanguageSystem => '系统默认';

  @override
  String get settingsSpellLanguageOther => '其他语言（不检查）';

  @override
  String get settingsEnglishAU => '英语（澳大利亚）';

  @override
  String get settingsEnglishGB => '英语（英国）';

  @override
  String get settingsEnglishUS => '英语（美国）';

  @override
  String get settingsEnglishCA => '英语（加拿大）';

  @override
  String get settingsEnglishIN => '英语（印度）';

  @override
  String get settingsWritingEnglishOnly =>
      '语法、拼写自动更正和大小写目前只适用于英语。其他语言下这些功能保持关闭。';

  @override
  String get barTabWrite => '书写';

  @override
  String get insertNotYet => '暂不支持';

  @override
  String get barHideKeyboard => '收起键盘';

  @override
  String get pageSheetBlank => '空白';

  @override
  String get pageSheetGrid => '方格';

  @override
  String get pageSheetDots => '点阵';

  @override
  String get pageSheetRuled => '横线';

  @override
  String get pageSheetPaper => '纸张';

  @override
  String get pageSheetCanvas => '画布';

  @override
  String get pageSheetSnap => '吸附';

  @override
  String get pageSheetFit => '适应';

  @override
  String get navOpening => '正在打开此笔记本…';

  @override
  String get openFolderTitle => '从文件夹打开笔记本';

  @override
  String get openFolderBody =>
      '请选择存放笔记本的文件夹，例如 Google Drive、OneDrive 或 Dropbox 中的文件夹。Openote 会在其中查找笔记本。';

  @override
  String get openFolderChoose => '选择文件夹…';

  @override
  String get openFolderNone =>
      '那里没有找到笔记本。请选择存放笔记本的文件夹，或笔记本自己的文件夹（名称以 .onotebook 结尾）。';

  @override
  String get openFolderLooking => '正在查找笔记本…';

  @override
  String get openFolderAndroidHint =>
      '请选择存放笔记本的文件夹。在 Google Drive 中通常是名为“Openote”的那个。然后点按“使用此文件夹”。';

  @override
  String get openFolderFound => '找到的笔记本';

  @override
  String protectLockTitle(String title) {
    return '锁定“$title”';
  }

  @override
  String protectLockedTitle(String title) {
    return '“$title”已锁定';
  }

  @override
  String get protectBetaHeadline => '测试版：这只会在 Openote 里隐藏该页面，还不会加密它。';

  @override
  String get protectBetaBody =>
      '目前，任何拿到你笔记本文件的人仍然可以读取该页面，而且忘记的密码无法找回。真正的加密功能正在计划中。';

  @override
  String get protectPasscode => '密码';

  @override
  String get protectPasscodeAgain => '再次输入密码';

  @override
  String get protectAskAgain => '再次询问…';

  @override
  String get protectLock => '锁定';

  @override
  String get protectEnterPasscode => '请输入密码。';

  @override
  String get protectMismatch => '两次输入不一致。';

  @override
  String get protectWrong => '密码不正确。';

  @override
  String get protectPolicyAlways => '每次打开时';

  @override
  String get protectPolicyTenMinutes => '10 分钟内';

  @override
  String get protectPolicyOneHour => '1 小时内';

  @override
  String get protectPolicySession => '直到关闭 Openote';

  @override
  String get linkTitleNew => '链接';

  @override
  String get linkTitleEdit => '编辑链接';

  @override
  String get linkTextToShow => '显示的文字';

  @override
  String get linkNothingSelected => '没有选中任何可以变成链接的内容';

  @override
  String get linkAddress => '地址';

  @override
  String get linkOrPage => '或链接到某个页面';

  @override
  String get linkRemove => '移除链接';

  @override
  String get linkUpdate => '更新';

  @override
  String get linkInsert => '插入';

  @override
  String get linkNeedWords => '请为链接填写要显示的文字。';

  @override
  String get linkBadAddress =>
      '这看起来不是 Openote 能打开的地址。可以试试 https://example.com 这样的地址';

  @override
  String get linkNoCaret => '请先把光标放到链接要放的位置。';

  @override
  String get linkOneLine => '链接必须在同一行内。请选中同一行里的文字。';

  @override
  String get linkOnObject => '图片、表格或卡片不能加链接。请把链接加在文字上。';

  @override
  String get linkOnMaths => '公式不能加链接——方括号属于公式本身。';

  @override
  String get linkBrackets => '链接文字不能包含方括号。请选择不含方括号的内容。';

  @override
  String get linkNested => '这段文字已经有格式或链接。请选择普通文字，或点进链接里编辑它。';

  @override
  String get alertsTitle => '上课前提醒';

  @override
  String get alertsIntro =>
      'Openote 可以在课表中的事项开始前弹出提醒。它会根据名称判断每个日程的类型，所以请只选你真正想被打断的类型。';

  @override
  String get alertsPreset => '上课前 10 分钟提醒我';

  @override
  String get alertsAllOff => '全部关闭';

  @override
  String get alertsWhileRunning =>
      '提醒只在 Openote 里显示，所以只有在它运行时才会提醒你。错过的提醒会在你下次打开时留在这个面板里。';

  @override
  String get alertsAtStart => '开始时';

  @override
  String alertsMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get eventKindLecture => '讲座课';

  @override
  String get eventKindTutorial => '辅导课';

  @override
  String get eventKindLab => '实验 / 实践';

  @override
  String get eventKindWorkshop => '研讨工作坊';

  @override
  String get eventKindSeminar => '研讨课';

  @override
  String get eventKindExam => '考试 / 测验';

  @override
  String get eventKindMeeting => '会议';

  @override
  String get eventKindOther => '其他所有';

  @override
  String get commonOk => '确定';

  @override
  String get saveProblemNotAddedShort => '没有添加成功';

  @override
  String get saveProblemNotAdded =>
      'Openote 无法保存你刚添加的图片或文件，所以它不在你的笔记本里。\n\n请检查磁盘是否已满、笔记本所在文件夹是否设为只读，然后重新粘贴或拖入。';

  @override
  String get saveProblemNotOnDriveShort => '尚未发送到 Drive';

  @override
  String get saveProblemNotOnDrive =>
      '你的更改已保存在这部手机上。暂时无法发送到 Drive 文件夹（没有网络，或无法访问该文件夹），等能访问时会自动发送。';

  @override
  String get saveProblemNotRecordedShort => '已保存，但未记录';

  @override
  String get saveProblemNotRecorded =>
      'Openote 已把你的笔记保存在这台电脑上，但无法把这次更改写入此笔记本的历史记录。\n\n你的其他设备、备份和共享文件夹都从历史记录读取，因此在恢复正常之前它们可能会落后。你写的内容没有丢失。\n\n请检查磁盘是否已满、笔记本所在文件夹是否设为只读，以及 OneDrive 或 Google Drive 等云应用是否已处理完它。每次保存时 Openote 都会重试。';

  @override
  String get saveProblemPageShort => '未能保存 — 更改仍在内存中';

  @override
  String get saveProblemPage =>
      'Openote 无法把此页面保存到你的电脑上。\n\n你的更改仍在屏幕上，下次你输入或关闭窗口时 Openote 会再试一次。第一次关闭窗口时，窗口会保持打开，方便你解决问题；如果再次关闭，Openote 将不保存这些更改直接退出。\n\n请检查磁盘是否已满，以及笔记本是否在其他程序中打开。';

  @override
  String get saveProblemPicturesShort => '部分图片可能丢失';

  @override
  String saveProblemPictures(int count) {
    return 'Openote 会在此笔记本自己的文件夹里为每张图片和绘图保留第二份副本，好让你的其他设备和备份也能显示它们。\n\n其中有 $count 个，Openote 在这台电脑上的任何地方都找不到完好的数据——第二份副本里没有，笔记本自己的工作文件里也没有。在它们重新出现之前（来自其他设备、备份，或重新添加图片），凡是用到它们的地方都会显示为空白，这台电脑和其他电脑都一样。\n\n请检查磁盘是否已满、文件夹是否设为只读，然后关闭笔记本再重新打开。每次打开时 Openote 都会重试。';
  }

  @override
  String get saveProblemListLockedShort => '你的笔记本列表已锁定';

  @override
  String get saveProblemNewerShort => '只读 — 由更新版 Openote 创建';

  @override
  String get saveProblemNewer =>
      '此笔记本包含由更新版本的 Openote 做出的更改，当前版本无法读取。\n\n因此 Openote 会在不改动它的情况下显示此笔记本。其中的内容都很安全，你在这里的任何操作都不会损坏它——但你现在输入的内容不会被保留。\n\n把 Openote 更新到最新版本后即可再次编辑。';

  @override
  String get saveProblemListShort => '无法保存笔记本列表';

  @override
  String get saveProblemList =>
      'Openote 无法保存你的笔记本列表和设置。第一次关闭窗口时，窗口会保持打开。请检查磁盘后重试，或再次关闭窗口直接退出。';

  @override
  String get mcpTitle => 'AI 访问';

  @override
  String get mcpIntro =>
      '让 AI 助手（例如 Claude）阅读和搜索你的笔记、向你提问，并根据笔记制作抽认卡。它只在 Openote 打开时、只在这台电脑上工作，它添加的任何内容都是普通编辑：按 Ctrl+Z 即可撤销。';

  @override
  String get mcpPasscodeNote =>
      '设了密码的内容保持私密：即使你已解锁，AI 助手也看不到、改不了。密码锁住的是 Openote，而不是文件本身，所以能打开你电脑上文件的 AI 工具仍可能读取它。';

  @override
  String mcpCouldNotStart(String error) {
    return '无法启动：$error';
  }

  @override
  String mcpReady(String lastUsed) {
    return '已就绪。$lastUsed';
  }

  @override
  String get mcpNeverUsed => '自 Openote 打开以来还没有 AI 助手使用过。';

  @override
  String get mcpUsedJustNow => '刚刚被 AI 助手使用过。';

  @override
  String mcpUsedMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes 分钟前被 AI 助手使用过。',
    );
    return '$_temp0';
  }

  @override
  String mcpUsedHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours 小时前被 AI 助手使用过。',
    );
    return '$_temp0';
  }

  @override
  String get mcpUsedOverADay => '一天多以前被 AI 助手使用过。';

  @override
  String get mcpRestartHint => 'AI 助手会在启动时寻找 Openote。如果你的助手之前已经打开，请重启它。';

  @override
  String mcpClientIsSetUp(String name) {
    return '$name — 已设置';
  }

  @override
  String mcpSetUpClient(String name) {
    return '设置 $name';
  }

  @override
  String get mcpClaudeApp => 'Claude 应用';

  @override
  String get mcpChatGptApp => 'ChatGPT 应用';

  @override
  String get mcpWebsiteNote =>
      'ChatGPT 网站无法连接：它的连接器运行在 OpenAI 的服务器上，看不到你的电脑。上面的按钮是给桌面应用用的，它从这台电脑读取设置。Gemini 应用和网站一样——它的 CLI 有按钮。';

  @override
  String get mcpCopyAddress => '复制地址';

  @override
  String get mcpCopyConfiguration => '复制配置';

  @override
  String get mcpOtherTools => '其他 AI 工具（高级）';

  @override
  String get mcpOtherToolsBody =>
      'Openote 支持 MCP，这是 AI 工具连接应用的标准。任何支持 MCP 的工具都能使用——其中的密钥相当于密码，只粘贴到你信任的工具里。';

  @override
  String mcpListening(String port) {
    return '正在监听端口 $port，仅限这台电脑。';
  }

  @override
  String get mcpNotListening => '未在监听。';

  @override
  String get mcpCopyConfig => '复制配置';

  @override
  String get mcpCliIntro => '或者，对于命令行工具，运行一次：';

  @override
  String get mcpCopyCommand => '复制命令';

  @override
  String get mcpCopied => '已复制。其中的密钥相当于密码——只粘贴到你自己的工具里。';

  @override
  String get mcpChatGptUnreadable =>
      '无法读取 ChatGPT 的设置文件，所以 Openote 没有动它。“高级”中的连接信息仍然可用。';

  @override
  String get mcpChatGptUnparsable =>
      'ChatGPT 的设置文件里有 Openote 看不懂的内容，所以没有动它。请复制“高级”中的配置，手动添加。';

  @override
  String mcpSaveFailed(String error) {
    return '无法保存连接：$error';
  }

  @override
  String get mcpChatGptSetUp =>
      '已设置。重启 ChatGPT 桌面应用后，Openote 会出现在它的 MCP 服务器中。网站无法使用——只有这台电脑上的应用才能看到 Openote。';

  @override
  String get mcpChatGptSavedOnly =>
      '已保存。在这台电脑上安装 ChatGPT 桌面应用或 Codex CLI 后，Openote 就会出现。';

  @override
  String mcpClientUnreadable(String name) {
    return '无法读取 $name 的设置文件，所以 Openote 没有动它。“高级”中的连接信息在任何支持 MCP 的工具里仍然可用。';
  }

  @override
  String mcpClientSetUp(String name) {
    return '已设置。如果 $name 已经打开，请重启它——它会在启动时寻找 Openote。然后问问它关于你笔记的问题，比如“就我这周写的内容考考我”。';
  }

  @override
  String mcpClientNotInstalled(String name) {
    return 'Openote 已就绪，但 $name 似乎还没有安装在这台电脑上。安装后连接就会自动生效。';
  }
}
