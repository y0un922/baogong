// The files the agent read found by the paths it names them by, those
// paths gone wrong too.

import 'package:baocode/chat/side_panel/file_link.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = '/Users/me/Desktop';
const _read = '/Users/me/Documents/app/lib/chat/step_folds.dart';

void main() {
  /// The scope of a conversation in [_root] whose agent read [_read].
  FileOpenScope scope(List<FileOpenRequest> opened) => FileOpenScope(
    root: _root,
    onOpen: opened.add,
    existence: FileExistence((path) async => path == _read),
    home: '/Users/me',
    seen: const [_read],
    child: const SizedBox(),
  );

  test('a path relative to another folder opens the file read', () async {
    final opened = <FileOpenRequest>[];
    final files = scope(opened);
    expect(
      files.openLink(
        FileLink(
          'Documents/app/lib/chat/step_folds.dart',
          FileLineRange(12, 27),
        ),
      ),
      isTrue,
    );
    await pumpEventQueue();
    expect(opened.single.path, _read);
    expect(opened.single.range, FileLineRange(12, 27));
    // Known now: it resolves there at once.
    expect(files.resolve('app/lib/chat/step_folds.dart'), _read);
  });

  test('inline code for a file already read is clickable immediately', () {
    final files = scope([]);
    expect(files.codeRecognizer('app/lib/chat/step_folds.dart'), isNotNull);
    expect(files.codeRecognizer(_read), isNotNull);
    expect(
      files.codeRecognizer('~/Documents/app/lib/chat/step_folds.dart'),
      isNotNull,
    );
  });

  test('a file read outside the project opens by its absolute path', () {
    final files = scope([]);
    expect(files.resolve(_read), _read);
    expect(files.resolve('../Documents/app/lib/chat/step_folds.dart'), _read);
    expect(files.resolve('~/Documents/app/lib/chat/step_folds.dart'), _read);
    expect(
      files.resolve('/Users/me/Documents/other.dart'),
      '/Users/me/Documents/other.dart',
    );
    expect(
      files.resolve('../Documents/other.dart'),
      '/Users/me/Documents/other.dart',
    );
  });

  test('only whole names match, and only files read', () async {
    final files = scope([]);
    await pumpEventQueue();
    expect(files.resolve('_folds.dart'), '$_root/_folds.dart');
    expect(files.resolve('lib/other/step_folds.dart'), isNot(_read));
  });

  group('a path relative to a folder the agent worked in', () {
    const root = '/Users/me/sakura';
    const made = '/Users/me/sakura/proposal/plan.pdf';
    const built = '/Users/me/out/report.pdf';

    FileOpenScope worked(List<FileOpenRequest> opened) => FileOpenScope(
      root: root,
      onOpen: opened.add,
      existence: FileExistence((path) async => path == made || path == built),
      // A script it wrote there, then ran to make the PDF beside it.
      seen: const ['/Users/me/sakura/proposal/build.py'],
      // And a folder it moved into.
      folders: const ['/Users/me/out'],
      child: const SizedBox(),
    );

    test('opens the file made beside one it read or changed', () async {
      final opened = <FileOpenRequest>[];
      final files = worked(opened);
      expect(files.openLink(const FileLink('plan.pdf')), isTrue);
      await pumpEventQueue();
      expect(opened.single.path, made);
      expect(files.resolve('plan.pdf'), made);
    });

    test('opens the file made in a folder it moved into', () async {
      final opened = <FileOpenRequest>[];
      final files = worked(opened);
      expect(files.openLink(const FileLink('report.pdf')), isTrue);
      await pumpEventQueue();
      expect(opened.single.path, built);
    });

    test('a file in none of them is still looked for in the project', () async {
      final opened = <FileOpenRequest>[];
      final files = worked(opened);
      expect(files.openLink(const FileLink('missing.pdf')), isTrue);
      await pumpEventQueue();
      expect(opened.single.path, '$root/missing.pdf');
    });
  });
}
