// What an agent's `baocode-agent` command asks of the app: to start other
// agents beside it, send them work, wait for them and read what they said,
// to work in the panes the user already opened, and to work in terminals
// (agent_terminals.dart; the baocode-agents skill tells agents how). The
// command is a script that posts its arguments to a server of the app's, at
// the address each agent's process is given; the answer is what it prints.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../chat/chat_session.dart' show ComposerMessage;
import '../kernel/agent_kernel.dart' show KernelChoiceKind, KernelDescriptor;
import '../kernel/claude_code/claude_sdk_tools.dart';
import '../kernel/kernel_types.dart';
import '../remote/remote_location.dart';
import 'agent_terminals.dart';
import 'chat_grid.dart' show PaneSide;
import 'workspace.dart';

/// What the command prints, and whether it did what it was asked.
class AgentReply {
  const AgentReply(this.text, {this.ok = true});

  const AgentReply.error(this.text) : ok = false;

  factory AgentReply.json(String id, Map<String, Object?> result) =>
      AgentReply(jsonEncode({'id': id, 'result': result}));

  factory AgentReply.jsonError(String id, String code, String message) =>
      AgentReply.error(
        jsonEncode({
          'id': id,
          'error': {'code': code, 'message': message},
        }),
      );

  final String text;
  final bool ok;
}

/// An agent another started (see [AgentHost._start]).
class _Worker {
  _Worker(this.name, this.thread, this.owner);

  final String name;
  final AgentThread thread;
  final AgentThread owner;
}

/// The agents' command's side in the app: who calls (each agent's process
/// is given an address of its own), and what each command does.
class AgentHost {
  AgentHost(this.workspace) {
    workspace.agentEnvironment = environmentOf;
  }

  final Workspace workspace;

  /// The terminals agents open (`baocode-agent pane split`).
  late final AgentTerminals terminals = AgentTerminals(this);

  /// The server's address, once it listens (`http://127.0.0.1:<port>`).
  String? url;

  /// The command's path, once written.
  String? command;

  static const urlVariable = 'BAOCODE_AGENT_URL';
  static const commandVariable = 'BAOCODE_AGENT';
  static const paneIdVariable = 'BAOCODE_PANE_ID';

  /// How long `pane run` waits by default: under the two minutes Claude
  /// Code gives a command before it stops it.
  static const defaultWait = Duration(seconds: 100);
  static const longestWait = Duration(minutes: 30);

  static final _namePattern = RegExp(r'^[a-z][a-z0-9_-]{0,31}$');
  static final _paneIdPattern = RegExp(r'^p[1-9]\d*$');

  /// The approval mode an agent started by another works in, by kernel:
  /// full access, running what it runs without asking. A kernel not here
  /// asks nothing anyway (pi).
  static const _fullAccess = {
    'claude-code': 'bypassPermissions',
    'codex': 'full',
  };

  static final _random = math.Random.secure();

  final Map<String, AgentThread> _callers = {};
  final Expando<String> _keys = Expando();
  final List<_Worker> _workers = [];
  final Map<AgentThread, String> _ids = {};
  final Map<AgentThread, String> _names = {};
  final Map<AgentThread, int> _sentAfter = {};
  int _named = 0;

  /// The variables [thread]'s process starts with: where to reach the app,
  /// as [thread]. None before the server listens, nor for an agent on
  /// another machine (it could not reach this one's).
  Map<String, String> environmentOf(AgentThread thread) {
    final (url, command) = (this.url, this.command);
    if (url == null ||
        command == null ||
        RemoteLocation.isRemote(thread.project.path)) {
      return const {};
    }
    final key = _keys[thread] ??= _newKey();
    _callers[key] = thread;
    return {
      urlVariable: '$url/$key',
      commandVariable: command,
      paneIdVariable: paneIdOf(thread),
    };
  }

  static String _newKey() =>
      [for (var i = 0; i < 24; i++) _random.nextInt(256).toRadixString(16)]
          .join();

  /// A new pane id for this run: agents and terminals share `p1`, `p2`, …
  String nextPaneId() => 'p${++_named}';

  /// [thread]'s pane id, assigned once and kept for this run.
  String paneIdOf(AgentThread thread) => _ids[thread] ??= nextPaneId();

  /// What `baocode-agent` [arguments] does, called by the agent of [key];
  /// [input], what a hook was given.
  Future<AgentReply> run(
    String key,
    List<String> arguments, {
    String? input,
  }) async {
    final caller = _callers[key];
    if (caller == null || !workspace.threads.contains(caller)) {
      return AgentReply.jsonError(
        'cli',
        'agent_not_found',
        'This agent is no longer in BaoCode.',
      );
    }
    final [command, ...rest] = arguments.isEmpty ? ['help'] : arguments;
    try {
      return switch (command) {
        'pane' => await _pane(caller, rest),
        'agent' => await _agent(caller, rest),
        'hook' => _hook(rest, input),
        'help' || '--help' || '-h' => const AgentReply(usage),
        _ => AgentReply.jsonError(
          'cli',
          'unknown_command',
          'Unknown command "$command".',
        ),
      };
    } on _Refused catch (refused) {
      return AgentReply.jsonError(refused.id, refused.code, refused.message);
    }
  }

