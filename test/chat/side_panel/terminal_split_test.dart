import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/side_panel/terminal_split.dart';
import 'package:baocode/chat/side_panel/terminal_split_view.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/ide/terminal/terminal_hosts.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';
import 'package:baocode/ide/terminal/terminal_view.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/terminal_deck.dart';
import 'package:baocode/workspace/terminal_splits.dart';

import '../../ide/terminal/fake_pty.dart';
import '../../ide/terminal/fake_terminal.dart';

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

  testWidgets('a project\'s terminals keep their splits: one of a split is '
      'in its tab; one closed leaves the tab to the rest, named after the '
      'next', (tester) async {
    final terminals = TerminalService(
      root: '/p',
      backend: fakeTerminalBackend(<FakePty>[]),
    );
    addTearDown(terminals.dispose);
    final splits = TerminalSplits.of(terminals);
    expect(TerminalSplits.of(terminals), same(splits));
    final a = terminals.create();
    final b = terminals.create();
    final c = terminals.create();
    splits
      ..split(a, b, Axis.horizontal)
      ..split(b, c, Axis.vertical);
    expect(splits.layoutOf(a).leaves, [a, b, c]);
    expect(splits.tabOf(c), a);

    // The tab's own terminal closed: the tab is the next one's.
    terminals.kill(a);
    await tester.pump();
    expect(splits.tabOf(c), b);
    expect(splits.layoutOf(b).leaves, [b, c]);
    terminals.kill(c);
    await tester.pump();
    expect(splits.layoutOf(b), isA<TerminalLeaf<TerminalInstance>>());
  });

  testWidgets('the deck shows a split as one tab, its terminals side by '
      'side, each its view where the tab is, mirrored elsewhere', (
    tester,
  ) async {
    final terminals = TerminalService(
      root: '/p',
      backend: fakeTerminalBackend(<FakePty>[]),
    );
    addTearDown(terminals.dispose);
    final hosts = TerminalHosts();
    addTearDown(hosts.dispose);
    final a = terminals.create();
    final b = terminals.create();
    final other = terminals.create();
    TerminalSplits.of(terminals).split(a, b, Axis.horizontal);

    Widget deck(String place) => Expanded(
      key: ValueKey(place),
      child: TerminalDeck(
        place: place,
        hosts: hosts,
        terminals: terminals,
        // One of the split asked for: its tab shows.
        shown: b,
        onShow: (_) {},
        onNew: ({cwd}) => null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Material(child: Row(children: [deck('side'), deck('panel')])),
      ),
    );
    Finder viewsIn(String place) => find.descendant(
      of: find.byKey(ValueKey(place)),
      matching: find.byType(TerminalView),
    );
    Finder tabIn(String place, TerminalInstance shell) => find.descendant(
      of: find.descendant(
        of: find.byKey(ValueKey(place)),
        matching: find.byType(IdeTabStrip),
      ),
      matching: find.byKey(ObjectKey(shell)),
    );

    expect(find.byType(TerminalSplitView<TerminalInstance>), findsNWidgets(2));
    expect(viewsIn('side'), findsNWidgets(2));
    expect(tabIn('side', a), findsOneWidget);
    expect(tabIn('side', b), findsNothing);
    expect(tabIn('side', other), findsOneWidget);
    // The place built first has them, the other mirrors them.
    expect([
      for (final view in tester.widgetList<TerminalView>(viewsIn('side')))
        view.mirror,
    ], [false, false]);
    expect([
      for (final view in tester.widgetList<TerminalView>(viewsIn('panel')))
        view.mirror,
    ], [true, true]);

    // One closed: the other alone in its tab.
    terminals.kill(a);
    await tester.pump();
    await tester.pump();
    expect(find.byType(TerminalSplitView<TerminalInstance>), findsNothing);
    expect(tabIn('side', b), findsOneWidget);
    // Gone, the resizes the last frames queued done.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
