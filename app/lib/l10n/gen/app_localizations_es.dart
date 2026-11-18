// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class LEs extends L {
  LEs([String locale = 'es']) : super(locale);

  @override
  String atomNewerVersion(String version) {
    return 'Creado en Openote $version';
  }

  @override
  String get atomNewerVersionUnknown =>
      'Creado en una versión más reciente de Openote';

  @override
  String get atomUpdateToView => 'Actualiza Openote para verlo';

  @override
  String get barBackToEquation => 'Volver a las herramientas de ecuaciones';

  @override
  String barBadgeCount(int count) {
    return '$count';
  }

  @override
  String get barBlankOut => 'Ocultar lo seleccionado';

  @override
  String get barBlankOutNeedsSelection =>
      'Selecciona primero las palabras que quieres ocultar.';

  @override
  String get barBold => 'Negrita  (Ctrl+B)';

  @override
  String get barBulletList => 'Lista con viñetas';

  @override
  String get barCheckbox => 'Casilla';

  @override
  String get barClickIntoTextBox => 'Haz clic en un cuadro de texto';

  @override
  String get barDefinitionCard => 'Ficha de definición';

  @override
  String get barDueDateChange => 'Cambiar la fecha límite…';

  @override
  String get barDueDateClear => 'Quitar la fecha límite';

  @override
  String get barDueDatePickerConfirm => 'Poner';

  @override
  String get barDueDatePickerTitle => 'Fecha límite';

  @override
  String get barDueDateSet => 'Fecha límite…';

  @override
  String get barEquationBadge => 'Ecuación';

  @override
  String get barEraserSplit => 'Parte los trazos por donde frotas';

  @override
  String get barEraserWhole => 'Quita el trazo entero que toques';

  @override
  String get barEscWhenDone => 'Pulsa Esc cuando termines';

  @override
  String get barExport => 'Exportar';

  @override
  String get barExportCanvas => 'Para Obsidian Canvas (.canvas)';

  @override
  String get barExportInk => 'Solo el dibujo (.inkml)';

  @override
  String get barExportMarkdown => 'Markdown (.md)';

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
  String get barExportPdf => 'PDF (.pdf)';

  @override
  String get barExportPdfPicture => 'PDF — imagen de la página';

  @override
  String get barExportPrint => 'Imprimir…';

  @override
  String get barExportTip => 'Exportar página…';

  @override
  String barExportedTo(String path) {
    return 'Exportado a $path';
  }

  @override
  String get barFindOnPage => 'Buscar en la página';

  @override
  String get barFindOnPageTip => 'Buscar en la página  (Ctrl+F)';

  @override
  String get barFontSizeDefault => 'Predeterminado';

  @override
  String barFontSizePt(String size) {
    return '$size pt';
  }

  @override
  String get barHeading1 => 'Título 1';

  @override
  String get barHighlight => 'Resaltado';

  @override
  String get barInkColourTitle => 'Color del lápiz';

  @override
  String get barInkDefaultColour =>
      'Tinta predeterminada: se adapta a la página';

  @override
  String get barInkHighlighterColourTitle => 'Color del marcador';

  @override
  String get barInkMoreColours => 'Más colores…';

  @override
  String get barInkPickColour => 'Tomar un color de la página';

  @override
  String get barInkPickingHint =>
      'Haz clic en algo de la página para usar su color';

  @override
  String get barInlineCode => 'Código en línea';

  @override
  String get barItalic => 'Cursiva  (Ctrl+I)';

  @override
  String get barLassoHint =>
      'Rodea la tinta con un lazo para seleccionarla — luego arrástrala o bórrala';

  @override
  String get barMakeCardFromLine => 'Convertir esta línea en una ficha';

  @override
  String get barNewCard => 'Ficha nueva';

  @override
  String get barNumberedList => 'Lista numerada';

  @override
  String get barOpenStudyPanel => 'Abrir el panel de estudio';

  @override
  String get barPageOverview => 'Resumen de la página';

  @override
  String get barPenProximity =>
      'Acercar el lápiz a la página cambia a tinta.\nSi eliges otra herramienta con el lápiz cerca, se mantiene hasta\nque el lápiz se aleja y vuelve. La punta trasera del lápiz (o su\nbotón lateral, pulsado al dibujar) borra.';

  @override
  String barPenSize(String size) {
    return 'Grosor $size';
  }

  @override
  String get barPenSizeExact => 'Tamaño exacto…';

  @override
  String get barPlanner => 'Agenda';

  @override
  String get barPlannerEmpty => 'Agenda — todas tus fechas en un mismo sitio';

  @override
  String barPlannerOverdue(int count) {
    return 'Agenda — $count para hoy o atrasadas';
  }

  @override
  String barPlannerToday(int count) {
    return 'Agenda — $count para hoy';
  }

  @override
  String get barQuestionCard => 'Ficha de pregunta';

  @override
  String get barQuote => 'Cita';

  @override
  String get barRedo => 'Rehacer  (Ctrl+Y)';

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
  String barSaveFailed(String reason) {
    return 'No se ha podido guardar: $reason';
  }

  @override
  String get barSettings => 'Ajustes';

  @override
  String get barSettingsTip => 'Ajustes…';

  @override
  String get barStrikethrough => 'Tachado';

  @override
  String get barStudy => 'Estudio';

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
  String get barStudyEmpty =>
      'Estudio — etiqueta una línea como Pregunta o Definición para crear una ficha';

  @override
  String barStudyExamCountdown(String when) {
    return ' · examen $when';
  }

  @override
  String get barTabDraw => 'Dibujar';

  @override
  String get barTabHome => 'Inicio';

  @override
  String get barTabInsert => 'Insertar';

  @override
  String get barTabPage => 'Página';

  @override
  String get barTagLine =>
      'Etiquetar esta línea (Tarea, Importante, Pregunta…)';

  @override
  String barTagged(String tags) {
    return 'Etiquetada: $tags';
  }

  @override
  String get barTextColour => 'Aplicar color al texto';

  @override
  String get barTextFont => 'Fuente del texto…';

  @override
  String get barTextSize => 'Tamaño del texto (puntos)';

  @override
  String get barTextSizeDisabled =>
      'Haz clic en un cuadro de texto para cambiar su tamaño';

  @override
  String get barToolEraser => 'Borrador  (E)';

  @override
  String get barToolHighlighter => 'Marcador  (H)';

  @override
  String get barToolLasso => 'Seleccionar tinta con lazo';

  @override
  String get barToolPen => 'Bolígrafo  (P)';

  @override
  String get barToolSelect => 'Seleccionar / mover  (V)';

  @override
  String get barToolText => 'Texto  (T)';

  @override
  String get barUnderline => 'Subrayado  (Ctrl+U)';

  @override
  String get barUndo => 'Deshacer  (Ctrl+Z)';

  @override
  String barUpdateTo(String version) {
    return 'Actualizar a $version…';
  }

  @override
  String get canvasDeleteSelection => 'Eliminar  (Supr)';

  @override
  String get canvasGroupSelection => 'Agrupar  (Ctrl+G)';

  @override
  String get canvasUngroupSelection => 'Desagrupar  (Ctrl+Mayús+G)';

  @override
  String get commandNotInDemo => 'No disponible en la demostración web';

  @override
  String get commonBack => 'Atrás';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get commonDelete => 'Borrar';

  @override
  String get commonDetailsAdvanced => 'Detalles (avanzado)';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonNext => 'Siguiente';

  @override
  String get commonOff => 'No';

  @override
  String get commonOn => 'Sí';

  @override
  String get commonOpen => 'Abrir';

  @override
  String get commonOpenEllipsis => 'Abrir…';

  @override
  String get commonSkip => 'Omitir';

  @override
  String importBringingIn(String name, int done, int total) {
    return 'Trayendo «$name» — $done de $total páginas…';
  }

  @override
  String get importCancelledLabel => 'Importación cancelada.';

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
      other: '$count páginas importadas, pero no se pudo traer $detail.',
      one: '1 página importada, pero no se pudo traer $detail.',
    );
    return '$_temp0';
  }

  @override
  String get importEmptyNotebook => 'Ese cuaderno no tenía páginas.';

  @override
  String get importFailedGeneric => 'No se pudo traer ese cuaderno.';

  @override
  String importFoundPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas por traer. Empezando…',
      one: '1 página por traer. Empezando…',
    );
    return '$_temp0';
  }

  @override
  String importFoundSections(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count secciones encontradas — viendo qué contienen…',
      one: '1 sección encontrada — viendo qué contiene…',
    );
    return '$_temp0';
  }

  @override
  String get importLookingAround => 'Revisando tu cuaderno…';

  @override
  String importPartialBroke(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Algo salió mal a mitad, pero las $count páginas ya traídas están aquí. Openote terminará el resto por su cuenta más tarde.',
    );
    return '$_temp0';
  }

  @override
  String importPartialThrottled(String detail, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$detail Las $count páginas ya traídas están aquí. Openote terminará el resto por su cuenta más tarde, o puedes empezarlo de nuevo cuando quieras.',
    );
    return '$_temp0';
  }

  @override
  String get importReading => 'Leyendo el cuaderno…';

  @override
  String get importSigningIn => 'Iniciando sesión en OneNote…';

  @override
  String importStoppedKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Detenido — se conservan las $count páginas ya traídas. Puedes terminarlo cuando quieras.',
      one:
          'Detenido — se conserva la página ya traída. Puedes terminarlo cuando quieras.',
    );
    return '$_temp0';
  }

  @override
  String get importStopping => 'Deteniendo…';

  @override
  String importThrottled(int seconds) {
    return 'Microsoft ha pedido a Openote que vaya más despacio — seguimos en ${seconds}s. No se pierde nada de lo ya traído.';
  }

  @override
  String get importThrottledSoon =>
      'Microsoft ha pedido a Openote que vaya más despacio — seguimos en un momento. No se pierde nada de lo ya traído.';

  @override
  String importWritingPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Importando $count páginas…',
      one: 'Importando 1 página…',
    );
    return '$_temp0';
  }

  @override
  String importWritingSection(String name) {
    return 'Importando «$name»…';
  }

  @override
  String get insertBoard => 'Tablero';

  @override
  String get insertBoardTip => 'Columnas de tarjetas que vas moviendo';

  @override
  String get insertCode => 'Código';

  @override
  String get insertEquation => 'Ecuación';

  @override
  String get insertEquationTip => 'Alt+=';

  @override
  String get insertFile => 'Archivo';

  @override
  String get insertFlashcardItem => 'Ficha';

  @override
  String get insertGroupBringIn => 'Traer';

  @override
  String get insertGroupLinkUp => 'Enlazar';

  @override
  String get insertGroupWrite => 'Escribir';

  @override
  String get insertLinkToPage => 'Enlazar a una página';

  @override
  String get insertPageLink => 'Enlace';

  @override
  String get insertPageWindow => 'Ventana';

  @override
  String get insertPdfAsCard => 'Como tarjeta — se abre en una ventana';

  @override
  String insertPdfFailed(String reason) {
    return 'La importación del PDF ha fallado: $reason';
  }

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
  String get insertPdfPerSlide => 'Una página por diapositiva';

  @override
  String get insertPdfPrintout => 'Impreso en esta página';

  @override
  String get insertPdfSlides => 'PDF';

  @override
  String get insertPdfUnreadable => 'No se ha podido leer ese PDF.';

  @override
  String get insertPickImages => 'Imágenes';

  @override
  String get insertPickTables => 'Tablas';

  @override
  String get insertPickVideo => 'Vídeo y audio';

  @override
  String get insertPicture => 'Imagen';

  @override
  String get insertTable => 'Tabla';

  @override
  String get insertTableFromFile => 'De un archivo';

  @override
  String get insertTableFromFileTip => 'CSV o Excel';

  @override
  String get insertTextBox => 'Cuadro';

  @override
  String get insertVideo => 'Vídeo';

  @override
  String get insertVideoTip => 'Una grabación de clase, o cualquier enlace web';

  @override
  String get linkEdit => 'Editar enlace…';

  @override
  String mathSemanticLabel(String latex) {
    return 'Ecuación: $latex';
  }

  @override
  String navAllCount(int total) {
    return 'Ver las $total';
  }

  @override
  String get navBinEmpty => 'No hay nada borrado.';

  @override
  String get navBinItems => 'Elementos';

  @override
  String get navBinNotebooks => 'Cuadernos';

  @override
  String navBinRetention(int days) {
    return 'Lo que hay aquí se borra definitivamente a los $days días.';
  }

  @override
  String get navClose => 'Cerrar';

  @override
  String get navCollapse => 'Plegar el navegador  (Ctrl+\\)';

  @override
  String get navColour => 'Color';

  @override
  String get navColourDefault => 'Predeterminado';

  @override
  String get navComingUp => 'PRÓXIMAMENTE';

  @override
  String get navDeleteForever => 'Borrar para siempre';

  @override
  String navDeleteForeverBody(String title, String caveat) {
    return '«$title» y todas sus páginas se borrarán para siempre. Esto no se puede deshacer.$caveat';
  }

  @override
  String get navDeleteForeverTitle => '¿Borrar definitivamente?';

  @override
  String get navDeletePermanently => 'Borrar definitivamente';

  @override
  String navDeletedGroup(String title) {
    return 'Grupo “$title” movido a la papelera';
  }

  @override
  String navDeletedPage(String title) {
    return 'Página “$title” movida a la papelera';
  }

  @override
  String navDeletedSection(String title) {
    return 'Sección “$title” movida a la papelera';
  }

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
  String get navDeletesSoon => 'Se borra pronto';

  @override
  String navExamCountdown(String when, String countdown) {
    return 'Examen $when · $countdown…';
  }

  @override
  String get navExpand => 'Desplegar el navegador  (Ctrl+\\)';

  @override
  String get navSectionsHeader => 'Secciones';

  @override
  String get navNewSectionOrGroup => 'Nueva sección o grupo';

  @override
  String get dropMoveAbove => 'Mover arriba';

  @override
  String get dropMoveBelow => 'Mover abajo';

  @override
  String get dropMakeSubpage => 'Hacer subpágina';

  @override
  String get dropGroupTogether => 'Agrupar';

  @override
  String get dropMoveIntoGroup => 'Mover al grupo';

  @override
  String get dropMoveToSection => 'Mover a esta sección';

  @override
  String get navBinEmptyAction => 'Vaciar';

  @override
  String get navBinEmptyTitle => '¿Vaciar la papelera?';

  @override
  String get navBinEmptyBody =>
      'Todo lo que contiene se borrará definitivamente. No se puede deshacer.';

  @override
  String get navBinEmptySharedNote =>
      'Los cuadernos de una carpeta compartida solo se quitan de este ordenador.';

  @override
  String navBinDeleteOneBody(String title) {
    return '«$title» se borrará definitivamente. No se puede deshacer.';
  }

  @override
  String get navBinKindPage => 'Página';

  @override
  String get navBinKindSection => 'Sección';

  @override
  String get navBinKindGroup => 'Grupo';

  @override
  String get navBinKindNotebook => 'Cuaderno';

  @override
  String navBinItemLine(String kind, String when) {
    return '$kind · $when';
  }

  @override
  String get navBinWhenToday => 'hoy';

  @override
  String get navBinWhenYesterday => 'ayer';

  @override
  String navBinWhenDaysAgo(int days) {
    return 'hace $days días';
  }

  @override
  String get reviewTitle => 'Revisar la escritura';

  @override
  String reviewChip(int count) {
    return '$count por revisar';
  }

  @override
  String get reviewChipClear => 'Sin problemas de escritura';

  @override
  String get reviewTooltip => 'Revisar la escritura (F7)';

  @override
  String get reviewChecking => 'Revisando la escritura…';

  @override
  String fixNoticeRevert(String word) {
    return 'Volver a «$word»';
  }

  @override
  String reviewSubtitle(int count, String language) {
    return 'En esta página · $count por revisar · $language';
  }

  @override
  String get reviewSpelling => 'Ortografía';

  @override
  String get reviewGrammar => 'Gramática';

  @override
  String get reviewPunctuation => 'Puntuación';

  @override
  String get reviewFixAll => 'Corregir todo';

  @override
  String get reviewAccept => 'Aceptar';

  @override
  String get reviewIgnore => 'Omitir';

  @override
  String get reviewAddToDictionary => 'Añadir al diccionario';

  @override
  String get reviewNotInDictionary => 'No está en el diccionario';

  @override
  String get reviewRemove => 'Quitar';

  @override
  String get reviewAllClear => 'No hay nada que revisar en esta página.';

  @override
  String reviewFixedSpelling(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errores de ortografía corregidos',
      one: '1 error de ortografía corregido',
    );
    return '$_temp0';
  }

  @override
  String reviewFixedGrammar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errores gramaticales corregidos',
      one: '1 error gramatical corregido',
    );
    return '$_temp0';
  }

  @override
  String reviewFixedPunctuation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errores de puntuación corregidos',
      one: '1 error de puntuación corregido',
    );
    return '$_temp0';
  }

  @override
  String get navHideSections => 'Ocultar la lista de secciones';

  @override
  String get navRecent => 'Recientes';

  @override
  String get navHomeEmpty =>
      'Aquí no hay nada todavía.\n\nHaz clic derecho en una página y elige Favorita para fijarla; las páginas que visites aparecen en Recientes.';

  @override
  String get navRecentTip => 'Páginas recientes y favoritas';

  @override
  String get navInPageContent => 'En el contenido de las páginas';

  @override
  String get navLinkCopied => 'Enlace copiado — pégalo en cualquier página';

  @override
  String navLockedCannotDelete(String title) {
    return '«$title» está bloqueada. Quita su código antes de borrarla.';
  }

  @override
  String navLockedNotEncrypted(String title) {
    return '«$title» está bloqueada. Está oculta dentro de Openote, no cifrada en el archivo.';
  }

  @override
  String get navMenuAddFavourite => 'Añadir a favoritos';

  @override
  String get navMenuCopyLink => 'Copiar el enlace a la página';

  @override
  String get navMenuDelete => 'Borrar';

  @override
  String get navMenuDuplicate => 'Duplicar';

  @override
  String get navMenuExportSectionPdf => 'Exportar la sección como PDF…';

  @override
  String get navMenuLock => 'Bloquear con un código…';

  @override
  String get navMenuMakeSubpage => 'Convertir en subpágina';

  @override
  String get navMenuMoveBackOut => 'Sacar de la subpágina';

  @override
  String get navMenuMoveDown => 'Bajar';

  @override
  String get navMenuMoveToGroup => 'Mover a un grupo…';

  @override
  String get navMenuMoveUp => 'Subir';

  @override
  String get navMenuNewPage => 'Nueva página';

  @override
  String get navMenuPrint => 'Imprimir…';

  @override
  String get navMenuPrintSection => 'Imprimir la sección…';

  @override
  String get navMenuRecentChanges => 'Cambios recientes…';

  @override
  String get navMenuRemoveExam => 'Quitar la fecha del examen';

  @override
  String get navMenuRemoveFavourite => 'Quitar de favoritos';

  @override
  String get navMenuRemovePasscode => 'Quitar el código…';

  @override
  String get navMenuRename => 'Renombrar';

  @override
  String get navMenuSetExam => 'Poner la fecha del examen…';

  @override
  String get navMenuSharePdf => 'Compartir como PDF…';

  @override
  String get navMenuSortAZ => 'Ordenar las páginas A→Z';

  @override
  String get navMenuSortEdited => 'Ordenar por última edición';

  @override
  String get navMoveSectionTo => 'Mover la sección a…';

  @override
  String navNewPageIn(String section) {
    return 'Nueva página en $section';
  }

  @override
  String get navNewSection => 'Nueva sección';

  @override
  String get navNewSectionGroup => 'Nuevo grupo';

  @override
  String get navNoGroupTopLevel => '(Sin grupo — nivel superior)';

  @override
  String navNoMatches(String query) {
    return 'Sin resultados para «$query»';
  }

  @override
  String get navNoPages => 'Aún no hay páginas';

  @override
  String get navNoSections => 'Aún no hay secciones.\nCrea una para empezar.';

  @override
  String get navNotebooksTip =>
      'Cuadernos — cambiar, renombrar, duplicar, importar';

  @override
  String get navOpen => 'Abrir';

  @override
  String navPasscodeRemoved(String title) {
    return 'Código quitado de «$title».';
  }

  @override
  String get navRecycleBin => 'Papelera';

  @override
  String get navRestore => 'Restaurar';

  @override
  String get navSave => 'Guardar';

  @override
  String navSavedTo(String path) {
    return 'Guardado en $path';
  }

  @override
  String get navSearchHint => 'Buscar o ir a…';

  @override
  String get navSection => 'Sección';

  @override
  String get navShowSections => 'Mostrar la lista de secciones';

  @override
  String get navUndo => 'Deshacer';

  @override
  String get navUntitled => 'Sin título';

  @override
  String nbCheckingPageProgress(int done, int total) {
    return 'Comprobando la página $done de $total…';
  }

  @override
  String get nbCheckingPages => 'Comprobando las páginas…';

  @override
  String get nbConfirmBin =>
      '¿Mover a la papelera? Podrás restaurarlo desde aquí.';

  @override
  String get nbConfirmBinShared =>
      'Este cuaderno está en una carpeta compartida. Quitarlo de este ordenador lo deja en la carpeta y en tus otros dispositivos; puedes volver a añadirlo cuando quieras con Abrir.';

  @override
  String get nbRemoveFromComputer => 'Quitar de este ordenador';

  @override
  String get nbDeleteEverywhere => 'Borrar en todas partes…';

  @override
  String nbDeleteEverywhereTitle(String title) {
    return '¿Borrar «$title» en todas partes?';
  }

  @override
  String get nbDeleteEverywhereBody =>
      'Se borrará de la carpeta compartida y desaparecerá de todos los dispositivos que la usan. Esto no se puede deshacer.';

  @override
  String get nbDeleteEverywhereConfirm => 'Borrar en todas partes';

  @override
  String nbRemoveSharedTitle(String title) {
    return '¿Quitar «$title» de este ordenador?';
  }

  @override
  String get nbRemoveSharedBody =>
      'Sigue en la carpeta compartida y en tus otros dispositivos. Puedes volver a añadirlo con Abrir.';

  @override
  String get nbCoreMissing =>
      'Importar de OneNote necesita el núcleo Rust — compila onote_core.dll (mira rust/onote_core/INTEGRATION.md).';

  @override
  String get nbCreate => 'Crear';

  @override
  String get nbDuplicate => 'Duplicar';

  @override
  String nbDuplicateGroup(int copies, String title, int pages, String size) {
    return '$copies copias de «$title» · $pages páginas cada una · se recuperarían $size';
  }

  @override
  String get nbDuplicates =>
      'Posibles duplicados · mismo título y mismo número de páginas';

  @override
  String get nbDuplicatesHint =>
      'Quédate con el más grande — el pequeño suele ser una importación que se cortó a medias. Las copias borradas van a la papelera.';

  @override
  String get nbGetStarted => 'Empezar';

  @override
  String get nbImport => 'Importar';

  @override
  String get nbImportBusy =>
      'Ya hay una importación en marcha — de una en una.';

  @override
  String get nbImportGit => 'Desde una dirección git';

  @override
  String get nbImportDriveFolder => 'Abrir desde una carpeta de Drive';

  @override
  String get nbImportInto => 'Importar a un cuaderno nuevo';

  @override
  String get nbImportMarkdown => 'Carpeta de Markdown';

  @override
  String get nbImportOne => 'Sección de OneNote (.one)';

  @override
  String get nbImportOnepkg => 'Cuaderno de OneNote (.onepkg)';

  @override
  String get nbImportStarted =>
      'Importando en segundo plano — sigue trabajando; la tarjeta de la esquina avisará cuando termine.';

  @override
  String nbImportedFromOneNote(String what, String strokeNote) {
    return 'Importado $what desde OneNote.$strokeNote';
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
    return 'En la papelera · se borra a los $days días';
  }

  @override
  String get nbMoveToBin => 'Mover a la papelera';

  @override
  String get nbNameHint => 'Nombre del cuaderno';

  @override
  String get nbNeedsNativeCore =>
      'Importar de OneNote necesita el núcleo Rust — compila onote_core.dll y ponlo junto a la aplicación.';

  @override
  String get nbNew => 'Nuevo';

  @override
  String get nbNewTitle => 'Cuaderno nuevo';

  @override
  String get nbNoMarkdown =>
      'No se han encontrado archivos Markdown en esa carpeta.';

  @override
  String get nbNothingToRepair =>
      'No hay nada que reparar — todas las páginas están al día.';

  @override
  String get nbOneFileEmpty => 'No se ha podido leer nada de ese archivo .one.';

  @override
  String get nbOnePkgFileType => 'Paquete de cuaderno de OneNote';

  @override
  String nbOpenCount(int count) {
    return '$count abiertos';
  }

  @override
  String get nbOpenThis => 'Abrir este cuaderno';

  @override
  String nbReadFileFailed(String reason) {
    return 'No se ha podido leer ese archivo: $reason';
  }

  @override
  String nbReadFolderFailed(String reason) {
    return 'No se ha podido importar esa carpeta: $reason';
  }

  @override
  String get nbReadingFolder => 'Leyendo la carpeta…';

  @override
  String get nbRename => 'Renombrar';

  @override
  String get nbRepair => 'Reparar';

  @override
  String nbRepairFailed(String reason) {
    return 'La reparación ha fallado: $reason';
  }

  @override
  String nbRepaired(String boxes, String pages) {
    return 'Reparados $boxes en $pages.';
  }

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
  String get nbTitle => 'Cuadernos';

  @override
  String objectRowBackground(String kind) {
    return 'Fondo: $kind';
  }

  @override
  String get objectRowBackgroundBlank => 'en blanco';

  @override
  String get objectRowBackgroundDotted => 'puntos';

  @override
  String get objectRowBackgroundGrid => 'cuadrícula';

  @override
  String get objectRowBackgroundRuled => 'rayado';

  @override
  String get objectRowCanvasMode =>
      'Modo lienzo: sin límites — haz clic para páginas';

  @override
  String get objectRowCharacters => 'Caracteres';

  @override
  String get objectRowCharactersNoSpaces => 'Sin espacios';

  @override
  String get objectRowLandscape => 'Horizontal';

  @override
  String get objectRowLandscapeSuffix => ' horizontal';

  @override
  String objectRowMinutes(int n) {
    return '$n min';
  }

  @override
  String objectRowPageMode(String paper, String landscape) {
    return 'Modo página: $paper$landscape — haz clic para lienzo';
  }

  @override
  String get objectRowPaperSize => 'Tamaño del papel';

  @override
  String get objectRowReadingTime => 'Tiempo de lectura';

  @override
  String get objectRowSnapOff =>
      'Ajustar a la cuadrícula: NO — colocación libre';

  @override
  String get objectRowSnapOn =>
      'Ajustar a la cuadrícula: SÍ (se ve al arrastrar)';

  @override
  String get objectRowWordCount =>
      'Palabras de esta página — haz clic para ver caracteres y tiempo de lectura';

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
  String get objectRowWords => 'Palabras';

  @override
  String get objectRowZoomFit => 'Ajustar el zoom al contenido';

  @override
  String get objectRowZoomIn => 'Acercar  (Ctrl+=)';

  @override
  String get objectRowZoomOut => 'Alejar  (Ctrl+-)';

  @override
  String objectRowZoomPercent(int percent) {
    return '$percent %';
  }

  @override
  String get objectRowZoomReset =>
      'Volver al 100% y al principio de la página  (Ctrl+0)';

  @override
  String get onboardingCloudAction => 'Iniciar sesión';

  @override
  String get onboardingCloudBody =>
      'Inicia sesión en Microsoft y elige un cuaderno. No hay que exportar nada antes, y funciona en cualquier ordenador.';

  @override
  String get onboardingCloudTitle => 'Traer notas desde OneNote';

  @override
  String get onboardingExportMacNote =>
      'En un Mac, o si solo tienes la versión de la Store: exporta sección a sección como .one, o pídele a un ordenador con Windows que haga el .onepkg. Openote nunca entra en tu cuenta de Microsoft — solo lee el archivo que le das.';

  @override
  String get onboardingExportSteps =>
      '1. Abre OneNote para Windows (la aplicación de escritorio — las versiones de la Store y de la web no pueden exportar).\n2. Espera a que el cuaderno termine de sincronizarse, para tenerlo entero en este ordenador.\n3. Archivo ▸ Exportar ▸ Bloc de notas ▸ Paquete de OneNote (*.onepkg), y luego Exportar.\n4. Vuelve aquí y elige ese archivo.';

  @override
  String get onboardingExportTitle => 'Exportar desde OneNote';

  @override
  String get onboardingFreshAction => 'Empezar de cero';

  @override
  String get onboardingFreshBody =>
      'Un cuaderno vacío, listo para escribir. Siempre puedes traer tus notas más tarde.';

  @override
  String get onboardingFreshTitle => 'Empezar un cuaderno nuevo';

  @override
  String get onboardingImportDone => 'Tu cuaderno está listo';

  @override
  String get onboardingImportRunning =>
      'Sigue con lo tuyo — esto va en segundo plano, y la tarjeta de la esquina avisará cuando termine.';

  @override
  String onboardingImportingFile(String fileName) {
    return 'Importando $fileName';
  }

  @override
  String get onboardingNoNativeCore =>
      'Importar de OneNote necesita el núcleo nativo, que esta versión no incluye.';

  @override
  String get onboardingOneNoteAction => 'Elegir archivo…';

  @override
  String get onboardingOneNoteBody =>
      'Páginas, formato, imágenes, tinta y etiquetas desde un .onepkg. Va en segundo plano — sigue con lo tuyo mientras trabaja.';

  @override
  String get onboardingOneNoteHideSteps => 'Ocultar los pasos';

  @override
  String get onboardingOneNoteHowTo => '¿Cómo lo exporto?';

  @override
  String get onboardingOneNoteTitle => 'Traer notas desde OneNote';

  @override
  String get onboardingOnePkgFileType => 'Paquete de cuaderno de OneNote';

  @override
  String get onboardingOpenFailed => 'Openote no ha podido abrir ese cuaderno.';

  @override
  String onboardingReadFailed(String reason) {
    return 'No se ha podido leer ese archivo: $reason';
  }

  @override
  String get onboardingStartWriting => 'Empezar a escribir';

  @override
  String get onboardingStep1Body =>
      'Haz clic donde quieras y empieza a escribir — el cuadro aparece donde hiciste clic, y solo cuando escribes. Muévelo con la barra de arriba, y arrastra imágenes desde donde sea.';

  @override
  String get onboardingStep1Title => 'La página es un lienzo';

  @override
  String get onboardingStep2Body =>
      'Escribe 1/2 o pulsa Alt+= y se va formando la notación de verdad mientras escribes, en su propio cuadro o dentro de la frase. La pestaña Dibujar acepta lápiz, dedo o ratón.';

  @override
  String get onboardingStep2Title => 'Matemáticas y dibujo, entre las palabras';

  @override
  String get onboardingStep3Body =>
      'Un archivo abierto y legible por cuaderno — sin cuenta y sin ataduras. Ponlo en una carpeta que tu nube ya sincronice y todos tus dispositivos irán a una.';

  @override
  String get onboardingStep3Title => 'Tus notas son un archivo tuyo';

  @override
  String get onboardingSyncAction => 'Configurar…';

  @override
  String get onboardingSyncBodyAlso => '¿Ninguno de esos? Elige tú la carpeta.';

  @override
  String get onboardingSyncBodyFirst =>
      'Drive, OneDrive, iCloud, Dropbox, Syncthing, un NAS — o un repositorio de GitHub.';

  @override
  String get onboardingSyncTitle => 'Sincronizar con otro dispositivo';

  @override
  String get oneNoteCloudContinue => 'Continuar con Microsoft';

  @override
  String get oneNoteCloudEmpty => 'No se encontraron cuadernos en esta cuenta.';

  @override
  String get oneNoteCloudIntro =>
      'Openote leerá tus cuadernos de OneNote. No puede modificarlos.';

  @override
  String get oneNoteCloudLoading => 'Buscando tus cuadernos…';

  @override
  String get oneNoteCloudNoInk =>
      'Las tablas se ajustan a la página en lugar de conservar su anchura exacta, y el color y la fuente del texto no se conservan.';

  @override
  String get oneNoteCloudOther => 'Usar otra cuenta';

  @override
  String get oneNoteCloudSignIn => 'Iniciar sesión en Microsoft';

  @override
  String get oneNoteCloudSigningIn => 'Esperando a tu navegador…';

  @override
  String get oneNoteCloudTitle => 'Traer un cuaderno desde OneNote';

  @override
  String get oneNoteFileBody =>
      'Sin iniciar sesión, y la copia más fiel: las tablas conservan su anchura exacta. Necesitarás OneNote en Windows para exportar el cuaderno antes.';

  @override
  String get oneNoteFileTitle => 'Usar un archivo exportado';

  @override
  String get oneNotePickTitle => '¿Qué cuaderno?';

  @override
  String get oneNoteSignInBody =>
      'Elige un cuaderno y pasa directamente, sin exportar nada antes. Funciona en cualquier ordenador.';

  @override
  String get penButtonEraser => 'Borrador';

  @override
  String get penButtonLasso => 'Lazo';

  @override
  String get penButtonNothing => 'Nada';

  @override
  String get penButtonSelect => 'Seleccionar';

  @override
  String get settingsAbout => 'Acerca de';

  @override
  String get settingsAi => 'Acceso de la IA';

  @override
  String get settingsAiOff => 'No — conecta Claude u otros asistentes de IA.';

  @override
  String get settingsAiOn =>
      'Sí — la IA de este ordenador puede leer tus notas.';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsCheckUpdates => 'Buscar actualizaciones';

  @override
  String get settingsConnections => 'Conexiones';

  @override
  String get settingsDiagnostics => 'Diagnóstico';

  @override
  String get settingsHelp => 'Ayuda';

  @override
  String get settingsUiScale => 'Tamaño de la interfaz';

  @override
  String get settingsUiScaleHint =>
      'Hace toda la ventana más grande o más pequeña.';

  @override
  String settingsUiScaleLimited(String size) {
    return 'Se muestra al $size: esta ventana es demasiado pequeña para más.';
  }

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageAuto => 'Predeterminado del sistema';

  @override
  String get settingsLanguageContribute => 'Cómo añadir o corregir un idioma';

  @override
  String get settingsPenAndTouch => 'Lápiz y táctil';

  @override
  String get settingsPenButton => 'El botón lateral del lápiz';

  @override
  String get settingsPenButtonHint =>
      'Mantenlo pulsado para usar esa herramienta.';

  @override
  String get settingsPenTest => 'Prueba de lápiz y táctil';

  @override
  String get settingsPenTestHint => 'Lo que informan tu lápiz y sus botones.';

  @override
  String get settingsShortcuts => 'Atajos de teclado';

  @override
  String get settingsShortcutsHint => 'Ctrl+/';

  @override
  String get settingsReportProblem =>
      'Informar de un problema o proponer una idea';

  @override
  String get settingsReportProblemHint =>
      'Abre GitHub. Hace falta una cuenta gratuita de GitHub.';

  @override
  String get settingsSpellCheck => 'Corrector ortográfico';

  @override
  String get settingsSync => 'Sincronización';

  @override
  String get settingsSyncHint =>
      'Copia este cuaderno en GitHub o en una carpeta.';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeDark => 'Oscuro';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsTouchDrawing => 'Dibujar con el dedo';

  @override
  String get settingsTouchDrawingHint =>
      'Dos dedos siempre mueven y hacen zoom.';

  @override
  String settingsUpToDate(String version) {
    return 'Todo está al día ($version es la versión más reciente).';
  }

  @override
  String settingsVersion(String version) {
    return 'Openote $version';
  }

  @override
  String get settingsWelcomeTour => 'Visita guiada';

  @override
  String get settingsWelcomeTourHint =>
      'Tres minutos sobre cómo funciona el lienzo.';

  @override
  String get settingsWhatsNew => 'Novedades';

  @override
  String get settingsWriting => 'Escritura y dibujo';

  @override
  String get shellAlreadyUpToDate => 'Ya está todo al día.';

  @override
  String get shellCheatSheet =>
      'V seleccionar · T texto · P bolígrafo · H marcador · E borrar · Ctrl+Z deshacer · Ctrl+rueda zoom';

  @override
  String get shellCloseEsc => 'Cerrar (Esc)';

  @override
  String get shellCreateFirstPage => 'Crea tu primera página';

  @override
  String get shellDemoNothingSaved => 'Demostración: no se guarda nada';

  @override
  String get shellEmptyBody =>
      'Todo lo que hagas aquí vive en tu dispositivo,\nen un formato abierto que es tuyo.';

  @override
  String get shellEmptyTitle => 'Una página abierta te espera';

  @override
  String get shellFindOnThisPage => 'Buscar en esta página…';

  @override
  String get shellHeadingsHint =>
      'Empieza una línea con # para hacer un título — el esquema se construye solo mientras escribes.';

  @override
  String get shellLinkedFrom => 'Enlazada desde';

  @override
  String get shellLinksTo => 'Enlaza a';

  @override
  String get shellNextMatch => 'Coincidencia siguiente (Enter)';

  @override
  String get shellNoBacklinks => 'Todavía no hay páginas que enlacen aquí.';

  @override
  String get shellNoHeadings => 'No hay títulos en esta página.';

  @override
  String get shellNoLinks => 'Esta página todavía no enlaza a nada.';

  @override
  String get shellNoMatches => 'Sin coincidencias';

  @override
  String get shellNoTags => 'Aún no hay etiquetas en este cuaderno.';

  @override
  String get shellNothingReplaced => 'No se ha reemplazado nada';

  @override
  String shellPageLocked(String title) {
    return '«$title» está bloqueada';
  }

  @override
  String get shellPreviousMatch => 'Coincidencia anterior (Shift+Enter)';

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
  String get shellReplace => 'Reemplazar';

  @override
  String get shellReplaceAll => 'Todo';

  @override
  String get shellReplaceWith => 'Reemplazar por…';

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
  String shellRustLinked(String build) {
    return 'El núcleo Rust (onote-core) está enlazado y calcula el hash del contenido de esta página al guardar.\n$build';
  }

  @override
  String get shellRustMissing =>
      'Funcionando con el motor puro de Dart. Compila la biblioteca onote-core para enlazar el núcleo Rust.';

  @override
  String get shellSavedLocally =>
      'Esta página está guardada en tu archivo .onote local.';

  @override
  String get shellSavedOnDevice => 'Guardado en este dispositivo';

  @override
  String get shellSaving => 'Guardando…';

  @override
  String shellTagGroup(String tag, int count) {
    return '$tag  ($count)';
  }

  @override
  String get shellTagTheLine => 'Etiquetar la línea en la que estás';

  @override
  String get shellTagsHint =>
      'Las etiquetas marcan una línea — tarea, importante, pregunta, definición — para que puedas volver a encontrarla, repasarla o ponerle una fecha límite.';

  @override
  String get shellUnlock => 'Desbloquear';

  @override
  String get tableColumnLeft => 'Insertar columna a la izquierda';

  @override
  String get tableColumnRight => 'Insertar columna a la derecha';

  @override
  String get tableDeleteColumn => 'Eliminar columna';

  @override
  String get tableDeleteRow => 'Eliminar fila';

  @override
  String get tableRowAbove => 'Insertar fila encima';

  @override
  String get tableRowBelow => 'Insertar fila debajo';

  @override
  String get tagContact => 'Contacto';

  @override
  String get tagCritical => 'Urgente';

  @override
  String get tagCustom => 'Etiqueta';

  @override
  String get tagDefinition => 'Definición';

  @override
  String get tagIdea => 'Idea';

  @override
  String get tagImportant => 'Importante';

  @override
  String get tagQuestion => 'Pregunta';

  @override
  String get tagRemember => 'Recordar';

  @override
  String get tagTodo => 'Tarea';

  @override
  String get touchDrawAlways => 'Siempre';

  @override
  String get touchDrawAuto => 'Auto (manda el lápiz)';

  @override
  String get touchDrawNever => 'Nunca';

  @override
  String updateAvailable(String version) {
    return 'Openote $version ya está disponible';
  }

  @override
  String updateYouHave(String version) {
    return 'Tienes la $version.';
  }

  @override
  String get updateDownloading => 'Descargando…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Descargando… $percent %';
  }

  @override
  String get updateSavedClosing =>
      'Tus notas están guardadas. Openote se cerrará, se actualizará y volverá a abrirse.';

  @override
  String get updateWillRestart =>
      'Primero se guardarán tus notas. Openote se cerrará mientras se instala la actualización y volverá a abrirse solo.';

  @override
  String get updateInstallYourself =>
      'Tendrás que descargarla e instalarla tú mismo.';

  @override
  String get updateNotNow => 'Ahora no';

  @override
  String get updateNow => 'Actualizar ahora';

  @override
  String get updateDownload => 'Descargar';

  @override
  String get settingsGrammarCheck => 'Revisar la gramática';

  @override
  String get settingsAutoCorrect => 'Corregir erratas pequeñas al escribir';

  @override
  String get settingsAutoCapitalize => 'Poner mayúscula al empezar frases';

  @override
  String get settingsSpellLanguage => 'Idioma de la ortografía';

  @override
  String get settingsSpellLanguageSystem => 'Predeterminado del sistema';

  @override
  String get settingsSpellLanguageOther => 'Otro idioma (sin revisar)';

  @override
  String get settingsEnglishAU => 'Inglés (Australia)';

  @override
  String get settingsEnglishGB => 'Inglés (Reino Unido)';

  @override
  String get settingsEnglishUS => 'Inglés (Estados Unidos)';

  @override
  String get settingsEnglishCA => 'Inglés (Canadá)';

  @override
  String get settingsEnglishIN => 'Inglés (India)';

  @override
  String get settingsWritingEnglishOnly =>
      'La gramática, la corrección de erratas y las mayúsculas solo funcionan en inglés por ahora. En otros idiomas permanecen desactivadas.';

  @override
  String get barTabWrite => 'Escribir';

  @override
  String get insertNotYet => 'Aún no';

  @override
  String get barHideKeyboard => 'Ocultar el teclado';

  @override
  String get pageSheetBlank => 'Vacía';

  @override
  String get pageSheetGrid => 'Cuadrícula';

  @override
  String get pageSheetDots => 'Puntos';

  @override
  String get pageSheetRuled => 'Rayada';

  @override
  String get pageSheetPaper => 'Papel';

  @override
  String get pageSheetCanvas => 'Lienzo';

  @override
  String get pageSheetSnap => 'Ajustar';

  @override
  String get pageSheetFit => 'Encajar';

  @override
  String get navOpening => 'Abriendo este cuaderno…';

  @override
  String get openFolderTitle => 'Abrir un cuaderno desde una carpeta';

  @override
  String get openFolderBody =>
      'Elige la carpeta donde guardas tus cuadernos, por ejemplo una de Google Drive, OneDrive o Dropbox. Openote busca cuadernos dentro de ella.';

  @override
  String get openFolderChoose => 'Elegir una carpeta…';

  @override
  String get openFolderNone =>
      'No se encontró ningún cuaderno ahí. Elige la carpeta que contiene tus cuadernos, o la carpeta propia de un cuaderno (su nombre termina en .onotebook).';

  @override
  String get openFolderLooking => 'Buscando cuadernos…';

  @override
  String get openFolderAndroidHint =>
      'Elige la carpeta donde están tus cuadernos. En Google Drive suele ser la que se llama «Openote». Luego toca «Usar esta carpeta».';

  @override
  String get openFolderFound => 'Cuadernos encontrados';

  @override
  String protectLockTitle(String title) {
    return 'Bloquear «$title»';
  }

  @override
  String protectLockedTitle(String title) {
    return '«$title» está bloqueada';
  }

  @override
  String get protectBetaHeadline =>
      'Beta: esto oculta la página en Openote, pero todavía no la cifra.';

  @override
  String get protectBetaBody =>
      'Por ahora, cualquiera que tenga el archivo de tu cuaderno puede leer la página, y un código olvidado no se puede recuperar. Está previsto añadir un cifrado real.';

  @override
  String get protectPasscode => 'Código';

  @override
  String get protectPasscodeAgain => 'Repite el código';

  @override
  String get protectAskAgain => 'Volver a pedirlo…';

  @override
  String get protectLock => 'Bloquear';

  @override
  String get protectEnterPasscode => 'Escribe un código.';

  @override
  String get protectMismatch => 'Los dos códigos no coinciden.';

  @override
  String get protectWrong => 'Ese no es el código.';

  @override
  String get protectPolicyAlways => 'Cada vez que se abra';

  @override
  String get protectPolicyTenMinutes => 'Durante 10 minutos';

  @override
  String get protectPolicyOneHour => 'Durante 1 hora';

  @override
  String get protectPolicySession => 'Hasta cerrar Openote';

  @override
  String get linkTitleNew => 'Enlace';

  @override
  String get linkTitleEdit => 'Editar enlace';

  @override
  String get linkTextToShow => 'Texto que se muestra';

  @override
  String get linkNothingSelected =>
      'No había nada seleccionado para convertir en enlace';

  @override
  String get linkAddress => 'Dirección';

  @override
  String get linkOrPage => 'o enlazar a una página';

  @override
  String get linkRemove => 'Quitar enlace';

  @override
  String get linkUpdate => 'Actualizar';

  @override
  String get linkInsert => 'Insertar';

  @override
  String get linkNeedWords => 'Escribe el texto que mostrará el enlace.';

  @override
  String get linkBadAddress =>
      'Eso no parece una dirección que Openote pueda abrir. Prueba algo como https://example.com';

  @override
  String get linkNoCaret => 'Pon primero el cursor donde debe ir el enlace.';

  @override
  String get linkOneLine =>
      'Un enlace tiene que estar en una sola línea. Selecciona palabras de una sola línea.';

  @override
  String get linkOnObject =>
      'Una imagen, una tabla o una tarjeta no pueden llevar un enlace. Ponlo en unas palabras.';

  @override
  String get linkOnMaths =>
      'Una ecuación no puede llevar un enlace: los corchetes son parte de las matemáticas.';

  @override
  String get linkBrackets =>
      'El texto de un enlace no puede tener corchetes. Selecciona algo sin ellos.';

  @override
  String get linkNested =>
      'Ese texto ya tiene formato o un enlace. Selecciona palabras sin formato, o haz clic dentro del enlace para editarlo.';

  @override
  String get alertsTitle => 'Avisos antes de clase';

  @override
  String get alertsIntro =>
      'Openote puede avisarte antes de que empiece algo de tu horario. Deduce qué es cada evento por su nombre, así que elige los tipos por los que de verdad quieres que te interrumpa.';

  @override
  String get alertsPreset => 'Avisarme 10 minutos antes de clase';

  @override
  String get alertsAllOff => 'Desactivar todos';

  @override
  String get alertsWhileRunning =>
      'Los avisos aparecen dentro de Openote, así que solo te llegan mientras está abierto. Lo que te hayas perdido te espera en este panel la próxima vez que lo abras.';

  @override
  String get alertsAtStart => 'Al empezar';

  @override
  String alertsMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get eventKindLecture => 'Clase teórica';

  @override
  String get eventKindTutorial => 'Tutoría';

  @override
  String get eventKindLab => 'Laboratorio / prácticas';

  @override
  String get eventKindWorkshop => 'Taller';

  @override
  String get eventKindSeminar => 'Seminario';

  @override
  String get eventKindExam => 'Examen / prueba';

  @override
  String get eventKindMeeting => 'Reunión';

  @override
  String get eventKindOther => 'Todo lo demás';

  @override
  String get commonOk => 'Aceptar';

  @override
  String get saveProblemNotAddedShort => 'No se ha añadido';

  @override
  String get saveProblemNotAdded =>
      'Openote no pudo guardar la imagen o el archivo que acabas de añadir, así que no está en tu cuaderno.\n\nComprueba que el disco no esté lleno y que la carpeta del cuaderno no sea de solo lectura, y vuelve a pegarlo o arrastrarlo.';

  @override
  String get saveProblemNotOnDriveShort => 'Aún no está en Drive';

  @override
  String get saveProblemNotOnDrive =>
      'Tus cambios están guardados en este teléfono. No se han podido enviar a la carpeta de Drive ahora mismo (no hay conexión o no se puede acceder a la carpeta) y se enviarán en cuanto se pueda.';

  @override
  String get saveProblemNotRecordedShort => 'Guardado, pero no registrado';

  @override
  String get saveProblemNotRecorded =>
      'Openote guardó tus notas en este ordenador, pero no pudo añadir el cambio al historial de este cuaderno.\n\nEl historial es la copia que leen tus otros dispositivos, tus copias de seguridad y tus carpetas compartidas, así que pueden quedarse atrás hasta que esto vuelva a funcionar. No se ha perdido nada de lo que has escrito.\n\nComprueba que el disco no esté lleno, que la carpeta del cuaderno no sea de solo lectura y que una app en la nube como OneDrive o Google Drive haya terminado con ella. Openote lo vuelve a intentar cada vez que guardas.';

  @override
  String get saveProblemPageShort => 'No guardado: cambios en memoria';

  @override
  String get saveProblemPage =>
      'Openote no pudo guardar esta página en tu ordenador.\n\nTus cambios siguen en pantalla y Openote lo volverá a intentar la próxima vez que escribas o cierres la ventana. La primera vez que cierres la ventana, se quedará abierta para que puedas solucionarlo; si la vuelves a cerrar, Openote se cierra sin estos cambios.\n\nComprueba que el disco no esté lleno y que el cuaderno no esté abierto en otro programa.';

  @override
  String get saveProblemPicturesShort => 'Puede que falten imágenes';

  @override
  String saveProblemPictures(int count) {
    return 'Openote guarda una segunda copia de cada imagen y dibujo dentro de la propia carpeta de este cuaderno, para que tus otros dispositivos y tus copias de seguridad también puedan mostrarlos.\n\nPara $count de ellos, Openote no encontró datos válidos en ningún sitio de este ordenador: ni en esa segunda copia ni en el archivo de trabajo del cuaderno. Hasta que aparezcan (desde otro dispositivo, una copia de seguridad o añadiendo la imagen de nuevo), se verán en blanco allí donde se usen, en este ordenador y en cualquier otro.\n\nComprueba que el disco no esté lleno y que la carpeta no sea de solo lectura, y luego cierra el cuaderno y vuelve a abrirlo. Openote lo vuelve a intentar cada vez que lo abres.';
  }

  @override
  String get saveProblemListLockedShort =>
      'Tu lista de cuadernos está bloqueada';

  @override
  String get saveProblemNewerShort => 'Solo lectura: de un Openote más nuevo';

  @override
  String get saveProblemNewer =>
      'Este cuaderno tiene cambios hechos con una versión más nueva de Openote, y esta versión no puede leerlos.\n\nPor eso Openote te muestra el cuaderno sin modificarlo. Todo lo que contiene está a salvo y nada de lo que hagas aquí puede dañarlo, pero lo que escribas ahora no se guardará.\n\nSi actualizas Openote a la última versión, podrás volver a editarlo.';

  @override
  String get saveProblemListShort => 'No se guardó la lista de cuadernos';

  @override
  String get saveProblemList =>
      'Openote no pudo guardar tu lista de cuadernos ni la configuración. La ventana seguirá abierta la primera vez que la cierres. Comprueba el disco y vuelve a intentarlo, o cierra la ventana otra vez para salir de todos modos.';

  @override
  String get mcpTitle => 'Acceso de IA';

  @override
  String get mcpIntro =>
      'Deja que un asistente de IA —como Claude— lea tus notas, busque en ellas, te haga preguntas y cree tarjetas de estudio a partir de ellas. Solo funciona mientras Openote está abierto, solo en este ordenador, y todo lo que añade es una edición normal: Ctrl+Z la deshace.';

  @override
  String get mcpPasscodeNote =>
      'Todo lo que tiene código sigue siendo privado: un asistente de IA no puede verlo ni cambiarlo, ni siquiera mientras lo tienes desbloqueado. Un código bloquea Openote, no el archivo en sí, así que una herramienta de IA que pueda abrir archivos en tu ordenador aún podría leerlo.';

  @override
  String mcpCouldNotStart(String error) {
    return 'No se pudo iniciar: $error';
  }

  @override
  String mcpReady(String lastUsed) {
    return 'Listo. $lastUsed';
  }

  @override
  String get mcpNeverUsed =>
      'Ningún asistente de IA lo ha usado desde que se abrió Openote.';

  @override
  String get mcpUsedJustNow => 'Usado por un asistente de IA hace un momento.';

  @override
  String mcpUsedMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Usado por un asistente de IA hace $minutes minutos.',
      one: 'Usado por un asistente de IA hace 1 minuto.',
    );
    return '$_temp0';
  }

  @override
  String mcpUsedHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'Usado por un asistente de IA hace $hours horas.',
      one: 'Usado por un asistente de IA hace 1 hora.',
    );
    return '$_temp0';
  }

  @override
  String get mcpUsedOverADay =>
      'Usado por un asistente de IA hace más de un día.';

  @override
  String get mcpRestartHint =>
      'Un asistente de IA busca Openote al iniciarse. Si el tuyo ya estaba abierto, reinícialo.';

  @override
  String mcpClientIsSetUp(String name) {
    return '$name: configurado';
  }

  @override
  String mcpSetUpClient(String name) {
    return 'Configurar $name';
  }

  @override
  String get mcpClaudeApp => 'App de Claude';

  @override
  String get mcpChatGptApp => 'App de ChatGPT';

  @override
  String get mcpWebsiteNote =>
      'El sitio web de ChatGPT no se puede conectar: sus conectores se ejecutan en los servidores de OpenAI, que no pueden ver tu ordenador. El botón de arriba es para la app de escritorio, que lee su configuración de este ordenador. La app de Gemini está en el mismo caso que el sitio web; su CLI sí tiene botón.';

  @override
  String get mcpCopyAddress => 'Copiar dirección';

  @override
  String get mcpCopyConfiguration => 'Copiar configuración';

  @override
  String get mcpOtherTools => 'Otras herramientas de IA (avanzado)';

  @override
  String get mcpOtherToolsBody =>
      'Openote habla MCP, el estándar que usan las herramientas de IA para conectarse a las apps. Cualquier herramienta compatible con MCP puede usarlo; la clave que contiene es una contraseña, así que pégala solo en herramientas de confianza.';

  @override
  String mcpListening(String port) {
    return 'Escuchando en el puerto $port, solo en este ordenador.';
  }

  @override
  String get mcpNotListening => 'No está escuchando.';

  @override
  String get mcpCopyConfig => 'Copiar config';

  @override
  String get mcpCliIntro =>
      'O, para herramientas de línea de comandos, ejecuta una vez:';

  @override
  String get mcpCopyCommand => 'Copiar comando';

  @override
  String get mcpCopied =>
      'Copiado. La clave que contiene es una contraseña: pégala solo en tus propias herramientas.';

  @override
  String get mcpChatGptUnreadable =>
      'No se pudo leer el archivo de configuración de ChatGPT, así que Openote no lo tocó. Los datos de conexión de Avanzado siguen funcionando.';

  @override
  String get mcpChatGptUnparsable =>
      'El archivo de configuración de ChatGPT tiene algo que Openote no entiende, así que no lo tocó. Copia la configuración de Avanzado y añádela a mano.';

  @override
  String mcpSaveFailed(String error) {
    return 'No se pudo guardar la conexión: $error';
  }

  @override
  String get mcpChatGptSetUp =>
      'Configurado. Reinicia la app de escritorio de ChatGPT y Openote aparecerá entre sus servidores MCP. El sitio web no puede usarlo: solo una app en este ordenador puede ver Openote.';

  @override
  String get mcpChatGptSavedOnly =>
      'Guardado. Openote aparecerá en cuanto la app de escritorio de ChatGPT o la CLI de Codex estén instaladas en este ordenador.';

  @override
  String mcpClientUnreadable(String name) {
    return 'No se pudo leer el archivo de configuración de $name, así que Openote no lo tocó. Los datos de conexión de Avanzado siguen funcionando en cualquier herramienta compatible con MCP.';
  }

  @override
  String mcpClientSetUp(String name) {
    return 'Configurado. Si $name ya está abierto, reinícialo: busca Openote al iniciarse. Luego pregúntale por tus notas; prueba con «hazme preguntas sobre lo que escribí esta semana».';
  }

  @override
  String mcpClientNotInstalled(String name) {
    return 'Openote está listo, pero $name no parece estar instalado en este ordenador todavía. En cuanto lo esté, la conexión funcionará sin más.';
  }

  @override
  String get timeNow => 'ahora';

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
    return '$n d';
  }

  @override
  String timeMonthsShort(String n) {
    return '$n mes.';
  }

  @override
  String timeYearsShort(String n) {
    return '$n a';
  }

  @override
  String get countdownToday => 'hoy';

  @override
  String get countdownTomorrow => 'mañana';

  @override
  String get countdownYesterday => 'ayer';

  @override
  String countdownDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días',
      one: '1 día',
    );
    return '$_temp0';
  }

  @override
  String countdownDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count días',
      one: 'hace 1 día',
    );
    return '$_temp0';
  }

  @override
  String get countdownPassed => 'ya pasó';

  @override
  String get monthsShort => 'ene,feb,mar,abr,may,jun,jul,ago,sept,oct,nov,dic';

  @override
  String dateDayMonth(String day, String month) {
    return '$day $month';
  }

  @override
  String dateDayMonthYear(String day, String month, String year) {
    return '$day $month $year';
  }

  @override
  String get gradeAgain => 'Otra vez';

  @override
  String get gradeHard => 'Difícil';

  @override
  String get gradeGood => 'Bien';

  @override
  String get gradeEasy => 'Fácil';

  @override
  String get deckThisPage => 'Esta página';

  @override
  String get deckThisSection => 'Esta sección';

  @override
  String get deckWholeNotebook => 'Todo el cuaderno';

  @override
  String get studyAnkiText => 'Texto de Anki';

  @override
  String studyExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count tarjetas exportadas: impórtalas en Anki con Archivo ▸ Importar',
      one: '1 tarjeta exportada: impórtala en Anki con Archivo ▸ Importar',
    );
    return '$_temp0';
  }

  @override
  String get studyForgetTitle => '¿Olvidar la programación de este mazo?';

  @override
  String studyForgetBody(String scope) {
    String _temp0 = intl.Intl.selectLogic(
      scope,
      {
        'page':
            'Todas las tarjetas de esta página vuelven a ser nuevas. Tus notas no se tocan.',
        'section':
            'Todas las tarjetas de esta sección vuelven a ser nuevas. Tus notas no se tocan.',
        'other':
            'Todas las tarjetas del cuaderno entero vuelven a ser nuevas. Tus notas no se tocan.',
      },
    );
    return '$_temp0';
  }

  @override
  String get studyForget => 'Olvidar';

  @override
  String studyResetCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tarjetas restablecidas',
      one: '1 tarjeta restablecida',
    );
    return '$_temp0';
  }

  @override
  String get studyEnd => 'Terminar';

  @override
  String get studyDeckActions => 'Acciones del mazo';

  @override
  String get studyExportAnki => 'Exportar a Anki…';

  @override
  String get studySetExam => 'Fijar fecha de examen…';

  @override
  String get studyChangeExam => 'Cambiar fecha de examen…';

  @override
  String get studyRemoveExam => 'Quitar fecha de examen';

  @override
  String get studyForgetSchedule => 'Olvidar programación…';

  @override
  String get studyDue => 'pendientes';

  @override
  String studyCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tarjetas',
      one: '1 tarjeta',
    );
    return '$_temp0';
  }

  @override
  String studyNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuevas',
      one: '1 nueva',
    );
    return '$_temp0';
  }

  @override
  String studyReview(String count) {
    return 'Repasar $count';
  }

  @override
  String get studyAllCaughtUp => 'Todo al día.';

  @override
  String studyAllCaughtUpNext(String delay) {
    return 'Todo al día: la próxima tarjeta, en $delay.';
  }

  @override
  String studyPracticeAll(String count) {
    return 'Practicar las $count';
  }

  @override
  String get studyPracticeNote => 'Practicar no cambia tu programación.';

  @override
  String get studyThisSection => 'Estudiar esta sección';

  @override
  String studyExamWhen(String when) {
    return 'Examen $when';
  }

  @override
  String get studyKeepSchedule => 'Estas tarjetas mantienen su programación.';

  @override
  String get studyExamGoodLuck => 'Todas las tarjetas vistas. ¡Suerte!';

  @override
  String studyExamUnseenToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count que aún no has visto.',
    );
    return '$_temp0';
  }

  @override
  String studyAllSeen(String count) {
    return 'Las $count vistas: sigue con los repasos.';
  }

  @override
  String studyToLearn(String count, String perDay) {
    return '$count por aprender · $perDay al día las cubren a tiempo';
  }

  @override
  String get studyExamToday => 'Examen hoy';

  @override
  String get studySeen => 'VISTAS';

  @override
  String studyNOfM(String n, String total) {
    return '$n de $total';
  }

  @override
  String get studyAddExam => 'Añadir fecha de examen';

  @override
  String studyReviewedToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count repasadas hoy',
      one: '1 repasada hoy',
    );
    return '$_temp0';
  }

  @override
  String get studyNothingToday => 'Nada repasado hoy';

  @override
  String studyStreakAtRisk(String days) {
    return 'Racha de $days días: mantenla hoy';
  }

  @override
  String studyStreak(String days, String today) {
    return 'Racha de $days días · $today hoy';
  }

  @override
  String studyActivityTip(String days) {
    return 'Repasos de los últimos $days días';
  }

  @override
  String get studyDeck => 'Mazo';

  @override
  String get studyNoCards => 'Aún no hay tarjetas aquí.';

  @override
  String get studyRecipeQuestion =>
      'Etiqueta una pregunta. La línea sangrada de debajo es la respuesta.';

  @override
  String get studyRecipeDefinition =>
      'Etiqueta una definición escrita como «término — significado».';

  @override
  String get studyRecipeCloze =>
      'Resalta parte de una línea etiquetada para ocultarla en su lugar.';

  @override
  String get studyCardsAreNotes =>
      'Las tarjetas son una vista de tus notas, así que editar la nota edita la tarjeta: no hay nada aparte que mantener.';

  @override
  String studyReviewedCards(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tarjetas repasadas',
      one: '1 tarjeta repasada',
    );
    return '$_temp0';
  }

  @override
  String studyStillDue(String count) {
    return '$count aún pendientes en este mazo.';
  }

  @override
  String get studyNothingElseDue => 'No queda nada pendiente.';

  @override
  String studyNextCardIn(String delay) {
    return 'Próxima tarjeta en $delay.';
  }

  @override
  String studyNeedAnotherLook(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count necesitan otro vistazo.',
      one: '1 necesita otro vistazo.',
    );
    return '$_temp0';
  }

  @override
  String get studyExamTodayDot => 'Examen hoy.';

  @override
  String studyUntilExam(String countdown) {
    return '$countdown para el examen.';
  }

  @override
  String studyUntilExamUnseen(String countdown, String count) {
    return '$countdown para el examen · $count aún sin ver.';
  }

  @override
  String studyReviewAgain(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Repasar esas $count otra vez',
      one: 'Repasar esa otra vez',
    );
    return '$_temp0';
  }

  @override
  String studyKeepGoing(String count) {
    return 'Seguir: $count pendientes';
  }

  @override
  String get studyPracticeBadge => 'PRÁCTICA';

  @override
  String get studyShowAnswer => 'Mostrar respuesta';

  @override
  String get studyOpenNote => 'Abrir la nota';

  @override
  String get studyAnswerHidden => 'Respuesta oculta';

  @override
  String get studyAnswer => 'RESPUESTA';

  @override
  String get studyFillBlank => 'RELLENA EL HUECO';

  @override
  String studyExamMenu(String when, String countdown) {
    return 'Examen $when · $countdown…';
  }

  @override
  String get examDateTitle => 'Fecha del examen';

  @override
  String examTitleFor(String section) {
    return 'Examen: $section';
  }

  @override
  String examRemoved(String date) {
    return 'Fecha de examen quitada ($date). Tus tarjetas no cambian.';
  }

  @override
  String get examUseDate => 'Usar esta fecha';

  @override
  String get examWhatTime => '¿A qué hora empieza?';

  @override
  String get examDate => 'Fecha';

  @override
  String get examAddTime => 'Añadir hora de inicio';

  @override
  String get examStarts => 'Empieza';

  @override
  String get examNoTime => 'Sin hora concreta';

  @override
  String get examTimeOptional =>
      'La cuenta atrás y el plan de repaso funcionan en días enteros, así que la hora es opcional.';

  @override
  String get examShownOnDay =>
      'Se muestra ese día. La cuenta atrás sigue funcionando en días enteros.';

  @override
  String get examSet => 'Fijar';

  @override
  String get weekdaysShort => 'lun,mar,mié,jue,vie,sáb,dom';

  @override
  String get weekdayInitials => 'L,M,X,J,V,S,D';

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
      other: 'dentro de $count días',
      one: 'dentro de 1 día',
    );
    return '$_temp0';
  }

  @override
  String get agendaOverdue => 'Atrasado';

  @override
  String get agendaToday => 'Hoy';

  @override
  String get agendaTomorrow => 'Mañana';

  @override
  String get agendaThisWeek => 'Esta semana';

  @override
  String get agendaLater => 'Más adelante';

  @override
  String get agendaDone => 'Hecho';

  @override
  String get planShowList => 'Mostrar la lista';

  @override
  String get planShowMonth => 'Mostrar el mes';

  @override
  String planRemindersAway(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordatorios mientras no estabas',
      one: '1 recordatorio mientras no estabas',
    );
    return '$_temp0';
  }

  @override
  String planRemindersHeading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordatorios',
      one: 'Un recordatorio',
    );
    return '$_temp0';
  }

  @override
  String get planDoneAll => 'Hecho con todos';

  @override
  String planTimetableError(String error) {
    return 'Horario: $error. Se muestra la última copia.';
  }

  @override
  String planCalendarNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notas sobre este calendario',
      one: '1 nota sobre este calendario',
    );
    return '$_temp0';
  }

  @override
  String get planShowAll => 'Mostrar todo';

  @override
  String get planNothingOnDay => 'Nada este día.';

  @override
  String get planDoneReminder => 'Hecho con este recordatorio';

  @override
  String get planEmptyHeadline => 'Aún no hay nada con fecha.';

  @override
  String get planEmptyBody =>
      'Todo lo que tiene fecha aparece aquí: fechas de examen, tareas con plazo, recordatorios y tu horario si te suscribes a uno.';

  @override
  String get planSetExam => 'Fijar una fecha de examen';

  @override
  String get planAddReminder => 'Añadir un recordatorio';

  @override
  String get planSubscribe => 'Suscribirse a un horario';

  @override
  String get planAddDate => 'Añadir una fecha';

  @override
  String get planAddDateMenu => 'Añadir una fecha…';

  @override
  String get planMenuReminder => 'Recordatorio…';

  @override
  String get planMenuExam => 'Fecha de examen…';

  @override
  String get planMenuTask => 'Plazo en esta página…';

  @override
  String get planMenuSubscribe => 'Suscribirse a un horario…';

  @override
  String get planSettings => 'Ajustes del planificador';

  @override
  String get planChangeTimetable => 'Cambiar el horario…';

  @override
  String get planAlerts => 'Avisos antes de clase…';

  @override
  String get planRemoveTimetable => 'Quitar el horario';

  @override
  String get planCalendarNotesMenu => 'Notas sobre este calendario…';

  @override
  String get planTimetable => 'Horario';

  @override
  String planRefreshError(String name, String error) {
    return '$name: $error. Actualizar';
  }

  @override
  String planRefresh(String name) {
    return 'Actualizar $name';
  }

  @override
  String planRefreshUpdated(String name, String when) {
    return 'Actualizar $name (actualizado $when)';
  }

  @override
  String get planGoToNote => 'Ir a la nota';

  @override
  String get planMoveToday => 'Pasar a hoy';

  @override
  String get planMoveTomorrow => 'Pasar a mañana';

  @override
  String get planMoveWeek => 'Retrasar una semana';

  @override
  String get planPickDateMenu => 'Elegir una fecha…';

  @override
  String get planDeleteReminder => 'Eliminar recordatorio';

  @override
  String get planClearDate => 'Quitar la fecha';

  @override
  String get planReadOnly => 'De tu calendario: solo lectura';

  @override
  String get planWhichSection => '¿Qué sección?';

  @override
  String get planTagFirst =>
      'Primero etiqueta una línea de esta página; después podrá tener un plazo.';

  @override
  String get planWhichLine => '¿Qué línea recibe el plazo?';

  @override
  String get planEmptyLine => '(línea vacía)';

  @override
  String get planDueDate => 'Plazo';

  @override
  String planReminderSet(String time, String when) {
    return 'Recordatorio para las $time $when. Openote te avisará si está abierto, y te lo dirá si no lo estaba.';
  }

  @override
  String get planTimetableAdded =>
      'Horario añadido. Se actualiza al abrir Openote.';

  @override
  String planCouldNotLoad(String error) {
    return 'No se pudo cargar ese calendario: $error';
  }

  @override
  String get planAboutCalendar => 'Sobre este calendario';

  @override
  String get planAboutCalendarBody =>
      'Openote lee las partes habituales de un archivo de calendario. Lo que no pudo leer, o no exactamente, aparece aquí en lugar de descartarse sin avisar. Las horas se muestran en la zona horaria de tu ordenador.';

  @override
  String get planPickDate => 'Elegir una fecha';

  @override
  String get planSnooze => 'Posponer';

  @override
  String get planSnooze10 => '10 minutos';

  @override
  String get planSnoozeHour => 'Una hora';

  @override
  String get planSnoozeEvening => 'Esta tarde (3 horas)';

  @override
  String get planSnoozeTomorrow => 'Mañana';

  @override
  String get planRemindMe => 'Recuérdamelo';

  @override
  String get planReminderHint => 'Volver a la demostración del 2.7';

  @override
  String get planIn30 => 'En 30 min';

  @override
  String get planInHour => 'En una hora';

  @override
  String get planThisEvening => 'Esta tarde';

  @override
  String get planTomorrowMorning => 'Mañana por la mañana';

  @override
  String get planNudgeNote =>
      'Openote te avisa mientras está abierto. Si estaba cerrado a esa hora, el recordatorio te espera la próxima vez que lo abras.';

  @override
  String get planSubscribeTitle => 'Suscribirse a un calendario';

  @override
  String get planSubscribeBody =>
      'Pega la dirección del calendario de tu horario universitario, Google Calendar, Outlook o Calendario de Apple. Suele terminar en .ics, y es lo único que Openote ve: sin inicio de sesión ni acceso a tu cuenta.';

  @override
  String get planReadOnlyNote =>
      'Solo lectura, en un sentido: Openote muestra tu horario junto a tus notas y nunca escribe nada en él.';

  @override
  String get planSubscribeButton => 'Suscribirse';

  @override
  String get planNow => 'Ahora';

  @override
  String get planNext => 'Luego';

  @override
  String get planThen => 'Después';

  @override
  String get planUntitledEvent => '(evento sin título)';

  @override
  String planJoin(String provider) {
    return 'Unirse a $provider';
  }

  @override
  String planInMinutes(String minutes) {
    return 'en $minutes min';
  }

  @override
  String planAtTime(String time) {
    return 'a las $time';
  }

  @override
  String planUntil(String time) {
    return 'hasta las $time';
  }

  @override
  String planCouldNotOpenLink(String url) {
    return 'No se pudo abrir ese enlace: $url';
  }

  @override
  String get planPrevMonth => 'Mes anterior';

  @override
  String get planNextMonth => 'Mes siguiente';

  @override
  String alertWaiting(String count) {
    return '$count en espera';
  }

  @override
  String alertWaitingMore(String count, String hidden) {
    return '$count en espera · $hidden más abajo';
  }

  @override
  String alertWhileAway(String count) {
    return '$count mientras no estabas';
  }

  @override
  String get alertDismissAll => 'Descartar todo';

  @override
  String get alertDismiss => 'Descartar';

  @override
  String get alertStartingNow => 'empieza ahora';

  @override
  String alertInMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'en $count minutos',
      one: 'en 1 minuto',
    );
    return '$_temp0';
  }

  @override
  String alertWasDue(String time) {
    return 'Era para las $time';
  }
}
