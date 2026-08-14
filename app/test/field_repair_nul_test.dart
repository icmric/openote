// The field-code repair must never shorten a note.
//
// It crosses to Rust as a NUL-TERMINATED C string, and imported OneNote prose
// really does carry interior NULs (the parser strips only a trailing one, so
// run-index offsets stay valid). One interior NUL therefore amputated
// everything after it — and the caller's only guard rejected "identical" and
// "empty", never "shorter", so the truncated PREFIX was written back over the
// block and saved. That is a page "cutting off mid sentence": not at import,
// but the first time it was opened, permanently, on every page holding a `$`
// or a Word field marker.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_ffi.dart';

void main() {
  group('the repair gate', () {
    test('fires on a bare dollar sign and on field markers', () {
      // Wide open by design — which is why the truncation reached ordinary
      // pages rather than only ones with real field codes.
      expect(textNeedsFieldRepair(r'costs $5'), isTrue);
      expect(textNeedsFieldRepair('﷟HYPERLINK "https://a.test"'), isTrue);
      expect(textNeedsFieldRepair(' field '), isTrue);
      expect(textNeedsFieldRepair('ordinary prose'), isFalse);
    });
  });

  group('a NUL in the text', () {
    test('does not stop the repair seeing the rest of the page', () {
      final core = OnoteCore.instance;
      if (core == null) {
        return markTestSkipped('onote_core not built for this test run');
      }
      // A realistic imported paragraph: prose, one NUL where a run ended,
      // and a `$` to arm the repair.
      const tail = 'and the rest of the sentence that must survive.';
      const text = 'The cost is \$5 \u0000 $tail';
      final fixed = core.repairFieldCodes(text);
      expect(fixed, contains(tail),
          reason: 'everything after the NUL was amputated and the truncated '
              'prefix written back over the note');
      expect(fixed.length, greaterThanOrEqualTo(text.length - 1),
          reason: 'only the NUL itself should go');
    });

    test('is removed rather than carried into the note', () {
      final core = OnoteCore.instance;
      if (core == null) {
        return markTestSkipped('onote_core not built for this test run');
      }
      final fixed = core.repairFieldCodes('a \u0000 b \$c');
      expect(fixed.contains('\u0000'), isFalse);
    });

    test('a long paragraph keeps every word after the NUL', () {
      final core = OnoteCore.instance;
      if (core == null) {
        return markTestSkipped('onote_core not built for this test run');
      }
      final words = List.generate(200, (i) => 'word$i').join(' ');
      final fixed = core.repairFieldCodes('start \$ \u0000 $words');
      expect(fixed, endsWith('word199'));
    });
  });
}
