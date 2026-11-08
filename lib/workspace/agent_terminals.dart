// The terminals an agent works in with `baocode-agent pane`: in the
// window's side panel, in the agent's project, where the user sees all
// it types and can take over. One on a server is ssh to it, with nothing
// put there (see [sshArguments]). What the agent runs is told back once it
// is done where the shell reports its commands (VS Code's shell
// integration), else once the terminal has printed nothing for a while.
//
// A command that looks destructive ([destructiveCommand]) is only typed at
// the prompt: the user runs it, with Enter, or not. That guards against a
// slip, not against an agent set on it (a script it wrote runs as any).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:bao_remote/terminal.dart'
    show generateShellIntegrationNonce, shellIntegrationScripts;

import '../ide/terminal/shell_integration/capabilities/capabilities.dart'
    show ICommandDetectionCapability;
import '../ide/terminal/terminal_instance.dart';
import 'agent_host.dart';
import 'workspace.dart';

/// A terminal an agent opened, and where.
class _AgentTerminal {
  _AgentTerminal(this.id, this.owner, this.place, this.instance, this.host);

  /// Its name to the command: `p1`, `p2`, … shared with agent panes.
  final String id;
  final AgentThread owner;
  final AgentTerminalPlace place;
  final TerminalInstance instance;

  /// Brings it in sight, in its tab of the side panel.
  void show() => place.show(instance);

  /// The server it is ssh to; null for one on this machine.
  final String? host;

  /// How many commands the shell had reported before the one the agent
  /// waits for: one still running when `run` gave up, or one typed for the
  /// user to run. `wait-output` tells how it went, even once it is over.
  int? awaited;
}

/// `baocode-agent pane`'s terminals in the app: each project's side panel,
/// and what each command does with them.
class AgentTerminals {
  AgentTerminals(this.host);

  final AgentHost host;

  Workspace get workspace => host.workspace;

  /// How long a terminal without shell integration prints nothing before
  /// what it was sent counts as done; after `send-text` and `send-keys`,
  /// before the screen is read back. Shorter in tests.
  Duration quiet = const Duration(seconds: 2);
  Duration settle = const Duration(milliseconds: 500);

  /// How long `split` waits for the shell's first prompt.
  Duration opening = const Duration(seconds: 30);

  /// The most lines of output told back at once.
  static const maxLines = 200;

  final List<_AgentTerminal> _terminals = [];

  List<Map<String, Object?>> records(AgentThread caller) {
    _adopt(caller);
    return [for (final terminal in _openOf(caller)) _record(terminal, caller)];
  }

  Map<String, Object?>? record(AgentThread caller, String id) {
    final terminal = _find(caller, id);
    return terminal == null ? null : _record(terminal, caller);
  }

  Future<AgentReply> open(
    AgentThread caller, {
    String? ssh,
    String? cwd,
    bool show = true,
  }) async {
    try {
      return await _open(caller, ssh: ssh, cwd: cwd, show: show);
    } on _Refused catch (refused) {
      return AgentReply.jsonError(
        'cli:pane:split',
        refused.code,
        refused.message,
      );
    }
  }

  Future<AgentReply> run(
    AgentThread caller,
    String id,
    String command, {
    Duration? timeout,
  }) async {
    try {
      return await _run(
        _need(caller, id, 'cli:pane:run'),
        command,
        timeout ?? AgentHost.defaultWait,
      );
    } on _Refused catch (refused) {
      return AgentReply.jsonError(
        'cli:pane:run',
        refused.code,
        refused.message,
      );
    }
  }

  Future<AgentReply> sendText(
    AgentThread caller,
    String id,
    String text,
  ) async {
    try {
      return await _type(_need(caller, id, 'cli:pane:send-text'), text);
    } on _Refused catch (refused) {
      return AgentReply.jsonError(
        'cli:pane:send-text',
        refused.code,
        refused.message,
      );
    }
  }

  Future<AgentReply> sendKeys(
    AgentThread caller,
    String id,
    List<String> names,
  ) async {
    try {
      return await _keys(_need(caller, id, 'cli:pane:send-keys'), names);
    } on _Refused catch (refused) {
      return AgentReply.jsonError(
        'cli:pane:send-keys',
        refused.code,
        refused.message,
      );
    }
  }

