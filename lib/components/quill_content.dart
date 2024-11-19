import 'package:flutter/foundation.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';

QuillEditor createQuillEditor(QuillController? controller) {
  controller ??= QuillController.basic();
  return QuillEditor.basic(
    controller: controller,
    configurations: QuillEditorConfigurations(
      embedBuilders: kIsWeb ? FlutterQuillEmbeds.editorWebBuilders() : FlutterQuillEmbeds.editorBuilders(),
    ),
  );
}

QuillSimpleToolbar createQuillToolbar(QuillController? controller) {
  controller ??= QuillController.basic();
  return QuillSimpleToolbar(
    configurations: QuillSimpleToolbarConfigurations(
      embedButtons: FlutterQuillEmbeds.toolbarButtons(),
    ),
    controller: controller,
  );
}
