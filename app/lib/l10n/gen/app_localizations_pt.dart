// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class LPt extends L {
  LPt([String locale = 'pt']) : super(locale);

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get barBlankOut => 'Ocultar a seleção';

  @override
  String get barBlankOutNeedsSelection =>
      'Selecione antes as palavras que quer ocultar.';

  @override
  String get barBold => 'Negrito  (Ctrl+B)';

  @override
  String get barBulletList => 'Lista com marcadores';

  @override
  String get barCheckbox => 'Caixa de seleção';

  @override
  String get barClickIntoTextBox => 'Clique numa caixa de texto';

  @override
  String get barDefinitionCard => 'Cartão de definição';

  @override
  String get barDone => 'Pronto';

  @override
  String get barDueDateChange => 'Mudar o prazo…';

  @override
  String get barDueDateClear => 'Tirar o prazo';

  @override
  String get barDueDatePickerConfirm => 'Definir';

  @override
  String get barDueDatePickerTitle => 'Prazo';

  @override
  String get barDueDateSet => 'Prazo…';

  @override
  String get barEquationBadge => 'Equação';

  @override
  String get barEraserSplit => 'Corta os traços onde você esfrega';

  @override
  String get barEraserWhole => 'Apaga o traço inteiro que você tocar';

  @override
  String get barEscWhenDone => 'Esc quando terminar';

  @override
  String get barExport => 'Exportar';

  @override
  String get barExportCanvas => 'Para o Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => 'Só o desenho (.inkml)';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

  @override
  String get barExportNotebook =>
      'Salvar o caderno inteiro como pastas e arquivos…';

  @override
  String get barExportNotebookBusy => 'Salvando o caderno…';

  @override
  String barExportPageProgress(int done, int total) {
    return 'Página $done de $total…';
  }

  @override
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPdfPicture => 'PDF — imagem da página';

  @override
  String get barExportPrint => 'Imprimir…';

  @override
  String get barExportTip => 'Exportar a página…';

  @override
  String barExportedTo(String path) {
    return 'Exportado para $path';
  }

  @override
  String get barFindOnPage => 'Procurar na página';

  @override
  String get barFindOnPageTip => 'Procurar na página  (Ctrl+F)';

  @override
  String get barFindTags => 'Procurar marcadores';

  @override
  String get barFontSizeDefault => 'Padrão';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barHeading1 => 'Título 1';

  @override
  String get barHighlight => 'Destaque';

  @override
  String get barInlineCode => 'Código no texto';

  @override
  String get barItalic => 'Itálico  (Ctrl+I)';

  @override
  String get barLassoHint =>
      'Contorne o traço para selecioná-lo — depois arraste ou apague';

  @override
  String get barLinks => 'Links e referências';

  @override
  String get barMakeCardFromLine => 'Transformar esta linha num cartão';

  @override
  String get barNewCard => 'Novo cartão';

  @override
  String get barNumberedList => 'Lista numerada';

  @override
  String get barOpenStudyPanel => 'Abrir o painel de estudo';

  @override
  String get barPageOutline => 'Estrutura da página';

  @override
  String get barPenProximity =>
      'Aproximar a caneta da página muda para traço.\nSe escolher outra ferramenta com a caneta por perto, ela fica\naté a caneta se afastar e voltar. A ponta traseira da caneta (ou\no botão dela, mantido apertado) apaga.';

  @override
  String get barPickPenHint => 'Pegue a caneta ou o marca-texto para desenhar';

  @override
  String get barPlanner => 'Agenda';

  @override
  String get barPlannerEmpty => 'Agenda — todas as suas datas num lugar só';

  @override
  String barPlannerOverdue(int count) {
    return 'Agenda — $count para hoje ou atrasados';
  }

  @override
  String barPlannerToday(int count) {
    return 'Agenda — $count para hoje';
  }

  @override
  String get barQuestionCard => 'Cartão de pergunta';

  @override
  String get barQuote => 'Citação';

  @override
  String get barRedo => 'Refazer  (Ctrl+Y)';

  @override
  String barRemindersWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lembretes',
      one: '1 lembrete',
    );
    return '$_temp0 esperando';
  }

  @override
  String barSaveFailed(String reason) {
    return 'Não deu para salvar: $reason';
  }

  @override
  String get barSettings => 'Configurações';

  @override
  String get barSettingsTip => 'Configurações…';

  @override
  String get barStrikethrough => 'Tachado';

  @override
  String get barStudy => 'Estudo';

  @override
  String barStudyDue(int due, int total, String countdown) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total cartões',
      one: '1 cartão',
    );
    return '$due de $_temp0 para revisar nesta seção$countdown';
  }

  @override
  String get barStudyEmpty =>
      'Estudo — marque uma linha como Pergunta ou Definição para virar cartão';

  @override
  String barStudyExamCountdown(String when) {
    return ' · prova $when';
  }

  @override
  String get barTabDraw => 'Desenhar';

  @override
  String get barTabHome => 'Início';

  @override
  String get barTabInsert => 'Inserir';

  @override
  String get barTagLine => 'Marcar esta linha (A fazer, Importante, Pergunta…)';

  @override
  String barTagged(String tags) {
    return 'Marcada: $tags';
  }

  @override
  String get barTextColour => 'Aplicar cor ao texto';

  @override
  String get barTextFont => 'Fonte do texto…';

  @override
  String get barTextSize => 'Tamanho do texto (pontos)';

  @override
  String get barTextSizeDisabled =>
      'Clique numa caixa de texto para mudar o tamanho';

  @override
  String get barToolEraser => 'Borracha  (E)';

  @override
  String get barToolHighlighter => 'Marca-texto  (H)';

  @override
  String get barToolLasso => 'Selecionar o traço com o laço';

  @override
  String get barToolPen => 'Caneta  (P)';

  @override
  String get barToolSelect => 'Selecionar / mover  (V)';

  @override
  String get barToolText => 'Texto  (T)';

  @override
  String get barTouchDrawing =>
      'Desenhe com o dedo.\nAuto: o dedo desenha até você usar a caneta; depois o dedo arrasta a página, para a palma da mão não marcar nada.\nDois dedos sempre arrastam e dão zoom.';

  @override
  String get barUnderline => 'Sublinhado  (Ctrl+U)';

  @override
  String get barUndo => 'Desfazer  (Ctrl+Z)';

  @override
  String barUpdateTo(String version) {
    return 'Atualizar para $version…';
  }

  @override
  String get commonBack => 'Voltar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonClose => 'Fechar';

  @override
  String get commonDelete => 'Apagar';

  @override
  String get commonDetailsAdvanced => 'Detalhes (avançado)';

  @override
  String get commonDone => 'Pronto';

  @override
  String get commonNext => 'Avançar';

  @override
  String get commonOff => 'Não';

  @override
  String get commonOn => 'Sim';

  @override
  String get commonOpen => 'Abrir';

  @override
  String get commonOpenEllipsis => 'Abrir…';

  @override
  String get commonSkip => 'Pular';

  @override
  String importBringingIn(String name, int done, int total) {
    return 'A trazer «$name» — $done de $total páginas…';
  }

  @override
  String get importCancelledLabel => 'Importação cancelada.';

  @override
  String importDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas importadas.',
      one: '1 página importada.',
    );
    return '$_temp0';
  }

  @override
  String importDoneButLost(int count, String detail) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas importadas, mas não foi possível trazer $detail.',
      one: '1 página importada, mas não foi possível trazer $detail.',
    );
    return '$_temp0';
  }

  @override
  String get importEmptyNotebook => 'Esse bloco de notas não tinha páginas.';

  @override
  String get importFailedGeneric =>
      'Não foi possível trazer esse bloco de notas.';

  @override
  String importFoundPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas para trazer. A começar…',
      one: '1 página para trazer. A começar…',
    );
    return '$_temp0';
  }

  @override
  String importFoundSections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count secções encontradas — a ver o que contêm…',
      one: '1 secção encontrada — a ver o que contém…',
    );
    return '$_temp0';
  }

  @override
  String get importLookingAround => 'A examinar o seu bloco de notas…';

  @override
  String importPartialBroke(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Algo correu mal a meio, mas as $count páginas já trazidas estão aqui. O Openote termina o resto sozinho mais tarde.',
    );
    return '$_temp0';
  }

  @override
  String importPartialThrottled(String detail, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$detail As $count páginas já trazidas estão aqui. O Openote termina o resto sozinho mais tarde, ou pode começar de novo quando quiser.',
    );
    return '$_temp0';
  }

  @override
  String get importReading => 'A ler o bloco de notas…';

  @override
  String get importSigningIn => 'A iniciar sessão no OneNote…';

  @override
  String importStoppedKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Parado — as $count páginas já trazidas ficam. Pode terminar quando quiser.',
      one: 'Parado — a página já trazida fica. Pode terminar quando quiser.',
    );
    return '$_temp0';
  }

  @override
  String get importStopping => 'A parar…';

  @override
  String importThrottled(int seconds) {
    return 'A Microsoft pediu ao Openote para abrandar — continua em ${seconds}s. Nada do que já chegou se perde.';
  }

  @override
  String get importThrottledSoon =>
      'A Microsoft pediu ao Openote para abrandar — continua num momento. Nada do que já chegou se perde.';

  @override
  String importWritingPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'A importar $count páginas…',
      one: 'A importar 1 página…',
    );
    return '$_temp0';
  }

  @override
  String importWritingSection(String name) {
    return 'A importar «$name»…';
  }

  @override
  String get insertBoard => 'Quadro';

  @override
  String get insertBoardTip => 'Colunas de cartões que você vai movendo';

  @override
  String get insertCode => 'Código';

  @override
  String get insertEquation => 'Equação';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertFile => 'Arquivo';

  @override
  String get insertFlashcardItem => 'Cartão';

  @override
  String get insertGroupBringIn => 'Trazer';

  @override
  String get insertGroupLinkUp => 'Ligar';

  @override
  String get insertGroupWrite => 'Escrever';

  @override
  String get insertLinkToPage => 'Ligar a uma página';

  @override
  String get insertPageLink => 'Link';

  @override
  String get insertPageWindow => 'Janela';

  @override
  String get insertPdfAsCard => 'Como cartão — abre numa janela';

  @override
  String insertPdfFailed(String reason) {
    return 'A importação do PDF falhou: $reason';
  }

  @override
  String insertPdfImported(int count, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slides importados',
      one: '1 slide importado',
    );
    return '$_temp0$where — pegue a caneta e escreva por cima. O texto dos slides pode ser procurado.';
  }

  @override
  String get insertPdfOntoThisPage => ' nesta página';

  @override
  String get insertPdfPerSlide => 'Uma página por slide';

  @override
  String get insertPdfPrintout => 'Impresso nesta página';

  @override
  String get insertPdfSlides => 'Slides PDF';

  @override
  String get insertPdfUnreadable => 'Não deu para ler esse PDF.';

  @override
  String get insertPickImages => 'Imagens';

  @override
  String get insertPickTables => 'Tabelas';

  @override
  String get insertPickVideo => 'Vídeo e áudio';

  @override
  String get insertPicture => 'Imagem';

  @override
  String get insertTable => 'Tabela';

  @override
  String get insertTableFromFile => 'De um arquivo';

  @override
  String get insertTableFromFileTip => 'CSV ou Excel';

  @override
  String get insertTemplate => 'Modelo';

  @override
  String get insertTextBox => 'Caixa';

  @override
  String get insertVideo => 'Vídeo';

  @override
  String get insertVideoTip => 'Uma gravação de aula, ou qualquer link da web';

  @override
  String mathSemanticLabel(String latex) {
    return 'Equação: $latex';
  }

  @override
  String navAllCount(int total) {
    return 'Todos os $total';
  }

  @override
  String get navApplyTemplate => 'Aplicar modelo';

  @override
  String get navBinEmpty => 'Nada apagado.';

  @override
  String get navBinItems => 'Itens';

  @override
  String get navBinNotebooks => 'Cadernos';

  @override
  String navBinRetention(int days) {
    return 'O que está aqui é apagado de vez depois de $days dias.';
  }

  @override
  String get navClose => 'Fechar';

  @override
  String get navCollapse => 'Fechar o navegador  (Ctrl+\\)';

  @override
  String get navColour => 'Cor';

  @override
  String get navColourDefault => 'Padrão';

  @override
  String get navComingUp => 'EM BREVE';

  @override
  String get navDeleteForever => 'Apagar para sempre';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '“$title” e todas as suas páginas serão removidas para sempre. Não dá para desfazer.$caveat';
  }

  @override
  String get navDeleteForeverTitle => 'Apagar de vez?';

  @override
  String get navDeletePermanently => 'Apagar de vez';

  @override
  String navDeletedRestorable(String title) {
    return '“$title” apagada — dá para restaurar pela lixeira.';
  }

  @override
  String navDeletesInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Apaga em $days dias',
      one: 'Apaga em 1 dia',
    );
    return '$_temp0';
  }

  @override
  String get navDeletesSoon => 'Apaga em breve';

  @override
  String navExamCountdown(String when, String countdown) {
    return 'Prova $when · $countdown…';
  }

  @override
  String get navExpand => 'Abrir o navegador  (Ctrl+\\)';

  @override
  String get navHome => 'Início';

  @override
  String get navHomeEmpty =>
      'Ainda não há nada aqui.\n\nClique com o botão direito numa página e escolha Favorita para fixá-la; as páginas que você abre aparecem em Recentes.';

  @override
  String get navHomeTip => 'Início — favoritos e recentes';

  @override
  String get navInPageContent => 'No conteúdo das páginas';

  @override
  String get navLinkCopied => 'Link copiado — cole em qualquer página';

  @override
  String navLockedCannotDelete(String title) {
    return '“$title” está bloqueada. Tire a senha antes de apagá-la.';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '“$title” está bloqueada. Ela fica escondida dentro do Openote, não criptografada no arquivo.';
  }

  @override
  String get navMenuAddFavourite => 'Adicionar aos favoritos';

  @override
  String get navMenuApplyTemplate => 'Aplicar um modelo…';

  @override
  String get navMenuCopyLink => 'Copiar o link da página';

  @override
  String get navMenuDelete => 'Apagar';

  @override
  String get navMenuExportSectionPdf => 'Exportar a seção em PDF…';

  @override
  String get navMenuLock => 'Bloquear com uma senha…';

  @override
  String get navMenuMakeSubpage => 'Tornar subpágina';

  @override
  String get navMenuMoveBackOut => 'Tirar de subpágina';

  @override
  String get navMenuMoveDown => 'Mover para baixo';

  @override
  String get navMenuMoveToGroup => 'Mover para um grupo…';

  @override
  String get navMenuMoveUp => 'Mover para cima';

  @override
  String get navMenuNewPage => 'Nova página';

  @override
  String get navMenuPrint => 'Imprimir…';

  @override
  String get navMenuPrintSection => 'Imprimir a seção…';

  @override
  String get navMenuRecentChanges => 'Alterações recentes…';

  @override
  String get navMenuRemoveExam => 'Tirar a data da prova';

  @override
  String get navMenuRemoveFavourite => 'Tirar dos favoritos';

  @override
  String get navMenuRemovePasscode => 'Tirar a senha…';

  @override
  String get navMenuSaveTemplate => 'Salvar como modelo…';

  @override
  String get navMenuSetExam => 'Definir a data da prova…';

  @override
  String get navMenuSharePdf => 'Compartilhar em PDF…';

  @override
  String get navMenuSortAZ => 'Ordenar as páginas de A a Z';

  @override
  String get navMenuSortEdited => 'Ordenar pela última edição';

  @override
  String get navMoveSectionTo => 'Mover a seção para…';

  @override
  String navNewPageIn(String section) {
    return 'Nova página em $section';
  }

  @override
  String get navNewSection => 'Nova seção';

  @override
  String get navNewSectionGroup => 'Novo grupo de seções';

  @override
  String get navNoGroupTopLevel => '(Sem grupo — nível principal)';

  @override
  String navNoMatches(String query) {
    return 'Nada encontrado para “$query”';
  }

  @override
  String get navNoPages => 'Ainda não há páginas';

  @override
  String get navNoSections => 'Ainda não há seções.\nCrie uma para começar.';

  @override
  String get navNoTemplates =>
      'Ainda não há modelos — use antes “Salvar como modelo…”.';

  @override
  String get navNotebooksTip =>
      'Cadernos — trocar, renomear, duplicar, importar';

  @override
  String get navOpen => 'Abrir';

  @override
  String navPasscodeRemoved(String title) {
    return 'Senha removida de “$title”.';
  }

  @override
  String get navRecycleBin => 'Lixeira';

  @override
  String get navRestore => 'Restaurar';

  @override
  String get navSave => 'Salvar';

  @override
  String get navSaveTemplateTitle => 'Salvar como modelo';

  @override
  String navSavedTo(String path) {
    return 'Salvo em $path';
  }

  @override
  String get navSearchHint => 'Procurar ou ir para…';

  @override
  String get navSection => 'Seção';

  @override
  String get navTemplateNameHint => 'Nome do modelo';

  @override
  String navTemplateSaved(String name) {
    return 'Modelo “$name” salvo';
  }

  @override
  String get navUntitled => 'Sem título';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return 'Conferindo a página $done de $total…';
  }

  @override
  String get nbCheckingPages => 'Conferindo as páginas…';

  @override
  String get nbConfirmBin =>
      'Mover para a lixeira? Dá para restaurar por aqui.';

  @override
  String get nbCoreMissing =>
      'A importação do OneNote precisa do núcleo Rust — compile onote_core.dll (veja rust/onote_core/INTEGRATION.md).';

  @override
  String get nbCreate => 'Criar';

  @override
  String get nbDuplicate => 'Duplicar';

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '$copies cópias de “$title” · $pages páginas cada · $size voltariam';
  }

  @override
  String get nbDuplicates =>
      'Possíveis duplicados · mesmo título e mesmo número de páginas';

  @override
  String get nbDuplicatesHint =>
      'Fique com o maior — o menor costuma ser uma importação interrompida no meio. As cópias apagadas vão para a lixeira.';

  @override
  String get nbGetStarted => 'Começar';

  @override
  String get nbImport => 'Importar';

  @override
  String get nbImportBusy =>
      'Já há uma importação em andamento — uma de cada vez.';

  @override
  String get nbImportGit => 'De um endereço git';

  @override
  String get nbImportInto => 'Importar para um caderno novo';

  @override
  String get nbImportMarkdown => 'Pasta de Markdown';

  @override
  String get nbImportOne => 'Seção do OneNote (.one)';

  @override
  String get nbImportOnepkg => 'Caderno do OneNote (.onepkg)';

  @override
  String get nbImportStarted =>
      'Importando em segundo plano — pode continuar; o cartão no canto avisa quando terminar.';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return 'Importado $what do OneNote.$strokeNote';
  }

  @override
  String nbImportedNamed(String name) {
    return '$name importado';
  }

  @override
  String nbImportedPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas importadas',
      one: '1 página importada',
    );
    return '$_temp0';
  }

  @override
  String nbImportedPagesProgress(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas importadas…',
      one: '1 página importada…',
    );
    return '$_temp0';
  }

  @override
  String nbImportedProgress(String done) {
    return 'Importado $done';
  }

  @override
  String nbInBin(int days) {
    return 'Na lixeira · apagado depois de $days dias';
  }

  @override
  String get nbMoveToBin => 'Mover para a lixeira';

  @override
  String get nbNameHint => 'Nome do caderno';

  @override
  String get nbNeedsNativeCore =>
      'A importação do OneNote precisa do núcleo Rust — compile onote_core.dll e coloque ao lado do aplicativo.';

  @override
  String get nbNew => 'Novo';

  @override
  String get nbNewTitle => 'Caderno novo';

  @override
  String get nbNoMarkdown => 'Nenhum arquivo Markdown encontrado nessa pasta.';

  @override
  String get nbNothingToRepair =>
      'Nada a reparar — todas as páginas estão em dia.';

  @override
  String get nbOneFileEmpty => 'Não deu para ler nada desse arquivo .one.';

  @override
  String get nbOnePkgFileType => 'Pacote de caderno do OneNote';

  @override
  String nbOpenCount(int count) {
    return '$count abertos';
  }

  @override
  String get nbOpenThis => 'Abrir este caderno';

  @override
  String nbReadFileFailed(String reason) {
    return 'Não deu para ler esse arquivo: $reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return 'Não deu para importar essa pasta: $reason';
  }

  @override
  String get nbReadingFolder => 'Lendo a pasta…';

  @override
  String get nbRename => 'Renomear';

  @override
  String get nbRepair => 'Reparar';

  @override
  String nbRepairFailed(String reason) {
    return 'O reparo falhou: $reason';
  }

  @override
  String nbRepaired(String boxes, String pages) {
    return 'Reparadas $boxes em $pages.';
  }

  @override
  String nbRepairedBoxes(int blocks) {
    String _temp0 = intl.Intl.pluralLogic(
      blocks,
      locale: localeName,
      other: '$blocks caixas',
      one: '1 caixa',
    );
    return '$_temp0';
  }

  @override
  String nbRepairedPages(int pages) {
    String _temp0 = intl.Intl.pluralLogic(
      pages,
      locale: localeName,
      other: '$pages páginas',
      one: '1 página',
    );
    return '$_temp0';
  }

  @override
  String get nbTitle => 'Cadernos';

  @override
  String objectRowBackground(String kind) {
    return 'Fundo: $kind';
  }

  @override
  String get objectRowBackgroundBlank => 'em branco';

  @override
  String get objectRowBackgroundDotted => 'pontilhado';

  @override
  String get objectRowBackgroundGrid => 'quadriculado';

  @override
  String get objectRowBackgroundRuled => 'pautado';

  @override
  String get objectRowCanvasMode =>
      'Modo tela livre: sem limites — clique para páginas';

  @override
  String get objectRowCharacters => 'Caracteres';

  @override
  String get objectRowCharactersNoSpaces => 'Sem espaços';

  @override
  String get objectRowLandscape => 'Paisagem';

  @override
  String get objectRowLandscapeSuffix => ' paisagem';

  @override
  String objectRowMinutes(int n) {
    return '$n min';
  }

  @override
  String objectRowPageMode(String paper, String landscape) {
    return 'Modo página: $paper$landscape — clique para tela livre';
  }

  @override
  String get objectRowPaperSize => 'Tamanho do papel';

  @override
  String get objectRowReadingTime => 'Tempo de leitura';

  @override
  String get objectRowSnapOff => 'Alinhar à grade: NÃO — posição livre';

  @override
  String get objectRowSnapOn =>
      'Alinhar à grade: SIM (a grade aparece ao arrastar)';

  @override
  String get objectRowWordCount =>
      'Palavras nesta página — clique para ver caracteres e tempo de leitura';

  @override
  String objectRowWordTally(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted palavras',
      one: '1 palavra',
      zero: 'nenhuma palavra',
    );
    return '$_temp0';
  }

  @override
  String get objectRowWords => 'Palavras';

  @override
  String get objectRowZoomFit => 'Ajustar o zoom ao conteúdo';

  @override
  String get objectRowZoomIn => 'Aproximar  (Ctrl+=)';

  @override
  String get objectRowZoomOut => 'Afastar  (Ctrl+-)';

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent%';
  }

  @override
  String get objectRowZoomReset =>
      'Voltar a 100% e ao topo da página  (Ctrl+0)';

  @override
  String get onboardingCloudAction => 'Iniciar sessão';

  @override
  String get onboardingCloudBody =>
      'Inicie sessão na Microsoft e escolha um bloco de notas. Não é preciso exportar nada antes, e funciona em qualquer computador.';

  @override
  String get onboardingCloudTitle => 'Trazer notas do OneNote';

  @override
  String get onboardingExportMacNote =>
      'No Mac, ou só com a versão da Store: exporte uma seção por vez como .one, ou peça a um computador com Windows para gerar o .onepkg. O Openote nunca entra na sua conta da Microsoft — ele só lê o arquivo que você entrega.';

  @override
  String get onboardingExportSteps =>
      '1. Abra o OneNote para Windows (o aplicativo de computador — as versões da Store e da web não exportam).\n2. Deixe o caderno terminar de sincronizar, para estar tudo neste computador.\n3. Arquivo ▸ Exportar ▸ Bloco de Anotações ▸ Pacote do OneNote (*.onepkg), e então Exportar.\n4. Volte aqui e escolha esse arquivo.';

  @override
  String get onboardingExportTitle => 'Exportar do OneNote';

  @override
  String get onboardingFreshAction => 'Começar do zero';

  @override
  String get onboardingFreshBody =>
      'Um bloco de notas vazio, pronto a escrever. Pode trazer as suas notas mais tarde.';

  @override
  String get onboardingFreshTitle => 'Começar um bloco de notas novo';

  @override
  String get onboardingImportDone => 'Seu caderno está pronto';

  @override
  String get onboardingImportRunning =>
      'Pode continuar — isto roda em segundo plano, e o cartão no canto avisa quando terminar.';

  @override
  String onboardingImportingFile(String fileName) {
    return 'Importando $fileName';
  }

  @override
  String get onboardingNoNativeCore =>
      'A importação do OneNote precisa do núcleo nativo, que esta versão não inclui.';

  @override
  String get onboardingOneNoteAction => 'Escolher arquivo…';

  @override
  String get onboardingOneNoteBody =>
      'Páginas, formatação, imagens, traços e marcadores de um .onepkg. Roda em segundo plano — pode continuar enquanto isso.';

  @override
  String get onboardingOneNoteHideSteps => 'Esconder os passos';

  @override
  String get onboardingOneNoteHowTo => 'Como eu exporto?';

  @override
  String get onboardingOneNoteTitle => 'Trazer anotações do OneNote';

  @override
  String get onboardingOnePkgFileType => 'Pacote de caderno do OneNote';

  @override
  String get onboardingOpenFailed =>
      'O Openote não conseguiu abrir esse caderno.';

  @override
  String onboardingReadFailed(String reason) {
    return 'Não deu para ler esse arquivo: $reason';
  }

  @override
  String get onboardingStartWriting => 'Começar a escrever';

  @override
  String get onboardingStep1Body =>
      'Clique em qualquer lugar e comece a escrever — a caixa aparece onde você clicou, e só quando você digita. Mova pela barra de cima, e arraste imagens de onde quiser.';

  @override
  String get onboardingStep1Title => 'A página é uma tela';

  @override
  String get onboardingStep2Body =>
      'Digite 1/2 ou aperte Alt+= e a notação de verdade vai se formando enquanto você escreve, numa caixa própria ou no meio da frase. A aba Desenhar aceita caneta, dedo ou mouse.';

  @override
  String get onboardingStep2Title =>
      'Matemática e desenho, junto com as palavras';

  @override
  String get onboardingStep3Body =>
      'Um arquivo aberto e legível por caderno — sem conta, sem amarras. Coloque numa pasta que sua nuvem já sincroniza e todos os aparelhos ficam juntos.';

  @override
  String get onboardingStep3Title => 'Suas anotações são um arquivo seu';

  @override
  String get onboardingSyncAction => 'Configurar…';

  @override
  String get onboardingSyncBodyAlso =>
      'Nenhum desses? Escolha você mesmo a pasta.';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive, OneDrive, iCloud, Dropbox, Syncthing, um NAS — ou um repositório do GitHub.';

  @override
  String get onboardingSyncTitle => 'Sincronizar com outro aparelho';

  @override
  String get oneNoteCloudContinue => 'Continuar com a Microsoft';

  @override
  String get oneNoteCloudEmpty =>
      'Não foram encontrados blocos de notas nesta conta.';

  @override
  String get oneNoteCloudIntro =>
      'O Openote vai ler os seus blocos de notas do OneNote. Não os pode alterar.';

  @override
  String get oneNoteCloudLoading => 'A procurar os seus blocos de notas…';

  @override
  String get oneNoteCloudNoInk =>
      'As tabelas são ajustadas à página em vez de manterem a largura exacta, e a cor e o tipo de letra do texto não são mantidos.';

  @override
  String get oneNoteCloudOther => 'Usar outra conta';

  @override
  String get oneNoteCloudSignIn => 'Iniciar sessão na Microsoft';

  @override
  String get oneNoteCloudSigningIn => 'A aguardar o seu navegador…';

  @override
  String get oneNoteCloudTitle => 'Trazer um bloco de notas do OneNote';

  @override
  String get oneNoteFileBody =>
      'Sem iniciar sessão, e a cópia mais fiel: as tabelas mantêm a largura exacta. Vai precisar do OneNote no Windows para exportar o bloco de notas primeiro.';

  @override
  String get oneNoteFileTitle => 'Usar um ficheiro exportado';

  @override
  String get oneNotePickTitle => 'Qual bloco de notas?';

  @override
  String get oneNoteSignInBody =>
      'Escolha um bloco de notas e vem directamente, sem exportar nada antes. Funciona em qualquer computador.';

  @override
  String get settingsAbout => 'Sobre';

  @override
  String get settingsAi => 'Acesso da IA';

  @override
  String get settingsAiOff =>
      'Não — conecte o Claude ou outros assistentes de IA.';

  @override
  String get settingsAiOn =>
      'Sim — os assistentes de IA deste computador podem ler suas anotações.';

  @override
  String get settingsAppearance => 'Aparência';

  @override
  String get settingsCheckUpdates => 'Procurar atualizações';

  @override
  String get settingsConnections => 'Conexões';

  @override
  String get settingsHelp => 'Ajuda';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageAuto => 'O mesmo do computador';

  @override
  String get settingsLanguageContribute =>
      'Como adicionar ou corrigir um idioma';

  @override
  String get settingsLanguageHelp =>
      'O Openote é traduzido por quem o usa. Se o seu falta ou está errado, é um arquivo só — o link explica como.';

  @override
  String get settingsPenProximity => 'Caneta perto da página muda para traço';

  @override
  String get settingsShortcuts => 'Atalhos de teclado';

  @override
  String get settingsShortcutsHint =>
      'Tudo tem uma tecla — a lista completa.  (Ctrl+/)';

  @override
  String get settingsSpellCheck => 'Corretor ortográfico';

  @override
  String get settingsSync => 'Sincronização';

  @override
  String get settingsSyncHint =>
      'Faça cópia deste caderno e compartilhe — GitHub ou uma pasta.';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeDark => 'Escuro';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String settingsUpToDate(String version) {
    return 'Está tudo em dia ($version é a versão mais recente).';
  }

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsWelcomeTour => 'Tour de boas-vindas';

  @override
  String get settingsWelcomeTourHint =>
      'A versão de três minutos: a tela, a matemática e o traço, e onde ficam suas anotações.';

  @override
  String get settingsWhatsNew => 'Novidades';

  @override
  String get settingsWriting => 'Escrita e desenho';

  @override
  String get shellAlreadyUpToDate => 'Já está em dia.';

  @override
  String get shellCheatSheet =>
      'V selecionar · T texto · P caneta · H marcar · E apagar · Ctrl+Z desfazer · Ctrl+roda zoom';

  @override
  String get shellCloseEsc => 'Fechar (Esc)';

  @override
  String get shellCreateFirstPage => 'Crie sua primeira página';

  @override
  String get shellEmptyBody =>
      'Tudo o que você faz aqui fica no seu aparelho,\nnum formato aberto que é seu.';

  @override
  String get shellEmptyTitle => 'Uma página aberta espera por você';

  @override
  String get shellFindOnThisPage => 'Procurar nesta página…';

  @override
  String get shellHeadingsHint =>
      'Comece uma linha com # para fazer um título — a estrutura se monta sozinha enquanto você escreve.';

  @override
  String get shellLinkedFrom => 'Ligada a partir de';

  @override
  String get shellLinksTo => 'Aponta para';

  @override
  String get shellNextMatch => 'Próximo resultado (Enter)';

  @override
  String get shellNoBacklinks => 'Nenhuma página aponta para cá ainda.';

  @override
  String get shellNoHeadings => 'Não há títulos nesta página.';

  @override
  String get shellNoLinks => 'Esta página ainda não aponta para nada.';

  @override
  String get shellNoMatches => 'Nada encontrado';

  @override
  String get shellNoTags => 'Ainda não há marcadores neste caderno.';

  @override
  String get shellNothingReplaced => 'Nada foi substituído';

  @override
  String shellPageLocked(String title) {
    return '“$title” está bloqueada';
  }

  @override
  String get shellPreviousMatch => 'Resultado anterior (Shift+Enter)';

  @override
  String shellPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alterações recebidas',
      one: '1 alteração recebida',
    );
    return '$_temp0';
  }

  @override
  String get shellReplace => 'Substituir';

  @override
  String get shellReplaceAll => 'Todas';

  @override
  String get shellReplaceWith => 'Substituir por…';

  @override
  String shellReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ocorrências substituídas',
      one: '1 ocorrência substituída',
    );
    return '$_temp0';
  }

  @override
  String shellRustLinked(String build) {
    return 'O núcleo Rust (onote-core) está ligado e calcula o hash do conteúdo desta página ao salvar.\n$build';
  }

  @override
  String get shellRustMissing =>
      'Rodando com o motor em Dart puro. Compile a biblioteca onote-core para ligar o núcleo Rust.';

  @override
  String get shellSavedLocally =>
      'Esta página está salva no seu arquivo .onote local.';

  @override
  String get shellSavedOnDevice => 'Salvo neste dispositivo';

  @override
  String get shellSaving => 'Salvando…';

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag  ($count)';
  }

  @override
  String get shellTagTheLine => 'Marcar a linha em que você está';

  @override
  String get shellTagsHint =>
      'Os marcadores assinalam uma linha — a fazer, importante, pergunta, definição — para você achar de novo, revisar ou dar um prazo.';

  @override
  String get shellUnlock => 'Desbloquear';

  @override
  String get tagContact => 'Contato';

  @override
  String get tagCritical => 'Urgente';

  @override
  String get tagCustom => 'Marcador';

  @override
  String get tagDefinition => 'Definição';

  @override
  String get tagIdea => 'Ideia';

  @override
  String get tagImportant => 'Importante';

  @override
  String get tagQuestion => 'Pergunta';

  @override
  String get tagRemember => 'Lembrar';

  @override
  String get tagTodo => 'A fazer';

  @override
  String get touchDrawAlways => 'Sempre';

  @override
  String get touchDrawAuto => 'Auto (a caneta manda)';

  @override
  String get touchDrawNever => 'Nunca';
}