  AgentReply read(
    AgentThread caller,
    String id, {
    String source = 'recent',
    int? lines,
  }) {
    try {
      return _read(
        _need(caller, id, 'cli:pane:read'),
        source: source,
        lines: lines,
      );
    } on _Refused catch (refused) {
      return AgentReply.jsonError(
        'cli:pane:read',
        refused.code,
        refused.message,
      );
    }
  }

  Future<AgentReply> waitOutput(
    AgentThread caller,
    String id, {
    String? match,
    String? regex,
    Duration? timeout,
    String source = 'recent',
    int? lines,
  }) async {
    try {
      return await _waitOutput(
        _need(caller, id, 'cli:pane:wait-output'),
        match: match,
        regex: regex,
        timeout: timeout ?? AgentHost.defaultWait,
        source: source,
        lines: lines,
      );
    } on _Refused catch (refused) {
      return AgentReply.jsonError(
        'cli:pane:wait-output',
        refused.code,
        refused.message,
      );
    }
  }

  AgentReply close(AgentThread caller, String id) {
    try {
      final terminal = _need(caller, id, 'cli:pane:close');
      terminal.place.service.kill(
        terminal.instance,
        TerminalExitReason.extension,
      );
      _terminals.remove(terminal);
      return AgentReply.json('cli:pane:close', {
        'type': 'ok',
        'pane_id': id,
        'closed': true,
      });
    } on _Refused catch (refused) {
      return AgentReply.jsonError(
        'cli:pane:close',
        refused.code,
        refused.message,
      );
    }
  }

  Future<AgentReply> _open(
    AgentThread caller, {
    String? ssh,
    String? cwd,
    bool show = true,
  }) async {
    if (ssh != null && (ssh.trim().isEmpty || ssh.startsWith('-'))) {
      throw const _Refused(
        '--ssh takes a host as ssh does: user@host, or a Host of ~/.ssh/config.',
      );
    }
    final place = workspace.agentTerminals?.call(caller);
    if (place == null) {
      throw const _Refused(
        'BaoCode has no terminals here: they need its chat window.',
      );
    }
    final id = host.nextPaneId();
    final nonce = generateShellIntegrationNonce();
    final instance = place.service.create(
      config: TerminalLaunchConfig(
        name: ssh == null ? 'Agent $id' : 'ssh $ssh',
        executable: ssh == null ? null : 'ssh',
        arguments: ssh == null ? null : sshArguments(ssh, nonce),
        cwd: cwd,
        shellIntegrationNonce: ssh == null ? null : nonce,
        // Kept once it exits, for the agent to read why.
        waitOnExit: (_) => 'Press any key to close the terminal.',
      ),
    );
    final terminal = _AgentTerminal(id, caller, place, instance, ssh);
    _terminals.add(terminal);
    if (show) terminal.show();
    // Its first prompt; or, without shell integration, ssh asking for a
    // password, say: until it prints nothing for a while.
    await _until(
      instance,
      done: () => _detection(instance) != null,
      quiet: () => _printed(instance) ? quiet : null,
      timeout: opening,
    );
    // The prompt's first sequence comes before the prompt is drawn.
    if (!instance.exited) {
      await _until(instance, quiet: () => settle, timeout: settle * 10);
    }
    if (instance.exited) {
      throw _Refused(
        '$id, ${ssh == null ? 'in your project' : 'ssh to $ssh'}, '
        '${_state(terminal)} before it had a prompt.',
        code: 'pane_exited',
      );
    }
    return AgentReply.json('cli:pane:split', {
      'type': 'pane_info',
      'pane': _record(terminal, caller),
    });
  }

