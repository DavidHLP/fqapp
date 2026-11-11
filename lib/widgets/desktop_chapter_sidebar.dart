import 'package:flutter/material.dart';
import '../models/media_item.dart';

class DesktopChapterSidebar extends StatefulWidget {
  const DesktopChapterSidebar({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.onSelected,
    this.width = 248,
    this.chapterUnit = '章',
  });
  final double width;
  final String chapterUnit;
  final List<Chapter> chapters;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  @override
  State<DesktopChapterSidebar> createState() => _DesktopChapterSidebarState();
}

class _DesktopChapterSidebarState extends State<DesktopChapterSidebar> {
  String _query = '';
  final _scroll = ScrollController();
  bool _locate = true;

  @override
  void didUpdateWidget(covariant DesktopChapterSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.chapters != widget.chapters) {
      _locate = true;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indices = [
      for (var i = 0; i < widget.chapters.length; i++)
        if (_query.isEmpty || widget.chapters[i].title.contains(_query)) i,
    ];
    final extent =
        80.0 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.5);
    if (_locate) {
      _locate = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final index = indices.indexOf(widget.currentIndex);
        _scroll.jumpTo(
          (index < 0 ? 0.0 : index * extent).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
      });
    }
    return SizedBox(
      width: widget.width,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '搜索目录',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (value) => setState(() {
                  _query = value.trim();
                  _locate = true;
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('共 ${widget.chapters.length} ${widget.chapterUnit}'),
            ),
            Expanded(
              child: ListView.builder(
                key: ValueKey(_query),
                controller: _scroll,
                itemExtent: extent,
                itemCount: indices.length,
                itemBuilder: (context, index) {
                  final i = indices[index];
                  return ListTile(
                    dense: true,
                    trailing: i == widget.currentIndex
                        ? const Text('当前')
                        : null,
                    subtitle: widget.chapters[i].volumeName.isEmpty
                        ? null
                        : Text(
                            widget.chapters[i].volumeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    selected: i == widget.currentIndex,
                    selectedTileColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .1),
                    title: Text(
                      widget.chapters[i].title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => widget.onSelected(i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