  /// The app's tools ([ClaudeSdkTools]) as an MCP server for the agent of
  /// [key], which has no other way to them (Codex, pi): the answer to
  /// [message] (JSON-RPC), none for a notification.
  Future<Map<String, Object?>?> mcp(
    String key,
    Map<String, Object?> message,
  ) async {
    final caller = _callers[key];
    if (caller == null || !workspace.threads.contains(caller)) {
      return {
        'jsonrpc': '2.0',
        'id': message['id'],
        'error': {
          'code': -32001,
          'message': 'This agent is no longer in BaoCode.',
        },
      };
    }
    // Its calls under way are its own (notifications/cancelled finds them
    // by its key).
    final answer = await ClaudeSdkTools.handle(
      message,
      ClaudeSdkCall(cwd: caller.project.path, sessionId: key),
    );
    return message.containsKey('id') ? answer : null;
  }

  static const usage = '''
Usage: baocode-agent <command>

  pane <command>     Control panes (agent chats in the grid, terminals in
                     the side panel). See baocode-agent pane.
  agent <command>    Control coding agents. See baocode-agent agent.
  help               This help.''';

  static const paneUsage = '''
Usage: baocode-agent pane [command]

Commands:
  list                 List panes: you, agent panes on screen (any project),
                       agents you started, and terminals in this project's
                       side panel.
  current [--current]  The focused pane, or yours with --current.
  get <pane>           Show a pane.
  split [--current|<pane>] [--direction right|down] [--cwd <path>] [--no-focus] [--ssh <host>]
                       Open a terminal in BaoCode's side panel. --direction
                       is accepted and ignored (terminals are not in the
                       grid). --ssh is a BaoCode extension: a shell on
                       <host>, nothing installed there.
  run <pane> <command> Run <command> in a terminal (text + Enter), wait until
                       it is done, print output and exit code. A command that
                       looks destructive is only typed. Not an agent pane.
  send-text <pane> <text>
                       Type <text> in a terminal, without Enter.
  send-keys <pane> <key>...
                       Press keys: enter, esc, tab, up, down, left, right,
                       space, backspace, delete, ctrl+c, ctrl+d, … (Enter
                       and C-c still work). On an agent pane, only esc /
                       ctrl+c (stop the turn).
  read <pane> [--source visible|recent|recent-unwrapped] [--lines N]
                       A terminal's screen, or an agent pane's last answer.
  wait-output <pane> (--match <text>|--regex <re>) [--timeout <ms>]
                       Wait until a terminal shows the text. Not an agent
                       pane. Default 100s; --timeout is milliseconds and
                       must stay under how long the shell lets a command
                       run. On timeout, wait-output again.
  close <pane>         Close a terminal, or an agent pane (it stays in the
                       sidebar). Not yourself.''';

  static const agentUsage = '''
Usage: baocode-agent agent [command]

Commands:
  list                 Agents on screen, you, and agents you started.
  get <name|pane>      Show an agent.
  start <name> --kind claude|codex|pi [--model <id>] [--effort <level>] [--pane <anchor>] [--direction right|down] [--no-focus] [-- <prompt>]
                       Start an agent in a new pane beside the anchor (you
                       by default). Name: [a-z][a-z0-9_-]{0,31}, unique
                       among live agents. Without a prompt, only starts.
                       An agent started by another cannot start agents.
  prompt <name|pane> <text> [--wait] [--timeout <ms>] [--until idle|working|blocked|done]
                       Send a prompt. Refused with agent_blocked if it is
                       waiting for the user's approval. --wait then waits
                       for idle, done or blocked (or --until). Default 100s;
                       --timeout is milliseconds and must stay under how
                       long the shell lets a command run. On timeout, wait
                       again.
  wait <name|pane> [--until idle|working|blocked|done] [--timeout <ms>]
                       Wait until that status. Default: idle, done or
                       blocked. Default 100s; --timeout as for prompt.
                       On timeout, wait again.
  read <name|pane> [--lines N]
                       The last answer.
  send-keys <name|pane> esc|ctrl+c
                       Stop the current turn.
  rename <pane> <name> Name an agent for the command (same rules as start).
                       Does not change the sidebar title.''';

  /// The hooks BaoCode gives its agents (see ClaudeLaunch.settings):
  /// `pre-tool-use` turns ssh to a server in the agent's shell, out of the
  /// user's sight, to a terminal of BaoCode's ([sshDestination]). Nothing
  /// printed lets the tool be.
  AgentReply _hook(List<String> arguments, String? input) {
    if (arguments.firstOrNull != 'pre-tool-use' || input == null) {
      return const AgentReply('');
    }
    final Object? event;
    try {
      event = jsonDecode(input);
    } on FormatException {
      return const AgentReply('');
    }
    if (event case {
      'tool_name': 'Bash',
      'tool_input': {'command': final String command},
    }) {
      if (sshDestination(command) case final host?) {
        return AgentReply(
          jsonEncode({
            'hookSpecificOutput': {
              'hookEventName': 'PreToolUse',
              'permissionDecision': 'deny',
              'permissionDecisionReason':
                  'ssh in your shell runs out of the user\'s sight. In '
                  'BaoCode, work on $host in a terminal the user watches: '
                  '"\$BAOCODE_AGENT" pane split --ssh $host, then '
                  '"\$BAOCODE_AGENT" pane run <pane> \'<command>\' for each '
                  'command (its output and exit code come back). See the '
                  'baocode-agents skill. scp, rsync and git over ssh are '
                  'fine as they are.',
            },
          }),
        );
      }
    }
    return const AgentReply('');
  }