  Future<AgentReply> _run(
    _AgentTerminal terminal,
    String text,
    Duration timeout,
  ) async {
    if (text.trim().isEmpty) throw const _Refused('run takes a command.');
    final instance = _alive(terminal);
    for (final line in _lines(text)) {
      if (destructiveCommand(line) case final reason?) {
        return _typeOnly(terminal, text, reason);
      }
    }
    final detection = _detection(instance);
    if (detection != null && !_executing(detection)) {
      final before = detection.commands.length;
      terminal.awaited = before;
      await instance.runCommand(text);
      await _until(
        instance,
        done: () => detection.commands.length > before,
        timeout: timeout,
      );
      return _finished(terminal, detection, before, timeout);
    }
    // No prompt to know it by (no shell integration, or a program reads
    // the line): sent, then read once the terminal is quiet.
    final from = instance.terminal.registerMarker(0);
    try {
      instance.sendText(text, shouldExecute: true);
      final quiet = await _until(
        instance,
        quiet: () => this.quiet,
        timeout: timeout,
      );
      final output = _text(instance, from.line);
      return AgentReply.json('cli:pane:run', {
        'type': 'ok',
        'pane_id': terminal.id,
        'command': text,
        'output': output,
        'guess': true,
        'running': !quiet,
      });
    } finally {
      from.dispose();
    }
  }

  /// [text] typed at the prompt, not run, as its line [reason] says why.
  AgentReply _typeOnly(_AgentTerminal terminal, String text, String reason) {
    final instance = terminal.instance;
    if (text.contains('\n') &&
        !instance.terminal.coreService.decPrivateModes.bracketedPasteMode) {
      throw _Refused(
        '${terminal.id}: that looks destructive ($reason), and its shell would '
        'run its lines as they are typed: run it one line at a time.',
      );
    }
    terminal.awaited = _detection(instance)?.commands.length;
    unawaited(instance.runCommand(text, shouldExecute: false));
    terminal.show();
    return AgentReply.json('cli:pane:run', {
      'type': 'ok',
      'pane_id': terminal.id,
      'command': text,
      'destructive': true,
      'ran': false,
      'reason': reason,
    });
  }

  /// What the command run after [before] of [detection]'s did; still
  /// running after [timeout] when there is none.
  AgentReply _finished(
    _AgentTerminal terminal,
    ICommandDetectionCapability detection,
    int before,
    Duration timeout,
  ) {
    final instance = terminal.instance;
    final commands = detection.commands;
    if (commands.length <= before) {
      if (instance.exited) {
        throw _Refused(_exitedMessage(terminal), code: 'pane_exited');
      }
      if (!_executing(detection)) {
        final typed = detection.promptInputModel.value;
        if (typed.trim().isEmpty) {
          terminal.awaited = null;
          return AgentReply.json('cli:pane:run', {
            'type': 'ok',
            'pane_id': terminal.id,
            'ran': false,
            'output': _screen(instance),
          });
        }
        return AgentReply.json('cli:pane:run', {
          'type': 'ok',
          'pane_id': terminal.id,
          'waiting_for_user': true,
          'command': typed,
          'output': _screen(instance),
        });
      }
      return AgentReply.json('cli:pane:run', {
        'type': 'ok',
        'pane_id': terminal.id,
        'running': true,
        'command': detection.executingCommand,
        'output': _screen(instance),
      });
    }
    terminal.awaited = null;
    final command = commands[before];
    final output = _cut(command.getOutput()?.trimRight() ?? '');
    return AgentReply.json('cli:pane:run', {
      'type': 'ok',
      'pane_id': terminal.id,
      'command': command.command,
      'exit_code': command.exitCode,
      'output': output,
    });
  }

  Future<AgentReply> _type(_AgentTerminal terminal, String text) async {
    if (text.isEmpty) {
      throw const _Refused('send-text takes the text to type.');
    }
    final instance = _alive(terminal);
    final lines = text.split(RegExp(r'\r\n|\r|\n'));
    _checkEntered(terminal, [
      for (var i = 0; i < lines.length - 1; i++)
        i == 0 ? _input(instance) + lines[i] : lines[i],
    ]);
    instance.sendText(text);
    return _settled(terminal, 'cli:pane:send-text');
  }

