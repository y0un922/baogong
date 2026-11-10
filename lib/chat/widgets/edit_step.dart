import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ide/ide_code_diff.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../edit_detail.dart';
import '../side_panel/file_link.dart';
import '../side_panel/file_link_menu.dart';
import '../side_panel/file_open.dart';
import 'code_citation.dart';
import 'hover_builder.dart';
import 'own_selection.dart';
import 'step_header.dart';

/// A file edit as one compact row that opens to its diff. Consecutive
/// edits of the same file ([also]) share the row, marked ×N, and open to
/// each diff in turn.
class EditStep extends StatelessWidget {
  const EditStep({
    super.key,
    required this.item,
    this.also = const [],
    this.expanded = false,
    this.onToggle,
  });

  final CodeDiffItem item;

  /// Later consecutive edits of the same file, shown as one row with [item].
  final List<CodeDiffItem> also;

  /// Whether the diff is open, as [EditDetail.compact] shows it; a card
  /// is always.
  final bool expanded;
  final VoidCallback? onToggle;

  /// How many lines the open diff shows before it fades and offers more.
  static const previewLines = 12;

  List<CodeDiffItem> get _all => [item, ...also];

  int get _added => _all.fold(0, (sum, item) => sum + item.added);
  int get _removed => _all.fold(0, (sum, item) => sum + item.removed);

  bool get _canOpen => _all.any((item) => item.lines.isNotEmpty);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: EditDetail.current,
    builder: (context, detail, _) {
      final alwaysOpen = detail == EditDetail.card;
      final open = alwaysOpen || expanded;
      final toggle = alwaysOpen || !_canOpen ? null : onToggle;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CompactRow(
            item: item,
            added: _added,
            removed: _removed,
            times: _all.length,
            onToggle: toggle,
          ),
          if (open)
            for (final diff in _all)
              if (diff.lines.isNotEmpty) _Card(item: diff),
        ],
      );
    },
  );
}

bool _isCreated(CodeDiffItem item) =>
    item.displayTool == 'write' && item.writeExisted != true;

bool _isOverwrite(CodeDiffItem item) =>
    item.displayTool == 'write' && item.writeExisted == true;

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// How many of the five diffstat squares are green and red. When the
/// total is at least 5, they fill all five (largest remainder; at least
/// one each when both added and removed). Below 5, the rest stay empty.
@visibleForTesting
(int added, int removed) editDiffStatSlots(int added, int removed) {
  const slots = 5;
  final total = added + removed;
  if (total <= 0) return (0, 0);
  if (total < slots) return (added, removed);
  final addShare = added / total * slots;
  final remShare = removed / total * slots;
  var add = addShare.floor();
  var rem = remShare.floor();
  if (add + rem < slots) {
    if (addShare - add >= remShare - rem) {
      add++;
    } else {
      rem++;
    }
  }
  if (added > 0 && add == 0) {
    add = 1;
    if (add + rem > slots) rem--;
  }
  if (removed > 0 && rem == 0) {
    rem = 1;
    if (add + rem > slots) add--;
  }
  return (add, rem);
}