  Future<AgentReply> _pane(AgentThread caller, List<String> arguments) async {
    if (arguments.isEmpty ||
        arguments.first == 'help' ||
        arguments.first == '--help' ||
        arguments.first == '-h') {
      return const AgentReply(paneUsage);
    }
    final [command, ...rest] = arguments;
    return switch (command) {
      'list' => _paneList(caller),
      'current' => _paneCurrent(caller, rest),
      'get' => _paneGet(caller, rest),
      'split' => await _paneSplit(caller, rest),
      'run' => await _paneRun(caller, rest),
      'send-text' => await _paneSendText(caller, rest),
      'send-keys' => await _paneSendKeys(caller, rest),
      'read' => _paneRead(caller, rest),
      'wait-output' => await _paneWaitOutput(caller, rest),
      'close' => _paneClose(caller, rest),
      _ => AgentReply.jsonError(
        'cli:pane',
        'unknown_command',
        'Unknown command "pane $command".',
      ),
    };
  }

  Future<AgentReply> _agent(AgentThread caller, List<String> arguments) async {
    if (arguments.isEmpty ||
        arguments.first == 'help' ||
        arguments.first == '--help' ||
        arguments.first == '-h') {
      return const AgentReply(agentUsage);
    }
    final [command, ...rest] = arguments;
    return switch (command) {
      'list' => _agentList(caller),
      'get' => _agentGet(caller, rest),
      'start' => _start(caller, rest),
      'prompt' => await _prompt(caller, rest),
      'wait' => await _agentWait(caller, rest),
      'read' => _agentRead(caller, rest),
      'send-keys' => _agentSendKeys(caller, rest),
      'rename' => _agentRename(caller, rest),
      _ => AgentReply.jsonError(
        'cli:agent',
        'unknown_command',
        'Unknown command "agent $command".',
      ),
    };
  }

  AgentReply _paneList(AgentThread caller) {
    return AgentReply.json('cli:pane:list', {
      'type': 'pane_list',
      'panes': _listedPanes(caller),
    });
  }

  AgentReply _agentList(AgentThread caller) {
    return AgentReply.json('cli:agent:list', {
      'type': 'agent_list',
      'agents': [
        for (final thread in _listedAgents(caller)) _agentInfo(caller, thread),
      ],
    });
  }

  AgentReply _paneCurrent(AgentThread caller, List<String> arguments) {
    final parsed = _flags(arguments, const {'--current'});
    if (parsed.rest.isNotEmpty) {
      throw _Refused(
        'pane current takes no "${parsed.rest.join(' ')}".',
        id: 'cli:pane:current',
      );
    }
    final thread = parsed.flags.contains('--current')
        ? caller
        : workspace.current ?? caller;
    return AgentReply.json('cli:pane:current', {
      'type': 'pane_current',
      'pane': _paneInfo(caller, thread),
    });
  }

  AgentReply _paneGet(AgentThread caller, List<String> arguments) {
    final id = arguments.singleOrNull;
    if (id == null) {
      throw const _Refused('pane get takes a pane id.', id: 'cli:pane:get');
    }
    return AgentReply.json('cli:pane:get', {
      'type': 'pane_info',
      'pane': _paneById(caller, id),
    });
  }

  Future<AgentReply> _paneSplit(
    AgentThread caller,
    List<String> arguments,
  ) async {
    final parsed = _options(
      arguments,
      valued: const {'--direction', '--cwd', '--ssh', '--pane'},
      flags: const {'--current', '--no-focus'},
    );
    if (parsed.options['--direction'] case final direction?
        when direction != 'right' && direction != 'down') {
      throw _Refused('--direction is right or down.', id: 'cli:pane:split');
    }
    final target = parsed.options['--pane'] ?? parsed.rest.singleOrNull;
    if (parsed.rest.length > 1) {
      throw _Refused(
        'pane split takes at most one pane.',
        id: 'cli:pane:split',
      );
    }
    if (target != null) _paneById(caller, target);
    return terminals.open(
      caller,
      ssh: parsed.options['--ssh'],
      cwd: parsed.options['--cwd'],
      show: !parsed.flags.contains('--no-focus'),
    );
  }

  Future<AgentReply> _paneRun(
    AgentThread caller,
    List<String> arguments,
  ) async {
    final parsed = _options(
      arguments,
      valued: const {'--timeout'},
      loose: true,
    );
    final id = parsed.rest.firstOrNull;
    final command = parsed.rest.skip(1).join(' ');
    if (id == null || command.trim().isEmpty) {
      throw const _Refused(
        'pane run takes a pane and a command.',
        id: 'cli:pane:run',
      );
    }
    _rejectAgentPane(
      id,
      'cli:pane:run',
      '$id is an agent pane: use baocode-agent agent prompt $id.',
    );
    return terminals.run(
      caller,
      id,
      command,
      timeout: timeoutMs(parsed.options['--timeout']) ?? defaultWait,
    );
  }