  Future<AgentReply> _keys(_AgentTerminal terminal, List<String> names) async {
    if (names.isEmpty) {
      throw const _Refused('send-keys takes the keys to press.');
    }
    final instance = _alive(terminal);
    final modes = instance.terminal.coreService.decPrivateModes;
    final sequences = [
      for (final name in names)
        keySequence(name, applicationCursor: modes.applicationCursorKeys) ??
            (throw _Refused('No key "$name": see baocode-agent pane.')),
    ];
    // Only the first Enter can run what is at the prompt: the keys type
    // nothing else of a line.
    if (sequences.any((keys) => keys == '\r' || keys == '\n')) {
      _checkEntered(terminal, [_input(instance)]);
    }
    for (final keys in sequences) {
      instance.writeText(keys);
    }
    return _settled(terminal, 'cli:pane:send-keys');
  }

  /// Refuses Enter on any of [lines] that looks destructive.
  void _checkEntered(_AgentTerminal terminal, List<String> lines) {
    for (final line in lines) {
      if (destructiveCommand(line) case final reason?) {
        throw _Refused(
          '${terminal.id}: Enter would run ${_quote(line.trim())}, which looks '
          'destructive ($reason). Send it with baocode-agent pane run '
          '${terminal.id} instead, for the user to run it.',
        );
      }
    }
  }

  /// The screen once [terminal] has taken what it was sent.
  Future<AgentReply> _settled(_AgentTerminal terminal, String id) async {
    final instance = terminal.instance;
    await _until(instance, quiet: () => settle, timeout: settle * 10);
    return AgentReply.json(id, {
      'type': 'ok',
      'pane_id': terminal.id,
      'text': _screen(instance),
    });
  }

  AgentReply _read(
    _AgentTerminal terminal, {
    required String source,
    int? lines,
  }) {
    final instance = terminal.instance;
    final text = _snapshot(instance, source, lines);
    final all = _snapshot(instance, source, null);
    return AgentReply.json('cli:pane:read', {
      'type': 'pane_read',
      'read': {
        'pane_id': terminal.id,
        'source': source == 'recent-unwrapped' ? 'recent_unwrapped' : source,
        'format': 'text',
        'text': text,
        'truncated': lines != null && all.split('\n').length > lines,
      },
    });
  }

  Future<AgentReply> _waitOutput(
    _AgentTerminal terminal, {
    String? match,
    String? regex,
    required Duration timeout,
    required String source,
    int? lines,
  }) async {
    final RegExp pattern;
    try {
      pattern = regex != null
          ? RegExp(regex, multiLine: true)
          : RegExp(RegExp.escape(match!), multiLine: true);
    } on FormatException catch (error) {
      throw _Refused('--regex takes a regular expression: ${error.message}');
    }
    final instance = terminal.instance;
    if (instance.exited) {
      throw _Refused(_exitedMessage(terminal), code: 'pane_exited');
    }
    String snapshot() => _snapshot(instance, source, lines);
    bool found() => pattern.hasMatch(snapshot());
    if (found()) {
      return _matched(terminal, snapshot(), source);
    }
    final ended = await _until(instance, done: found, timeout: timeout);
    if (!ended || !found()) {
      throw _Refused(
        'timed out waiting for output match. Wait again: baocode-agent '
        'pane wait-output ${terminal.id}',
        code: 'timeout',
      );
    }
    return _matched(terminal, snapshot(), source);
  }

  AgentReply _matched(_AgentTerminal terminal, String text, String source) {
    return AgentReply.json('cli:pane:wait-output', {
      'type': 'output_matched',
      'pane_id': terminal.id,
      'read': {
        'pane_id': terminal.id,
        'source': source == 'recent-unwrapped' ? 'recent_unwrapped' : source,
        'format': 'text',
        'text': text,
        'truncated': false,
      },
    });
  }

  Map<String, Object?> _record(_AgentTerminal terminal, AgentThread caller) => {
    'pane_id': terminal.id,
    'kind': 'terminal',
    'name': null,
    'agent': null,
    'agent_kind': null,
    'agent_status': 'unknown',
    'title': terminal.instance.title,
    'project': caller.project.name,
    'cwd': terminal.instance.shellIntegration?.cwd ?? caller.project.path,
    'is_caller': false,
    'focused': false,
    if (terminal.host != null) 'host': terminal.host,
    'state': _state(terminal),
  };

