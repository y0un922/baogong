import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/edit_detail.dart';
import 'package:baocode/chat/widgets/edit_step.dart';
import 'package:baocode/chat/widgets/step_header.dart';
import 'package:baocode/ide/ide_code_diff.dart';

CodeDiffItem _edit({
  String fileName = 'a.dart',
  String directory = 'lib',
  List<DiffLine> lines = const [
    DiffLine(DiffLineType.removed, 3, 'old'),
    DiffLine(DiffLineType.added, 3, 'new'),
  ],
  int? added,
  int? removed,
  String? displayTool,
  bool? writeExisted,
  int? writeLines,
  int? writeBytes,
  int? writeOldLines,
}) => CodeDiffItem(
  fileName: fileName,
  directory: directory,
  lines: lines,
  added: added,
  removed: removed,
  displayTool: displayTool,
  writeExisted: writeExisted,
  writeLines: writeLines,
  writeBytes: writeBytes,
  writeOldLines: writeOldLines,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(800, 1200),
}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('a compact row shows the file, directory and counts', (
    tester,
  ) async {
    await _pump(
      tester,
      EditStep(
        item: _edit(fileName: 'auth.dart', directory: 'lib/services'),
      ),
    );
    expect(find.text('Edited'), findsOneWidget);
    expect(find.text('auth.dart'), findsOneWidget);
    expect(find.text('lib/services'), findsOneWidget);
    expect(find.text('+1 -1', findRichText: true), findsOneWidget);
    expect(find.byType(IdeCodeDiff), findsNothing);
  });

  testWidgets('a new file is Created, with +lines and size', (tester) async {
    await _pump(
      tester,
      EditStep(
        item: _edit(
          fileName: 'note.txt',
          directory: '',
          displayTool: 'write',
          writeExisted: false,
          writeLines: 2,
          writeBytes: 8,
          lines: [
            DiffLine(DiffLineType.added, 1, 'one'),
            DiffLine(DiffLineType.added, 2, 'two'),
          ],
          added: 2,
          removed: 0,
        ),
      ),
    );
    expect(find.text('Created'), findsOneWidget);
    expect(find.text('2 lines'), findsNothing);
    expect(find.text('+2', findRichText: true), findsOneWidget);
    expect(find.text(' · 8 B'), findsOneWidget);
  });

  testWidgets('an overwrite shows old → new line counts', (tester) async {
    await _pump(
      tester,
      EditStep(
        item: _edit(
          displayTool: 'write',
          writeExisted: true,
          writeOldLines: 40,
          writeLines: 48,
          added: 12,
          removed: 4,
        ),
      ),
    );
    expect(find.text('Overwrote'), findsOneWidget);
    expect(find.text('40 → 48 lines'), findsOneWidget);
    expect(find.text('+12 -4', findRichText: true), findsOneWidget);
  });

  testWidgets('consecutive edits of one file share a row marked ×N', (
    tester,
  ) async {
    final first = _edit(added: 2, removed: 1);
    final second = _edit(added: 4, removed: 2);
    final third = _edit(added: 1, removed: 0);
    var expanded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => EditStep(
              item: first,
              also: [second, third],
              expanded: expanded,
              onToggle: () => setState(() => expanded = !expanded),
            ),
          ),
        ),
      ),
    );
    expect(find.text('×3'), findsOneWidget);
    expect(find.text('+7 -3', findRichText: true), findsOneWidget);
    expect(find.byType(IdeCodeDiff), findsNothing);

    await tester.tap(find.text('a.dart'));
    await tester.pump();
    expect(find.byType(IdeCodeDiff), findsNWidgets(3));
  });

  testWidgets('opening a long diff clips it and offers Show all', (
    tester,
  ) async {
    final item = CodeDiffItem(
      fileName: 'a.dart',
      directory: 'lib',
      lines: [
        for (var i = 1; i <= 40; i++)
          DiffLine(DiffLineType.added, i, 'line $i'),
      ],
    );
    await _pump(tester, EditStep(item: item, expanded: true));
    expect(find.text('Show all 40 lines'), findsOneWidget);
    expect(find.byType(StepBody), findsNothing);

    await tester.tap(find.text('Show all 40 lines'));
    await tester.pump();
    expect(find.text('Show all 40 lines'), findsNothing);
    expect(find.byType(StepBody), findsOneWidget);
  });

  testWidgets('a new file opens as highlighted code, not a green diff', (
    tester,
  ) async {
    const item = CodeDiffItem(
      fileName: 'note.txt',
      directory: '',
      displayTool: 'write',
      writeExisted: false,
      writeLines: 2,
      lines: [
        DiffLine(DiffLineType.added, 1, 'one'),
        DiffLine(DiffLineType.added, 2, 'two'),
      ],
    );
    await _pump(tester, const EditStep(item: item, expanded: true));
    final diff = tester.widget<IdeCodeDiff>(find.byType(IdeCodeDiff));
    expect(diff.sideBySide, isFalse);
    expect(diff.original, diff.modified);
    expect(diff.modified, 'one\ntwo');
  });

  test('the sides number their lines as their files do, across hunks', () {
    final sides = DiffSides(const [
      DiffLine(DiffLineType.context, 142, 'a'),
      DiffLine(DiffLineType.removed, 143, 'b'),
      DiffLine(DiffLineType.added, 143, 'B'),
      DiffLine(DiffLineType.added, 144, 'B2'),
      DiffLine(DiffLineType.context, 145, 'c'),
      // The next hunk: one line further on the new side than the old.
      DiffLine(DiffLineType.context, 201, 'd'),
      DiffLine(DiffLineType.removed, 201, 'e'),
      DiffLine(DiffLineType.context, 202, 'f'),
    ]);
    expect(sides.original, 'a\nb\nc\nd\ne\nf');
    expect(sides.modified, 'a\nB\nB2\nc\nd\nf');
    expect(sides.originalNumbers, [142, 143, 144, 200, 201, 202]);
    expect(sides.modifiedNumbers, [142, 143, 144, 145, 201, 202]);
    expect(sides.originalNumberOf(4), 200);
    expect(sides.modifiedNumberOf(2), 143);
    expect(sides.created, isFalse);
    expect(sides.rows, 6);
  });

  test('a new file has nothing on the old side', () {
    final sides = DiffSides(const [
      DiffLine(DiffLineType.added, 1, 'one'),
      DiffLine(DiffLineType.added, 2, 'two'),
    ]);
    expect(sides.created, isTrue);
    expect(sides.original, '');
    expect(sides.modified, 'one\ntwo');
    expect(sides.rows, 2);
  });

  testWidgets('the card shows the diff side by side, as tall as its lines', (
    tester,
  ) async {
    const item = CodeDiffItem(
      fileName: 'a.dart',
      directory: 'lib',
      lines: [
        DiffLine(DiffLineType.context, 10, 'final a = 1;'),
        DiffLine(DiffLineType.removed, 11, 'final b = 2;'),
        DiffLine(DiffLineType.added, 11, 'final b = 3;'),
      ],
    );
    await _pump(tester, const EditStep(item: item, expanded: true));
    final diff = tester.widget<IdeCodeDiff>(find.byType(IdeCodeDiff));
    expect(diff.sideBySide, isTrue);
    expect(diff.embedded, isTrue);
    expect(diff.original, 'final a = 1;\nfinal b = 2;');
    expect(diff.modified, 'final a = 1;\nfinal b = 3;');
    expect(diff.originalLineNumberOf!(2), 11);
    final context = tester.element(find.byType(IdeCodeDiff));
    expect(
      tester.getSize(find.byType(IdeCodeDiff)).height,
      2 * IdeCodeDiff.lineHeight(context),
    );
  });

  group('a card taller than it shows', () {
    final item = CodeDiffItem(
      fileName: 'a.dart',
      directory: 'lib',
      lines: [
        for (var i = 1; i <= 40; i++) ...[
          DiffLine(
            DiffLineType.removed,
            i,
            'final value$i = ${'"${'x' * 120}"'};',
          ),
          DiffLine(
            DiffLineType.added,
            i,
            'final value$i = ${'"${'y' * 120}"'};',
          ),
        ],
      ],
    );

    Future<ScrollController> pumpInList(WidgetTester tester) async {
      final outer = ScrollController();
      addTearDown(outer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: outer,
              children: [
                const SizedBox(height: 100),
                EditStep(item: item, expanded: true),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Show all 40 lines'));
      await tester.pump();
      return outer;
    }

    ScrollPosition inner(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(StepBody),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    testWidgets('keeps the wheel at its end, a new gesture too', (
      tester,
    ) async {
      final outer = await pumpInList(tester);
      final at = tester.getCenter(find.byType(StepBody));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      var clock = const Duration(seconds: 1);
      Future<void> wheel() async {
        clock += const Duration(milliseconds: 50);
        await tester.sendEventToBinding(pointer.hover(at, timeStamp: clock));
        await tester.sendEventToBinding(
          pointer.scroll(const Offset(0, 120), timeStamp: clock),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      for (var i = 0; i < 20; i++) {
        await wheel();
      }
      await tester.pumpAndSettle();
      final position = inner(tester);
      expect(position.pixels, position.maxScrollExtent);
      // A pause, then the wheel again: still the card's.
      clock += const Duration(seconds: 1);
      await wheel();
      await tester.pumpAndSettle();
      expect(outer.offset, 0);
    });
  });

  test('diffstat fills all five squares once the total is 5', () {
    expect(editDiffStatSlots(5, 2), (4, 1));
    expect(editDiffStatSlots(3, 1), (3, 1));
    expect(editDiffStatSlots(4, 0), (4, 0));
    expect(editDiffStatSlots(30, 0), (5, 0));
    expect(editDiffStatSlots(10, 1), (4, 1));
    expect(editDiffStatSlots(1, 1), (1, 1));
    expect(editDiffStatSlots(0, 0), (0, 0));
  });

  testWidgets('card detail starts with the diff open', (tester) async {
    EditDetail.current.value = EditDetail.card;
    addTearDown(() => EditDetail.current.value = EditDetail.compact);
    await _pump(tester, EditStep(item: _edit()));
    expect(find.byType(IdeCodeDiff), findsOneWidget);
  });
}
