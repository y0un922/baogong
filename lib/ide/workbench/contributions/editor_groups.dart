// The editor groups' commands (upstream editorActions.ts: Split Editor,
// Close Split, Focus Second Editor Group) over EditorGroupsService, and
// the context keys a keybinding's `when` reads for them.

import 'dart:async';

import '../../ide_workspace.dart';
import '../../services/editor_groups.dart';
import '../../services/editors.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';

class EditorGroupsContribution extends WorkbenchRegistrations {
  EditorGroupsContribution(WorkbenchServices services) {
    final groups = services.get<EditorGroupsService>();
    final editors = services.get<EditorService>();
    IdeDocument? active() => services.find<IdeWorkspace>()?.active;

    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'workbench.action.splitEditorRight',
          category: 'View',
          title: 'Open to the Side',
          precondition: (_) => active()?.isFileTab ?? false,
          run: (_, _) {
            if (active() case final doc?) groups.openDocumentToSide(doc);
          },
        ),
        WorkbenchAction(
          id: 'baocode.ide.closeSplitEditor',
          category: 'View',
          title: 'Close Split Editor',
          precondition: (_) => groups.hasSplit,
          run: (_, _) => unawaited(editors.closeSplit()),
        ),
        WorkbenchAction(
          id: 'workbench.action.focusSecondEditorGroup',
          category: 'View',
          title: 'Focus Right Editor',
          precondition: (_) => groups.hasSplit,
          run: (_, _) {
            groups.focusSide(true);
            editors.focusEditorOrWorkbench();
          },
        ),
      ]),
    );
    add(
      services.get<ContextKeyService>().addProvider(
        (key) => switch (key) {
          'multipleEditorGroups' => groups.hasSplit,
          'activeEditorGroupIndex' =>
            groups.hasSplit && groups.rightFocused ? 1 : 0,
          _ => null,
        },
      ),
    );
  }
}