  String _snapshot(TerminalInstance instance, String source, int? lines) {
    final text = switch (source) {
      'visible' => _screen(instance),
      'recent' => _rendered(instance),
      'recent-unwrapped' => _text(instance, 0),
      _ => throw const _Refused(
        '--source is visible, recent or recent-unwrapped.',
      ),
    };
    if (lines == null) return text;
    return _last(text, math.min(lines, 2000));
  }

  /// Names the project's terminals the user opened, so `list` and the
  /// rest can reach them by the same ids as those an agent opened.
  void _adopt(AgentThread caller) {
    final place = workspace.agentTerminals?.call(caller);
    if (place == null) return;
    for (final instance in place.service.instances) {
      if (_terminals.any(
        (terminal) => identical(terminal.instance, instance),
      )) {
        continue;
      }
      _terminals.add(
        _AgentTerminal(host.nextPaneId(), caller, place, instance, null),
      );
    }
  }

  Iterable<_AgentTerminal> _openOf(AgentThread caller) {
    final place = workspace.agentTerminals?.call(caller);
    return [
      for (final terminal in _terminals)
        if (_isOpen(terminal) &&
            (place == null || identical(terminal.place.service, place.service)))
          terminal,
    ];
  }

  _AgentTerminal? _find(AgentThread caller, String id) {
    _adopt(caller);
    final place = workspace.agentTerminals?.call(caller);
    final terminal = _terminals.where((t) => t.id == id).firstOrNull;
    if (terminal == null ||
        (place != null && !identical(terminal.place.service, place.service))) {
      return null;
    }
    if (!_isOpen(terminal)) {
      _terminals.remove(terminal);
      return null;
    }
    return terminal;
  }

  _AgentTerminal _need(AgentThread caller, String id, String _) {
    final terminal = _find(caller, id);
    if (terminal == null) {
      throw _Refused('pane $id not found', code: 'pane_not_found');
    }
    return terminal;
  }

  static bool _isOpen(_AgentTerminal terminal) =>
      terminal.place.service.allInstances.contains(terminal.instance);

  /// [terminal]'s instance, its process running.
  TerminalInstance _alive(_AgentTerminal terminal) {
    if (terminal.instance.exited) {
      throw _Refused(_exitedMessage(terminal), code: 'pane_exited');
    }
    return terminal.instance;
  }

  String _exitedMessage(_AgentTerminal terminal) {
    final code = terminal.instance.exitCode;
    return '${terminal.id} has exited${code == null ? '' : ' ($code)'}';
  }

  /// What [terminal] is doing, in a few words.
  static String _state(_AgentTerminal terminal) {
    final instance = terminal.instance;
    if (instance.exited) {
      final code = instance.exitCode;
      return 'exited${code == null ? '' : ' ($code)'}';
    }
    final detection = _detection(instance);
    if (detection == null) return 'no shell integration';
    if (_executing(detection)) {
      return 'running ${_quote(detection.executingCommand)}';
    }
    final cwd = instance.shellIntegration?.cwd;
    return cwd == null ? 'at the prompt' : 'at the prompt in $cwd';
  }

  static ICommandDetectionCapability? _detection(TerminalInstance instance) =>
      instance.shellIntegration?.commandDetection;

  /// Whether a command runs, past its prompt.
  static bool _executing(ICommandDetectionCapability detection) =>
      detection.currentCommand?.commandExecutedMarker != null;

  /// What Enter would run: at a prompt the shell reports, what is typed
  /// at it; else the cursor's line, whatever prompt it starts with.
  static String _input(TerminalInstance instance) {
    final detection = _detection(instance);
    if (detection != null && !_executing(detection)) {
      return detection.promptInputModel.value;
    }
    final buffer = instance.terminal.buffer;
    return buffer.translateBufferLineToString(buffer.ybase + buffer.y, true);
  }

  /// Whether [instance] has printed anything yet.
  static bool _printed(TerminalInstance instance) {
    final buffer = instance.terminal.buffer;
    return buffer.ybase + buffer.y > 0 || buffer.x > 0;
  }

