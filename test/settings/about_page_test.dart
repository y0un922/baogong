import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/settings/pages/about_page.dart';
import 'package:baocode/update/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AboutSettingsPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('says what Baogong is, which build, and where it is made', (
    tester,
  ) async {
    await show(tester, const Locale('zh'));
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('包工头'), findsOneWidget);
    expect(find.text('BaoCode 的非官方修改版，与官方开发者无关。'), findsOneWidget);
    expect(
      find.text(
        '版本 ${currentAppVersion.marketing}（${currentAppVersion.build}）',
      ),
      findsOneWidget,
    );
    expect(
      find.text('github.com/y0un922/baogong · 免费开源，GPL-3.0 许可证'),
      findsOneWidget,
    );
    expect(find.textContaining('Star'), findsNothing);
    expect(find.text('baocode.dev'), findsOneWidget);
    expect(find.text('更新日志'), findsOneWidget);
    expect(find.text('反馈问题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('its links: this fork\'s, not upstream\'s', () {
    expect(
      AboutSettingsPage.issues,
      Uri.parse('https://github.com/y0un922/baogong/issues'),
    );
    expect(
      AboutSettingsPage.releases,
      Uri.parse('https://github.com/y0un922/baogong/releases'),
    );
  });
}