/// `Edited  [icon] auth.dart  lib/services    +12 -3  ▮▮▮▮▮`
class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.item,
    required this.added,
    required this.removed,
    required this.times,
    this.onToggle,
  });

  final CodeDiffItem item;
  final int added;
  final int removed;
  final int times;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final files = FileOpenScope.maybeOf(context);
    final path = files?.resolve(item.path);
    final first = item.firstChangedLine;
    final created = _isCreated(item);
    final overwrite = _isOverwrite(item);
    Widget row = HoverBuilder(
      cursor: onToggle == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) {
        final buttons = hovered && files != null && path != null;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: Row(
                    children: [
                      Text(
                        created
                            ? l10n.editCreated
                            : overwrite
                            ? l10n.toolOverwrote
                            : l10n.toolEdited,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: StepHeader.fontSize,
                        ),
                      ),
                      const SizedBox(width: 6),
                      FileIcon(item.fileName, size: 15),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: StepHeader.fontSize,
                          ),
                        ),
                      ),
                      if (item.directory.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            item.directory,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textFaint,
                              fontSize: StepHeader.fontSize,
                            ),
                          ),
                        ),
                      ],
                      if (overwrite &&
                          (item.writeOldLines != null ||
                              item.writeLines != null)) ...[
                        const SizedBox(width: 8),
                        Text(
                          l10n.editOverwriteLines(
                            item.writeOldLines ?? 0,
                            item.writeLines ?? 0,
                          ),
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: StepHeader.fontSize,
                          ),
                        ),
                      ],
                      if (added > 0 || removed > 0) ...[
                        const SizedBox(width: 8),
                        _Counts(added: added, removed: removed),
                      ],
                      if (created && item.writeBytes != null)
                        Text(
                          ' · ${_fileSize(item.writeBytes!)}',
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: StepHeader.fontSize,
                          ),
                        ),
                      if (times > 1) ...[
                        const SizedBox(width: 6),
                        Text(
                          '×$times',
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: StepHeader.fontSize,
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      _DiffStat(added: added, removed: removed),
                    ],
                  ),
                ),
              ),
              if (buttons) ...[
                const SizedBox(width: 4),
                CodeBlockIconButton(
                  icon: Codicons.diff,
                  tooltip: l10n.sidePanelOpenDiff,
                  onTap: () => files.onOpen(
                    FileOpenRequest(
                      path,
                      diff: true,
                      range: first == null ? null : FileLineRange(first),
                    ),
                  ),
                ),
                CodeBlockIconButton(
                  icon: Codicons.goToFile,
                  tooltip: l10n.sidePanelOpenFile,
                  onTap: () => files.onOpen(FileOpenRequest(path)),
                ),
              ],
            ],
          ),
        );
      },
    );
    row = SelectionContainer.disabled(child: row);
    if (files == null || path == null) return row;
    return FileLinkMenuRegion(
      menu: files.menuFor(
        path,
        () => files.onOpen(FileOpenRequest(path, diff: true)),
        context: context,
      ),
      child: row,
    );
  }
}

/// Five GitHub-style squares: green / red / empty by added vs removed.
class _DiffStat extends StatelessWidget {
  const _DiffStat({required this.added, required this.removed});

  final int added;
  final int removed;

  static const _slots = 5;

  @override
  Widget build(BuildContext context) {
    final (add, rem) = editDiffStatSlots(added, removed);
    final empty = _slots - add - rem;
    Widget box(Color color) => Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < add; i++)
          box(themeColors['chat.linesAddedForeground']),
        for (var i = 0; i < rem; i++)
          box(themeColors['chat.linesRemovedForeground']),
        for (var i = 0; i < empty; i++)
          box(AppColors.textFaint.withValues(alpha: 0.35)),
      ],
    );
  }
}

/// The diff in a framed card, about [EditStep.previewLines] tall until
/// asked for the rest.
class _Card extends StatefulWidget {
  const _Card({required this.item});