  /// Waits until [done] (checked at once, then each time the terminal has
  /// parsed what was printed), or the terminal has printed nothing for
  /// [quiet] (when it gives one), or its process exits or it is closed;
  /// false when [timeout] came first.
  static Future<bool> _until(
    TerminalInstance instance, {
    bool Function()? done,
    Duration? Function()? quiet,
    required Duration timeout,
  }) async {
    final ended = Completer<bool>();
    void end(bool value) {
      if (!ended.isCompleted) ended.complete(value);
    }

    Timer? quietTimer;
    void check() {
      if (instance.exited || (done?.call() ?? false)) return end(true);
      quietTimer?.cancel();
      if (quiet?.call() case final quiet?) {
        quietTimer = Timer(quiet, () => end(true));
      }
    }

    final parsed = instance.terminal.onWriteParsed((_) => check());
    final exits = instance.onProcessExit.listen(
      (_) => end(true),
      onDone: () => end(true),
    );
    final timer = Timer(timeout, () => end(false));
    check();
    try {
      return await ended.future;
    } finally {
      parsed.dispose();
      unawaited(exits.cancel());
      quietTimer?.cancel();
      timer.cancel();
    }
  }

  /// The screen's lines, without the empty ones under the last.
  static String _screen(TerminalInstance instance) {
    final buffer = instance.terminal.buffer;
    return _text(instance, buffer.ybase, buffer.ybase + instance.rows);
  }

  /// Scrollback as rendered, wrapped lines kept separate.
  static String _rendered(TerminalInstance instance) {
    final lines = instance.terminal.buffer.lines;
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines.get(i);
      if (line == null) continue;
      out.add(line.translateToString(true));
    }
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    return _cut(out.join('\n'));
  }

  /// [instance]'s lines from [from] to [to] (the end by default), wrapped
  /// ones joined, without the empty ones at the end; at most [maxLines].
  static String _text(TerminalInstance instance, int from, [int? to]) {
    final lines = instance.terminal.buffer.lines;
    final end = math.min(to ?? lines.length, lines.length);
    final out = <String>[];
    var current = StringBuffer();
    for (var i = math.max(from, 0); i < end; i++) {
      final line = lines.get(i);
      if (line == null) continue;
      final wraps = i + 1 < end && (lines.get(i + 1)?.isWrapped ?? false);
      current.write(line.translateToString(!wraps));
      if (!wraps) {
        out.add(current.toString());
        current = StringBuffer();
      }
    }
    if (current.isNotEmpty) out.add(current.toString());
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    return _cut(out.join('\n'));
  }

  /// [text] with only its last [maxLines] lines, saying how many went.
  static String _cut(String text) => _last(text, maxLines);

  static String _last(String text, int count) {
    final lines = text.split('\n');
    if (lines.length <= count) return text;
    return lines.skip(lines.length - count).join('\n');
  }

  static Iterable<String> _lines(String text) =>
      text.split(RegExp(r'\r\n|\r|\n'));

  static String _quote(String? command) {
    final text = (command ?? '').trim();
    if (text.isEmpty) return 'a command';
    final line = text.split('\n').first;
    return '`${line.length > 80 ? '${line.substring(0, 80)}…' : line}`';
  }
}

/// What `ssh` runs with for a terminal on [destination]: bash there with
/// VS Code's shell integration, trusting [nonce]. The script goes with the
/// command, into a file of the user's only that it deletes as bash reads it
/// (bash reads an init file whole before running it): nothing is left on
/// the server. Read from a pipe (`<(…)`) instead, bash now and then reads
/// nothing. Where there is no bash, the user's shell there, logged in.
List<String> sshArguments(String destination, String nonce) {
  final script = base64.encode(
    utf8.encode(
      'command rm -f -- "\$BAOCODE_INIT_FILE"; unset BAOCODE_INIT_FILE\n'
      '${shellIntegrationScripts['shellIntegration-bash.sh']!}',
    ),
  );
  // Run by sh whatever the user's shell there is (fish, csh, …).
  final start =
      r'if command -v bash >/dev/null 2>&1 && f=$(mktemp 2>/dev/null); then '
      'if printf %s $script | base64 -d >"\$f" 2>/dev/null; then '
      'export VSCODE_INJECTION=1 VSCODE_SHELL_LOGIN=1 VSCODE_NONCE=$nonce '
      r'BAOCODE_INIT_FILE="$f"; exec bash --init-file "$f" -i; fi; '
      r'rm -f "$f"; fi; exec "${SHELL:-/bin/sh}" -l';
  return ['-t', '--', destination, "exec sh -c '$start'"];
}

