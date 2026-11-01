import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/panels/context_usage_panel.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/kernel/kernel_types.dart';

void main() {
  testWidgets('the plan limits show under the context, a row each', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 400000, used: 364600),
            stats: UsageStats(
              costUsd: 1.5,
              limits: [
                RateLimitWindow(
                  '5-hour limit',
                  0.98,
                  resetsAt: now.add(const Duration(minutes: 46, seconds: 30)),
                ),
                RateLimitWindow(
                  'Weekly limit',
                  0.37,
                  resetsAt: now.add(
                    const Duration(days: 3, hours: 5, seconds: 30),
                  ),
                ),
                RateLimitWindow(
                  'Weekly Opus limit',
                  0.8,
                  resetsAt: now.subtract(const Duration(hours: 1)),
                ),
              ],
            ),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Plan usage'), findsOneWidget);
    expect(find.text(r'$1.50'), findsOneWidget);
    expect(find.text('98%'), findsOneWidget);
    expect(find.text('resets in 46m'), findsOneWidget);
    expect(find.text('37%'), findsOneWidget);
    expect(find.text('resets in 3d 5h'), findsOneWidget);
    // Past its reset: started over.
    expect(find.text('0%'), findsOneWidget);
    // Below what fills the context.
    expect(
      tester.getTopLeft(find.text('Plan usage')).dy,
      greaterThan(tester.getTopLeft(find.text('Context window')).dy),
    );
  });

  testWidgets('a breakdown the kernel guessed reads as about so much', (
    tester,
  ) async {
    Future<void> show({required bool estimated}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: ContextUsage(
              window: 258400,
              used: 20000,
              estimated: estimated,
              segments: const [
                ContextSegment('System prompt & tools', 14100),
                ContextSegment('Messages', 5900),
              ],
            ),
            onClose: () {},
          ),
        ),
      ),
    );
    await show(estimated: true);
    expect(find.text('System prompt & tools'), findsOneWidget);
    expect(find.text('~14.1k'), findsOneWidget);
    expect(find.text('~5.9k'), findsOneWidget);
    // The agent's own count: as it is.
    await show(estimated: false);
    expect(find.text('14.1k'), findsOneWidget);
    expect(find.text('~14.1k'), findsNothing);
  });

  testWidgets('the prompt cache shows the conversation, its last request on '
      'hover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 64000),
            stats: const UsageStats(
              costUsd: 0.27,
              cache: PromptCache(
                last: CacheTokens(read: 61330, written: 2408, uncached: 2),
                conversation: CacheTokens(
                  read: 1200000,
                  written: 85300,
                  uncached: 40,
                ),
              ),
            ),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Prompt cache'), findsOneWidget);
    // The conversation's, to a tenth; not the last request's 96%.
    expect(find.text('93.4%'), findsOneWidget);
    expect(find.text('96.2%'), findsNothing);
    // The counts on hover.
    expect(
      tester.widget<IdeHover>(find.byType(IdeHover).last).message,
      'Last request: 61.3k read · 2.4k written · 2 uncached\n'
      'Main conversation: 1.2M read · 85.3k written · 93.4% hit\n'
      "Not counting subagents, compaction or the CLI's side requests",
    );
    // Between the context and the cost.
    expect(
      tester.getTopLeft(find.text('Prompt cache')).dy,
      allOf(
        greaterThan(tester.getTopLeft(find.text('Context window')).dy),
        lessThan(tester.getTopLeft(find.text(r'$0.27')).dy),
      ),
    );
  });

  testWidgets('on no plan, the cost shows without one', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 1000),
            stats: const UsageStats(costUsd: 0.27),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Plan usage'), findsNothing);
    expect(find.text('This session'), findsOneWidget);
    expect(find.text(r'$0.27'), findsOneWidget);
  });

  testWidgets('without limits or cost, no plan section', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 1000),
            stats: const UsageStats(),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Plan usage'), findsNothing);
  });

  test('reset times read short', () {
    final now = DateTime(2026, 9, 28, 12);
    expect(resetsIn(now.add(const Duration(minutes: 46)), now: now), 'in 46m');
    expect(resetsIn(now.add(const Duration(hours: 3)), now: now), 'in 3h');
    expect(
      resetsIn(now.add(const Duration(hours: 3, minutes: 20)), now: now),
      'in 3h 20m',
    );
    expect(resetsIn(now.add(const Duration(days: 2)), now: now), 'in 2d');
  });

  testWidgets('while nothing is known yet, it says so', (tester) async {
    Future<void> pumpState(LimitsState state) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 1000),
            stats: UsageStats(limitsState: state),
            onClose: () {},
          ),
        ),
      ),
    );
    await pumpState(LimitsState.checking);
    expect(find.text('Plan usage'), findsOneWidget);
    expect(find.text('Checking limits…'), findsOneWidget);
    await pumpState(LimitsState.unavailable);
    expect(
      find.textContaining('Limits are unavailable right now'),
      findsOneWidget,
    );
  });

  testWidgets('turned off, it says the replies will tell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsagePanel(
            usage: const ContextUsage(window: 200000, used: 1000),
            stats: const UsageStats(
              limitsState: LimitsState.off,
              limitsOffBy: 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
            ),
            onClose: () {},
          ),
        ),
      ),
    );
    expect(
      find.text(
        'Limits update with the conversation; they show after a message.',
      ),
      findsOneWidget,
    );
  });
}
