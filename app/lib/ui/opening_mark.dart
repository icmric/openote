/// **"This is on its way", not "this is empty".**
///
/// A notebook that is still being read in (its history replayed, what another
/// device wrote folded in) has an outline that is empty or short until that is
/// done. Showing the ordinary empty-state words there ("no sections") told
/// people the notebook was broken, and then the sections appeared. So wherever
/// an empty outline or page would be shown while a notebook is opening, this is
/// shown instead: a progress mark and one line.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';

class OpeningMark extends StatelessWidget {
  const OpeningMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6)),
          const SizedBox(height: 14),
          Text(L.of(context).navOpening,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.surfaces.textSecondary)),
        ]),
      ),
    );
  }
}
