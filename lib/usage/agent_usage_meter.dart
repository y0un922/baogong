import 'usage_ledger.dart';
import 'usage_record.dart';

/// The calls of an agent whose own CLI asks its model, out of the model
/// proxy's sight (Codex, pi): each kept for the [UsageLedger] as its usage
/// is told, as Claude Code's are (see ClaudeUsageMeter).
///
/// A call is timed from when it was asked ([asking]: the turn sent, its
/// tools' results back, the call before answered) to its usage, unless
/// the CLI says how long it took; its first token is the first of its
/// answer streamed ([streamed]).
class AgentUsageMeter {
  AgentUsageMeter({
    required this.provider,
    required this.providerName,
    required this.session,
    void Function(UsageCall call)? record,
    DateTime Function()? clock,
  }) : _record = record ?? ((call) => UsageLedger.current.record(call)),
       _clock = clock ?? DateTime.now;

  /// The agent's id for the ledger (`codex`, `pi`), and its name.
  final String provider;
  final String providerName;

  /// The conversation's id as it is now.
  final String? Function() session;
  final void Function(UsageCall call) _record;
  final DateTime Function() _clock;

  DateTime? _askedAt;
  DateTime? _firstToken;

  /// A request is asked now.
  void asking() {
    _askedAt = _clock();
    _firstToken = null;
  }

  /// Some of the answer to the request asked came.
  void streamed() {
    if (_askedAt != null) _firstToken ??= _clock();
  }

  /// The request asked was answered: [input] is what was not read from the
  /// cache. The next is asked from now, unless said otherwise.
  void answered({
    required String model,
    String? protocol,
    String? providerName,
    int input = 0,
    int output = 0,
    int cacheRead = 0,
    int cacheWrite = 0,
    int reasoning = 0,
    String? stopReason,
    String? error,
    Duration? duration,
  }) {
    final now = _clock();
    final at = switch (duration) {
      final duration? => now.subtract(duration),
      null => _askedAt ?? now,
    };
    final firstToken = switch (_firstToken) {
      final first? when !first.isBefore(at) => first.difference(at),
      _ => null,
    };
    _record(
      UsageCall(
        at: at,
        duration: now.difference(at),
        firstToken: firstToken,
        status: error == null ? 200 : 0,
        error: error,
        provider: provider,
        providerName: providerName ?? this.providerName,
        protocol: protocol,
        model: model,
        session: session(),
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite,
        reasoning: reasoning,
        stopReason: stopReason,
      ),
    );
    asking();
  }
}
