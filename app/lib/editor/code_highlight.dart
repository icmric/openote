import 'package:flutter/material.dart';

import '../theme/onote_theme.dart';

/// Dependency-free syntax highlighter (CODE-1). A single-pass tokenizer that
/// classifies comments, strings, numbers, keywords and types across a set of
/// common languages. Deliberately small and self-contained — no external
/// grammar package — so it always compiles and stays fast for note-sized
/// snippets. Swappable for re_highlight later without touching call sites.
List<TextSpan> highlightCode(String src, String language, bool dark) {
  final cfg = _langs[language] ?? _defaultCfg;

  final kwStyle = TextStyle(color: dark ? OnoteColors.ink300 : OnoteColors.ink600);
  final typeStyle =
      TextStyle(color: dark ? const Color(0xFFA78BFA) : const Color(0xFF6A4BC0));
  final strStyle =
      TextStyle(color: dark ? const Color(0xFF7FCB98) : OnoteColors.success);
  final numStyle =
      TextStyle(color: dark ? OnoteColors.brass400 : OnoteColors.brass700);
  const comStyle = TextStyle(
      color: OnoteColors.graphite400, fontStyle: FontStyle.italic);

  final spans = <TextSpan>[];
  final buf = StringBuffer();
  TextStyle? cur;
  void flush() {
    if (buf.isNotEmpty) {
      spans.add(TextSpan(text: buf.toString(), style: cur));
      buf.clear();
    }
  }

  void emit(String s, TextStyle? style) {
    if (style != cur) {
      flush();
      cur = style;
    }
    buf.write(s);
  }

  final n = src.length;
  var i = 0;
  while (i < n) {
    final c = src.codeUnitAt(i);

    // Line comment: // or (hash langs) #
    if (cfg.cLike && c == 0x2F && i + 1 < n && src.codeUnitAt(i + 1) == 0x2F) {
      final j = _toEol(src, i);
      emit(src.substring(i, j), comStyle);
      i = j;
      continue;
    }
    if (cfg.hash && c == 0x23) {
      final j = _toEol(src, i);
      emit(src.substring(i, j), comStyle);
      i = j;
      continue;
    }
    if (cfg.dashComment &&
        c == 0x2D &&
        i + 1 < n &&
        src.codeUnitAt(i + 1) == 0x2D) {
      final j = _toEol(src, i);
      emit(src.substring(i, j), comStyle);
      i = j;
      continue;
    }
    // Block comment /* ... */
    if (cfg.cLike && c == 0x2F && i + 1 < n && src.codeUnitAt(i + 1) == 0x2A) {
      var j = i + 2;
      while (j + 1 < n &&
          !(src.codeUnitAt(j) == 0x2A && src.codeUnitAt(j + 1) == 0x2F)) {
        j++;
      }
      j = (j + 1 < n) ? j + 2 : n;
      emit(src.substring(i, j), comStyle);
      i = j;
      continue;
    }
    // String: " ' `
    if (c == 0x22 || c == 0x27 || c == 0x60) {
      var j = i + 1;
      while (j < n) {
        final cj = src.codeUnitAt(j);
        if (cj == 0x5C) {
          j += 2;
          continue;
        } // backslash escape
        if (cj == c) {
          j++;
          break;
        }
        if (cj == 0x0A && c != 0x60) break; // unterminated non-backtick
        j++;
      }
      if (j > n) j = n;
      emit(src.substring(i, j), strStyle);
      i = j;
      continue;
    }
    // Number
    if (_isDigit(c)) {
      var j = i;
      while (j < n && _isNumChar(src.codeUnitAt(j))) {
        j++;
      }
      emit(src.substring(i, j), numStyle);
      i = j;
      continue;
    }
    // Identifier / keyword
    if (_isIdStart(c)) {
      var j = i;
      while (j < n && _isIdChar(src.codeUnitAt(j))) {
        j++;
      }
      final word = src.substring(i, j);
      final style = cfg.keywords.contains(word)
          ? kwStyle
          : cfg.types.contains(word)
              ? typeStyle
              : null;
      emit(word, style);
      i = j;
      continue;
    }
    emit(src[i], null);
    i++;
  }
  flush();
  return spans;
}