  Future<AgentReply> _paneSendText(
    AgentThread caller,
    List<String> arguments,
  ) async {
    final id = arguments.firstOrNull;
    final text = arguments.skip(1).join(' ');
    if (id == null || text.isEmpty) {
      throw const _Refused(
        'pane send-text takes a pane and the text to type.',
        id: 'cli:pane:send-text',
      );
    }
    _rejectAgentPane(
      id,
      'cli:pane:send-text',
      '$id is an agent pane: use baocode-agent agent prompt $id.',
    );
    return terminals.sendText(caller, id, text);
  }

  Future<AgentReply> _paneSendKeys(
    AgentThread caller,
    List<String> arguments,
  ) async {
    final id = arguments.firstOrNull;
    final keys = arguments.skip(1).toList();
    if (id == null || keys.isEmpty) {
      throw const _Refused(
        'pane send-keys takes a pane and the keys to press.',
        id: 'cli:pane:send-keys',
      );
    }
    if (_threadByPane(id) case final thread?) {
      _alive(thread, id, 'cli:pane:send-keys');
      _notSelf(caller, thread, 'send keys to', 'cli:pane:send-keys');
      return _stopKeys(thread, keys, 'cli:pane:send-keys');
    }
    return terminals.sendKeys(caller, id, keys);
  }

  AgentReply _paneRead(AgentThread caller, List<String> arguments) {
    final parsed = _options(arguments, valued: const {'--source', '--lines'});
    final id = parsed.rest.singleOrNull;
    if (id == null) {
      throw _Refused(
        parsed.rest.isEmpty
            ? 'pane read takes a pane id.'
            : 'pane read takes one pane id.',
        id: 'cli:pane:read',
      );
    }
    final source = parsed.options['--source'] ?? 'recent';
    final lines = _lines(parsed.options['--lines'], id: 'cli:pane:read');
    if (_threadByPane(id) case final thread?) {
      _alive(thread, id, 'cli:pane:read');
      return _readJson('cli:pane:read', thread, source: source, lines: lines);
    }
    return terminals.read(caller, id, source: source, lines: lines);
  }

  Future<AgentReply> _paneWaitOutput(
    AgentThread caller,
    List<String> arguments,
  ) async {
    final parsed = _options(
      arguments,
      valued: const {'--match', '--regex', '--timeout', '--source', '--lines'},
    );
    final id = parsed.rest.singleOrNull;
    if (id == null) {
      throw _Refused(
        parsed.rest.isEmpty
            ? 'pane wait-output takes a pane id.'
            : 'pane wait-output takes one pane id.',
        id: 'cli:pane:wait-output',
      );
    }
    if (parsed.options.containsKey('--match') &&
        parsed.options.containsKey('--regex')) {
      throw const _Refused(
        'pane wait-output takes --match or --regex, not both.',
        id: 'cli:pane:wait-output',
      );
    }
    if (!parsed.options.containsKey('--match') &&
        !parsed.options.containsKey('--regex')) {
      throw const _Refused(
        'pane wait-output takes --match <text> or --regex <re>.',
        id: 'cli:pane:wait-output',
      );
    }
    _rejectAgentPane(
      id,
      'cli:pane:wait-output',
      '$id is an agent pane: use baocode-agent agent wait $id.',
    );
    return terminals.waitOutput(
      caller,
      id,
      match: parsed.options['--match'],
      regex: parsed.options['--regex'],
      timeout: timeoutMs(parsed.options['--timeout']) ?? defaultWait,
      source: parsed.options['--source'] ?? 'recent',
      lines: _lines(parsed.options['--lines'], id: 'cli:pane:wait-output'),
    );
  }

  AgentReply _paneClose(AgentThread caller, List<String> arguments) {
    final id = arguments.singleOrNull;
    if (id == null) {
      throw const _Refused('pane close takes a pane id.', id: 'cli:pane:close');
    }
    if (_threadByPane(id) case final thread?) {
      _alive(thread, id, 'cli:pane:close');
      _notSelf(caller, thread, 'close', 'cli:pane:close');
      return _close(thread);
    }
    return terminals.close(caller, id);
  }

  AgentReply _agentGet(AgentThread caller, List<String> arguments) {
    final target = arguments.singleOrNull;
    if (target == null) {
      throw const _Refused(
        'agent get takes a name or pane id.',
        id: 'cli:agent:get',
      );
    }
    return AgentReply.json('cli:agent:get', {
      'type': 'agent_info',
      'agent': _agentInfo(caller, _agentTarget(caller, target)),
    });
  }

