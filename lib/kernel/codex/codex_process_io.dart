import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/local.dart' show ClaudeEnvironment;

import '../../network/network_proxy_io.dart';
import '../context_estimate.dart';
import '../jsonl_process_io.dart';
import 'codex_transport.dart';

/// `codex app-server` as a child process, over its stdin and stdout.
class CodexProcess extends JsonLinesProcess implements CodexTransport {
  CodexProcess(super.process) : super(exitMessage: CodexExit.message);
}

Future<CodexTransport> startCodexProcess(
  String cwd, {
  Map<String, String> environment = const {},
}) async {
  if (!Directory(cwd).existsSync()) {
    throw CodexUnavailable('The project folder is gone', detail: cwd);
  }
  // The login shell's: where Codex is installed, and what it is signed in
  // with.
  final variables = {
    ...await ClaudeEnvironment.of(),
    ...await NetworkProxy.instance.environment(),
    ...environment,
  };
  final executable = locateExecutable(variables, 'codex');
  if (executable == null) {
    throw const CodexUnavailable(
      'Codex is not installed',
      detail:
          'Install it, then try again:\n'
          'npm install -g @openai/codex',
    );
  }
  try {
    final process = await Process.start(
      executable,
      const ['app-server'],
      workingDirectory: cwd,
      environment: variables,
      includeParentEnvironment: Platform.isWindows,
      // An npm shim is a `.cmd`, which only the shell can run.
      runInShell: Platform.isWindows,
    );
    return CodexProcess(process);
  } on ProcessException catch (error) {
    throw CodexUnavailable(
      'Codex could not start',
      detail: '$executable\n${error.message}',
    );
  }
}

/// What every request of the thread in [rollout] starts with, as its first
/// request tells: its input less a guess at what the user sent. Null when
/// the file says no such thing (gone, or kept some other way).
Future<int?> readCodexFixedContext(String rollout) async {
  // Older Codex keeps what was sent as `user_message`, newer as a
  // `UserMessage` item: one or the other, counted apart.
  var messages = 0;
  var items = 0;
  try {
    final lines = File(rollout)
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.contains('"event_msg"')) continue;
      switch (jsonDecode(line)) {
        case {
          'type': 'event_msg',
          'payload': {
            'type': 'token_count',
            'info': {'last_token_usage': {'input_tokens': final int input}},
          },
        }:
          return input - (messages > items ? messages : items);
        case {
              'type': 'event_msg',
              'payload': {'type': 'user_message', 'message': final String text},
            } &&
            final Map<String, Object?> line:
          messages += estimateTokens(text);
          if ((line['payload'] as Map)['images'] case final List images) {
            messages += images.length * imageTokens;
          }
        case {
          'type': 'event_msg',
          'payload': {
            'type': 'item_completed',
            'item': {'type': 'UserMessage', 'content': final List content},
          },
        }:
          for (final block in content) {
            switch (block) {
              case {'type': 'text', 'text': final String text}:
                items += estimateTokens(text);
              case {'type': 'image'} || {'type': 'localImage'}:
                items += imageTokens;
            }
          }
      }
    }
  } on Object {
    // Not to be read: no guess.
  }
  return null;
}
