/// **MathML into LaTeX**, for equations that arrive from OneNote.
///
/// ## Why this is parsed as XML and not as HTML
///
/// MathML is XML embedded in HTML, and the two disagree about the one thing
/// that matters here: **self-closing tags**. OneNote writes `<mrow />` freely,
/// and an HTML parser has no such concept — it reads that as an *opening*
/// `<mrow>` which then swallows everything after it until something closes it.
/// Measured on a real equation: `⌊ ⌋ Floor (Round down)` came through the HTML
/// tree as the single word `Floor`, because the empty `<mrow />` inside the
/// first fence had eaten the rest.
///
/// So the `<math>` elements are lifted out of the source and parsed with a
/// real XML parser before the HTML parser ever sees them. That also side-steps
/// every other foreign-content quirk in one go.
///
/// ## Why LaTeX
///
/// Because the app already has it. A `.one` import produces LaTeX (the Rust
/// core converts OneNote's OMML), the equation editor reads and writes LaTeX,
/// and `$…$` inside a paragraph is the app's own inline-maths syntax. An
/// equation that arrives from the internet is therefore the same object as one
/// typed by hand — editable, searchable, re-renderable — rather than a picture
/// of one.
///
/// ## What OneNote's MathML is actually like
///
/// Taken off the wire rather than from the specification:
///
///  * **One `<mi>` per letter.** `sin` arrives as three elements and `Floor`
///    as five, so anything that treats an `<mi>` as a whole symbol produces
///    one item per character — which is what the owner saw as *"text inside a
///    maths equation is being new lined after every char"*.
///  * **Invisible operators.** `<mo>&#8289;</mo>` (FUNCTION APPLICATION) and
///    its relatives carry no meaning to read and render as a missing glyph.
///  * **Mathematical italic letters.** Theta is `&#120579;`, which is
///    U+1D703 MATHEMATICAL ITALIC SMALL THETA — a character most fonts do not
///    have. The equation renderer italicises for itself, so these become
///    ordinary letters and LaTeX names.
///  * **`<mfenced>`**, which was removed from MathML 4 but is what OneNote
///    sends.
library;

import 'package:xml/xml.dart';

/// Every `<math>` element in [htmlSource], replaced by inline `$…$` LaTeX.
///
/// Done as a source-level substitution BEFORE the HTML is parsed, for the
/// reason in the library doc. The replacement is escaped so the HTML parser
/// sees it as ordinary text.
String inlineMathIntoHtml(String htmlSource) {
  if (!htmlSource.contains('<math')) return htmlSource;
  return htmlSource.replaceAllMapped(_mathElement, (m) {
    final latex = mathmlToLatex(m.group(0)!);
    if (latex.trim().isEmpty) return '';
    // `$` is not special to HTML, but `<`, `>` and `&` are, and LaTeX uses all
    // three. Escaping here means the parser hands the text back unchanged.
    final escaped = '\$$latex\$'
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return escaped;
  });
}

final RegExp _mathElement =
    RegExp(r'<math\b[^>]*>.*?</math\s*>', dotAll: true, caseSensitive: false);

/// One `<math>` element as LaTeX, or an empty string when it holds nothing.
String mathmlToLatex(String mathXml) {
  try {
    final doc = XmlDocument.parse(mathXml);
    // **One line, always.** MathML is pretty-printed, so the whitespace
    // between elements becomes text nodes and the LaTeX comes out with
    // the source's newlines still in it. A dollar-delimited run holding
    // a newline is not one equation to the markdown reader: it is an
    // unterminated delimiter and a broken paragraph, which is how the
    // floor-brackets equation arrived with everything after the first
    // fence missing.
    return _node(doc.rootElement).replaceAll(RegExp(r'\s+'), ' ').trim();
  } on XmlException {
    // Not well-formed after all. An equation that cannot be read costs that
    // equation and never the page around it.
    return '';
  }
}

String _children(XmlElement el) {
  final out = StringBuffer();
  for (final child in el.children) {
    out.write(_node(child));
  }
  return out.toString();
}

/// The children as a list, with empty ones dropped — what a fence or a table
/// needs to know how many arguments it really has.
List<String> _parts(XmlElement el) => [
      for (final child in el.childElements)
        if (_node(child).trim().isNotEmpty) _node(child).trim()
    ];

