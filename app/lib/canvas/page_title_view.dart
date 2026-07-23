import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// In-page title band (OneNote-style): the title and date live at the top of
/// the page itself, editable in place — no menu. Rendered in page-space so it
/// pans and zooms with the page. Bound to the page node, not a Block.
class PageTitleView extends StatefulWidget {
  const PageTitleView({super.key, required this.app, required this.width});
  final AppState app;
  final double width;

  @override
  State<PageTitleView> createState() => _PageTitleViewState();
}

class _PageTitleViewState extends State<PageTitleView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  TreeNode? get _page => widget.app.node(widget.app.pageId ?? '');

  @override
  void dispose() {
    if (_editing) widget.app.titleEditing = false; // clear without notify
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit() {
    final page = _page;
    if (page == null) return;
    _controller.text = page.title == 'Untitled page' ? '' : page.title;
    widget.app.setTitleEditing(true);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _controller.selection = TextSelection(
          baseOffset: 0, extentOffset: _controller.text.length);
    });
  }

  void _commit() {
    final page = _page;
    if (page != null) {
      final t = _controller.text.trim();
      widget.app.renameNode(page.id, t.isEmpty ? 'Untitled page' : t);
    }
    widget.app.setTitleEditing(false);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final page = _page;
    if (page == null) return const SizedBox.shrink();

    final titleColor = dark ? OnoteColors.moon0 : OnoteColors.graphite900;
    final titleStyle = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w600,
      height: 1.1,
      color: titleColor,
    );
    final isPlaceholder = page.title == 'Untitled page';

    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editing)
            TextField(
              controller: _controller,
              focusNode: _focus,
              style: titleStyle,
              maxLines: 1,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Page title',
              ),
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) {
                if (_editing) _commit();
              },
            )
          else
            Semantics(
              label: 'Page title: ${page.title}',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _startEdit,
                child: Text(
                  isPlaceholder ? 'Untitled page' : page.title,
                  style: titleStyle.copyWith(
                    color: isPlaceholder ? OnoteColors.graphite400 : titleColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            _dateLine(page.createdAt),
            style: TextStyle(fontSize: 12, color: OnoteColors.graphite400),
          ),
          const SizedBox(height: 6),
          Container(
              height: 1,
              color: dark ? OnoteColors.night200 : OnoteColors.paper200),
        ],
      ),
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _dateLine(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour < 12 ? 'AM' : 'PM';
    final mm = d.minute.toString().padLeft(2, '0');
    return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}    $h:$mm $ap';
  }
}