  AgentReply _start(AgentThread caller, List<String> arguments) {
    if (_workers.any((worker) => worker.thread == caller)) {
      throw const _Refused(
        'An agent started by another cannot start agents of its own.',
        code: 'forbidden',
        id: 'cli:agent:start',
      );
    }
    String? kind, model, effort, anchor, direction;
    var noFocus = false;
    final rest = <String>[];
    for (var i = 0; i < arguments.length; i++) {
      String value() => i + 1 < arguments.length
          ? arguments[++i]
          : throw _Refused(
              '${arguments[i]} takes a value.',
              id: 'cli:agent:start',
            );
      switch (arguments[i]) {
        case '--kind':
          kind = value();
        case '--model':
          model = value();
        case '--effort':
          effort = value();
        case '--pane':
          anchor = value();
        case '--direction':
          direction = value();
        case '--no-focus':
          noFocus = true;
        case '--':
          rest.addAll(arguments.skip(i + 1));
          i = arguments.length;
        default:
          if (arguments[i].startsWith('-')) {
            throw _Refused(
              'Unknown option "${arguments[i]}".',
              id: 'cli:agent:start',
            );
          }
          rest.add(arguments[i]);
      }
    }
    final name = rest.firstOrNull;
    final prompt = rest.skip(1).join(' ').trim();
    if (name == null) {
      throw const _Refused('agent start takes a name.', id: 'cli:agent:start');
    }
    _checkName(name, id: 'cli:agent:start');
    if (kind == null) {
      throw const _Refused(
        'agent start takes --kind claude|codex|pi.',
        id: 'cli:agent:start',
      );
    }
    if (direction != null && direction != 'right' && direction != 'down') {
      throw const _Refused(
        '--direction is right or down.',
        id: 'cli:agent:start',
      );
    }
    final kernel = _kernelByKind(kind);
    if (kernel == null) {
      final names = [for (final kernel in workspace.kernels) kernel.id];
      throw _Refused(
        'No agent kind "$kind" here: one of ${names.join(', ')}.',
        id: 'cli:agent:start',
      );
    }
    final beside = anchor == null
        ? caller
        : _agentTarget(caller, anchor, id: 'cli:agent:start');
    final thread = workspace.startWorker(caller.project, kernel, {
      KernelChoiceKind.mode: 'agent',
      KernelChoiceKind.permission: ?_fullAccess[kernel.id],
      KernelChoiceKind.model: ?model,
      KernelChoiceKind.effort: ?effort,
    });
    paneIdOf(thread);
    _names[thread] = name;
    _workers.add(_Worker(name, thread, caller));
    _show(
      thread,
      beside,
      owner: caller,
      prefer: direction == 'down' ? PaneSide.bottom : PaneSide.right,
      focus: !noFocus,
    );
    if (prompt.isNotEmpty) _sendTo(thread, prompt);
    return AgentReply.json('cli:agent:start', {
      'type': 'agent_started',
      'agent': _agentInfo(caller, thread),
      'argv': prompt.isEmpty ? const <String>[] : [prompt],
    });
  }

  Future<AgentReply> _prompt(AgentThread caller, List<String> arguments) async {
    final parsed = _options(
      arguments,
      valued: const {'--timeout', '--until'},
      flags: const {'--wait'},
      repeat: const {'--until'},
    );
    final target = parsed.rest.firstOrNull;
    final text = parsed.rest.skip(1).join(' ');
    if (target == null || text.trim().isEmpty) {
      throw const _Refused(
        'agent prompt takes a name or pane and the text to send.',
        id: 'cli:agent:prompt',
      );
    }
    if (parsed.repeat['--until']!.isNotEmpty &&
        !parsed.flags.contains('--wait')) {
      throw const _Refused('--until requires --wait.', id: 'cli:agent:prompt');
    }
    final thread = _agentTarget(
      caller,
      target,
      self: 'prompt',
      id: 'cli:agent:prompt',
    );
    if (thread.isOpen && thread.session.pendingInteraction != null) {
      throw const _Refused(
        'agent is blocked; not sending',
        code: 'agent_blocked',
        id: 'cli:agent:prompt',
      );
    }
    if (_working(thread)) {
      throw _Refused(
        '${paneIdOf(thread)} is still working: baocode-agent agent wait '
        '${_ref(thread)} first.',
        code: 'agent_busy',
        id: 'cli:agent:prompt',
      );
    }
    _sendTo(thread, text);
    if (parsed.flags.contains('--wait')) {
      final until = _until(
        parsed.repeat['--until']!,
        or: const ['idle', 'done', 'blocked'],
      );
      await _untilStatus(
        thread,
        until,
        timeoutMs(parsed.options['--timeout']) ?? defaultWait,
      );
      if (!_statusIn(thread, until)) {
        throw _Refused(
          'timed out waiting for agent status. Wait again: baocode-agent '
          'agent wait ${_ref(thread)}',
          code: 'timeout',
          id: 'cli:agent:prompt',
        );
      }
    }
    return AgentReply.json('cli:agent:prompt', {
      'type': 'agent_prompted',
      'agent': _agentInfo(caller, thread),
    });
  }

