// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class LEs extends L {
  LEs([String locale = 'es']) : super(locale);

  @override
  String get commonBack => 'Atrás';

  @override
  String get commonSkip => 'Omitir';

  @override
  String get commonNext => 'Siguiente';

  @override
  String get commonOpen => 'Abrir';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDetailsAdvanced => 'Detalles (avanzado)';

  @override
  String objectRowBackground(String kind) {
    return 'Fondo: $kind';
  }

  @override
  String get objectRowBackgroundBlank => 'en blanco';

  @override
  String get objectRowBackgroundGrid => 'cuadrícula';

  @override
  String get objectRowBackgroundDotted => 'puntos';

  @override
  String get objectRowBackgroundRuled => 'rayado';

  @override
  String objectRowPageMode(String paper, String landscape) {
    return 'Modo página: $paper$landscape — haz clic para lienzo';
  }

  @override
  String get objectRowLandscapeSuffix => ' horizontal';

  @override
  String get objectRowCanvasMode =>
      'Modo lienzo: sin límites — haz clic para páginas';

  @override
  String get objectRowPaperSize => 'Tamaño del papel';

  @override
  String get objectRowLandscape => 'Horizontal';

  @override
  String get objectRowSnapOn =>
      'Ajustar a la cuadrícula: SÍ (se ve al arrastrar)';

  @override
  String get objectRowSnapOff =>
      'Ajustar a la cuadrícula: NO — colocación libre';

  @override
  String get objectRowZoomOut => 'Alejar  (Ctrl+-)';

  @override
  String get objectRowZoomIn => 'Acercar  (Ctrl+=)';

  @override
  String get objectRowZoomReset =>
      'Volver al 100% y al principio de la página  (Ctrl+0)';

  @override
  String get objectRowZoomFit => 'Ajustar el zoom al contenido';

  @override
  String get objectRowWordCount =>
      'Palabras de esta página — haz clic para ver caracteres y tiempo de lectura';

  @override
  String get objectRowWords => 'Palabras';

  @override
  String get objectRowCharacters => 'Caracteres';

  @override
  String get objectRowCharactersNoSpaces => 'Sin espacios';

  @override
  String get objectRowReadingTime => 'Tiempo de lectura';

  @override
  String objectRowMinutes(int n) {
    return '$n min';
  }

  @override
  String objectRowWordTally(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted palabras',
      one: '1 palabra',
      zero: 'sin palabras',
    );
    return '$_temp0';
  }

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent %';
  }

  @override
  String get barTabHome => 'Inicio';

  @override
  String get barTabInsert => 'Insertar';

  @override
  String get barTabDraw => 'Dibujar';

  @override
  String get barEquationBadge => 'Ecuación';

  @override
  String barUpdateTo(String version) {
    return 'Actualizar a $version…';
  }

  @override
  String get barDone => 'Listo';

  @override
  String get barStudy => 'Estudio';

  @override
  String get barPlanner => 'Agenda';

  @override
  String get barFindTags => 'Buscar etiquetas';

  @override
  String get barPageOutline => 'Esquema de la página';

  @override
  String get barLinks => 'Enlaces y retroenlaces';

  @override
  String get barFindOnPage => 'Buscar en la página';

  @override
  String get barFindOnPageTip => 'Buscar en la página  (Ctrl+F)';

  @override
  String get barExport => 'Exportar';

  @override
  String get barExportTip => 'Exportar página…';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

  @override
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPrint => 'Imprimir…';

  @override
  String get barExportPdfPicture => 'PDF — imagen de la página';

  @override
  String get barExportCanvas => 'Para Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => 'Solo el dibujo (.inkml)';

  @override
  String get barExportNotebook =>
      'Guardar el cuaderno entero como carpetas y archivos…';

  @override
  String get barExportNotebookBusy => 'Guardando el cuaderno…';

  @override
  String barExportPageProgress(int done, int total) {
    return 'Página $done de $total…';
  }

  @override
  String barExportedTo(String path) {
    return 'Exportado a $path';
  }

  @override
  String get barSettings => 'Ajustes';

  @override
  String get barSettingsTip => 'Ajustes…';

  @override
  String get barUndo => 'Deshacer  (Ctrl+Z)';

  @override
  String get barRedo => 'Rehacer  (Ctrl+Y)';

  @override
  String get barBold => 'Negrita  (Ctrl+B)';

  @override
  String get barItalic => 'Cursiva  (Ctrl+I)';

  @override
  String get barUnderline => 'Subrayado  (Ctrl+U)';

  @override
  String get barStrikethrough => 'Tachado';

  @override
  String get barInlineCode => 'Código en línea';

  @override
  String get barHighlight => 'Resaltado';

  @override
  String get barHeading1 => 'Título 1';

  @override
  String get barBulletList => 'Lista con viñetas';

  @override
  String get barNumberedList => 'Lista numerada';

  @override
  String get barCheckbox => 'Casilla';

  @override
  String get barQuote => 'Cita';

  @override
  String get barTextColour => 'Aplicar color al texto';

  @override
  String get barTextFont => 'Fuente del texto…';

  @override
  String get barClickIntoTextBox => 'Haz clic en un cuadro de texto';

  @override
  String get barToolSelect => 'Seleccionar / mover  (V)';

  @override
  String get barToolText => 'Texto  (T)';

  @override
  String get barToolPen => 'Bolígrafo  (P)';

  @override
  String get barToolHighlighter => 'Marcador  (H)';

  @override
  String get barToolEraser => 'Borrador  (E)';

  @override
  String get barToolLasso => 'Seleccionar tinta con lazo';

  @override
  String get barEraserSplit => 'Parte los trazos por donde frotas';

  @override
  String get barEraserWhole => 'Quita el trazo entero que toques';

  @override
  String get barLassoHint =>
      'Rodea la tinta con un lazo para seleccionarla — luego arrástrala o bórrala';

  @override
  String get barPickPenHint => 'Elige el bolígrafo o el marcador para dibujar';

  @override
  String get barTouchDrawing =>
      'Dibuja con el dedo.\nAuto: el dedo dibuja hasta que usas el lápiz; después el dedo mueve la página para que la palma no la marque.\nDos dedos siempre mueven y hacen zoom.';

  @override
  String get barPenProximity =>
      'Acercar el lápiz a la página cambia a tinta.\nSi eliges otra herramienta con el lápiz cerca, se mantiene hasta\nque el lápiz se aleja y vuelve. La punta trasera del lápiz (o su\nbotón lateral, pulsado al dibujar) borra.';

  @override
  String get barTextSize => 'Tamaño del texto (puntos)';

  @override
  String get barTextSizeDisabled =>
      'Haz clic en un cuadro de texto para cambiar su tamaño';

  @override
  String get barFontSizeDefault => 'Predeterminado';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barTagLine =>
      'Etiquetar esta línea (Tarea, Importante, Pregunta…)';

  @override
  String barTagged(String tags) {
    return 'Etiquetada: $tags';
  }

  @override
  String get barDueDateSet => 'Fecha límite…';

  @override
  String get barDueDateChange => 'Cambiar la fecha límite…';

  @override
  String get barDueDateClear => 'Quitar la fecha límite';

  @override
  String get barDueDatePickerTitle => 'Fecha límite';

  @override
  String get barDueDatePickerConfirm => 'Poner';

  @override
  String get barMakeCardFromLine => 'Convertir esta línea en una ficha';

  @override
  String get barNewCard => 'Ficha nueva';

  @override
  String get barQuestionCard => 'Ficha de pregunta';

  @override
  String get barDefinitionCard => 'Ficha de definición';

  @override
  String get barBlankOut => 'Ocultar lo seleccionado';

  @override
  String get barBlankOutNeedsSelection =>
      'Selecciona primero las palabras que quieres ocultar.';

  @override
  String get barOpenStudyPanel => 'Abrir el panel de estudio';

  @override
  String get barStudyEmpty =>
      'Estudio — etiqueta una línea como Pregunta o Definición para crear una ficha';

  @override
  String barStudyDue(int due, int total, String countdown) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total fichas',
      one: '1 ficha',
    );
    return '$due de $_temp0 para repasar en esta sección$countdown';
  }

  @override
  String barStudyExamCountdown(String when) {
    return ' · examen $when';
  }

  @override
  String get barPlannerEmpty => 'Agenda — todas tus fechas en un mismo sitio';

  @override
  String barPlannerToday(int count) {
    return 'Agenda — $count para hoy';
  }

  @override
  String barPlannerOverdue(int count) {
    return 'Agenda — $count para hoy o atrasadas';
  }

  @override
  String barRemindersWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordatorios',
      one: '1 recordatorio',
    );
    return '$_temp0 esperando';
  }

  @override
  String get barEscWhenDone => 'Pulsa Esc cuando termines';

  @override
  String barSaveFailed(String reason) {
    return 'No se ha podido guardar: $reason';
  }

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get navSearchHint => 'Buscar o ir a…';

  @override
  String navNoMatches(String query) {
    return 'Sin resultados para «$query»';
  }

  @override
  String get navInPageContent => 'En el contenido de las páginas';

  @override
  String get navUntitled => 'Sin título';

  @override
  String get navNoSections => 'Aún no hay secciones.\nCrea una para empezar.';

  @override
  String get navNewSection => 'Nueva sección';

  @override
  String navNewPageIn(String section) {
    return 'Nueva página en $section';
  }

  @override
  String get navNoPages => 'Aún no hay páginas';

  @override
  String get navSection => 'Sección';

  @override
  String get navNewSectionGroup => 'Nuevo grupo de secciones';

  @override
  String get navRecycleBin => 'Papelera';

  @override
  String get navHome => 'Inicio';

  @override
  String get navHomeTip => 'Inicio — favoritos y recientes';

  @override
  String get navHomeEmpty =>
      'Aquí no hay nada todavía.\n\nHaz clic derecho en una página y elige Favorita para fijarla; las páginas que visites aparecen en Recientes.';

  @override
  String get navComingUp => 'PRÓXIMAMENTE';

  @override
  String navAllCount(int total) {
    return 'Ver las $total';
  }

  @override
  String get navOpen => 'Abrir';

  @override
  String get navExpand => 'Desplegar el navegador  (Ctrl+\\)';

  @override
  String get navCollapse => 'Plegar el navegador  (Ctrl+\\)';

  @override
  String get navNotebooksTip =>
      'Cuadernos — cambiar, renombrar, duplicar, importar';

  @override
  String get navDeletesSoon => 'Se borra pronto';

  @override
  String navDeletesInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Se borra en $days días',
      one: 'Se borra en 1 día',
    );
    return '$_temp0';
  }

  @override
  String get navBinEmpty => 'No hay nada borrado.';

  @override
  String navBinRetention(int days) {
    return 'Lo que hay aquí se borra definitivamente a los $days días.';
  }

  @override
  String get navBinNotebooks => 'Cuadernos';

  @override
  String get navBinItems => 'Elementos';

  @override
  String get navRestore => 'Restaurar';

  @override
  String get navDeletePermanently => 'Borrar definitivamente';

  @override
  String get navClose => 'Cerrar';

  @override
  String get navDeleteForeverTitle => '¿Borrar definitivamente?';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '«$title» y todas sus páginas se borrarán para siempre. Esto no se puede deshacer.$caveat';
  }

  @override
  String get navDeleteForever => 'Borrar para siempre';

  @override
  String navLockedCannotDelete(String title) {
    return '«$title» está bloqueada. Quita su código antes de borrarla.';
  }

  @override
  String navDeletedRestorable(String title) {
    return '«$title» borrada — puedes restaurarla desde la papelera.';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '«$title» está bloqueada. Está oculta dentro de Openote, no cifrada en el archivo.';
  }

  @override
  String navPasscodeRemoved(String title) {
    return 'Código quitado de «$title».';
  }

  @override
  String navSavedTo(String path) {
    return 'Guardado en $path';
  }

  @override
  String get navLinkCopied => 'Enlace copiado — pégalo en cualquier página';

  @override
  String get navMoveSectionTo => 'Mover la sección a…';

  @override
  String get navNoGroupTopLevel => '(Sin grupo — nivel superior)';

  @override
  String get navSaveTemplateTitle => 'Guardar como plantilla';

  @override
  String get navSave => 'Guardar';

  @override
  String get navTemplateNameHint => 'Nombre de la plantilla';

  @override
  String navTemplateSaved(String name) {
    return 'Plantilla «$name» guardada';
  }

  @override
  String get navNoTemplates =>
      'Aún no hay plantillas — usa antes «Guardar como plantilla…».';

  @override
  String get navApplyTemplate => 'Aplicar plantilla';

  @override
  String get navColour => 'Color';

  @override
  String get navColourDefault => 'Predeterminado';

  @override
  String navExamCountdown(String when, String countdown) {
    return 'Examen $when · $countdown…';
  }

  @override
  String get navMenuMoveUp => 'Subir';

  @override
  String get navMenuMoveDown => 'Bajar';

  @override
  String get navMenuNewPage => 'Nueva página';

  @override
  String get navMenuMoveToGroup => 'Mover a un grupo…';

  @override
  String get navMenuSortAZ => 'Ordenar las páginas A→Z';

  @override
  String get navMenuSortEdited => 'Ordenar por última edición';

  @override
  String get navMenuExportSectionPdf => 'Exportar la sección como PDF…';

  @override
  String get navMenuPrintSection => 'Imprimir la sección…';

  @override
  String get navMenuRemoveExam => 'Quitar la fecha del examen';

  @override
  String get navMenuSetExam => 'Poner la fecha del examen…';

  @override
  String get navMenuMakeSubpage => 'Convertir en subpágina';

  @override
  String get navMenuMoveBackOut => 'Sacar de la subpágina';

  @override
  String get navMenuRemoveFavourite => 'Quitar de favoritos';

  @override
  String get navMenuAddFavourite => 'Añadir a favoritos';

  @override
  String get navMenuSharePdf => 'Compartir como PDF…';

  @override
  String get navMenuPrint => 'Imprimir…';

  @override
  String get navMenuCopyLink => 'Copiar el enlace a la página';

  @override
  String get navMenuRecentChanges => 'Cambios recientes…';

  @override
  String get navMenuSaveTemplate => 'Guardar como plantilla…';

  @override
  String get navMenuApplyTemplate => 'Aplicar una plantilla…';

  @override
  String get navMenuRemovePasscode => 'Quitar el código…';

  @override
  String get navMenuLock => 'Bloquear con un código…';

  @override
  String get navMenuDelete => 'Borrar';

  @override
  String get commonOn => 'Sí';

  @override
  String get commonOff => 'No';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonDelete => 'Borrar';

  @override
  String get commonOpenEllipsis => 'Abrir…';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeDark => 'Oscuro';

  @override
  String get settingsWriting => 'Escritura y dibujo';

  @override
  String get settingsSpellCheck => 'Corrector ortográfico';

  @override
  String get settingsPenProximity =>
      'Acercar el lápiz a la página cambia a tinta';

  @override
  String get settingsConnections => 'Conexiones';

  @override
  String get settingsSync => 'Sincronización';

  @override
  String get settingsSyncHint =>
      'Haz copia de este cuaderno y compártelo — GitHub o una carpeta.';

  @override
  String get settingsAi => 'Acceso de la IA';

  @override
  String get settingsAiOn =>
      'Sí — los asistentes de IA de este ordenador pueden usar tus notas.';

  @override
  String get settingsAiOff => 'No — conecta Claude u otros asistentes de IA.';

  @override
  String get settingsHelp => 'Ayuda';

  @override
  String get settingsWelcomeTour => 'Visita guiada';

  @override
  String get settingsWelcomeTourHint =>
      'La versión de tres minutos: el lienzo, las matemáticas y la tinta, y dónde viven tus notas.';

  @override
  String get settingsShortcuts => 'Atajos de teclado';

  @override
  String get settingsShortcutsHint =>
      'Todo tiene una tecla — la lista completa.  (Ctrl+/)';

  @override
  String get settingsAbout => 'Acerca de';

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsCheckUpdates => 'Buscar actualizaciones';

  @override
  String settingsUpToDate(String version) {
    return 'Todo está al día ($version es la versión más reciente).';
  }

  @override
  String get settingsWhatsNew => 'Novedades';

  @override
  String get nbTitle => 'Cuadernos';

  @override
  String nbOpenCount(int count) {
    return '$count abiertos';
  }

  @override
  String nbInBin(int days) {
    return 'En la papelera · se borra a los $days días';
  }

  @override
  String get nbImportInto => 'Importar a un cuaderno nuevo';

  @override
  String get nbNew => 'Nuevo';

  @override
  String get nbNewTitle => 'Cuaderno nuevo';

  @override
  String get nbCreate => 'Crear';

  @override
  String get nbNameHint => 'Nombre del cuaderno';

  @override
  String get nbImport => 'Importar';

  @override
  String get nbRepair => 'Reparar';

  @override
  String get nbGetStarted => 'Empezar';

  @override
  String get nbImportOnepkg => 'Cuaderno de OneNote (.onepkg)';

  @override
  String get nbImportOne => 'Sección de OneNote (.one)';

  @override
  String get nbImportMarkdown => 'Carpeta de Markdown';

  @override
  String get nbImportGit => 'Desde una dirección git';

  @override
  String get nbDuplicates =>
      'Posibles duplicados · mismo título y mismo número de páginas';

  @override
  String get nbDuplicatesHint =>
      'Quédate con el más grande — el pequeño suele ser una importación que se cortó a medias. Las copias borradas van a la papelera.';

  @override
  String get nbOpenThis => 'Abrir este cuaderno';

  @override
  String get nbRename => 'Renombrar';

  @override
  String get nbDuplicate => 'Duplicar';

  @override
  String get nbMoveToBin => 'Mover a la papelera';

  @override
  String get nbConfirmBin =>
      '¿Mover a la papelera? Podrás restaurarlo desde aquí.';

  @override
  String get nbOnePkgFileType => 'Paquete de cuaderno de OneNote';

  @override
  String get nbImportBusy =>
      'Ya hay una importación en marcha — de una en una.';

  @override
  String get nbImportStarted =>
      'Importando en segundo plano — sigue trabajando; la tarjeta de la esquina avisará cuando termine.';

  @override
  String nbImportedNamed(String name) {
    return '$name importado';
  }

  @override
  String get nbReadingFolder => 'Leyendo la carpeta…';

  @override
  String nbImportedProgress(String done) {
    return 'Importado $done';
  }

  @override
  String get nbNoMarkdown =>
      'No se han encontrado archivos Markdown en esa carpeta.';

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
  String get nbNeedsNativeCore =>
      'Importar de OneNote necesita el núcleo Rust — compila onote_core.dll y ponlo junto a la aplicación.';

  @override
  String get nbCheckingPages => 'Comprobando las páginas…';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return 'Comprobando la página $done de $total…';
  }

  @override
  String get nbNothingToRepair =>
      'No hay nada que reparar — todas las páginas están al día.';

  @override
  String nbRepairedBoxes(int blocks) {
    String _temp0 = intl.Intl.pluralLogic(
      blocks,
      locale: localeName,
      other: '$blocks cuadros',
      one: '1 cuadro',
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
  String nbRepaired(String boxes, String pages) {
    return 'Reparados $boxes en $pages.';
  }

  @override
  String nbRepairFailed(String reason) {
    return 'La reparación ha fallado: $reason';
  }

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '$copies copias de «$title» · $pages páginas cada una · se recuperarían $size';
  }

  @override
  String get nbCoreMissing =>
      'Importar de OneNote necesita el núcleo Rust — compila onote_core.dll (mira rust/onote_core/INTEGRATION.md).';

  @override
  String nbReadFileFailed(String reason) {
    return 'No se ha podido leer ese archivo: $reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return 'No se ha podido importar esa carpeta: $reason';
  }

  @override
  String get nbOneFileEmpty => 'No se ha podido leer nada de ese archivo .one.';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return 'Importado $what desde OneNote.$strokeNote';
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
  String mathSemanticLabel(String latex) {
    return 'Ecuación: $latex';
  }

  @override
  String get insertGroupWrite => 'Escribir';

  @override
  String get insertGroupBringIn => 'Traer';

  @override
  String get insertGroupLinkUp => 'Enlazar';

  @override
  String get insertTextBox => 'Cuadro';

  @override
  String get insertEquation => 'Ecuación';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertTable => 'Tabla';

  @override
  String get insertTableFromFile => 'De un archivo';

  @override
  String get insertTableFromFileTip => 'CSV o Excel';

  @override
  String get insertCode => 'Código';

  @override
  String get insertBoard => 'Tablero';

  @override
  String get insertBoardTip => 'Columnas de tarjetas que vas moviendo';

  @override
  String get insertPicture => 'Imagen';

  @override
  String get insertPdfSlides => 'PDF';

  @override
  String get insertPdfPrintout => 'Impreso en esta página';

  @override
  String get insertPdfPerSlide => 'Una página por diapositiva';

  @override
  String get insertPdfAsCard => 'Como tarjeta — se abre en una ventana';

  @override
  String get insertVideo => 'Vídeo';

  @override
  String get insertVideoTip => 'Una grabación de clase, o cualquier enlace web';

  @override
  String get insertFile => 'Archivo';

  @override
  String get insertFlashcardItem => 'Ficha';

  @override
  String get insertPageLink => 'Enlace';

  @override
  String get insertPageWindow => 'Ventana';

  @override
  String get insertTemplate => 'Plantilla';

  @override
  String get insertPickImages => 'Imágenes';

  @override
  String get insertPickTables => 'Tablas';

  @override
  String get insertPickVideo => 'Vídeo y audio';

  @override
  String get tagTodo => 'Tarea';

  @override
  String get tagImportant => 'Importante';

  @override
  String get tagQuestion => 'Pregunta';

  @override
  String get tagRemember => 'Recordar';

  @override
  String get tagDefinition => 'Definición';

  @override
  String get tagIdea => 'Idea';

  @override
  String get tagCritical => 'Urgente';

  @override
  String get tagContact => 'Contacto';

  @override
  String get tagCustom => 'Etiqueta';

  @override
  String get touchDrawAuto => 'Auto (manda el lápiz)';

  @override
  String get touchDrawAlways => 'Siempre';

  @override
  String get touchDrawNever => 'Nunca';

  @override
  String get insertLinkToPage => 'Enlazar a una página';

  @override
  String get insertPdfUnreadable => 'No se ha podido leer ese PDF.';

  @override
  String insertPdfImported(int count, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count diapositivas importadas',
      one: '1 diapositiva importada',
    );
    return '$_temp0$where — coge el bolígrafo y escribe encima. El texto de las diapositivas se puede buscar.';
  }

  @override
  String get insertPdfOntoThisPage => ' en esta página';

  @override
  String insertPdfFailed(String reason) {
    return 'La importación del PDF ha fallado: $reason';
  }

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageAuto => 'El mismo que mi ordenador';

  @override
  String get settingsLanguageHelp =>
      'Openote lo traduce quien lo usa. Si falta el tuyo o algo está mal, es un solo archivo — el enlace explica cómo.';

  @override
  String get settingsLanguageContribute => 'Cómo añadir o corregir un idioma';

  @override
  String get shellNothingReplaced => 'No se ha reemplazado nada';

  @override
  String shellReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coincidencias reemplazadas',
      one: '1 coincidencia reemplazada',
    );
    return '$_temp0';
  }

  @override
  String get shellReplaceWith => 'Reemplazar por…';

  @override
  String get shellReplace => 'Reemplazar';

  @override
  String get shellReplaceAll => 'Todo';

  @override
  String get shellFindOnThisPage => 'Buscar en esta página…';

  @override
  String get shellNoMatches => 'Sin coincidencias';

  @override
  String get shellPreviousMatch => 'Coincidencia anterior (Shift+Enter)';

  @override
  String get shellNextMatch => 'Coincidencia siguiente (Enter)';

  @override
  String get shellCloseEsc => 'Cerrar (Esc)';

  @override
  String get shellNoTags => 'Aún no hay etiquetas en este cuaderno.';

  @override
  String get shellTagsHint =>
      'Las etiquetas marcan una línea — tarea, importante, pregunta, definición — para que puedas volver a encontrarla, repasarla o ponerle una fecha límite.';

  @override
  String get shellTagTheLine => 'Etiquetar la línea en la que estás';

  @override
  String get shellNoHeadings => 'No hay títulos en esta página.';

  @override
  String get shellHeadingsHint =>
      'Empieza una línea con # para hacer un título — el esquema se construye solo mientras escribes.';

  @override
  String get shellLinkedFrom => 'Enlazada desde';

  @override
  String get shellNoBacklinks => 'Todavía no hay páginas que enlacen aquí.';

  @override
  String get shellLinksTo => 'Enlaza a';

  @override
  String get shellNoLinks => 'Esta página todavía no enlaza a nada.';

  @override
  String get shellSavedLocally =>
      'Esta página está guardada en tu archivo .onote local.';

  @override
  String get shellSaving => 'Guardando…';

  @override
  String get shellSavedOnDevice => 'Guardado en este dispositivo';

  @override
  String shellRustLinked(String build) {
    return 'El núcleo Rust (onote-core) está enlazado y calcula el hash del contenido de esta página al guardar.\n$build';
  }

  @override
  String get shellRustMissing =>
      'Funcionando con el motor puro de Dart. Compila la biblioteca onote-core para enlazar el núcleo Rust.';

  @override
  String get shellCheatSheet =>
      'V seleccionar · T texto · P bolígrafo · H marcador · E borrar · Ctrl+Z deshacer · Ctrl+rueda zoom';

  @override
  String get shellEmptyTitle => 'Una página abierta te espera';

  @override
  String get shellEmptyBody =>
      'Todo lo que hagas aquí vive en tu dispositivo,\nen un formato abierto que es tuyo.';

  @override
  String get shellCreateFirstPage => 'Crea tu primera página';

  @override
  String get shellAlreadyUpToDate => 'Ya está todo al día.';

  @override
  String shellPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cambios recibidos',
      one: '1 cambio recibido',
    );
    return '$_temp0';
  }

  @override
  String shellPageLocked(String title) {
    return '«$title» está bloqueada';
  }

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag  ($count)';
  }

  @override
  String get shellUnlock => 'Desbloquear';

  @override
  String get onboardingStep1Title => 'La página es un lienzo';

  @override
  String get onboardingStep1Body =>
      'Haz clic donde quieras y empieza a escribir — el cuadro aparece donde hiciste clic, y solo cuando escribes. Muévelo con la barra de arriba, y arrastra imágenes desde donde sea.';

  @override
  String get onboardingStep2Title => 'Matemáticas y dibujo, entre las palabras';

  @override
  String get onboardingStep2Body =>
      'Escribe 1/2 o pulsa Alt+= y se va formando la notación de verdad mientras escribes, en su propio cuadro o dentro de la frase. La pestaña Dibujar acepta lápiz, dedo o ratón.';

  @override
  String get onboardingStep3Title => 'Tus notas son un archivo tuyo';

  @override
  String get onboardingStep3Body =>
      'Un archivo abierto y legible por cuaderno — sin cuenta y sin ataduras. Ponlo en una carpeta que tu nube ya sincronice y todos tus dispositivos irán a una.';

  @override
  String get onboardingStartWriting => 'Empezar a escribir';

  @override
  String get onboardingSyncTitle => 'Sincronizar con otro dispositivo';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive, OneDrive, iCloud, Dropbox, Syncthing, un NAS — o un repositorio de GitHub.';

  @override
  String get onboardingSyncBodyAlso => '¿Ninguno de esos? Elige tú la carpeta.';

  @override
  String get onboardingSyncAction => 'Configurar…';

  @override
  String get onboardingOneNoteTitle => 'Traer notas desde OneNote';

  @override
  String get onboardingOneNoteBody =>
      'Páginas, formato, imágenes, tinta y etiquetas desde un .onepkg. Va en segundo plano — sigue con lo tuyo mientras trabaja.';

  @override
  String get onboardingOneNoteAction => 'Elegir archivo…';

  @override
  String get onboardingOnePkgFileType => 'Paquete de cuaderno de OneNote';

  @override
  String get onboardingOneNoteHowTo => '¿Cómo lo exporto?';

  @override
  String get onboardingOneNoteHideSteps => 'Ocultar los pasos';

  @override
  String get onboardingExportTitle => 'Exportar desde OneNote';

  @override
  String get onboardingExportSteps =>
      '1. Abre OneNote para Windows (la aplicación de escritorio — las versiones de la Store y de la web no pueden exportar).\n2. Espera a que el cuaderno termine de sincronizarse, para tenerlo entero en este ordenador.\n3. Archivo ▸ Exportar ▸ Bloc de notas ▸ Paquete de OneNote (*.onepkg), y luego Exportar.\n4. Vuelve aquí y elige ese archivo.';

  @override
  String get onboardingExportMacNote =>
      'En un Mac, o si solo tienes la versión de la Store: exporta sección a sección como .one, o pídele a un ordenador con Windows que haga el .onepkg. Openote nunca entra en tu cuenta de Microsoft — solo lee el archivo que le das.';

  @override
  String onboardingImportingFile(String fileName) {
    return 'Importando $fileName';
  }

  @override
  String get onboardingImportRunning =>
      'Sigue con lo tuyo — esto va en segundo plano, y la tarjeta de la esquina avisará cuando termine.';

  @override
  String get onboardingImportDone => 'Tu cuaderno está listo';

  @override
  String get onboardingOpenFailed => 'Openote no ha podido abrir ese cuaderno.';

  @override
  String get onboardingNoNativeCore =>
      'Importar de OneNote necesita el núcleo nativo, que esta versión no incluye.';

  @override
  String onboardingReadFailed(String reason) {
    return 'No se ha podido leer ese archivo: $reason';
  }
}
