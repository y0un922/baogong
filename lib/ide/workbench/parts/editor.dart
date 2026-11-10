// The editor part (upstream editorPart.ts): the tabs, the breadcrumbs
// and the editor in front, a pane of the registry's (see
// EditorPaneRegistry) or the text editor; the start page or the welcome
// with none. Two groups sit side by side when the editor is split. Built
// again as the workspace's editors and the services that decorate them
// change.

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../debug/ui/debug_toolbar.dart';
import '../../../keybindings/keybinding_service.dart';
import '../../../theme/workbench_theme.dart';
import '../../../workspace/islands.dart';
import '../../file_service.dart';
import '../../ide_workspace.dart';
import '../../ide_agent_edits.dart';
import '../../ide_breadcrumbs.dart';
import '../../ide_commands.dart';
import '../../ide_editor.dart';
import '../../ide_tab_bar.dart';
import '../../ide_welcome.dart';
import '../../services/commands.dart';
import '../../services/configuration.dart';
import '../../services/debug_view.dart';
import '../../services/editor_groups.dart';
import '../../services/editors.dart';
import '../../services/explorer.dart';
import '../../services/extensions_view.dart';
import '../../services/keybindings.dart';
import '../../services/language.dart';
import '../../services/markdown_preview.dart';
import '../../services/quick_input.dart';
import '../../services/references.dart';
import '../../services/scm_service.dart';
import '../contributions.dart';
import '../editor_panes.dart';
import '../options.dart';
import '../services.dart';
import '../style.dart';
import 'extensions.dart';
import 'sash.dart';

class EditorPart extends StatelessWidget {
  const EditorPart({super.key, required this.options});

  final WorkbenchOptions options;

