// The editor's two groups (upstream editor groups, one beside the other):
// each keeps its own tabs. With one group, the tabs are the workspace's.
// A file closes in the workspace only once no group has it. Opened with
// the layout (see WorkbenchStorage).

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ide_editor.dart';
import '../ide_workspace.dart';
import '../workbench/storage.dart';

/// The tabs of one side, and which side is in front.
class EditorGroupsService extends ChangeNotifier
    implements WorkbenchStorageParticipant {
  EditorGroupsService({
    required this._workspace,
    required this._ready,
    required this._closing,
    this.storage,
  });

  final IdeWorkspace Function() _workspace;

  /// The workbench is in the tree (a close asks about unsaved files).
  final bool Function() _ready;

  /// Editors are closing: the document that comes to the front for it is
  /// not one opened into the group in front.
  final bool Function() _closing;

  /// Where the split is kept with the window.
  final WorkbenchStorage? storage;

  /// The text editor of each side. [EditorService.editor] is the focused
  /// one's.
  final leftEditorKey = GlobalKey<IdeEditorState>();
  final rightEditorKey = GlobalKey<IdeEditorState>();

  final List<IdeDocument> _leftGroup = [];
  final List<IdeDocument> _rightGroup = [];
  IdeDocument? _splitLeft;
  IdeDocument? _splitRight;
  bool _rightFocused = false;
  double _ratio = 0.5;

  /// Hides an extension's page when a file is brought to the front. The
  /// editors are made after this service.
  VoidCallback? _shown;

  /// An editor is opening or closing.
  bool Function()? _busy;

  IdeWorkspace? _attached;
  String? _seenActive;
  bool _suspend = false;

  /// The split read from the window, applied once its files are open
  /// ([finishRestore]).
  Map<String, Object?>? _pending;

  static const minRatio = 0.15;
  static const maxRatio = 0.85;

  IdeWorkspace get _ws => _workspace();

  /// [shown] hides an extension's page; [busy] while an editor opens.
  void bind({required VoidCallback shown, required bool Function() busy}) {
    _shown = shown;
    _busy = busy;
  }

  /// Follows [workspace]'s documents until [detach].
  void attach(IdeWorkspace workspace) {
    if (identical(_attached, workspace)) return;
    detach();
    _attached = workspace;
    _seenActive = workspace.active?.key;
    workspace.addListener(_onWorkspace);
  }

  void detach() {
    _attached?.removeListener(_onWorkspace);
    _attached = null;
    _clear();
  }

  /// A second group is open.
  bool get hasSplit => _splitRight != null;

  /// The right group is the one in front.
  bool get rightFocused => hasSplit && _rightFocused;

  /// The left group's share of the editor width, from [minRatio] to
  /// [maxRatio].
  double get ratio => _ratio;

  /// [right] is the group in front (the only one, when there is no split).
  bool isFocused(bool right) => hasSplit ? _rightFocused == right : !right;

  GlobalKey<IdeEditorState> editorKey({required bool right}) =>
      right ? rightEditorKey : leftEditorKey;

  IdeEditorState? editorFor({required bool right}) =>
      editorKey(right: right).currentState;

  /// The text editor in front.
  IdeEditorState? get focusedEditor =>
      editorFor(right: hasSplit && _rightFocused);

  /// The tabs [right] shows: every document, with no split, on the left.
  List<IdeDocument> documents({required bool right}) {
    if (!hasSplit) return right ? const [] : _ws.documents;
    return _liveGroup(right ? _rightGroup : _leftGroup);
  }

  /// The tabs of the group in front.
  List<IdeDocument> get activeDocuments =>
      documents(right: hasSplit && _rightFocused);

  /// The document [right] shows.
  IdeDocument? paneDocument({required bool right}) {
    if (!hasSplit) return right ? null : _ws.active;
    return _live(right ? _splitRight : _splitLeft);
  }

  void keepViewStates() {
    leftEditorKey.currentState?.keepViewStates();
    rightEditorKey.currentState?.keepViewStates();
  }

  /// Both editors' changes written back, the one in front last.
  Future<void> flush() async {
    final right = hasSplit && _rightFocused;
    if (hasSplit) await editorFor(right: !right)?.flush();
    await focusedEditor?.flush();
  }

  void setRatio(double value) {
    final next = value.clamp(minRatio, maxRatio).toDouble();
    if (next == _ratio) return;
    _ratio = next;
    notifyListeners();
    storage?.changed();
  }

  /// The keyboard and the active document to the left, or the right.
  void focusSide(bool right) {
    if (!hasSplit || _rightFocused == right) return;
    unawaited(focusedEditor?.flush());
    _rightFocused = right;
    final document = paneDocument(right: right);
    notifyListeners();
    if (document != null && _ws.active?.key != document.key) {
      _seenActive = document.key;
      _ws.select(document.key);
    }
    storage?.changed();
  }

  /// [document] in the group to the right of the one in front. A file's
  /// own tab (see [IdeDocument.isFileTab]); nothing otherwise.
  void openDocumentToSide(IdeDocument document) {
    if (_busy?.call() ?? false) return;
    final left = _live(_splitLeft) ?? _ws.active;
    if (!document.isFileTab || left == null || !left.isFileTab) return;
    unawaited(flush());
    if (!hasSplit) {
      _leftGroup
        ..clear()
        ..addAll([
          for (final doc in _ws.documents)
            if (doc.isFileTab) doc,
        ]);
    }
    _add(_leftGroup, left);
    _add(_rightGroup, document);
    _splitLeft = _live(left) ?? left;
    _splitRight = document;
    _rightFocused = true;
    _seenActive = document.key;
    notifyListeners();
    storage?.changed();
    // Synchronous: a caller may select another file before a later task
    // would (the split command, then the focused group's next file).
    _shown?.call();
    if (_ws.active?.key != document.key) _ws.select(document.key);
  }

  /// Opens [path] into the right group. With nothing on the left to keep
  /// beside it, opens it as usual.
  Future<void> openPath(
    String path,
    Future<void> Function(String path) open,
  ) async {
    if (_busy?.call() ?? false) return;
    final left = _live(_splitLeft) ?? _ws.active;
    if (left == null || !left.isFileTab) {
      await open(path);
      return;
    }
    final creating = !hasSplit;
    final existed = _ws.documents.any(
      (doc) => doc.path == path || doc.key == path,
    );
    if (creating) {
      _leftGroup
        ..clear()
        ..addAll([
          for (final doc in _ws.documents)
            if (doc.isFileTab) doc,
        ]);
    } else {
      _rightFocused = true;
    }
    await open(path);
    if (!_ready()) return;
    final right = _ws.active;
    if (right == null || !right.isFileTab) {
      if (creating) _leftGroup.clear();
      notifyListeners();
      return;
    }
    if (creating && !existed) {
      _leftGroup.removeWhere((doc) => doc.key == right.key);
    }
    _add(_leftGroup, left);
    _add(_rightGroup, right);
    _splitLeft = _live(left) ?? _leftGroup.firstOrNull ?? left;
    _splitRight = right;
    _rightFocused = true;
    _seenActive = right.key;
    notifyListeners();
    storage?.changed();
  }

  /// Closes the right group: its tabs, and the documents no other group
  /// has. One group again.
  Future<void> closeSplit(
    Future<void> Function(List<IdeDocument> docs) closeDocuments,
  ) async {
    if (!hasSplit) return;
    await flush();
    keepViewStates();
    await closeInGroup(
      _liveGroup(_rightGroup),
      right: true,
      closeDocuments: closeDocuments,
    );
  }

  /// Closes [docs] in the group [right]. One the other group does not have
  /// closes in the workspace ([closeDocuments]); Cancel leaves it.
  Future<void> closeInGroup(
    List<IdeDocument> docs, {
    required bool right,
    required Future<void> Function(List<IdeDocument> docs) closeDocuments,
  }) async {
    if (!hasSplit) {
      await closeDocuments(docs);
      return;
    }
    final group = right ? _rightGroup : _leftGroup;
    final other = right ? _leftGroup : _rightGroup;
    final closing = [
      for (final doc in docs)
        if (_inGroup(group, doc)) doc,
    ];
    if (closing.isEmpty) return;

    var shown = _live(right ? _splitRight : _splitLeft);
    final before = _liveGroup(group);
    final gone = [
      for (final doc in closing)
        if (!_inGroup(other, doc)) doc,
    ];
    _suspend = true;
    try {
      if (gone.isNotEmpty) {
        await closeDocuments(gone);
        if (!_ready()) return;
      }
      final open = {for (final doc in _ws.documents) doc.key};
      for (final doc in closing) {
        // Still open, and not on the other side: the close was cancelled.
        if (open.contains(doc.key) && !_inGroup(other, doc)) continue;
        group.removeWhere((d) => d.key == doc.key);
      }
      final remaining = _liveGroup(group);
      if (shown != null && !_inGroup(remaining, shown)) {
        shown = remaining.isEmpty
            ? null
            : before
                      .skipWhile((d) => d.key != shown!.key)
                      .skip(1)
                      .firstOrNull ??
                  remaining.last;
        if (shown != null && !_inGroup(remaining, shown)) {
          shown = remaining.firstOrNull;
        }
      }
      if (right) {
        _splitRight = shown;
      } else {
        _splitLeft = shown;
      }
      final focus = remaining.isEmpty
          ? (right ? _live(_splitLeft) : _live(_splitRight))
          : shown;
      if (remaining.isEmpty) _clear();
      _seenActive = focus?.key;
      notifyListeners();
      if (focus != null &&
          _ws.active?.key != focus.key &&
          _ws.documents.any((d) => d.key == focus.key)) {
        _ws.select(focus.key);
      }
    } finally {
      _suspend = false;
    }
    storage?.changed();
  }

  /// [doc] to [index] in its group (among the workspace's, with no split).
  void move(IdeDocument doc, int index, {required bool right}) {
    if (!hasSplit) {
      _ws.moveDocument(doc, index);
      return;
    }
    final group = right ? _rightGroup : _leftGroup;
    final from = group.indexWhere((d) => d.key == doc.key);
    if (from < 0) return;
    group
      ..removeAt(from)
      ..insert(index.clamp(0, group.length), doc);
    notifyListeners();
    storage?.changed();
  }

  void _onWorkspace() {
    if (!hasSplit || _suspend) return;
    final beforeLeft = [for (final doc in _leftGroup) doc.key];
    final beforeRight = [for (final doc in _rightGroup) doc.key];
    final beforeLeftActive = _splitLeft?.key;
    final beforeRightActive = _splitRight?.key;
    _refresh();
    if (!hasSplit) {
      notifyListeners();
      storage?.changed();
      return;
    }
    final active = _ws.active;
    if (active != null && active.key != _seenActive && !_closing()) {
      if (_rightFocused) {
        _add(_rightGroup, active);
        _splitRight = active;
      } else {
        _add(_leftGroup, active);
        _splitLeft = active;
      }
    }
    _seenActive = active?.key;
    final changed =
        !_keysEqual(beforeLeft, _leftGroup) ||
        !_keysEqual(beforeRight, _rightGroup) ||
        beforeLeftActive != _splitLeft?.key ||
        beforeRightActive != _splitRight?.key;
    if (!changed) return;
    notifyListeners();
    storage?.changed();
  }

  void _refresh() {
    final left = _liveGroup(_leftGroup);
    final right = _liveGroup(_rightGroup);
    _leftGroup
      ..clear()
      ..addAll(left);
    _rightGroup
      ..clear()
      ..addAll(right);
    _splitLeft = _live(_splitLeft);
    _splitRight = _live(_splitRight);
    if (_leftGroup.isEmpty || _rightGroup.isEmpty) {
      _clear();
      return;
    }
    _splitLeft ??= _leftGroup.first;
    _splitRight ??= _rightGroup.first;
  }

  void _clear() {
    _leftGroup.clear();
    _rightGroup.clear();
    _splitLeft = null;
    _splitRight = null;
    _rightFocused = false;
  }

  IdeDocument? _live(IdeDocument? document) {
    if (document == null) return null;
    final docs = _ws.documents;
    if (docs.contains(document)) return document;
    return docs
        .where(
          (candidate) =>
              candidate.key == document.key ||
              (candidate.label == document.label &&
                  identical(candidate.model, document.model)),
        )
        .firstOrNull;
  }

  List<IdeDocument> _liveGroup(List<IdeDocument> group) {
    final live = <IdeDocument>[];
    final seen = <String>{};
    for (final doc in group) {
      final next = _live(doc);
      if (next == null || !seen.add(next.key)) continue;
      live.add(next);
    }
    return live;
  }

  bool _inGroup(List<IdeDocument> group, IdeDocument doc) =>
      group.any((d) => d.key == doc.key);

  void _add(List<IdeDocument> group, IdeDocument doc) {
    if (!_inGroup(group, doc)) group.add(doc);
  }

  bool _keysEqual(List<String> keys, List<IdeDocument> group) {
    if (keys.length != group.length) return false;
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] != group[i].key) return false;
    }
    return true;
  }

  IdeDocument? _fileAt(String path) => _ws.documents
      .where((doc) => doc.path == path && doc.isFileTab)
      .firstOrNull;

  List<IdeDocument> _files(List<String> paths) {
    final out = <IdeDocument>[];
    final seen = <String>{};
    for (final path in paths) {
      final doc = _fileAt(path);
      if (doc == null || !seen.add(doc.key)) continue;
      out.add(doc);
    }
    return out;
  }

  /// Reads the split, applied once the editors it names are open again
  /// ([finishRestore]).
  @override
  void restoreState(Map<String, Object?> kept) {
    if (kept['splitEditors'] case [final String _, final String _]) {
      _pending = kept;
    }
  }

  /// The split [restoreState] read, now that its files are open.
  /// `splitEditors` is the two shown paths; `splitLeft` and `splitRight`
  /// are each group's files. With either list empty, the right group is
  /// the right path and the left group is the other file tabs.
  void finishRestore() {
    final kept = _pending;
    _pending = null;
    if (kept == null) return;
    if (kept['splitEditors'] case [
      final String leftPath,
      final String rightPath,
    ]) {
      final left = _fileAt(leftPath);
      final right = _fileAt(rightPath);
      if (left == null || right == null) return;
      var leftGroup = _files(_paths(kept['splitLeft']));
      var rightGroup = _files(_paths(kept['splitRight']));
      if (leftGroup.isEmpty || rightGroup.isEmpty) {
        rightGroup = [right];
        leftGroup = [
          for (final doc in _ws.documents)
            if (doc.isFileTab &&
                (doc.path != right.path || identical(doc, left)))
              doc,
        ];
        if (leftGroup.isEmpty) leftGroup = [left];
      }
      _add(leftGroup, left);
      _add(rightGroup, right);
      final ratio = switch (kept['splitRatio']) {
        final num value => value.toDouble(),
        _ => 0.5,
      };
      _install(
        leftGroup: leftGroup,
        rightGroup: rightGroup,
        left: left,
        right: right,
        rightFocused: kept['splitRightFocused'] == true,
        ratio: ratio,
      );
    }
  }

  void _install({
    required List<IdeDocument> leftGroup,
    required List<IdeDocument> rightGroup,
    required IdeDocument left,
    required IdeDocument right,
    required bool rightFocused,
    required double ratio,
  }) {
    _suspend = true;
    _leftGroup
      ..clear()
      ..addAll(leftGroup);
    _rightGroup
      ..clear()
      ..addAll(rightGroup);
    _splitLeft = left;
    _splitRight = right;
    _rightFocused = rightFocused;
    _ratio = ratio.clamp(minRatio, maxRatio).toDouble();
    final focus = rightFocused ? right : left;
    _seenActive = focus.key;
    _suspend = false;
    notifyListeners();
    if (_ws.active?.key != focus.key) _ws.select(focus.key);
    storage?.changed();
  }

  @override
  void saveState(Map<String, Object?> into) {
    if (!hasSplit) return;
    final leftFiles = [
      for (final doc in _liveGroup(_leftGroup))
        if (doc.isFileTab) doc.path,
    ];
    final rightFiles = [
      for (final doc in _liveGroup(_rightGroup))
        if (doc.isFileTab) doc.path,
    ];
    final left = _live(_splitLeft);
    final right = _live(_splitRight);
    if (left == null ||
        right == null ||
        leftFiles.isEmpty ||
        rightFiles.isEmpty) {
      return;
    }
    // The two files in front, then each group's files.
    into['splitEditors'] = [
      left.isFileTab ? left.path : leftFiles.first,
      right.isFileTab ? right.path : rightFiles.first,
    ];
    into['splitLeft'] = leftFiles;
    into['splitRight'] = rightFiles;
    into['splitRightFocused'] = _rightFocused;
    into['splitRatio'] = _ratio;
  }

  static List<String> _paths(Object? value) => switch (value) {
    final List<Object?> paths => paths.whereType<String>().toList(),
    _ => const [],
  };

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
