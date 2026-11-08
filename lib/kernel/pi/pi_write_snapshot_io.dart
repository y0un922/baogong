import 'dart:io';

typedef WriteSnapshot = ({bool existed, String? content});

String displayPath(String path) {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  return home != null && path.startsWith(home)
      ? '~${path.substring(home.length)}'
      : path;
}

/// Captured when pi starts a write, before it replaces the file. The pi
/// tool-display plugin also caps its preview read at one megabyte.
WriteSnapshot readBeforeWrite(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return (existed: false, content: null);
    if (file.lengthSync() > 1000000) return (existed: true, content: null);
    return (existed: true, content: file.readAsStringSync());
  } on FileSystemException {
    return (existed: true, content: null);
  } on FormatException {
    return (existed: true, content: null);
  }
}