  @override
  Widget build(BuildContext context) {
    final services = WorkbenchScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        options.workspace,
        services.get<EditorService>(),
        services.get<EditorGroupsService>(),
        services.get<ExtensionsViewService>(),
        services.get<MarkdownPreviewService>(),
        services.get<DebugViewService>(),
        services.get<ConfigurationService>(),
        KeybindingService.instance,
      ]),
      builder: (context, _) => _area(context, services),
    );
  }

  Widget _area(BuildContext context, WorkbenchServices services) {
    final groups = services.get<EditorGroupsService>();
    final pageShown = services.get<ExtensionsViewService>().pageShown;
    // An extension's page takes the part; the split stays, just hidden.
    final split = groups.hasSplit && !pageShown;
    final left = _group(context, services, right: false);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: WorkbenchStyle.gap / 2),
      child: HeadedIsland(
        header: IdeTabStrip.height,
        color: themeColors['editor.background'],
        child: split
            ? _EditorSplit(
                groups: groups,
                left: _side(groups, right: false, child: left),
                right: _side(
                  groups,
                  right: true,
                  child: _group(context, services, right: true),
                ),
              )
            : left,
      ),
    );
  }

  /// A pointer in the group focuses it.
  Widget _side(
    EditorGroupsService groups, {
    required bool right,
    required Widget child,
  }) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => groups.focusSide(right),
    child: child,
  );

  /// One group's tabs and the document they show. The only group, when
  /// the editor is not split ([right] false).
  Widget _group(
    BuildContext context,
    WorkbenchServices services, {
    required bool right,
  }) {
    final workspace = options.workspace;
    final editors = services.get<EditorService>();
    final groups = services.get<EditorGroupsService>();
    final extensions = services.get<ExtensionsViewService>();
    final markdown = services.get<MarkdownPreviewService>();
    final language = services.get<LanguageService>();
    final active = groups.paneDocument(right: right);
    final page = right ? null : extensions.page;
    final pageShown = !right && extensions.pageShown;
    final debug = services.get<DebugViewService>().service;
    final local = workspace.files is! IdeHostFiles;
    // The start page's and the welcome's commands, as the palette has them.
    final commands = !right && active == null
        ? services.get<CommandService>().palette()
        : const <IdeCommand>[];
    final dockedToolbar =
        !right && debug != null && debug.settings().toolBarLocation == 'docked';
    final documents = groups.documents(right: right);
    // Its tabs on the window's color over its card; their row there with
    // none, the card's top where the side bar's and the chat's are.
    final tabs = documents.isNotEmpty || page != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!tabs) ...[
          // Not islands, no row: nothing over the editor's part.
          if (WorkbenchStyle.islands)
            const SizedBox(height: IdeTabStrip.height),
          if (dockedToolbar) DebugToolbar(service: debug),
        ],
        if (tabs) ...[
          IdeTabBar(
            documents: documents,
            active: pageShown ? null : active,
            root: workspace.root,
            onSelect: (doc) {
              if (groups.hasSplit) groups.focusSide(right);
              unawaited(editors.select(doc));
            },
            onClose: (doc) => unawaited(editors.closeTabs([doc], right: right)),
            onAction: (doc, action) =>
                editors.tabAction(doc, action, right: right),
            onMove: (doc, index) => groups.move(doc, index, right: right),
            local: local,
            markdownPreview:
                !pageShown && active != null && markdown.hasPreview(active)
                ? markdown.previewing(active)
                : null,
            onMarkdownPreview: (preview) {
              if (groups.hasSplit && !groups.isFocused(right)) {
                groups.focusSide(right);
              }
              unawaited(markdown.setPreview(preview));
            },
            page: page == null ? null : ExtensionPageTab(service: extensions),
            actions: right
                ? null
                : switch (options.agentEdits) {
                    final edits? when !pageShown && active != null =>
                      ListenableBuilder(
                        listenable: edits,
                        builder: (context, _) =>
                            switch (edits.of(active.path)) {
                              final edit? when active.diff == null =>
                                IdeAgentEditActions(
                                  edit: edit,
                                  hunks: edits.hunksOf(active.path),
                                ),
                              _ => const SizedBox.shrink(),
                            },
                      ),
                    _ => null,
                  },
          ),
          // On the card, under the tabs.
          if (dockedToolbar) DebugToolbar(service: debug),
          if (!pageShown && active != null && !active.isUntitled)
            ListenableBuilder(
              listenable: Listenable.merge([editors.caret, language]),
              builder: (context, _) => IdeBreadcrumbs(
                root: workspace.root,
                path: active.path,
                onReveal: services.get<ExplorerService>().reveal,
                symbols: groups.isFocused(right)
                    ? language.symbolPath
                    : const [],
                onSymbol: language.revealSymbol,
              ),
            ),
        ],
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The editors stay built under an extension's page.
              Offstage(
                offstage: pageShown,
                child: markdown.drops(
                  active,
                  right && active == null
                      ? const SizedBox.shrink()
                      : active == null && !workspace.hasFolder
                      ? IdeStartPage(
                          actions: [
                            for (final id in const [
                              'workbench.action.files.openFolder',
                              'git.clone',
                              'baocode.remote.openFolder',
                              WorkbenchOptions.createWorkspaceCommandId,
                              'workbench.action.files.openFile',
                              'workbench.action.files.newUntitledFile',
                            ])
                              ...commands.where((command) => command.id == id),
                          ],
                          recent: options.recentFolders,
                          onOpenRecent: options.onOpenRecent,
                          workspaceOf: options.recentWorkspaceOf,
                          onShowAllRecent: commands
                              .where(
                                (c) => c.id == 'workbench.action.openRecent',
                              )
                              .firstOrNull
                              ?.run,
                        )
                      : active == null
                      ? IdeWelcome(
                          commands: [
                            for (final id in const [
                              'workbench.action.showCommands',
                              'workbench.action.quickOpen',
                              // Upstream's watermark: Show Search has no key of
                              // its own, Find in Files takes its ⇧⌘F.
                              'workbench.action.findInFiles',
                              'actions.find',
                              'workbench.action.gotoLine',
                              'workbench.action.toggleSidebarVisibility',
                              'workbench.action.toggleAuxiliaryBar',
                            ])
                              ...commands.where((command) => command.id == id),
                          ],
                        )
                      // A pane of its own (a file view, an image, a
                      // preview), else the text editor.
                      : _document(context, services, active, right: right),
                  right: right,
                ),
              ),
              // And it under them, while another tab is in front.
              if (page != null)
                Offstage(
                  offstage: !pageShown,
                  child: ExtensionPageView(service: extensions),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// What shows [doc]: a pane of the registry's, or the text editor. The
  /// left group keeps [WorkbenchOptions.editorBuilder].
  Widget _document(
    BuildContext context,
    WorkbenchServices services,
    IdeDocument doc, {
    required bool right,
  }) {
    final workspace = options.workspace;
    final host = services.get<WorkbenchHost>();
    final editors = services.get<EditorService>();
    final groups = services.get<EditorGroupsService>();
    final markdown = services.get<MarkdownPreviewService>();
    final config = services.get<ConfigurationService>();
    final scm = services.get<ScmService>();
    final pane = services.get<EditorPaneRegistry>().paneFor(doc);
    if (pane != null) {
      return EditorGroupSide(
        right: right,
        child: Builder(builder: (context) => pane.build(context, doc)),
      );
    }
    if (!right) {
      final built = options.editorBuilder?.call(context, workspace);
      if (built != null) return built;
    }
    return IdeEditor(
      nativeEditorEnabled: options.nativeEditorEnabled,
      key: groups.editorKey(right: right),
      workspace: workspace,
      active: doc,
      onError: host.report,
      onLspStatus: (_) {},
      onPositionChanged: (position) {
        if (groups.isFocused(right)) editors.positionChanged(position);
      },
      onScrolled: () {
        if (groups.isFocused(right)) editors.viewChanged();
      },
      // Go to Definition's target (F12), centered even when already in view.
      onOpenLocation: (location) =>
          editors.openLocation(location, center: true),
      onShowReferences: services.get<ReferencesService>().show,
      onShowCommands: () => services.get<QuickInputService>().show('>'),
      gitBlame: config.gitBlame,
      onShowCommit: scm.showCommitInLog,
      onShowHistory: scm.showHistory,
      onCompare: (path, what) => unawaited(scm.compareWith(path, what)),
      keyResolver: services.get<KeybindingDispatchService>().resolveEditorKey,
      onPaste: markdown.pasteInEditor,
      formatOnSave: config.formatOnSave,
      debug: services.get<DebugViewService>().service,
      agentEdits: options.agentEdits,
    );
  }
}

/// The two groups and the sash between them. The ratio at the drag's start
/// is kept here: the sash reports how far the pointer has moved in all.
class _EditorSplit extends StatefulWidget {
  const _EditorSplit({
    required this.groups,
    required this.left,
    required this.right,
  });

  final EditorGroupsService groups;
  final Widget left;
  final Widget right;

  @override
  State<_EditorSplit> createState() => _EditorSplitState();
}

class _EditorSplitState extends State<_EditorSplit> {
  double _from = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sash = WorkbenchStyle.sashWidth;
        final available = math.max(0.0, constraints.maxWidth - sash);
        if (available < 1) return widget.left;
        final minimum = math.min(160.0, available / 2);
        final leftWidth = (available * widget.groups.ratio)
            .clamp(minimum, math.max(minimum, available - minimum))
            .toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: leftWidth, child: widget.left),
            WorkbenchSash(
              key: const ValueKey('ide-editor-split-sash'),
              onStart: () => _from = widget.groups.ratio,
              onDrag: (dx) => widget.groups.setRatio(_from + dx / available),
              onReset: () => widget.groups.setRatio(0.5),
            ),
            Expanded(child: widget.right),
          ],
        );
      },
    );
  }
}
