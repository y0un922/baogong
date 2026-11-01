import 'dart:async';

import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_controller.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/composer_polish.dart';
import 'package:baocode/chat/composer/composer_translate.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = ComposerTokenEmbed.file('/w/lib/main.dart');

  group('composerTranslateToEnglish', () {
    test('Chinese goes to English, English to Chinese', () {
      expect(
        composerTranslateToEnglish(composerPolishText('修一下这个 bug')),
        isTrue,
      );
      expect(
        composerTranslateToEnglish(composerPolishText('fix this bug')),
        isFalse,
      );
      // A tag alone says nothing: it goes the way of the words with it.
      expect(
        composerTranslateToEnglish(composerPolishText(file.atom)),
        isFalse,
      );
    });
  });

  group('translateComposerText', () {
    tearDown(() => composerTranslateAsker = null);

    test('the words translated, the tag, code and path put back as they '
        'were', () async {
      String? asked;
      composerTranslateAsker =
          (system, prompt, {model, exact = false, location}) async {
            asked = prompt;
            return 'Fix the bug in ⟦1⟧:\n⟦2⟧\nThe log is in ⟦3⟧.';
          };
      final content = await translateComposerText(
        composerPolishText(
          '修一下 ${file.atom} 这个 bug：\n```\nlet x = 1\n```\n'
          '日志在 /tmp/run/out.log',
        ),
      );
      expect(asked, contains('<message>\n修一下 ⟦1⟧ 这个 bug：\n⟦2⟧'));
      expect(
        content,
        'Fix the bug in ${file.atom}:\n```\nlet x = 1\n```\n'
        'The log is in /tmp/run/out.log.',
      );
    });

    test('into English, a reply far longer than the message is taken '
        '(Chinese is fewer characters)', () async {
      // 800 characters of Chinese come back as about 3,000 of English.
      final asked = composerPolishText('雨' * 800);
      composerTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => 'a' * 3000;
      expect(await translateComposerText(asked), 'a' * 3000);
    });

    test('a marker lost or empty is not taken; a longer reply is', () async {
      final asked = composerPolishText('修一下 ${file.atom}');
      composerTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => 'Fix it.';
      await expectLater(
        translateComposerText(asked),
        throwsA(isA<ComposerPolishException>()),
      );
      composerTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => '  ';
      await expectLater(
        translateComposerText(asked),
        throwsA(isA<ComposerPolishException>()),
      );
      // However long it comes back, it is taken.
      composerTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => 'Fix it in ⟦1⟧. ${'x' * 4000}';
      expect(
        await translateComposerText(asked),
        'Fix it in ${file.atom}. ${'x' * 4000}',
      );
    });
  });

  group('the composer', () {
    tearDown(() => composerTranslateAsker = null);

    Future<ComposerController> pumpComposer(WidgetTester tester) async {
      final session = ChatSession(historyCount: 0);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: ChatComposer(session: session, draft: session.draft),
          ),
        ),
      );
      await tester.pump();
      return tester
              .widget<MarkdownEditor>(find.byType(MarkdownEditor))
              .controller
          as ComposerController;
    }

    Finder translateButton() => find.byWidgetPredicate(
      (widget) =>
          widget is IdeHover &&
          (widget.message ==
                  englishLocalizations.composerTranslateToEnglishHint ||
              widget.message ==
                  englishLocalizations.composerTranslateToChineseHint ||
              widget.message == englishLocalizations.composerTranslating),
    );

    testWidgets('Translate puts the English in, the tag as it was; Undo '
        'takes it back', (tester) async {
      final reply = Completer<String>();
      String? prompt;
      composerTranslateAsker =
          (system, asked, {model, exact = false, location}) {
            prompt = asked;
            return reply.future;
          };
      final controller = await pumpComposer(tester);
      controller.replace(
        0,
        0,
        '修一下 ${file.atom} 这个 bug',
        selection: const TextSelection.collapsed(offset: 0),
      );
      await tester.pump();
      final before = controller.text;

      // Chinese first: the hint says English.
      expect(
        tester.widget<IdeHover>(translateButton()).message,
        englishLocalizations.composerTranslateToEnglishHint,
      );
      await tester.tap(translateButton());
      await tester.pump();
      expect(prompt, contains('修一下 ⟦1⟧ 这个 bug'));
      reply.complete('Fix the bug in ⟦1⟧.');
      await tester.pumpAndSettle();
      expect(controller.text, 'Fix the bug in ${file.atom}.');
      expect(controller.embeds.single.embed, file);
      // English now: the hint says Chinese.
      expect(
        tester.widget<IdeHover>(translateButton()).message,
        englishLocalizations.composerTranslateToChineseHint,
      );

      controller.undo();
      await tester.pump();
      expect(controller.text, before);
    });

    testWidgets('with nothing to translate, the button does nothing', (
      tester,
    ) async {
      var asked = 0;
      composerTranslateAsker =
          (system, prompt, {model, exact = false, location}) async {
            asked++;
            return 'Fix it.';
          };
      final controller = await pumpComposer(tester);
      controller.replace(0, 0, file.atom);
      await tester.pump();
      await tester.tap(translateButton());
      await tester.pump();
      expect(asked, 0);
    });
  });
}
