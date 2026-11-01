import 'package:flutter/widgets.dart';

/// A terminal tab's layout, as Ghostty splits a window: one terminal, or
/// two layouts side by side ([Axis.horizontal]) or one over the other.
sealed class TerminalSplit<T extends Object> {
  const TerminalSplit();

  /// Its terminals, left to right and top to bottom.
  Iterable<T> get leaves;

  bool contains(T leaf) => leaves.contains(leaf);

  /// [added] beside [at], at its right (or under it, [Axis.vertical]),
  /// each with half of [at]'s room.
  TerminalSplit<T> split(T at, T added, Axis axis) => switch (this) {
    TerminalLeaf(:final terminal) when terminal == at => TerminalBranch(
      axis,
      this,
      TerminalLeaf(added),
    ),
    TerminalLeaf() => this,
    final TerminalBranch<T> branch =>
      branch
        ..first = branch.first.split(at, added, axis)
        ..second = branch.second.split(at, added, axis),
  };

  /// Without [leaf], the other side of its split taking the room; null
  /// where it was the only one.
  TerminalSplit<T>? remove(T leaf) => switch (this) {
    TerminalLeaf(:final terminal) => terminal == leaf ? null : this,
    final TerminalBranch<T> branch => switch ((
      branch.first.remove(leaf),
      branch.second.remove(leaf),
    )) {
      (null, final second) => second,
      (final first, null) => first,
      (final first?, final second?) =>
        branch
          ..first = first
          ..second = second,
    },
  };

  /// Where each terminal is in [rect].
  Map<T, Rect> layout(Rect rect) => switch (this) {
    TerminalLeaf(:final terminal) => {terminal: rect},
    final TerminalBranch<T> branch => {
      ...branch.first.layout(branch.firstRect(rect)),
      ...branch.second.layout(branch.secondRect(rect)),
    },
  };

  /// The terminal next to [from] at [direction]: of those whose edge meets
  /// its edge there and that share some of its side, the one whose middle
  /// is nearest; none at the edge of the layout.
  T? neighbor(T from, AxisDirection direction) {
    final rects = layout(const Rect.fromLTWH(0, 0, 1, 1));
    final at = rects[from];
    if (at == null) return null;
    const slack = 1e-9;
    T? best;
    var bestDistance = double.infinity;
    for (final MapEntry(key: leaf, value: rect) in rects.entries) {
      if (leaf == from) continue;
      final meets = switch (direction) {
        AxisDirection.left => (rect.right - at.left).abs() < slack,
        AxisDirection.right => (rect.left - at.right).abs() < slack,
        AxisDirection.up => (rect.bottom - at.top).abs() < slack,
        AxisDirection.down => (rect.top - at.bottom).abs() < slack,
      };
      final overlaps = switch (direction) {
        AxisDirection.left || AxisDirection.right =>
          rect.top < at.bottom - slack && rect.bottom > at.top + slack,
        AxisDirection.up || AxisDirection.down =>
          rect.left < at.right - slack && rect.right > at.left + slack,
      };
      if (!meets || !overlaps) continue;
      final distance = (rect.center - at.center).distance;
      if (distance < bestDistance) {
        best = leaf;
        bestDistance = distance;
      }
    }
    return best;
  }
}

final class TerminalLeaf<T extends Object> extends TerminalSplit<T> {
  const TerminalLeaf(this.terminal);

  final T terminal;

  @override
  Iterable<T> get leaves => [terminal];
}

final class TerminalBranch<T extends Object> extends TerminalSplit<T> {
  TerminalBranch(this.axis, this.first, this.second);

  final Axis axis;
  TerminalSplit<T> first;
  TerminalSplit<T> second;

  /// The share of the room [first] has, as dragged.
  double ratio = 0.5;

  static const minRatio = 0.1;

  @override
  Iterable<T> get leaves => [...first.leaves, ...second.leaves];

  Rect firstRect(Rect rect) => axis == Axis.horizontal
      ? Rect.fromLTWH(rect.left, rect.top, rect.width * ratio, rect.height)
      : Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * ratio);

  Rect secondRect(Rect rect) => axis == Axis.horizontal
      ? Rect.fromLTRB(
          rect.left + rect.width * ratio,
          rect.top,
          rect.right,
          rect.bottom,
        )
      : Rect.fromLTRB(
          rect.left,
          rect.top + rect.height * ratio,
          rect.right,
          rect.bottom,
        );
}
