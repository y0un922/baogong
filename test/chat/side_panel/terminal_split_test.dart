import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/chat/side_panel/terminal_split.dart';

void main() {
  test('splits nest; each terminal has its room; one removed gives its '
      'room to the other side', () {
    // a | b, then b over c.
    TerminalSplit<String> split = const TerminalLeaf('a');
    split = split.split('a', 'b', Axis.horizontal);
    split = split.split('b', 'c', Axis.vertical);
    expect(split.leaves, ['a', 'b', 'c']);
    expect(split.layout(const Rect.fromLTWH(0, 0, 100, 100)), {
      'a': const Rect.fromLTWH(0, 0, 50, 100),
      'b': const Rect.fromLTWH(50, 0, 50, 50),
      'c': const Rect.fromLTWH(50, 50, 50, 50),
    });

    final withoutB = split.remove('b')!;
    expect(withoutB.layout(const Rect.fromLTWH(0, 0, 100, 100)), {
      'a': const Rect.fromLTWH(0, 0, 50, 100),
      'c': const Rect.fromLTWH(50, 0, 50, 100),
    });
    expect(withoutB.remove('a')!.leaves, ['c']);
    expect(const TerminalLeaf('a').remove('a'), isNull);
  });

  test('the neighbor at a side is the one whose edge meets it there, the '
      'nearest of them; none at the layout\'s edge', () {
    // a | (b over c)
    final split = const TerminalLeaf('a')
        .split('a', 'b', Axis.horizontal)
        .split('b', 'c', Axis.vertical);
    expect(split.neighbor('a', AxisDirection.right), 'b');
    expect(split.neighbor('b', AxisDirection.left), 'a');
    expect(split.neighbor('c', AxisDirection.left), 'a');
    expect(split.neighbor('b', AxisDirection.down), 'c');
    expect(split.neighbor('c', AxisDirection.up), 'b');
    expect(split.neighbor('a', AxisDirection.left), isNull);
    expect(split.neighbor('a', AxisDirection.up), isNull);
    expect(split.neighbor('b', AxisDirection.right), isNull);
  });

  test('the side panel keeps a tab\'s split; a terminal of it opens its tab; '
      'one closed leaves the tab to the rest, named after the next', () {
    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final chat = Object();
    final tabs = panel.tabsOf(chat);
    panel.openTerminal(chat, 'a');
    panel.splitTerminal(chat, 'a', 'b', Axis.horizontal);
    panel.splitTerminal(chat, 'b', 'c', Axis.vertical);
    expect(tabs.terminals, ['a']);
    expect(tabs.layoutOf('a').leaves, ['a', 'b', 'c']);
    expect(tabs.tabOf('c'), 'a');

    panel.openTerminal(chat, 'other');
    panel.openTerminal(chat, 'c');
    expect(tabs.terminals, ['a', 'other']);
    expect(tabs.terminal, 'a');

    // The tab's own terminal closed: the tab is the next one's.
    panel.dropTerminal('a');
    expect(tabs.terminals, ['b', 'other']);
    expect(tabs.terminal, 'b');
    expect(tabs.layoutOf('b').leaves, ['b', 'c']);
    panel.dropTerminal('c');
    expect(tabs.splits, isEmpty);
    expect(tabs.layoutOf('b').leaves, ['b']);
    expect(tabs.terminals, ['b', 'other']);
  });
}