int _toEol(String s, int i) {
  var j = i;
  while (j < s.length && s.codeUnitAt(j) != 0x0A) {
    j++;
  }
  return j;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isNumChar(int c) =>
    _isDigit(c) ||
    c == 0x2E ||
    c == 0x78 ||
    c == 0x58 ||
    (c >= 0x61 && c <= 0x66) ||
    (c >= 0x41 && c <= 0x46) ||
    c == 0x5F;
bool _isIdStart(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x24;
bool _isIdChar(int c) => _isIdStart(c) || _isDigit(c);

class _LangCfg {
  const _LangCfg(
    this.keywords, {
    this.types = const {},
    this.cLike = true,
    this.hash = false,
    this.dashComment = false,
  });
  final Set<String> keywords;
  final Set<String> types;
  final bool cLike;
  final bool hash;
  final bool dashComment;
}

const _defaultCfg = _LangCfg({});

const _cKeywords = {
  'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default', 'break',
  'continue', 'return', 'goto', 'sizeof', 'typedef', 'struct', 'union', 'enum',
  'const', 'static', 'extern', 'void', 'inline', 'volatile', 'register'
};
const _cTypes = {
  'int', 'char', 'float', 'double', 'long', 'short', 'unsigned', 'signed',
  'bool', 'size_t', 'uint8_t', 'uint32_t', 'int64_t'
};

final Map<String, _LangCfg> _langs = {
  'dart': const _LangCfg({
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
    'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
    'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
    'factory', 'false', 'final', 'finally', 'for', 'Function', 'get', 'hide',
    'if', 'implements', 'import', 'in', 'is', 'late', 'library', 'mixin', 'new',
    'null', 'on', 'operator', 'part', 'required', 'rethrow', 'return', 'sealed',
    'set', 'show', 'static', 'super', 'switch', 'sync', 'this', 'throw', 'true',
    'try', 'typedef', 'var', 'void', 'while', 'with', 'yield'
  }, types: {
    'int', 'double', 'num', 'bool', 'String', 'List', 'Map', 'Set', 'Object',
    'Widget', 'Future', 'Stream', 'void'
  }),
  'python': const _LangCfg({
    'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue',
    'def', 'del', 'elif', 'else', 'except', 'False', 'finally', 'for', 'from',
    'global', 'if', 'import', 'in', 'is', 'lambda', 'None', 'nonlocal', 'not',
    'or', 'pass', 'raise', 'return', 'True', 'try', 'while', 'with', 'yield',
    'self', 'match', 'case'
  }, cLike: false, hash: true),
  'js': const _LangCfg({
    'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'debugger', 'default', 'delete', 'do', 'else', 'export', 'extends', 'false',
    'finally', 'for', 'function', 'if', 'import', 'in', 'instanceof', 'let',
    'new', 'null', 'of', 'return', 'super', 'switch', 'this', 'throw', 'true',
    'try', 'typeof', 'var', 'void', 'while', 'with', 'yield'
  }),
  'ts': const _LangCfg({
    'abstract', 'any', 'as', 'async', 'await', 'boolean', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'declare', 'default', 'else', 'enum',
    'export', 'extends', 'false', 'finally', 'for', 'function', 'if',
    'implements', 'import', 'in', 'interface', 'let', 'new', 'null', 'number',
    'private', 'protected', 'public', 'readonly', 'return', 'string', 'super',
    'switch', 'this', 'throw', 'true', 'try', 'type', 'typeof', 'var', 'void',
    'while', 'yield'
  }, types: {
    'string', 'number', 'boolean', 'any', 'void', 'unknown', 'never', 'Array'
  }),
  'rust': const _LangCfg({
    'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn',
    'else', 'enum', 'extern', 'false', 'fn', 'for', 'if', 'impl', 'in', 'let',
    'loop', 'match', 'mod', 'move', 'mut', 'pub', 'ref', 'return', 'self',
    'Self', 'static', 'struct', 'super', 'trait', 'true', 'type', 'unsafe',
    'use', 'where', 'while'
  }, types: {
    'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'usize', 'isize',
    'f32', 'f64', 'bool', 'char', 'str', 'String', 'Vec', 'Option', 'Result'
  }),
  'c': const _LangCfg(_cKeywords, types: _cTypes),
  'cpp': const _LangCfg({
    ..._cKeywords, 'class', 'public', 'private', 'protected', 'virtual',
    'namespace', 'using', 'template', 'typename', 'new', 'delete', 'this',
    'try', 'catch', 'throw', 'nullptr', 'true', 'false', 'auto', 'constexpr',
    'override', 'final'
  }, types: {..._cTypes, 'string', 'vector', 'map', 'set', 'auto'}),
  'java': const _LangCfg({
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
    'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
    'extends', 'final', 'finally', 'float', 'for', 'if', 'implements', 'import',
    'instanceof', 'int', 'interface', 'long', 'native', 'new', 'package',
    'private', 'protected', 'public', 'return', 'short', 'static', 'super',
    'switch', 'synchronized', 'this', 'throw', 'throws', 'try', 'void',
    'volatile', 'while', 'true', 'false', 'null', 'var'
  }, types: {'String', 'Integer', 'List', 'Map', 'Object', 'boolean', 'int'}),
  'kotlin': const _LangCfg({
    'as', 'break', 'class', 'continue', 'do', 'else', 'false', 'for', 'fun',
    'if', 'in', 'interface', 'is', 'null', 'object', 'package', 'return',
    'super', 'this', 'throw', 'true', 'try', 'typealias', 'val', 'var', 'when',
    'while', 'by', 'catch', 'constructor', 'data', 'finally', 'import',
    'override', 'private', 'public', 'internal', 'sealed', 'suspend', 'lateinit',
    'companion', 'init'
  }, types: {'Int', 'String', 'Boolean', 'List', 'Map', 'Double', 'Unit'}),
  'go': const _LangCfg({
    'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else',
    'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import', 'interface',
    'map', 'package', 'range', 'return', 'select', 'struct', 'switch', 'type',
    'var', 'nil', 'true', 'false'
  }, types: {'int', 'string', 'bool', 'byte', 'rune', 'float64', 'error'}),
  'sql': const _LangCfg({
    'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET',
    'DELETE', 'CREATE', 'TABLE', 'DROP', 'ALTER', 'JOIN', 'LEFT', 'RIGHT',
    'INNER', 'OUTER', 'ON', 'GROUP', 'BY', 'ORDER', 'HAVING', 'LIMIT', 'AS',
    'AND', 'OR', 'NOT', 'NULL', 'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES',
    'INDEX', 'DISTINCT', 'COUNT', 'select', 'from', 'where', 'insert', 'update',
    'delete', 'create', 'table', 'join', 'and', 'or', 'not', 'null'
  }, cLike: false, dashComment: true, hash: false),
  'bash': const _LangCfg({
    'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done', 'case',
    'esac', 'function', 'in', 'return', 'echo', 'export', 'local', 'read',
    'cd', 'exit'
  }, cLike: false, hash: true),
  'yaml': const _LangCfg({'true', 'false', 'null', 'yes', 'no'},
      cLike: false, hash: true),
  'json': const _LangCfg({'true', 'false', 'null'}, cLike: false),
  'html': const _LangCfg({}),
  'css': const _LangCfg({}),
  'text': _defaultCfg,
};
