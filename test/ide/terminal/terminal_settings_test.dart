import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/terminal_settings.dart';

/// Settings → Terminal's values as settings.json keeps them.
void main() {
  test('reads VS Code\'s keys; what it does not know is the default', () {
    expect(
      TerminalSettings.parseCursorStyle('line'),
      TerminalCursorStyle.line,
    );
    expect(
      TerminalSettings.parseCursorStyle('bar'),
      TerminalCursorStyle.block,
    );
    expect(TerminalSettings.parseScrollback(5000), 5000);
    expect(TerminalSettings.parseScrollback(-1), 0);
    expect(
      TerminalSettings.parseScrollback(1e9),
      TerminalSettings.maxScrollback,
    );
    expect(
      TerminalSettings.parseScrollback('lots'),
      TerminalSettings.defaultScrollback,
    );
    expect(TerminalSettings.parseBool(true), isTrue);
    expect(TerminalSettings.parseBool('true'), isFalse);
  });

  test('keeps only what differs from the default', () {
    expect(
      TerminalSettings.cursorStyleSetting(TerminalCursorStyle.block),
      isNull,
    );
    expect(
      TerminalSettings.cursorStyleSetting(TerminalCursorStyle.underline),
      'underline',
    );
    expect(
      TerminalSettings.scrollbackSetting(TerminalSettings.defaultScrollback),
      isNull,
    );
    expect(TerminalSettings.scrollbackSetting(10000), 10000);
    expect(TerminalSettings.boolSetting(false), isNull);
    expect(TerminalSettings.boolSetting(true), isTrue);
  });

  test('follows the file as it changes', () {
    addTearDown(() {
      TerminalSettings.cursorStyle.value = TerminalCursorStyle.block;
      TerminalSettings.cursorBlinking.value = false;
      TerminalSettings.scrollback.value = TerminalSettings.defaultScrollback;
      TerminalSettings.macOptionIsMeta.value = false;
    });
    final file = ValueNotifier<Map<String, Object?>>({
      TerminalSettings.macOptionIsMetaKey: true,
    });
    TerminalSettings.follow(file, (key) => file.value[key]);
    expect(TerminalSettings.macOptionIsMeta.value, isTrue);
    expect(TerminalSettings.cursorStyle.value, TerminalCursorStyle.block);

    file.value = {
      TerminalSettings.cursorStyleKey: 'underline',
      TerminalSettings.cursorBlinkingKey: true,
      TerminalSettings.scrollbackKey: 10000,
    };
    expect(TerminalSettings.cursorStyle.value, TerminalCursorStyle.underline);
    expect(TerminalSettings.cursorBlinking.value, isTrue);
    expect(TerminalSettings.scrollback.value, 10000);
    expect(TerminalSettings.macOptionIsMeta.value, isFalse);
  });
}
