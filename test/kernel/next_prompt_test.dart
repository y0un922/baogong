import 'package:baocode/kernel/next_prompt.dart';
import 'package:baocode/kernel/prompt_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a reply as the next prompt: its first line, unquoted; none for NONE, '
      'markup or a paragraph', () {
    expect(cleanNextPrompt('  "run the tests"\nbecause…'), 'run the tests');
    expect(cleanNextPrompt('「提交一下」'), '提交一下');
    expect(cleanNextPrompt('NONE'), isNull);
    expect(cleanNextPrompt('none.'), isNull);
    expect(cleanNextPrompt('<tool_call>{}</tool_call>'), isNull);
    expect(cleanNextPrompt('x' * 121), isNull);
    expect(cleanNextPrompt('\n\n'), isNull);
  });

  test('none asked for while suggestions are off; an answer to what was '
      'asked before the user sent something is dropped', () async {
    var asks = 0;
    NextPrompt.asker = (_, _, {cancel, model, exact = false, location}) async {
      asks++;
      return 'go ahead';
    };
    addTearDown(() => NextPrompt.asker = null);
    final was = PromptSuggestions.current;
    addTearDown(() => PromptSuggestions.current = was);
    var changes = 0;
    final next = NextPrompt(() => changes++);

    PromptSuggestions.current = () => false;
    next.turnEnded(asked: 'Fix it', answer: 'Fixed. Shall I go on?');
    await pumpEventQueue();
    expect((asks, next.suggestion), (0, null));

    PromptSuggestions.current = () => true;
    next.turnEnded(asked: 'Fix it', answer: 'Fixed. Shall I go on?');
    next.clear();
    await pumpEventQueue();
    expect((asks, next.suggestion, changes), (1, null, 0));

    next.turnEnded(asked: 'Fix it', answer: 'Fixed. Shall I go on?');
    await pumpEventQueue();
    expect((next.suggestion, changes), ('go ahead', 1));
  });
}
