import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:mosapad/components/resizable_image.dart';

class ResizableImageEmbedBuilder extends EmbedBuilder {
  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(
    BuildContext context,
    QuillController controller,
    Embed node,
    bool readOnly,
    bool inline,
    TextStyle textStyle,
  ) {
    final imageUrl = node.value.data;
    return ResizableImage(
      imageUrl: imageUrl,
      onResize: (newWidth, newHeight) {
        // Find the index of the image in the document
        final document = controller.document;
        final index = document.toDelta().toList().indexWhere(
              (element) => element.key == BlockEmbed.imageType && element.value == node.value,
            );

        if (index != -1) {
          // Update the image size in the document
          controller.formatText(
            index,
            1, // Length of the embed (1 for a single image)
            Attribute.width,
          );
          controller.formatText(
            index,
            1,
            Attribute.height,
          );
        }
      },
    );
  }
}