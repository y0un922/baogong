import 'kernel_types.dart';

/// What a picture is taken to cost, as pi counts one.
const imageTokens = 1200;

/// A guess at the tokens of [text]: a quarter of its ASCII characters, one
/// for each other (CJK and the like take about one each).
int estimateTokens(String text) {
  var ascii = 0;
  var other = 0;
  for (final unit in text.runes) {
    if (unit < 0x80) {
      ascii++;
    } else {
      other++;
    }
  }
  return (ascii / 4).ceil() + other;
}

/// The context [used] of [window], split by the kernel's guess at what of
/// it is [fixed] (the system prompt, tools and instructions every request
/// starts with); without one, the total alone.
ContextUsage estimatedContext({
  required int window,
  required int used,
  required int? fixed,
}) {
  if (fixed == null || fixed <= 0) {
    return ContextUsage(window: window, used: used);
  }
  final base = fixed > used ? used : fixed;
  return ContextUsage(
    window: window,
    used: used,
    estimated: true,
    segments: [
      ContextSegment('System prompt & tools', base),
      ContextSegment('Messages', used - base),
    ],
  );
}
