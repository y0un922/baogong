import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'terminal_split.dart';

/// [split]'s terminals, each [leaf] builds, in their rooms: a line between
/// the two sides of each split, dragged to give one more.
class TerminalSplitView<T extends Object> extends StatefulWidget {
  const TerminalSplitView({super.key, required this.split, required this.leaf});

  final TerminalSplit<T> split;
  final Widget Function(T terminal) leaf;

  /// The line's width, and the room a drag catches on either side of it.
  static const lineWidth = 1.0;
  static const grabWidth = 6.0;

  @override
  State<TerminalSplitView<T>> createState() => _TerminalSplitViewState<T>();
}

class _TerminalSplitViewState<T extends Object>
    extends State<TerminalSplitView<T>> {
  @override
  Widget build(BuildContext context) => _build(widget.split);

  Widget _build(TerminalSplit<T> split) => switch (split) {
    TerminalLeaf(:final terminal) => KeyedSubtree(
      key: ObjectKey(terminal),
      child: widget.leaf(terminal),
    ),
    final TerminalBranch<T> branch => _branch(branch),
  };

  Widget _branch(TerminalBranch<T> branch) {
    final horizontal = branch.axis == Axis.horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        const line = TerminalSplitView.lineWidth;
        final first = ((extent - line) * branch.ratio).clamp(0.0, extent);
        return Stack(
          children: [
            Flex(
              direction: branch.axis,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: horizontal ? first : null,
                  height: horizontal ? null : first,
                  child: _build(branch.first),
                ),
                SizedBox(
                  width: horizontal ? line : null,
                  height: horizontal ? null : line,
                  child: ColoredBox(color: AppColors.partBorder),
                ),
                Expanded(child: _build(branch.second)),
              ],
            ),
            Positioned(
              left: horizontal ? first - TerminalSplitView.grabWidth / 2 : 0,
              top: horizontal ? 0 : first - TerminalSplitView.grabWidth / 2,
              right: horizontal ? null : 0,
              bottom: horizontal ? 0 : null,
              width: horizontal ? TerminalSplitView.grabWidth : null,
              height: horizontal ? null : TerminalSplitView.grabWidth,
              child: MouseRegion(
                cursor: horizontal
                    ? SystemMouseCursors.resizeColumn
                    : SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    if (extent <= line) return;
                    final delta = horizontal
                        ? details.delta.dx
                        : details.delta.dy;
                    setState(() {
                      branch.ratio = (branch.ratio + delta / (extent - line))
                          .clamp(
                            TerminalBranch.minRatio,
                            1 - TerminalBranch.minRatio,
                          );
                    });
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