String _node(XmlNode node) {
  if (node is XmlText) return _text(node.value);
  if (node is XmlCDATA) return _text(node.value);
  if (node is! XmlElement) return '';
  final name = node.name.local.toLowerCase();
  switch (name) {
    // Leaves. `<mi>` is a single letter far more often than a whole name, so
    // the letters are simply concatenated and rejoin themselves.
    case 'mi':
    case 'mn':
    case 'mtext':
    case 'ms':
      return _children(node);
    case 'mo':
      return _operator(_children(node));
    case 'mspace':
      return ' ';
    // Grouping.
    case 'math':
    case 'mrow':
    case 'mstyle':
    case 'mpadded':
    case 'mphantom':
    case 'semantics':
      return _children(node);
    // `<annotation>` holds the original TeX or MathML-content form. Skipped
    // rather than read: it is an alternative encoding of the same equation,
    // and emitting both would duplicate every symbol.
    case 'annotation':
    case 'annotation-xml':
      return '';
    case 'mfrac':
      final p = _parts(node);
      if (p.length < 2) return _children(node);
      return '\\frac{${p[0]}}{${p[1]}}';
    case 'msup':
      final p = _parts(node);
      if (p.length < 2) return _children(node);
      return '${_atom(p[0])}^{${p[1]}}';
    case 'msub':
      final p = _parts(node);
      if (p.length < 2) return _children(node);
      return '${_atom(p[0])}_{${p[1]}}';
    case 'msubsup':
      final p = _parts(node);
      if (p.length < 3) return _children(node);
      return '${_atom(p[0])}_{${p[1]}}^{${p[2]}}';
    case 'msqrt':
      return '\\sqrt{${_children(node).trim()}}';
    case 'mroot':
      final p = _parts(node);
      if (p.length < 2) return '\\sqrt{${_children(node).trim()}}';
      return '\\sqrt[${p[1]}]{${p[0]}}';
    case 'mover':
      final p = _parts(node);
      if (p.length < 2) return _children(node);
      return '\\overset{${p[1]}}{${p[0]}}';
    case 'munder':
      final p = _parts(node);
      if (p.length < 2) return _children(node);
      return '\\underset{${p[1]}}{${p[0]}}';
    case 'munderover':
      final p = _parts(node);
      if (p.length < 3) return _children(node);
      return '${_atom(p[0])}_{${p[1]}}^{${p[2]}}';
    case 'mfenced':
      // Removed from MathML 4 and still what OneNote sends. The brackets are
      // attributes, and default to round when unstated.
      final open = _bracket(node.getAttribute('open') ?? '(');
      final close = _bracket(node.getAttribute('close') ?? ')');
      final sep = node.getAttribute('separators') ?? ',';
      final inner = _parts(node).join(sep.isEmpty ? '' : sep[0]);
      return '$open$inner$close';
    case 'mtable':
      final rows = [
        for (final tr in node.childElements)
          if (tr.name.local.toLowerCase() == 'mtr')
            [
              for (final td in tr.childElements) _node(td).trim(),
            ].join(' & ')
      ];
      if (rows.isEmpty) return '';
      return '\\begin{matrix}${rows.join(' \\\\ ')}\\end{matrix}';
    case 'mtr':
    case 'mtd':
      return _children(node);
    default:
      return _children(node);
  }
}

/// An operator, with the ones that mean nothing to a reader removed.
String _operator(String raw) {
  final cleaned = _text(raw);
  if (cleaned.trim().isEmpty) return cleaned.isEmpty ? '' : ' ';
  return cleaned;
}

/// Wrap in braces when it is more than one symbol, so `x^{2}` stays right and
/// `\frac{1}{2}^{3}` does not become `\frac{1}{2^{3}}`.
String _atom(String s) {
  if (s.length <= 1) return s;
  if (s.startsWith('\\') && !s.contains(' ')) return s;
  return '{$s}';
}

/// A fence attribute as LaTeX, since several of them need escaping.
String _bracket(String raw) {
  switch (raw.trim()) {
    case '':
      return '';
    case '{':
      return '\\{';
    case '}':
      return '\\}';
    case '⌊':
      return '\\lfloor ';
    case '⌋':
      return '\\rfloor ';
    case '⌈':
      return '\\lceil ';
    case '⌉':
      return '\\rceil ';
    case '‖':
      return '\\|';
    case '⟨':
      return '\\langle ';
    case '⟩':
      return '\\rangle ';
    default:
      return _text(raw.trim());
  }
}

