import 'package:baocode/chat/composer/file_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SizedBox, TextField, ValueKey;
import 'package:flutter/services.dart' show MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_pdf_preview.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/markdown/markdown_preview.dart';

import 'fake_files.dart';

void main() {
  testWidgets(
    'two ordinary files open side by side and keep their own editor',
    (tester) async {
      final workspace = await pumpWorkbench(
        tester,
        {'a.dart': 'first\n', 'b.dart': 'second\n', 'c.dart': 'third\n'},
        open: ['a.dart', 'b.dart'],
      );
      final state = tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));
      final aTab = find.descendant(
        of: find.byType(IdeTabBar),
        matching: find.text('a.dart'),
      );
      await tester.tapAt(
        tester.getCenter(aTab),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open to the Side'));
      await tester.pumpAndSettle();

      expect(find.byType(IdeEditor), findsNWidgets(2));
      expect(
        [
          for (final editor in tester.widgetList<IdeEditor>(
            find.byType(IdeEditor),
          ))
            editor.active.path,
        ],
        [inRoot('b.dart'), inRoot('a.dart')],
      );
      expect(workspace.active?.path, inRoot('a.dart'));
      final leftWidth = tester.getSize(find.byType(IdeEditor).first).width;
      await tester.drag(
        find.byKey(const ValueKey('ide-editor-split-sash')),
        const Offset(80, 0),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(IdeEditor).first).width,
        greaterThan(leftWidth),
      );
      await tester.enterText(
        find.descendant(
          of: find.byType(IdeEditor).last,
          matching: find.byType(TextField),
        ),
        'right edited\n',
      );
      await tester.pump();
      state.commands
          .firstWhere((command) => command.id == 'workbench.action.files.save')
          .invoke();
      await tester.pumpAndSettle();
      expect(
        (workspace.files as TreeFiles).contents[inRoot('a.dart')],
        'right edited\n',
      );

      await tester.tapAt(tester.getCenter(find.byType(IdeEditor).first));
      await tester.pump();
      expect(workspace.active?.path, inRoot('b.dart'));
      await tester.enterText(
        find.descendant(
          of: find.byType(IdeEditor).first,
          matching: find.byType(TextField),
        ),
        'left edited\n',
      );
      await tester.pump();
      state.commands
          .firstWhere((command) => command.id == 'workbench.action.files.save')
          .invoke();
      await tester.pumpAndSettle();
      expect(
        (workspace.files as TreeFiles).contents[inRoot('b.dart')],
        'left edited\n',
      );
      state.commands
          .firstWhere(
            (command) =>
                command.id == 'workbench.action.focusSecondEditorGroup',
          )
          .invoke();
      await tester.pump();
      expect(workspace.active?.path, inRoot('a.dart'));
      state.commands
          .firstWhere(
            (command) => command.id == 'workbench.action.focusFirstEditorGroup',
          )
          .invoke();
      await tester.pump();
      expect(workspace.active?.path, inRoot('b.dart'));
      await workspace.open(inRoot('c.dart'));
      await tester.pump();
      expect(
        [
          for (final editor in tester.widgetList<IdeEditor>(
            find.byType(IdeEditor),
          ))
            editor.active.path,
        ],
        [inRoot('c.dart'), inRoot('a.dart')],
      );

      state.commands
          .firstWhere((command) => command.id == 'baocode.ide.closeSplitEditor')
          .invoke();
      await tester.pump();
      expect(find.byType(IdeEditor), findsOneWidget);
      expect(workspace.active?.path, inRoot('c.dart'));
    },
  );

  testWidgets('split editors are restored with their files', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.dart': 'a\n', 'b.dart': 'b\n'},
      viewState: {
        'editors': [inRoot('a.dart'), inRoot('b.dart')],
        'active': inRoot('b.dart'),
        'splitEditors': [inRoot('a.dart'), inRoot('b.dart')],
        'splitRightFocused': true,
        'splitRatio': 0.6,
      },
    );
    await tester.pumpAndSettle();
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(workspace.active?.path, inRoot('b.dart'));
  });

  testWidgets('explorer can open another file to the side', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.dart': 'a\n', 'b.dart': 'b\n'},
      open: ['a.dart'],
    );
    final file = find.descendant(
      of: find.byType(IdeExplorer),
      matching: find.text('b.dart'),
    );
    await tester.tapAt(
      tester.getCenter(file),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open to the Side'));
    await tester.pumpAndSettle();
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(workspace.active?.path, inRoot('b.dart'));
  });

  testWidgets('native editor renders both sides', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.dart': 'a\n', 'b.dart': 'b\n'},
      open: ['a.dart', 'b.dart'],
      nativeEditor: true,
    );
    final state = tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));
    state.commands
        .firstWhere(
          (command) => command.id == 'workbench.action.splitEditorRight',
        )
        .invoke();
    workspace.select(inRoot('a.dart'));
    await tester.pump();
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(
      [
        for (final editor in tester.widgetList<IdeEditor>(
          find.byType(IdeEditor),
        ))
          editor.active.path,
      ],
      [inRoot('b.dart'), inRoot('a.dart')],
    );
  });
  testWidgets('a PDF and a markdown file open side by side', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'slides.pdf': '%PDF\x00\x01', 'notes.md': '# Notes\n'},
      open: ['notes.md', 'slides.pdf'],
    );
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IdeExplorer),
          matching: find.text('notes.md'),
        ),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open to the Side'));
    await tester.pumpAndSettle();
    expect(find.byType(IdePdfPreview), findsOneWidget);
    expect(find.byType(IdeMarkdownPreview), findsOneWidget);
    expect(workspace.active?.path, inRoot('notes.md'));

    // Back to the PDF: the split stays.
    await tester.tapAt(tester.getCenter(find.byType(IdePdfPreview)));
    await tester.pumpAndSettle();
    expect(workspace.active?.path, inRoot('slides.pdf'));
    expect(find.byType(IdeMarkdownPreview), findsOneWidget);

    // The right pane's own Preview | Markdown switch.
    await tester.tap(
      find.descendant(
        of: find.byType(MarkdownSwitch),
        matching: find.text('Markdown'),
      ),
    );
    await tester.pumpAndSettle();
    expect(workspace.active?.path, inRoot('notes.md'));
    expect(find.byType(IdeMarkdownPreview), findsNothing);
    expect(find.byType(IdePdfPreview), findsOneWidget);
    expect(
      [
        for (final editor in tester.widgetList<IdeEditor>(
          find.byType(IdeEditor),
        ))
          editor.active.path,
      ],
      [inRoot('notes.md')],
    );
  });
  testWidgets('closing the right split tab leaves the left editor', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.dart': 'a\n', 'b.dart': 'b\n'},
      open: ['a.dart'],
    );
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IdeExplorer),
          matching: find.text('b.dart'),
        ),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open to the Side'));
    await tester.pumpAndSettle();
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(workspace.active?.path, inRoot('b.dart'));

    final state = tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));
    state.commands
        .firstWhere(
          (command) => command.id == 'workbench.action.closeActiveEditor',
        )
        .invoke();
    await tester.pumpAndSettle();
    expect(find.byType(IdeEditor), findsOneWidget);
    expect(workspace.active?.path, inRoot('a.dart'));
    expect(
      [for (final doc in workspace.documents) doc.path],
      [inRoot('a.dart')],
    );
  });

  testWidgets('splitting the same file and closing the right keeps it', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.dart': 'a\n'},
      open: ['a.dart'],
    );
    final state = tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));
    state.commands
        .firstWhere(
          (command) => command.id == 'workbench.action.splitEditorRight',
        )
        .invoke();
    await tester.pump();
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(workspace.documents, hasLength(1));

    state.commands
        .firstWhere(
          (command) => command.id == 'workbench.action.closeActiveEditor',
        )
        .invoke();
    await tester.pumpAndSettle();
    expect(find.byType(IdeEditor), findsOneWidget);
    expect(workspace.active?.path, inRoot('a.dart'));
    expect(workspace.documents, hasLength(1));
  });

  testWidgets('each split group keeps its own tabs', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.dart': 'a\n', 'b.dart': 'b\n', 'c.dart': 'c\n'},
      open: ['a.dart'],
    );
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IdeExplorer),
          matching: find.text('b.dart'),
        ),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open to the Side'));
    await tester.pumpAndSettle();

    await workspace.open(inRoot('c.dart'));
    await tester.pump();
    expect(
      [
        for (final editor in tester.widgetList<IdeEditor>(
          find.byType(IdeEditor),
        ))
          editor.active.path,
      ],
      [inRoot('a.dart'), inRoot('c.dart')],
    );

    final state = tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));
    state.commands
        .firstWhere(
          (command) => command.id == 'workbench.action.closeActiveEditor',
        )
        .invoke();
    await tester.pumpAndSettle();
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(
      [
        for (final editor in tester.widgetList<IdeEditor>(
          find.byType(IdeEditor),
        ))
          editor.active.path,
      ],
      [inRoot('a.dart'), inRoot('b.dart')],
    );
    expect(workspace.active?.path, inRoot('b.dart'));
    expect(workspace.documents.map((doc) => doc.path), [
      inRoot('a.dart'),
      inRoot('b.dart'),
    ]);
  });

  testWidgets('a diff or untitled tab stays in the focused split group', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.dart': 'a\n', 'b.dart': 'b\n'},
      open: ['a.dart'],
    );
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IdeExplorer),
          matching: find.text('b.dart'),
        ),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open to the Side'));
    await tester.pumpAndSettle();
    expect(find.byType(IdeEditor), findsNWidgets(2));

    workspace.newUntitled();
    await tester.pump();
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(workspace.active?.isUntitled, isTrue);
    expect(
      [
        for (final editor in tester.widgetList<IdeEditor>(
          find.byType(IdeEditor),
        ))
          editor.active.isUntitled,
      ],
      [false, true],
    );

    await workspace.openDiff(
      inRoot('b.dart'),
      label: 'b.dart (HEAD)',
      original: () async => 'old\n',
    );
    await tester.pump();
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(workspace.active?.diff, isNotNull);
    expect(
      [
        for (final editor in tester.widgetList<IdeEditor>(
          find.byType(IdeEditor),
        ))
          editor.active.diff != null,
      ],
      [false, true],
    );
  });

  testWidgets('Close Split closes tabs only in the right group', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.dart': 'a\n', 'b.dart': 'b\n'},
      open: ['a.dart'],
    );
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IdeExplorer),
          matching: find.text('b.dart'),
        ),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open to the Side'));
    await tester.pumpAndSettle();
    expect(
      [for (final doc in workspace.documents) doc.path],
      [inRoot('a.dart'), inRoot('b.dart')],
    );

    final state = tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));
    state.commands
        .firstWhere((command) => command.id == 'baocode.ide.closeSplitEditor')
        .invoke();
    await tester.pumpAndSettle();
    expect(find.byType(IdeEditor), findsOneWidget);
    expect(workspace.active?.path, inRoot('a.dart'));
    expect(
      [for (final doc in workspace.documents) doc.path],
      [inRoot('a.dart')],
    );
  });

  testWidgets('close-other commands apply to the active split group', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.dart': 'a\n', 'b.dart': 'b\n', 'c.dart': 'c\n'},
      open: ['a.dart'],
    );
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IdeExplorer),
          matching: find.text('b.dart'),
        ),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open to the Side'));
    await tester.pumpAndSettle();

    IdeCommand command(String id) => tester
        .state<IdeWorkbenchState>(find.byType(IdeWorkbench))
        .commands
        .firstWhere((item) => item.id == id);

    expect(command('workbench.action.closeOtherEditors').enabled, isFalse);
    expect(command('workbench.action.closeEditorsToTheRight').enabled, isFalse);

    await workspace.open(inRoot('c.dart'));
    await tester.pump();
    expect(command('workbench.action.closeOtherEditors').enabled, isTrue);
    expect(command('workbench.action.closeEditorsToTheRight').enabled, isFalse);

    await tester.tap(
      find.descendant(
        of: find.byType(IdeTabBar).last,
        matching: find.text('b.dart'),
      ),
    );
    await tester.pump();
    expect(workspace.active?.path, inRoot('b.dart'));
    expect(command('workbench.action.closeEditorsToTheRight').enabled, isTrue);
    command('workbench.action.closeEditorsToTheRight').invoke();
    await tester.pumpAndSettle();
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(
      [for (final doc in workspace.documents) doc.path],
      [inRoot('a.dart'), inRoot('b.dart')],
    );

    workspace.edit(inRoot('b.dart'), 'dirty\n');
    await workspace.open(inRoot('c.dart'));
    await tester.pump();
    expect(command('workbench.action.closeUnmodifiedEditors').enabled, isTrue);
    command('workbench.action.closeUnmodifiedEditors').invoke();
    await tester.pumpAndSettle();
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(workspace.active?.path, inRoot('b.dart'));
    expect(
      [for (final doc in workspace.documents) doc.path],
      [inRoot('a.dart'), inRoot('b.dart')],
    );
    expect(command('workbench.action.closeOtherEditors').enabled, isFalse);
  });

  testWidgets('a file dropped on the right pane goes in its document', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      {
        'a.md': '# Alpha\n\nText a.\n',
        'b.md': '# Beta\n\nText b.\n',
        '../elsewhere/shot.png': 'png',
      },
      open: ['a.md', 'b.md'],
    );
    final state = tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IdeTabBar),
          matching: find.text('a.md'),
        ),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open to the Side'));
    await tester.pumpAndSettle();
    // The left pane in front.
    state.commands
        .firstWhere(
          (command) => command.id == 'workbench.action.focusFirstEditorGroup',
        )
        .invoke();
    await tester.pumpAndSettle();
    expect(workspace.active?.path, inRoot('b.md'));

    final at = tester.getCenter(find.text('Alpha', findRichText: true));
    final taken = await tester.runAsync(
      () => FileDrops.handle(
        MethodCall('drop', {
          'x': at.dx,
          'y': at.dy,
          'files': [
            {'path': inRoot('../elsewhere/shot.png')},
          ],
        }),
      ),
    );
    expect(taken, isTrue);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final docs = {for (final doc in workspace.documents) doc.path: doc.text};
    expect(docs[inRoot('a.md')], '# Alpha\n\n![](shot.png)\n\nText a.\n');
    expect(docs[inRoot('b.md')], '# Beta\n\nText b.\n');
  });

  testWidgets('a split is kept and comes back with its groups', (tester) async {
    final kept = <Map<String, Object?>>[];
    await pumpWorkbench(
      tester,
      {'a.dart': 'a\n', 'b.dart': 'b\n', 'c.dart': 'c\n'},
      open: ['a.dart', 'b.dart'],
      onViewState: kept.add,
    );
    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(IdeExplorer),
          matching: find.text('c.dart'),
        ),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open to the Side'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('ide-editor-split-sash')),
      const Offset(80, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final saved = kept.last;
    expect(saved['splitEditors'], [inRoot('b.dart'), inRoot('c.dart')]);
    expect(saved['splitLeft'], [inRoot('a.dart'), inRoot('b.dart')]);
    expect(saved['splitRight'], [inRoot('c.dart')]);
    expect(saved['splitRightFocused'], isTrue);
    expect(saved['splitRatio'], greaterThan(0.5));
    expect(saved['active'], inRoot('c.dart'));

    // The same widget type would update the workbench already in the tree,
    // which restores its view once, as it is made.
    await tester.pumpWidget(const SizedBox());
    final restored = await pumpWorkbench(tester, {
      'a.dart': 'a\n',
      'b.dart': 'b\n',
      'c.dart': 'c\n',
    }, viewState: saved);
    await tester.pumpAndSettle();
    expect(restored.active?.path, inRoot('c.dart'));
    expect(find.byType(IdeEditor), findsNWidgets(2));
    expect(
      [
        for (final editor in tester.widgetList<IdeEditor>(
          find.byType(IdeEditor),
        ))
          editor.active.path,
      ],
      [inRoot('b.dart'), inRoot('c.dart')],
    );
    final bars = tester.widgetList<IdeTabBar>(find.byType(IdeTabBar)).toList();
    expect(
      [for (final doc in bars[0].documents) doc.path],
      [inRoot('a.dart'), inRoot('b.dart')],
    );
    expect(bars[0].active?.path, inRoot('b.dart'));
    expect([for (final doc in bars[1].documents) doc.path], [inRoot('c.dart')]);
    expect(bars[1].active?.path, inRoot('c.dart'));
  });
}
