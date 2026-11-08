import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../theme/workbench_theme.dart' show themeColors;
import 'file_service.dart';
import 'ide_editor_placeholder.dart';

/// [path]'s pages, one under another, to scroll and zoom. PDFium, loaded
/// only once a PDF opens, renders just the pages in view.
class IdePdfPreview extends StatefulWidget {
  const IdePdfPreview({
    super.key,
    required this.path,
    this.read,
    this.onOpenInDefaultApp,
  });

  final String path;

  /// Offered when the file cannot be shown.
  final VoidCallback? onOpenInDefaultApp;

  /// Reads the file (a remote project's, on its host); read from this
  /// machine's disk as its pages are rendered when null.
  final Future<Uint8List> Function(String path)? read;

  @override
  State<IdePdfPreview> createState() => _IdePdfPreviewState();
}

class _IdePdfPreviewState extends State<IdePdfPreview> {
  Uint8List? _bytes;
  Object? _error;
  int _load = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(IdePdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.read != widget.read) {
      unawaited(_read());
    }
  }

  @override
  void dispose() {
    _load++;
    super.dispose();
  }

  Future<void> _read() async {
    final load = ++_load;
    setState(() {
      _bytes = null;
      _error = null;
    });
    final read = widget.read;
    if (read == null) {
      // PDFium opens this machine's file itself, and tells a missing one
      // from a broken one only as an unexpected error.
      try {
        await fileByteSize(widget.path);
      } on IdeFileNotFoundException catch (error) {
        if (!mounted || load != _load) return;
        setState(() => _error = error);
      } catch (_) {
        // Left to PDFium to say.
      }
      return;
    }
    try {
      final bytes = await read(widget.path);
      if (!mounted || load != _load) return;
      setState(() => _bytes = bytes);
    } catch (error) {
      if (!mounted || load != _load) return;
      setState(() => _error = error);
    }
  }

  Widget _placeholder(Object error) => IdeEditorPlaceholder(
    error: error,
    onOpenAnyway: () => unawaited(_read()),
    onRetry: () => unawaited(_read()),
    onOpenInDefaultApp: widget.onOpenInDefaultApp,
  );

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) return _placeholder(error);
    final params = PdfViewerParams(
      backgroundColor: themeColors['editor.background'],
      margin: 12,
      loadingBannerBuilder: (context, _, _) => const SizedBox.expand(),
      errorBannerBuilder: (context, error, _, _) => _placeholder(error),
    );
    if (widget.read == null) {
      return PdfViewer.file(
        widget.path,
        // Retried, opened anew.
        key: ValueKey((widget.path, _load)),
        params: params,
      );
    }
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.expand();
    return PdfViewer.data(
      bytes,
      // Read again, its pages are the bytes read this time.
      sourceName: '${widget.path}#$_load',
      key: ValueKey((widget.path, _load)),
      params: params,
    );
  }
}