  Future<AgentReply> _agentWait(
    AgentThread caller,
    List<String> arguments,
  ) async {
    final parsed = _options(
      arguments,
      valued: const {'--timeout', '--until'},
      repeat: const {'--until'},
    );
    final target = parsed.rest.singleOrNull;
    if (target == null) {
      throw _Refused(
        parsed.rest.isEmpty
            ? 'agent wait takes a name or pane id.'
            : 'agent wait takes one name or pane id.',
        id: 'cli:agent:wait',
      );
    }
    final thread = _agentTarget(
      caller,
      target,
      self: 'wait for',
      id: 'cli:agent:wait',
    );
    final until = _until(
      parsed.repeat['--until']!,
      or: const ['idle', 'done', 'blocked'],
    );
    await _untilStatus(
      thread,
      until,
      timeoutMs(parsed.options['--timeout']) ?? defaultWait,
    );
    if (!_statusIn(thread, until)) {
      throw _Refused(
        'timed out waiting for agent status. Wait again: baocode-agent '
        'agent wait ${_ref(thread)}',
        code: 'timeout',
        id: 'cli:agent:wait',
      );
    }
    return AgentReply.json('cli:agent:wait', {
      'type': 'agent_info',
      'agent': _agentInfo(caller, thread),
    });
  }

  AgentReply _agentRead(AgentThread caller, List<String> arguments) {
    final parsed = _options(arguments, valued: const {'--lines'});
    final target = parsed.rest.singleOrNull;
    if (target == null) {
      throw const _Refused(
        'agent read takes a name or pane id.',
        id: 'cli:agent:read',
      );
    }
    final thread = _agentTarget(caller, target, id: 'cli:agent:read');
    return _readJson(
      'cli:agent:read',
      thread,
      source: 'recent',
      lines: _lines(parsed.options['--lines'], id: 'cli:agent:read'),
    );
  }

  AgentReply _agentSendKeys(AgentThread caller, List<String> arguments) {
    final target = arguments.firstOrNull;
    final keys = arguments.skip(1).toList();
    if (target == null || keys.isEmpty) {
      throw const _Refused(
        'agent send-keys takes a name or pane and esc or ctrl+c.',
        id: 'cli:agent:send-keys',
      );
    }
    final thread = _agentTarget(
      caller,
      target,
      self: 'send keys to',
      id: 'cli:agent:send-keys',
    );
    return _stopKeys(thread, keys, 'cli:agent:send-keys');
  }

  AgentReply _agentRename(AgentThread caller, List<String> arguments) {
    if (arguments.length != 2) {
      throw const _Refused(
        'agent rename takes a pane id and a name.',
        id: 'cli:agent:rename',
      );
    }
    final thread = _threadByPane(arguments[0]);
    if (thread == null) {
      throw _Refused(
        'pane ${arguments[0]} not found',
        code: 'pane_not_found',
        id: 'cli:agent:rename',
      );
    }
    _alive(thread, arguments[0], 'cli:agent:rename');
    _checkName(arguments[1], except: thread, id: 'cli:agent:rename');
    _names[thread] = arguments[1];
    return AgentReply.json('cli:agent:rename', {
      'type': 'agent_info',
      'agent': _agentInfo(caller, thread),
    });
  }

  /// Opens [thread] in half of [anchor]'s pane, or of another of the
  /// owner's agents', the newest first; where there is no room, it is
  /// only listed.
  void _show(
    AgentThread thread,
    AgentThread anchor, {
    required AgentThread owner,
    required PaneSide prefer,
    required bool focus,
  }) {
    final grid = workspace.grid;
    final sides = prefer == PaneSide.bottom
        ? const [PaneSide.bottom, PaneSide.right]
        : const [PaneSide.right, PaneSide.bottom];
    final targets = [
      anchor,
      for (final other in _workers.reversed)
        if (other.owner == owner && other.thread != thread) other.thread,
    ];
    for (final target in targets) {
      if (!grid.contains(target)) continue;
      for (final side in sides) {
        if (grid.canSplit(target, side)) {
          workspace.openBeside(thread, target, side, focus: focus);
          return;
        }
      }
    }
  }

  void _sendTo(AgentThread thread, String text) {
    final session = thread.session;
    _sentAfter[thread] = session.lastTurnEndSeq;
    session.send(ComposerMessage(text: text));
  }

  AgentReply _close(AgentThread thread) {
    final id = paneIdOf(thread);
    if (_working(thread)) thread.session.stop();
    if (!workspace.grid.contains(thread)) {
      return AgentReply.json('cli:pane:close', {
        'type': 'ok',
        'pane_id': id,
        'closed': false,
      });
    }
    workspace.closePane(thread);
    return AgentReply.json('cli:pane:close', {
      'type': 'ok',
      'pane_id': id,
      'closed': !workspace.grid.contains(thread),
    });
  }

  AgentReply _stopKeys(AgentThread thread, List<String> keys, String id) {
    for (final key in keys) {
      if (!_isStopKey(key)) {
        throw _Refused(
          'No key "$key" for an agent pane: esc or ctrl+c stops the turn.',
          id: id,
        );
      }
    }
    if (_working(thread)) thread.session.stop();
    return AgentReply.json(id, {
      'type': 'ok',
      'pane_id': paneIdOf(thread),
      'stopped': true,
    });
  }

