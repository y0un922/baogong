import 'dart:async';

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/composer/composer_embeds.dart';
import 'package:baocode/chat/composer/composer_polish.dart';
import 'package:baocode/chat/composer/composer_translate.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = ComposerTokenEmbed.file('/w/lib/main.dart');

  group('composerTranslateToEnglish', () {
    test('Chinese goes to English, English to Chinese', () {
      expect(
        composerTranslateToEnglish(
          composerPolishText(Delta()..insert('修一下这个 bug')),
        ),
        isTrue,
      );
      expect(
        composerTranslateToEnglish(
          composerPolishText(Delta()..insert('fix this bug')),
        ),
        isFalse,
      );
      // A tag alone says nothing: it goes the way of the words with it.
      expect(
        composerTranslateToEnglish(
          composerPolishText(Delta()..insert({file.type: file.data})),
        ),
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
          Delta()
            ..insert('修一下 ')
            ..insert({file.type: file.data})
            ..insert(' 这个 bug：\n```\nlet x = 1\n```\n日志在 /tmp/run/out.log'),
        ),
      );
      expect(asked, contains('<message>\n修一下 ⟦1⟧ 这个 bug：\n⟦2⟧'));
      final ops = content.toList();
      expect(ops[0].data, 'Fix the bug in ');
      expect(ops[1].data, {file.type: file.data});
      expect(
        ops.skip(2).map((op) => op.data).join(),
        ':\n```\nlet x = 1\n```\nThe log is in /tmp/run/out.log.',
      );
    });

    test('into English, a reply far longer than the message is taken '
        '(Chinese is fewer characters)', () async {
      // 800 characters of Chinese come back as about 3,000 of English.
      final asked = composerPolishText(Delta()..insert('雨' * 800));
      composerTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => 'a' * 3000;
      final content = await translateComposerText(asked);
      expect(content.toList().map((op) => op.data).join(), 'a' * 3000);
    });

    test('a marker lost or empty is not taken; a longer reply is', () async {
      final asked = composerPolishText(
        Delta()
          ..insert('修一下 ')
          ..insert({file.type: file.data}),
      );
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
      final content = await translateComposerText(asked);
      final ops = content.toList();
      expect(ops[0].data, 'Fix it in ');
      expect(ops[1].data, {file.type: file.data});
      expect(ops.skip(2).map((op) => op.data).join(), '. ${'x' * 4000}');
    });
  });

  group('the composer', () {
    tearDown(() => composerTranslateAsker = null);

    Future<QuillController> pumpComposer(WidgetTester tester) async {
      final session = ChatSession(historyCount: 0);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          home: Scaffold(
            body: ChatComposer(session: session, draft: session.draft),
          ),
        ),
      );
      await tester.pump();
      return tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;
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
      controller.compose(
        Delta()
          ..insert('修一下 ')
          ..insert({file.type: file.data})
          ..insert(' 这个 bug'),
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
      await tester.pump();
      final before = controller.document.toDelta();

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
      final ops = controller.document.toDelta().toList();
      expect(ops[0].data, 'Fix the bug in ');
      expect(ops[1].data, {file.type: file.data});
      expect(ops[2].data, '.\n');
      // English now: the hint says Chinese.
      expect(
        tester.widget<IdeHover>(translateButton()).message,
        englishLocalizations.composerTranslateToChineseHint,
      );

      controller.undo();
      await tester.pump();
      expect(controller.document.toDelta(), before);
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
      controller.compose(
        Delta()..insert({file.type: file.data}),
        const TextSelection.collapsed(offset: 0),
        ChangeSource.local,
      );
      await tester.pump();
      await tester.tap(translateButton());
      await tester.pump();
      expect(asked, 0);
    });
  });
}