  final CodeDiffItem item;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  final _horizontal = ValueNotifier<List<IdeDiffHorizontal>>(const []);
  bool _showAll = false;

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  /// Its scrollbars as the change view's editors' are: square, against the
  /// edge, in their colors at rest, under the pointer and dragged; a little
  /// thinner ([_AcrossBar.thickness]).
  static ScrollbarThemeData _bars(BuildContext context) {
    final rest = themeColors['scrollbarSlider.background'];
    final hover = themeColors['scrollbarSlider.hoverBackground'];
    final active = themeColors['scrollbarSlider.activeBackground'];
    return ScrollbarTheme.of(context).copyWith(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.dragged)
            ? active
            : states.contains(WidgetState.hovered)
            ? hover
            : rest,
      ),
      thickness: const WidgetStatePropertyAll(_AcrossBar.thickness),
      radius: Radius.zero,
      crossAxisMargin: 0,
      mainAxisMargin: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sides = DiffSides(widget.item.lines);
    final lineH = IdeCodeDiff.lineHeight(context);
    final clipped = !_showAll && sides.rows > EditStep.previewLines;
    final diff = _Diff(widget.item, horizontal: _horizontal);
    if (clipped) {
      final fade = AppColors.conversationSurface;
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 2, bottom: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.partBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: EditStep.previewLines * lineH,
              child: Stack(
                children: [
                  SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: diff,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 28,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [fade.withValues(alpha: 0), fade],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: GestureDetector(
                onTap: () => setState(() => _showAll = true),
                child: Text(
                  context.l10n.editShowAllLines(sides.rows),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final maxHeight = math.min(math.max(sides.rows, 1) * lineH, 480.0);
    return ScrollbarTheme(
      data: _bars(context),
      child: StepBody(
        maxHeight: maxHeight,
        padding: EdgeInsets.zero,
        fadeEdges: true,
        scrollbar: true,
        codeBlock: true,
        keepWheel: true,
        bottom: (context, hovered) => ValueListenableBuilder(
          valueListenable: _horizontal,
          builder: (context, editors, _) => SizedBox(
            height: _AcrossBar.thickness,
            child: Stack(
              children: [
                for (final editor in editors)
                  if (editor.max > 0)
                    Positioned(
                      left: editor.left,
                      width: editor.width,
                      top: 0,
                      bottom: 0,
                      child: _AcrossBar(editor: editor, visible: hovered),
                    ),
              ],
            ),
          ),
        ),
        child: diff,
      ),
    );
  }
}

/// A scrollbar across an [editor]'s text, as the card's own down it is
/// ([ScrollbarThemeData]): shown while [visible], or dragged.
class _AcrossBar extends StatefulWidget {
  const _AcrossBar({required this.editor, required this.visible});

  final IdeDiffHorizontal editor;
  final bool visible;

  /// Its and the card's own down it: a little thinner than the change
  /// view's editors' (14 down, 12 across).
  static const thickness = 10.0;

  @override
  State<_AcrossBar> createState() => _AcrossBarState();
}

class _AcrossBarState extends State<_AcrossBar> {
  bool _dragging = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final IdeDiffHorizontal(:width, :max, :scroll) = widget.editor;
    final theme = ScrollbarTheme.of(context);
    final length = math.min(
      width,
      math.max(theme.minThumbLength ?? 48, width * width / (width + max)),
    );
    final travel = width - length;
    return ValueListenableBuilder(
      valueListenable: scroll,
      builder: (context, offset, _) => Stack(
        children: [
          Positioned(
            left: travel * (offset.dx / max).clamp(0.0, 1.0),
            width: length,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => setState(() => _dragging = true),
                onHorizontalDragUpdate: (details) {
                  if (travel <= 0) return;
                  final at = scroll.value;
                  scroll.value = Offset(
                    (at.dx + details.delta.dx * max / travel).clamp(0.0, max),
                    at.dy,
                  );
                },
                onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                onHorizontalDragCancel: () => setState(() => _dragging = false),
                child: Visibility.maintain(
                  visible: widget.visible || _dragging,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.thumbColor?.resolve({
                        if (_dragging) WidgetState.dragged,
                        if (_hovered) WidgetState.hovered,
                      }),
                      borderRadius: BorderRadius.all(
                        theme.radius ?? const Radius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "+12 -3", in the chat's colors for lines added and removed; a count of
/// none is left out.
class _Counts extends StatelessWidget {
  const _Counts({required this.added, required this.removed});

  final int added;
  final int removed;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        if (added > 0)
          TextSpan(
            text: '+$added',
            style: TextStyle(color: themeColors['chat.linesAddedForeground']),
          ),
        if (added > 0 && removed > 0) const TextSpan(text: ' '),
        if (removed > 0)
          TextSpan(
            text: '-$removed',
            style: TextStyle(color: themeColors['chat.linesRemovedForeground']),
          ),
      ],
    ),
    style: TextStyle(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallbacks,
      fontSize: 11.5,
    ),
  );
}

/// The diff's two sides, as texts of their own: the old (its context and
/// removed lines) and the new (its context and added lines), each line
/// with the number it has in its file.
class DiffSides {
  DiffSides(List<DiffLine> lines) {
    final original = <String>[], modified = <String>[];
    // The next line's numbers on each side, to number the old side's
    // context (a line keeps its new number).
    int? oldNext, newNext;
    for (final line in lines) {
      switch (line.type) {
        case DiffLineType.context:
          _context++;
          // After a gap (the next hunk), the lines between moved both
          // sides alike.
          final old = newNext == null || oldNext == null
              ? line.lineNumber
              : line.lineNumber - newNext + oldNext;
          original.add(line.text);
          originalNumbers.add(old);
          modified.add(line.text);
          modifiedNumbers.add(line.lineNumber);
          oldNext = old + 1;
          newNext = line.lineNumber + 1;
        case DiffLineType.removed:
          original.add(line.text);
          originalNumbers.add(line.lineNumber);
          oldNext = line.lineNumber + 1;
        case DiffLineType.added:
          modified.add(line.text);
          modifiedNumbers.add(line.lineNumber);
          newNext = line.lineNumber + 1;
      }
    }
    this.original = original.join('\n');
    this.modified = modified.join('\n');
  }

  late final String original;
  late final String modified;
  final List<int> originalNumbers = [];
  final List<int> modifiedNumbers = [];

  /// A new file's: nothing on the old side.
  bool get created => originalNumbers.isEmpty;

  int _context = 0;

  int originalNumberOf(int line) =>
      originalNumbers.elementAtOrNull(line - 1) ?? line;
  int modifiedNumberOf(int line) =>
      modifiedNumbers.elementAtOrNull(line - 1) ?? line;

  /// How many lines tall the diff is, inline: its context lines once, its
  /// removed and added lines each.
  int get rows => originalNumbers.length + modifiedNumbers.length - _context;
}

/// The diff as the IDE's diff editor shows it ([IdeCodeDiff]), inline
/// (the removed lines over the added; a new file alone, as highlighted
/// code with a green bar), its lines numbered as in the file, as tall as
/// they are: the card scrolls it.
class _Diff extends StatefulWidget {
  const _Diff(this.item, {required this.horizontal});

  final CodeDiffItem item;

  /// Told how its editors scroll across ([IdeCodeDiff.horizontal]).
  final ValueNotifier<List<IdeDiffHorizontal>> horizontal;

  @override
  State<_Diff> createState() => _DiffState();
}

class _DiffState extends State<_Diff> {
  late DiffSides _sides = DiffSides(widget.item.lines);

  @override
  void didUpdateWidget(_Diff oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.item.lines, widget.item.lines)) {
      _sides = DiffSides(widget.item.lines);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sides = _sides;
    final rows = sides.rows < 1 ? 1 : sides.rows;
    final created = sides.created;
    return SizedBox(
      height: rows * IdeCodeDiff.lineHeight(context),
      // The editors' own selection, apart from the conversation's.
      child: OwnSelection(
        child: DecoratedBox(
          decoration: created
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: themeColors['chat.linesAddedForeground'],
                      width: 2,
                    ),
                  ),
                )
              : const BoxDecoration(),
          child: IdeCodeDiff(
            path: widget.item.fileName,
            original: created ? sides.modified : sides.original,
            modified: sides.modified,
            syntax: CodeCitationScope.maybeOf(context)?.syntax?.call(),
            sideBySide: false,
            originalLineNumberOf: created
                ? sides.modifiedNumberOf
                : sides.originalNumberOf,
            modifiedLineNumberOf: sides.modifiedNumberOf,
            embedded: true,
            bars: false,
            horizontal: widget.horizontal,
          ),
        ),
      ),
    );
  }
}