/// The server [command] (a shell command line) runs ssh to, for a shell or
/// a command there; null for none: no ssh (scp, rsync, ssh-keygen), ssh to
/// a git host (`git@…`, `ssh -T git@github.com`), or none named (`ssh -V`).
String? sshDestination(String command) {
  for (final call in _sshCall.allMatches(command)) {
    final words = [
      for (final match in _shellWord.allMatches(command.substring(call.end)))
        match[0]!,
    ];
    String? destination;
    for (var i = 0; i < words.length && destination == null; i++) {
      final word = words[i];
      if (RegExp(r'^[;&|)]').hasMatch(word)) break;
      if (word == '--') {
        destination = words.elementAtOrNull(i + 1);
      } else if (word.startsWith('-') && word.length > 1) {
        // A cluster of flags (-tt, -NL): the first that takes a value takes
        // the rest of it, else the next word.
        for (var at = 1; at < word.length; at++) {
          if (_sshValued.contains(word[at])) {
            if (at == word.length - 1) i++;
            break;
          }
        }
      } else {
        destination = word;
      }
    }
    if (destination == null || RegExp(r'^[;&|)]').hasMatch(destination)) {
      continue;
    }
    destination = destination.replaceAll(RegExp(r'''^["']|["']$'''), '');
    final host = destination.split('@').last.split(':').first;
    if (destination.startsWith('git@') || _gitHosts.contains(host)) continue;
    return destination;
  }
  return null;
}

/// ssh where a command starts: at the line's start or after `;`, `&&`,
/// `|`, `(`, `$(`, a backquote; after `sudo`, `env`, `timeout 30`, `X=1`.
final _sshCall = RegExp(
  r'(?:^|[;&|(\n`]|\$\()\s*'
  r'(?:(?:sudo|env|exec|nohup|command|time|timeout\s+\S+)\s+|\w+=\S*\s+)*'
  r'ssh(?=\s|$)',
);

/// A word of a command line, quoted or not, or what ends a command.
final _shellWord = RegExp(r'''"[^"]*"|'[^']*'|[^\s;&|)]+|[;&|)]''');

/// ssh's flags that take a value (`-p 22`, `-i key`).
const _sshValued = 'BbcDEeFIiJLlmOopQRSWw';

const _gitHosts = {
  'github.com',
  'ssh.github.com',
  'gitlab.com',
  'bitbucket.org',
};

/// Why [line] looks destructive, in a few words; null when it does not.
/// Wherever it is in the line (after `sudo`, `;` or `&&` too).
String? destructiveCommand(String line) {
  for (final (pattern, reason) in _destructive) {
    if (pattern.hasMatch(line)) return reason;
  }
  return null;
}

