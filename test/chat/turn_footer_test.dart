import 'dart:async';

import 'package:baocode/base/step_clock.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/widgets/rolling_text.dart';
import 'package:baocode/chat/widgets/turn_footer.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/usage/usage_ledger.dart';
import 'package:baocode/usage/usage_prices.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  test('its runs: each digit alone, what is between them together', () {
    expect(RollingText.runsOf('342.15 tok/s'), [
      '3',
      '4',
      '2',
      '.',
      '1',
      '5',
      ' tok/s',
    ]);
    expect(RollingText.runsOf('↓ 1.2k tokens'), [
      '↓ ',
      '1',
      '.',
      '2',
      'k tokens',
    ]);
  });

  testWidgets('a digit changed rolls: the old one going as the new one '
      'comes, back and forth however fast', (tester) async {
    const style = TextStyle(fontSize: 12);
    await _pump(tester, const RollingText('12', style: style));
    expect(find.text('2'), findsOneWidget);
    await _pump(tester, const RollingText('13', style: style));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // Back before it has gone: another child, no key twice.
    await _pump(tester, const RollingText('12', style: style));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    // On the shared clock's frames, not every vsync.
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(RollingText.duration + StepClock.frame);
    await tester.pump(StepClock.frame);
    expect(find.text('3'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    // The one unchanged never moved.
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('where motion is turned down, one text, at once', (tester) async {
    await _pump(
      tester,
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: RollingText('12 tok/s', style: TextStyle()),
      ),
    );
    expect(find.text('12 tok/s'), findsOneWidget);
  });

  testWidgets('the turn under way\'s line turned off in settings, as it '
      'changes: none at all; a finished turn\'s stays', (tester) async {
    final shown = ValueNotifier(true);
    LiveTurnStatsSetting.current = () => shown.value;
    LiveTurnStatsSetting.changes = shown;
    addTearDown(() {
      LiveTurnStatsSetting.current = () => true;
      LiveTurnStatsSetting.changes = null;
    });

    await _pump(
      tester,
      TurnFooter(
        live: const TurnOutput(tokens: 1234, tokensPerSecond: 42),
        since: DateTime.now().subtract(const Duration(seconds: 3)),
      ),
    );
    expect(find.byType(RollingText), findsNWidgets(3));

    shown.value = false;
    await tester.pump();
    expect(find.byType(RollingText), findsNothing);
    expect(tester.getSize(find.byType(TurnFooter)), Size.zero);

    shown.value = true;
    await tester.pump();
    expect(find.byType(RollingText), findsNWidgets(3));

    shown.value = false;
    await _pump(
      tester,
      const TurnFooter(
        worked: Duration(seconds: 12),
        usage: TurnUsage(outputTokens: 234, tokensPerSecond: 50),
      ),
    );
    expect(find.text('12s'), findsOneWidget);
    expect(find.text('50.00 tok/s'), findsOneWidget);
  });

  testWidgets('TPS waits for usage, then shows even on a short turn', (
    tester,
  ) async {
    await _pump(tester, const TurnFooter(live: TurnOutput(tokens: 30)));
    expect(find.byType(RollingText), findsOneWidget);

    await _pump(
      tester,
      const TurnFooter(live: TurnOutput(tokens: 30, tokensPerSecond: 150)),
    );
    expect(find.byType(RollingText), findsNWidgets(2));

    await _pump(
      tester,
      const TurnFooter(
        worked: Duration(milliseconds: 200),
        usage: TurnUsage(outputTokens: 30, tokensPerSecond: 150),
      ),
    );
    expect(find.text('150.00 tok/s'), findsOneWidget);
  });

  test('when a turn ended: the time today, the day before', () {
    final now = DateTime(2026, 10, 21, 18);
    expect(
      TurnFooter.formatEnded(DateTime(2026, 10, 21, 9, 5, 7), now: now),
      '09:05',
    );
    expect(
      TurnFooter.formatEnded(
        DateTime(2026, 10, 21, 9, 5, 7),
        now: now,
        seconds: true,
      ),
      '09:05:07',
    );
    expect(
      TurnFooter.formatEnded(DateTime(2026, 10, 20, 23, 59), now: now),
      '10-20 23:59',
    );
    expect(
      TurnFooter.formatEnded(DateTime(2025, 12, 31, 8, 0), now: now),
      '2025-12-31 08:00',
    );
  });

  test('a turn that ends is kept with when it ended', () {
    final transcript = Transcript()
      ..apply(const TurnStarted(1, 'u1'))
      ..apply(const ItemUpserted(2, 'u1', UserMessageItem(text: 'hi')));
    final before = DateTime.now();
    transcript.apply(const TurnEnded(3, 'u1', worked: Duration(seconds: 3)));
    final message = transcript.itemAt(0) as UserMessageItem;
    expect(message.worked, const Duration(seconds: 3));
    expect(message.endedAt!.isBefore(before), isFalse);
  });

  testWidgets('a finished turn says when it ended, last', (tester) async {
    final ended = DateTime.now();
    await _pump(
      tester,
      TurnFooter(worked: const Duration(seconds: 12), endedAt: ended),
    );
    final text = 'ended ${TurnFooter.formatEnded(ended)}';
    expect(find.text(text), findsOneWidget);
    expect(
      tester.getRect(find.text('12s')).right,
      lessThan(tester.getRect(find.text(text)).left),
    );
  });

  testWidgets('a finished turn\'s time comes first, its tokens last', (
    tester,
  ) async {
    await _pump(
      tester,
      const TurnFooter(
        answer: 'Done.',
        worked: Duration(seconds: 12),
        usage: TurnUsage(
          inputTokens: 1000,
          outputTokens: 234,
          costUsd: 0.42,
          tokensPerSecond: 50,
        ),
      ),
    );
    final tokens = tester.getRect(find.text('1.23k tokens'));
    final rects = [
      for (final text in ['12s', '50.00 tok/s', r'$0.42'])
        tester.getRect(find.text(text)),
      tokens,
    ];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i - 1].right, lessThan(rects[i].left));
    }
  });

  testWidgets('a conversation too narrow for the line: the rest goes on '
      'under it, nothing cut', (tester) async {
    await _pump(
      tester,
      const SizedBox(
        width: 220,
        child: TurnFooter(
          answer: 'Done.',
          worked: Duration(seconds: 11),
          usage: TurnUsage(
            inputTokens: 90000,
            outputTokens: 2720,
            costUsd: 0.074,
            tokensPerSecond: 136.92,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final first = tester.getRect(find.text('11s'));
    final last = tester.getRect(find.text('92.72k tokens'));
    expect(last.top, greaterThan(first.bottom - 1));
  });

  testWidgets(
    'TurnFooter prefers UsageCost and hides CLI \$0.00 when unpriced',
    (tester) async {
      final priced = UsageCost()..add('CNY', 1.25);
      await _pump(
        tester,
        TurnFooter(
          worked: const Duration(seconds: 5),
          usage: const TurnUsage(
            inputTokens: 1000,
            outputTokens: 200,
            costUsd: 0,
          ),
          cost: priced,
        ),
      );
      expect(find.text('¥1.25'), findsOneWidget);
      expect(find.text(r'$0.00'), findsNothing);

      final unpriced = UsageCost()..unpriced = 1;
      await _pump(
        tester,
        TurnFooter(
          worked: const Duration(seconds: 5),
          usage: const TurnUsage(
            inputTokens: 1000,
            outputTokens: 200,
            costUsd: 0,
          ),
          cost: unpriced,
        ),
      );
      expect(find.text(r'$0.00'), findsNothing);
      expect(find.text('1.20k tokens'), findsOneWidget);
    },
  );

  testWidgets('ChatHistoryView updates turn footer costs live as UsagePrices '
      'changes', (tester) async {
    final prevLedger = UsageLedger.current;
    final prevPrices = UsagePrices.current;
    final ledger = UsageLedger(MemoryUsageStorage());
    final prices = UsagePrices();
    UsageLedger.current = ledger;
    UsagePrices.current = prices;
    addTearDown(() {
      ledger.dispose();
      prices.dispose();
      UsageLedger.current = prevLedger;
      UsagePrices.current = prevPrices;
    });

    final cli = _TestCli();
    final descriptor = KernelDescriptor(
      id: 'claude-code',
      label: 'Claude Code',
      icon: Icons.auto_awesome_rounded,
      description: '',
      create: (context) => ClaudeCodeKernel(
        MockKernels.claudeCode,
        context,
        start: (_) async => cli,
      ),
    );
    final session = ChatSession(
      kernel: descriptor,
      kernels: [descriptor],
      historyCount: 0,
    );
    addTearDown(session.dispose);

    await _pump(tester, ChatHistoryView(feed: session));
    await tester.pump();

    session.send(const ComposerMessage(text: 'hi'));
    await tester.pump();
    cli.push({
      'type': 'system',
      'subtype': 'init',
      'session_id': 'sess-live-price',
    });
    cli.push({
      'type': 'assistant',
      'parent_tool_use_id': null,
      'message': {
        'id': 'm1',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'hello'},
        ],
      },
    });
    ledger.record(
      UsageCall(
        at: DateTime.now(),
        duration: const Duration(seconds: 1),
        status: 200,
        provider: 'provider-3',
        model: 'gemini-4-neon',
        session: 'sess-live-price',
        input: 100000,
        output: 10000,
      ),
    );
    cli.push({
      'type': 'result',
      'subtype': 'success',
      'is_error': false,
      'duration_ms': 1000,
      'total_cost_usd': 0,
      'usage': {'input_tokens': 100000, 'output_tokens': 10000},
    });
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    // Unpriced custom upstream: hides misleading $0.00.
    expect(find.text('hello'), findsOneWidget);
    expect(find.text(r'$0.00'), findsNothing);

    // Price added: footer updates immediately without reopening the chat.
    await prices.update({
      'provider-3/gemini-4-neon': const ModelPrice(input: 3, output: 15),
    });
    await tester.pump();
    expect(find.text(r'$0.450'), findsOneWidget);

    // Price changed again: footer updates immediately.
    await prices.update({
      'provider-3/gemini-4-neon': const ModelPrice(
        input: 10,
        output: 50,
        currency: 'CNY',
      ),
    });
    await tester.pump();
    expect(find.text('¥1.50'), findsOneWidget);
  });
}

class _TestCli implements ClaudeCodeTransport {
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();
  final Completer<void> _exited = Completer<void>();

  void push(Map<String, Object?> message) => _out.add(message);

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  void write(Map<String, Object?> message) {
    if (message['type'] == 'control_request') {
      _out.add({
        'type': 'control_response',
        'response': {
          'subtype': 'success',
          'request_id': message['request_id'],
          'response': const <String, Object?>{},
        },
      });
    }
  }

  @override
  void close() {
    if (!_exited.isCompleted) _exited.complete();
    _out.close();
  }

  @override
  Future<void> get exited => _exited.future;
}