/// Normalise the characters OneNote actually emits.
String _text(String raw) {
  final out = StringBuffer();
  for (final rune in raw.runes) {
    // Invisible operators: FUNCTION APPLICATION, INVISIBLE TIMES, INVISIBLE
    // SEPARATOR, INVISIBLE PLUS. They mean something to a formula processor
    // and nothing to a reader, and render as a missing glyph.
    if (rune >= 0x2061 && rune <= 0x2064) continue;
    // Zero-width and directional marks, same reasoning.
    if (rune == 0x200B || rune == 0x200C || rune == 0x200D || rune == 0xFEFF) {
      continue;
    }
    if (rune == 0x00A0) {
      out.write(' ');
      continue;
    }
    final mapped = _mathAlphanumeric(rune);
    if (mapped != null) {
      out.write(mapped);
      continue;
    }
    final greek = _greekName(rune);
    if (greek != null) {
      out.write(greek);
      continue;
    }
    out.write(String.fromCharCode(rune));
  }
  return out.toString();
}

/// Mathematical Alphanumeric Symbols back to ordinary letters.
///
/// OneNote writes variables in this block — theta as U+1D703, not U+03B8 —
/// and most fonts have none of it, so an imported equation was full of boxes.
/// LaTeX italicises maths by itself, so the plain letter is both readable and
/// more correct.
String? _mathAlphanumeric(int rune) {
  // The Latin ranges, each 26 capitals then 26 smalls.
  const latinStarts = [
    0x1D400, // bold
    0x1D434, // italic
    0x1D468, // bold italic
    0x1D5A0, // sans-serif
    0x1D5D4, // sans-serif bold
    0x1D608, // sans-serif italic
    0x1D670, // monospace
  ];
  for (final start in latinStarts) {
    if (rune >= start && rune < start + 52) {
      final i = rune - start;
      return i < 26
          ? String.fromCharCode(0x41 + i)
          : String.fromCharCode(0x61 + i - 26);
    }
  }
  // Digits.
  const digitStarts = [0x1D7CE, 0x1D7D8, 0x1D7E2, 0x1D7EC, 0x1D7F6];
  for (final start in digitStarts) {
    if (rune >= start && rune < start + 10) {
      return String.fromCharCode(0x30 + rune - start);
    }
  }
  // Greek: italic capitals then smalls, and the same shape for bold.
  // Each Greek block is 25 capitals, then NABLA, then 25 smalls. Missing the
  // nabla shifted every small letter by one, so theta came out as iota and
  // alpha as beta.
  const greekStarts = [0x1D6A8, 0x1D6E2, 0x1D71C, 0x1D756, 0x1D790];
  for (final start in greekStarts) {
    if (rune >= start && rune < start + 25) {
      return _greekName(0x0391 + rune - start);
    }
    if (rune == start + 25) return '\nabla ';
    if (rune >= start + 26 && rune < start + 51) {
      return _greekName(0x03B1 + rune - start - 26);
    }
  }
  return null;
}

/// A Greek letter as its LaTeX name, or null when it is not one.
String? _greekName(int rune) {
  const smalls = [
    'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta',
    'iota', 'kappa', 'lambda', 'mu', 'nu', 'xi', 'omicron', 'pi', 'rho',
    'varsigma', 'sigma', 'tau', 'upsilon', 'phi', 'chi', 'psi', 'omega',
  ];
  // Only the capitals with a shape of their own get a LaTeX name; the rest
  // are Latin letters and are written as such.
  const capitals = <int, String>{
    2: 'Gamma', 3: 'Delta', 7: 'Theta', 10: 'Lambda', 13: 'Xi', 15: 'Pi',
    18: 'Sigma', 20: 'Upsilon', 21: 'Phi', 23: 'Psi', 24: 'Omega',
  };
  const capitalLatin = <int, String>{
    0: 'A', 1: 'B', 4: 'E', 5: 'Z', 6: 'H', 8: 'I', 9: 'K', 11: 'M', 12: 'N',
    14: 'O', 16: 'P', 17: 'T', 19: 'T', 22: 'X',
  };
  if (rune >= 0x03B1 && rune <= 0x03C9) {
    return '\\${smalls[rune - 0x03B1]} ';
  }
  if (rune >= 0x0391 && rune <= 0x03A9) {
    final i = rune - 0x0391;
    final name = capitals[i];
    if (name != null) return '\\$name ';
    return capitalLatin[i] ?? String.fromCharCode(rune);
  }
  return null;
}