final _destructive = <(RegExp, String)>[
  (
    RegExp(
      r'(^|[\s;&|(`])rm\s+(.*\s)?(-[a-zA-Z]*[rRf]|--recursive\b|--force\b)',
    ),
    'rm -r/-f',
  ),
  (RegExp(r'\bfind\b.*\s-delete\b'), 'find -delete'),
  (RegExp(r'\b(mkfs(\.\w+)?|wipefs|shred)\b'), 'wipes a disk or file'),
  (RegExp(r'\bdd\b.*\bof=/dev/'), 'dd to a device'),
  (RegExp(r'>\s*/dev/(sd|hd|vd|xvd|nvme|disk|mmcblk)'), 'writes over a device'),
  (
    RegExp(r'\b(shutdown|reboot|halt|poweroff)\b|\binit\s+[06]\b'),
    'stops the machine',
  ),
  (
    RegExp(
      r'\b(chmod|chown|chgrp)\s+(.*\s)?(-[a-zA-Z]*R|--recursive\b).*'
      r'\s(/|/\*|~|/(etc|usr|bin|sbin|lib|boot|var|home|root))/?(\s|$)',
    ),
    'recursive permissions on a system folder',
  ),
  (RegExp(r':\(\)\s*\{.*:\s*\|\s*:.*\}'), 'fork bomb'),
  (RegExp(r'\bkill\s+-(9|KILL)\s+-1\b'), 'kills every process'),
  (RegExp(r'\bcrontab\s+(.*\s)?-r\b'), 'removes the crontab'),
  (
    RegExp(
      r'\bgit\s+(push\b.*(\s--force\b|\s-f\b|\s--force-with-lease\b)|'
      r'reset\s+--hard\b|clean\s+-\w*f)',
    ),
    'git history or files lost',
  ),
  (
    RegExp(
      r'\b(drop\s+(database|schema|table)|truncate\s+table)\b',
      caseSensitive: false,
    ),
    'drops data',
  ),
  (
    RegExp(
      r'\bdocker\s+((system|volume|image|container)\s+prune|volume\s+rm)\b',
    ),
    'removes Docker data',
  ),
  (RegExp(r'\bkubectl\s+delete\b'), 'kubectl delete'),
];

/// What pressing the key [name] sends: `enter`, `ctrl+c`, `esc`, `up`, …
/// (case aside); null for no key. The arrows as the application asked
/// ([applicationCursor]: DECCKM).
String? keySequence(String name, {bool applicationCursor = false}) {
  final arrow = applicationCursor ? '\x1bO' : '\x1b[';
  final key = name.toLowerCase();
  if (_named[key] case final sequence?) return sequence;
  switch (key) {
    case 'up':
      return '${arrow}A';
    case 'down':
      return '${arrow}B';
    case 'right':
      return '${arrow}C';
    case 'left':
      return '${arrow}D';
    case 'home':
      return '${arrow}H';
    case 'end':
      return '${arrow}F';
  }
  if (RegExp(r'^(c|ctrl)[-+](.)$').firstMatch(key) case final match?) {
    final char = match[2]!;
    final code = char.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7a) return String.fromCharCode(code - 0x60);
    return switch (char) {
      '@' || ' ' => '\x00',
      '[' => '\x1b',
      r'\' => '\x1c',
      ']' => '\x1d',
      '^' => '\x1e',
      '_' => '\x1f',
      '?' => '\x7f',
      _ => null,
    };
  }
  if (RegExp(r'^(m|alt)[-+](.)$').firstMatch(name.toLowerCase()) != null) {
    // The key as typed, its case kept: M-b, M-B, alt+b.
    return '\x1b${name.substring(name.length - 1)}';
  }
  // A character's key: itself (q, y, :, 中).
  if (name.runes.length == 1) return name;
  return null;
}

const _named = {
  'enter': '\r',
  'return': '\r',
  'tab': '\t',
  'esc': '\x1b',
  'escape': '\x1b',
  'space': ' ',
  'backspace': '\x7f',
  'bspace': '\x7f',
  'delete': '\x1b[3~',
  'del': '\x1b[3~',
  'insert': '\x1b[2~',
  'pageup': '\x1b[5~',
  'pgup': '\x1b[5~',
  'pagedown': '\x1b[6~',
  'pgdn': '\x1b[6~',
  'f1': '\x1bOP',
  'f2': '\x1bOQ',
  'f3': '\x1bOR',
  'f4': '\x1bOS',
  'f5': '\x1b[15~',
  'f6': '\x1b[17~',
  'f7': '\x1b[18~',
  'f8': '\x1b[19~',
  'f9': '\x1b[20~',
  'f10': '\x1b[21~',
  'f11': '\x1b[23~',
  'f12': '\x1b[24~',
};

/// A command that cannot be done, and why: printed as it fails.
class _Refused implements Exception {
  const _Refused(this.message, {this.code = 'invalid_request'});

  final String message;
  final String code;
}
