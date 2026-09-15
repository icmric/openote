import 'dart:convert';

import '../core/ids.dart';
import 'inline_atom.dart';
import 'models.dart';

/// **Turning a table block into a paragraph that carries the table.**
///
/// The owner's decision, and the reasoning with it: *"Assuming the conversion
/// is bulletproof and other than the incompatability is not noticable to the
/// user if its the new or old, lets just automatically update them all on open
/// … so that we dont end up with a staggered mess of mix and match table
/// types."*
///
/// Which puts the whole weight on "bulletproof", so this function is written
/// to be refusable rather than clever:
///
/// * **It proves the result before returning it.** The table is read back out
///   of the new block and compared cell for cell against the one that went in
///   ([TableData.sameAs]); anything less than identical returns null and the
///   caller leaves the block exactly as it was. A block that cannot be
///   converted is not a broken block — it is a table that goes on working as
///   a table, which is why refusing is a real answer.
/// * **It keeps the block's identity.** The same id, position, size, z-order,
///   frame, access and unknown fields come through, because the new block is
///   built from the old one's own JSON with two keys changed. Selection, tags,
///   links and the op log all key on that id; a new id would be a delete and
///   an insert to every one of them.
/// * **It loses nothing it did not understand.** Every key the table block's
///   content carried that is not the table itself is carried over, and a
///   `text` key (which a table block should never have, but might, after a
///   hand edit or a foreign writer) is kept ABOVE the table rather than
///   overwritten.
///
/// [madeIn] is stamped into the payload so that a build too old to draw an
/// atom of some future type can say which version made it — see
/// `inline_atom_view.dart`. It is information for a stranger, not state.
Block? tableBlockAsText(
  Block b, {
  required String madeIn,
  String Function()? atomId,
}) {
  if (b.type != BlockType.table) return null;
  // **Refuse a shape this cannot carry across.** `TableData.from` reads a
  // `cells` that is not a list as "no table", and drawing it as an empty 2x2
  // grid is what the editor has always done — but the original value is still
  // IN the file, and converting would write the empty grid over it. Whatever
  // that value is, it is somebody's, and a converter that runs on its own
  // while nobody is watching does not get to decide it was worthless.
  final cells = b.content['cells'];
  final widths = b.content['colWidths'];
  if ((cells != null && cells is! List) ||
      (widths != null && widths is! List)) {
    return null;
  }
  final before = TableData.from(b.content);
  final id = (atomId ?? newId)();
  // **Carried across verbatim, not re-serialised through `TableData`.**
  //
  // `TableData.from` NORMALISES — it stringifies every cell and pads every
  // short row — because that is what the editor has always done when it DRAWS
  // a table. Writing the normalised form back is a different thing entirely:
  // it rewrites somebody's file, in a job that runs on its own while they are
  // not looking. Measured on the previous version: `22.99` became `"22.99"`,
  // `['d']` became `['d','','']`, and a `null` cell became `''`.
  //
  // None of that loses a value you could see, which is exactly why it went
  // unnoticed — and why the proof below could not catch it, since both sides
  // of that comparison normalise too. Taking the original values means the
  // conversion moves the table and changes nothing about it. The first time
  // somebody EDITS a cell the normalised form is written, which is right: an
  // edit is a person changing their data, not a migration doing it for them.
  //
  // Deep-copied so the new block shares no list with the old one.
  final carried = jsonDecode(jsonEncode(<String, dynamic>{
    if (b.content.containsKey('cells')) 'cells': b.content['cells'],
    if (b.content.containsKey('colWidths')) 'colWidths': b.content['colWidths'],
  })) as Map<String, dynamic>;
  final atom = InlineAtom(
    id: id,
    type: 'table',
    content: {...carried, 'madeIn': madeIn},
  );

  final content = <String, dynamic>{
    for (final e in b.content.entries)
      if (e.key != 'cells' && e.key != 'colWidths' && e.key != 'text')
        e.key: e.value,
  };
  final kept = b.content['text'];
  final ref = atom.reference(TableData.referenceAlt);
  content['text'] =
      kept is String && kept.isNotEmpty ? '$kept\n$ref' : ref;
  InlineAtom.putIn(content, atom);

  // **The proof, in two halves.**
  //
  // The first reads the table back through the very code the editor and every
  // exporter will use, and compares it cell for cell with what went in. The
  // second compares the STORED form, which the first cannot see: both sides of
  // it run through `TableData.from`, so two different files that normalise to
  // the same grid compare equal. Only the second would have caught a
  // conversion that turned every number into a string.
  final back = tablesIn(content);
  if (back.length != 1 || !back.single.sameAs(before)) return null;
  final wrote = InlineAtom.allIn(content)[id]?.content;
  if (wrote == null) return null;
  for (final key in const ['cells', 'colWidths']) {
    if (jsonEncode(wrote[key]) != jsonEncode(b.content[key])) return null;
  }

  final j = b.toJson();
  j['type'] = 'text';
  j['content'] = content;
  final out = Block.fromJson(j);
  if (out.id != b.id || out.type != BlockType.text) return null;
  return out..updatedAt = nowMs();
}
