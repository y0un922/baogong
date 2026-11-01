import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/reply_translate.dart';
import 'package:baocode/chat/widgets/turn_footer.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('translateReply', () {
    tearDown(() => replyTranslateAsker = null);

    test('the answer, between its tags, into Chinese', () async {
      String? system;
      String? asked;
      replyTranslateAsker =
          (promptSystem, prompt, {model, exact = false, location}) async {
            system = promptSystem;
            asked = prompt;
            return '已在 `chat_feed.dart` 里修好监听器。';
          };
      expect(
        await translateReply('Fixed the listener in `chat_feed.dart`.'),
        '已在 `chat_feed.dart` 里修好监听器。',
      );
      expect(system, contains('Simplified Chinese'));
      expect(
        asked,
        '<answer>\nFixed the listener in `chat_feed.dart`.\n'
        '</answer>',
      );
    });

    test('tags echoed back are dropped', () async {
      replyTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => '<answer>\n  修好了。\n</answer>';
      expect(await translateReply('Fixed it.'), '修好了。');
    });

    test('an empty reply is not taken; a long one is', () async {
      replyTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => '   ';
      await expectLater(
        translateReply('Fixed it.'),
        throwsA(isA<ReplyTranslateException>()),
      );
      replyTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => 'x' * 800;
      expect(await translateReply('Fixed it.'), 'x' * 800);
    });

    test('what went wrong asking says why', () async {
      replyTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => throw Exception('Not signed in');
      await expectLater(
        translateReply('Fixed it.'),
        throwsA(
          isA<ReplyTranslateException>().having(
            (error) => error.message,
            'message',
            contains('Not signed in'),
          ),
        ),
      );
    });
  });

  group('a session', () {
    tearDown(() => replyTranslateAsker = null);

    test('shows a turn in Chinese, and back as it was written', () async {
      final session = ChatSession(
        kernel: MockKernels.claudeCode,
        historyCount: 8,
      );
      addTearDown(session.dispose);
      var index = session.itemCount - 1;
      while (session.itemAt(index) is! AssistantTextItem) {
        index--;
      }
      final original = session.itemAt(index) as AssistantTextItem;
      var notified = 0;
      session.addListener(() => notified++);
      replyTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => '译好的。';

      await session.toggleTranslationAt(index);
      expect(session.translatedAt(index), isTrue);
      expect((session.itemAt(index) as AssistantTextItem).text, '译好的。');
      expect(notified, 1);

      await session.toggleTranslationAt(index);
      expect(session.translatedAt(index), isFalse);
      expect((session.itemAt(index) as AssistantTextItem).text, original.text);
      expect(notified, 2);
    });

    test('puts nothing in when the model does not answer', () async {
      final session = ChatSession(
        kernel: MockKernels.claudeCode,
        historyCount: 8,
      );
      addTearDown(session.dispose);
      var index = session.itemCount - 1;
      while (session.itemAt(index) is! AssistantTextItem) {
        index--;
      }
      final original = session.itemAt(index) as AssistantTextItem;
      replyTranslateAsker = (
        system,
        prompt, {
        model,
        exact = false,
        location,
      }) async => throw Exception('Not signed in');

      await expectLater(
        session.toggleTranslationAt(index),
        throwsA(isA<ReplyTranslateException>()),
      );
      expect(session.translatedAt(index), isFalse);
      expect((session.itemAt(index) as AssistantTextItem).text, original.text);
    });
  });

  testWidgets('the footer offers the answer in Chinese, then as it was', (
    tester,
  ) async {
    var translated = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TurnFooter(
              answer: 'Fixed it.',
              translated: translated,
              onTranslate: () async {
                translated = true;
                setState(() {});
              },
            ),
          ),
        ),
      ),
    );

    Finder hint(String message) => find.byWidgetPredicate(
      (widget) => widget is IdeHover && widget.message == message,
    );

    expect(hint(englishLocalizations.turnTranslate), findsOneWidget);
    await tester.tap(hint(englishLocalizations.turnTranslate));
    await tester.pumpAndSettle();
    expect(hint(englishLocalizations.turnShowOriginal), findsOneWidget);
  });
}