  AgentReply _readJson(
    String id,
    AgentThread thread, {
    required String source,
    int? lines,
  }) {
    _readSource(source, id);
    final session = thread.session;
    final health = session.health;
    final text = _cut(
      health.status == KernelHealthStatus.failed
          ? (health.message ?? 'it stopped')
          : (session.lastTurnReply ?? session.lastReply ?? ''),
      lines,
    );
    return AgentReply.json(id, {
      'type': 'pane_read',
      'read': {
        'pane_id': paneIdOf(thread),
        'source': source == 'recent-unwrapped' ? 'recent_unwrapped' : source,
        'format': 'text',
        'text': text,
        'truncated':
            lines != null &&
            _lineCount(session.lastTurnReply ?? session.lastReply ?? '') >
                lines,
      },
    });
  }

  List<AgentThread> _listedAgents(AgentThread caller) {
    final seen = <AgentThread>{};
    final listed = <AgentThread>[];
    void add(AgentThread thread) {
      if (!seen.add(thread) || !workspace.threads.contains(thread)) return;
      listed.add(thread);
    }

    for (final pane in workspace.grid.panes) {
      add(pane);
    }
    add(caller);
    for (final worker in _workers) {
      if (worker.owner == caller) add(worker.thread);
    }
    return listed;
  }

  List<Map<String, Object?>> _listedPanes(AgentThread caller) => [
    for (final thread in _listedAgents(caller)) _paneInfo(caller, thread),
    ...terminals.records(caller),
  ];

  Map<String, Object?> _paneById(AgentThread caller, String id) {
    if (_threadByPane(id) case final thread?) {
      _alive(thread, id, 'cli:pane:get');
      return _paneInfo(caller, thread);
    }
    if (terminals.record(caller, id) case final pane?) return pane;
    throw _Refused(
      'pane $id not found',
      code: 'pane_not_found',
      id: 'cli:pane:get',
    );
  }

  Map<String, Object?> _paneInfo(AgentThread caller, AgentThread thread) => {
    'pane_id': paneIdOf(thread),
    'kind': 'agent',
    'name': _names[thread],
    'agent': kindName(thread.kernel),
    'agent_kind': kindName(thread.kernel),
    'agent_status': _agentStatus(thread),
    'title': thread.title,
    'project': thread.project.name,
    'cwd': thread.project.path,
    'is_caller': identical(thread, caller),
    'focused': identical(thread, workspace.current),
    'error': ?_errorOf(thread),
  };

  Map<String, Object?> _agentInfo(AgentThread caller, AgentThread thread) => {
    ..._paneInfo(caller, thread),
    'interactive_ready':
        thread.isOpen &&
        thread.session.health.status != KernelHealthStatus.failed,
  };

  AgentThread? _threadByPane(String id) {
    for (final MapEntry(:key, :value) in _ids.entries) {
      if (value == id) return key;
    }
    return null;
  }

  AgentThread _agentTarget(
    AgentThread caller,
    String target, {
    String? self,
    String id = 'cli:agent',
  }) {
    AgentThread? thread;
    for (final MapEntry(:key, :value) in _names.entries) {
      if (value == target && workspace.threads.contains(key)) {
        thread = key;
        break;
      }
    }
    thread ??= _threadByPane(target);
    if (thread == null) {
      throw _Refused(
        'agent target $target not found',
        code: 'agent_not_found',
        id: id,
      );
    }
    _alive(thread, target, id, code: 'agent_not_found');
    if (self != null) _notSelf(caller, thread, self, id);
    return thread;
  }

  void _alive(
    AgentThread thread,
    String target,
    String id, {
    String code = 'pane_not_found',
  }) {
    if (!workspace.threads.contains(thread)) {
      throw _Refused('$target was closed by the user.', code: code, id: id);
    }
  }

  void _notSelf(
    AgentThread caller,
    AgentThread thread,
    String verb,
    String id,
  ) {
    if (identical(thread, caller)) {
      throw _Refused(
        'You cannot $verb yourself (${paneIdOf(caller)}).',
        code: 'cannot_target_self',
        id: id,
      );
    }
  }

  void _rejectAgentPane(String id, String commandId, String message) {
    final thread = _threadByPane(id);
    if (thread == null) return;
    _alive(thread, id, commandId);
    throw _Refused(message, code: 'not_a_terminal', id: commandId);
  }

  void _checkName(String name, {AgentThread? except, required String id}) {
    if (!_namePattern.hasMatch(name) || _paneIdPattern.hasMatch(name)) {
      throw _Refused(
        'Name "$name" is not [a-z][a-z0-9_-]{0,31}, or looks like a pane id.',
        id: id,
      );
    }
    for (final MapEntry(:key, :value) in _names.entries) {
      if (value == name && key != except && workspace.threads.contains(key)) {
        throw _Refused(
          'Name "$name" is already used by ${paneIdOf(key)}.',
          code: 'agent_name_taken',
          id: id,
        );
      }
    }
  }

  KernelDescriptor? _kernelByKind(String kind) {
    final want = kind.toLowerCase();
    return workspace.kernels
        .where(
          (kernel) =>
              kernel.id == want ||
              kernel.id == '$want-code' ||
              kindName(kernel) == want ||
              kernel.label.toLowerCase() == want,
        )
        .firstOrNull;
  }

  static String kindName(KernelDescriptor kernel) {
    final id = kernel.id;
    if (id == 'claude-code' || id == 'claude') return 'claude';
    if (id == 'codex') return 'codex';
    if (id == 'pi') return 'pi';
    return id;
  }

