import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/terminal_settings.dart';
import 'package:baocode/settings/pages/settings_dropdown.dart';
import 'package:baocode/settings/pages/terminal_page.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory data;
  late UserSettings settings;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('baocode-terminal-settings');
    settings = UserSettings(p.join(data.path, 'settings.json'));
    await settings.load();
  });

  tearDown(() async {
    settings.dispose();
    await data.delete(recursive: true);
    TerminalSettings.cursorStyle.value = TerminalCursorStyle.block;
    TerminalSettings.cursorBlinking.value = false;
    TerminalSettings.scrollback.value = TerminalSettings.defaultScrollback;
    TerminalSettings.macOptionIsMeta.value = false;
    TerminalSettings.copyOnSelection.value = false;
  });

  /// Lets the disk catch up until [done].
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100; i++) {
      if (done()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    fail('timed out');
  }

  testWidgets('choices apply at once and are kept in settings.json under '
      'VS Code\'s keys, defaults unwritten', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TerminalSettingsPage(settings: settings)),
      ),
    );
    await tester.pump();

    Future<void> choose(Finder dropdown, String label) async {
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    final style = find.byType(SettingsDropdown).first;
    expect(tester.widget<SettingsDropdown>(style).current, 'Block');
    await choose(style, 'Underline');
    expect(TerminalSettings.cursorStyle.value, TerminalCursorStyle.underline);
    await settle(
      tester,
      () => settings[TerminalSettings.cursorStyleKey] == 'underline',
    );

    await choose(find.byType(SettingsDropdown).last, '10000 lines');
    expect(TerminalSettings.scrollback.value, 10000);
    await settle(
      tester,
      () => settings[TerminalSettings.scrollbackKey] == 10000,
    );

    await tester.tap(find.text('Option as Meta'));
    await tester.pump();
    expect(TerminalSettings.macOptionIsMeta.value, isTrue);
    await settle(
      tester,
      () => settings[TerminalSettings.macOptionIsMetaKey] == true,
    );

    await tester.tap(find.text('Copy on Selection'));
    await tester.pump();
    expect(TerminalSettings.copyOnSelection.value, isTrue);
    await settle(
      tester,
      () => settings[TerminalSettings.copyOnSelectionKey] == true,
    );

    await choose(style, 'Block');
    await settle(
      tester,
      () => !settings.values.containsKey(TerminalSettings.cursorStyleKey),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
