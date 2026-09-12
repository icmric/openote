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
  final before = TableData.from(b.content);
  final id = (atomId ?? newId)();
  final atom = InlineAtom(
    id: id,
    type: 'table',
    content: {...before.toContent(), 'madeIn': madeIn},
  );

  final content = <String, dynamic>{
    for (final e in b.content.entries)
      if (e.key != 'cells' && e.key != 'colWidths' && e.key != 'text')
        e.key: e.value,
  };
  final kept = b.content['text'];
  final ref = atom.reference(before.referenceAlt);
  content['text'] =
      kept is String && kept.isNotEmpty ? '$kept\n$ref' : ref;
  InlineAtom.putIn(content, atom);

  // **The proof.** Everything above is arithmetic on maps; this is the part
  // that decides whether the arithmetic was right, and it reads the table
  // back through the very code the editor and every exporter will use.
  final back = tablesIn(content);
  if (back.length != 1 || !back.single.sameAs(before)) return null;

  final j = b.toJson();
  j['type'] = 'text';
  j['content'] = content;
  final out = Block.fromJson(j);
  if (out.id != b.id || out.type != BlockType.text) return null;
  return out..updatedAt = nowMs();
}
