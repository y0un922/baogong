import 'package:flutter/widgets.dart';

import '../chat/side_panel/terminal_split.dart';
import '../ide/terminal/terminal_instance.dart';
import '../ide/terminal/terminal_service.dart';

/// The tabs of a project's terminals split in more than one, as Ghostty
/// splits a window: the same in each place its [TerminalDeck] shows. Each
/// is by its tab's terminal, its first; one closed leaves its split, the
/// rest keeping its room, and a tab it named is named by the next.
class TerminalSplits extends ChangeNotifier {
  TerminalSplits._(TerminalService terminals) {
    terminals.onDidDispose.listen(_drop);
  }

  static final Expando<TerminalSplits> _of = Expando('terminal splits');

  /// [terminals]'s, made the first time.
  static TerminalSplits of(TerminalService terminals) =>
      _of[terminals] ??= TerminalSplits._(terminals);

  final Map<TerminalInstance, TerminalBranch<TerminalInstance>> _splits = {};

  /// The terminals of [tab]: its split's, else it alone.
  TerminalSplit<TerminalInstance> layoutOf(TerminalInstance tab) =>
      _splits[tab] ?? TerminalLeaf(tab);

  /// The tab [terminal] shows in: its split's first, else its own.
  TerminalInstance tabOf(TerminalInstance terminal) {
    for (final MapEntry(key: tab, value: split) in _splits.entries) {
      if (split.contains(terminal)) return tab;
    }
    return terminal;
  }

  /// [added] beside [at] in its tab, at its right (or under it,
  /// [Axis.vertical]).
  void split(TerminalInstance at, TerminalInstance added, Axis axis) {
    final tab = tabOf(at);
    if (layoutOf(tab).split(at, added, axis)
        case final TerminalBranch<TerminalInstance> branch) {
      _splits[tab] = branch;
    }
    notifyListeners();
  }

  void _drop(TerminalInstance terminal) {
    final tab = tabOf(terminal);
    final split = _splits.remove(tab);
    if (split == null) return;
    // Two at least were in it: one is left.
    final rest = split.remove(terminal)!;
    if (rest is TerminalBranch<TerminalInstance>) {
      _splits[rest.leaves.first] = rest;
    }
    notifyListeners();
  }
}