  String _ref(AgentThread thread) => _names[thread] ?? paneIdOf(thread);

  /// Whether [thread] has yet to answer its last message from us; if we
  /// have sent none, whether a turn is under way.
  bool _working(AgentThread thread) {
    if (!thread.isOpen) return false;
    final session = thread.session;
    final after = _sentAfter[thread] ?? -1;
    return session.health.status != KernelHealthStatus.failed &&
        (session.isStreaming || session.lastTurnEndSeq <= after);
  }

  String _agentStatus(AgentThread thread) {
    if (!thread.isOpen) return 'idle';
    final session = thread.session;
    if (session.health.status == KernelHealthStatus.failed) return 'unknown';
    if (session.pendingInteraction != null) return 'blocked';
    if (_working(thread)) return 'working';
    if (thread.unread) return 'done';
    return 'idle';
  }

  String? _errorOf(AgentThread thread) {
    if (!thread.isOpen) return null;
    final health = thread.session.health;
    if (health.status != KernelHealthStatus.failed) return null;
    return health.message ?? 'it stopped';
  }

  Future<void> _untilStatus(
    AgentThread thread,
    Set<String> until,
    Duration? timeout,
  ) async {
    if (_statusIn(thread, until)) return;
    final session = thread.session;
    final done = Completer<void>();
    void changed() {
      if (_statusIn(thread, until) && !done.isCompleted) done.complete();
    }

    session.addListener(changed);
    try {
      final wait = timeout ?? defaultWait;
      await done.future.timeout(wait, onTimeout: () {});
    } finally {
      session.removeListener(changed);
    }
  }

  bool _statusIn(AgentThread thread, Set<String> until) =>
      until.contains(_agentStatus(thread));

  static Set<String> _until(List<String> given, {required List<String> or}) {
    final until = given.isEmpty ? or : given;
    for (final status in until) {
      if (!_statuses.contains(status)) {
        throw _Refused('--until is idle, working, blocked, done or unknown.');
      }
    }
    return until.toSet();
  }

  static const _statuses = {'idle', 'working', 'blocked', 'done', 'unknown'};

  static bool _isStopKey(String name) {
    final key = name.toLowerCase();
    return key == 'esc' ||
        key == 'escape' ||
        key == 'ctrl+c' ||
        key == 'ctrl-c' ||
        key == 'c-c';
  }

  static String _readSource(String source, String id) {
    if (source == 'visible' ||
        source == 'recent' ||
        source == 'recent-unwrapped') {
      return source;
    }
    throw _Refused('--source is visible, recent or recent-unwrapped.', id: id);
  }

  static int? _lines(String? value, {required String id}) {
    if (value == null) return null;
    final lines = int.tryParse(value);
    if (lines == null || lines < 1) {
      throw _Refused('--lines takes a number of lines.', id: id);
    }
    return lines;
  }

  static String _cut(String text, int? lines) {
    if (lines == null) return text;
    final all = text.split('\n');
    if (all.length <= lines) return text;
    return all.sublist(all.length - lines).join('\n');
  }

  static int _lineCount(String text) =>
      text.isEmpty ? 0 : text.split('\n').length;

  /// `--timeout` as milliseconds; null when omitted. Capped at [longestWait].
  static Duration? timeoutMs(String? value) {
    if (value == null) return null;
    final milliseconds = int.tryParse(value);
    if (milliseconds == null || milliseconds < 0) {
      throw const _Refused('--timeout takes a number of milliseconds.');
    }
    final timeout = Duration(milliseconds: milliseconds);
    return timeout > longestWait ? longestWait : timeout;
  }
}

class _Parsed {
  const _Parsed(this.options, this.flags, this.repeat, this.rest);

  final Map<String, String> options;
  final Set<String> flags;
  final Map<String, List<String>> repeat;
  final List<String> rest;
}

_Parsed _options(
  List<String> arguments, {
  Set<String> valued = const {},
  Set<String> flags = const {},
  Set<String> repeat = const {},
  bool loose = false,
}) {
  final options = <String, String>{};
  final seen = <String>{};
  final repeated = {for (final name in repeat) name: <String>[]};
  final rest = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    if (argument == '--') {
      rest.addAll(arguments.skip(i + 1));
      break;
    }
    if (flags.contains(argument)) {
      seen.add(argument);
      continue;
    }
    if (valued.contains(argument) || repeat.contains(argument)) {
      if (i + 1 >= arguments.length) {
        throw _Refused('$argument takes a value.');
      }
      final value = arguments[++i];
      if (repeat.contains(argument)) {
        repeated[argument]!.add(value);
      } else {
        options[argument] = value;
      }
    } else if (argument.startsWith('-') && !loose) {
      throw _Refused('Unknown option "$argument".');
    } else {
      rest.add(argument);
    }
  }
  return _Parsed(options, seen, repeated, rest);
}

_Parsed _flags(List<String> arguments, Set<String> flags) =>
    _options(arguments, flags: flags);

/// A command that cannot be done, and why: printed as it fails.
class _Refused implements Exception {
  const _Refused(
    this.message, {
    this.code = 'invalid_request',
    this.id = 'cli',
  });

  final String message;
  final String code;
  final String id;
}
