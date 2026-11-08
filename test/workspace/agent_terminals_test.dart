import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/kernel/agent_instructions.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:baocode/kernel/pi/pi_transport.dart';
import 'package:baocode/workspace/agent_host.dart';
import 'package:baocode/workspace/agent_pi_extension.dart';
import 'package:baocode/workspace/agent_server.dart';
import 'package:baocode/workspace/agent_terminals.dart';
import 'package:baocode/workspace/workspace.dart';

import '../ide/terminal/fake_pty.dart';
import '../ide/terminal/fake_terminal.dart';

class _RealHttp extends HttpOverrides {}

/// A prompt as VS Code's shell integration reports it.
const _prompt = '\x1b]633;A\x07\$ \x1b]633;B\x07';

void main() {
  group('destructiveCommand', () {
    test('finds what could lose data, wherever it is in the line', () {
      for (final line in [
        'rm -rf /',
        'sudo rm -r /var/www',
        'ls && rm -f a.txt',
        'rm --recursive build',
        'find . -name "*.log" -delete',
        'mkfs.ext4 /dev/sdb1',
        'dd if=/dev/zero of=/dev/sda bs=1M',
        'cat x > /dev/nvme0n1',
        'sudo reboot',
        'chmod -R 777 /',
        'chown -R me /etc',
        ':(){ :|:& };:',
        'kill -9 -1',
        'crontab -r',
        'git push origin main --force',
        'git push -f',
        'git reset --hard HEAD~3',
        'git clean -fdx',
        'mysql -e "drop table users"',
        'TRUNCATE TABLE orders;',
        'docker system prune -a',
        'kubectl delete pod web-1',
      ]) {
        expect(destructiveCommand(line), isNotNull, reason: line);
      }
    });

    test('lets the everyday through', () {
      for (final line in [
        'ls -la',
        'rm notes.txt',
        'grep -r rm .',
        'npm run format',
        'git push origin main',
        'chmod -R 755 ./dist',
        'systemctl status nginx',
        'tail -f /var/log/syslog',
        'SELECT * FROM users;',
      ]) {
        expect(destructiveCommand(line), isNull, reason: line);
      }
    });
  });

  test('ssh to a server is found wherever it starts a command', () {
    for (final (command, host) in [
      ('ssh jiageng', 'jiageng'),
      ("ssh deploy@web 'systemctl status nginx'", 'deploy@web'),
      ('ssh -p 2222 -i ~/.ssh/k me@10.0.0.1 uptime', 'me@10.0.0.1'),
      ('ssh -tt -oStrictHostKeyChecking=no box ls', 'box'),
      ('ssh -NL 8080:localhost:80 box', 'box'),
      ('cd /x && ssh box "df -h"', 'box'),
      ('echo hi; sudo ssh root@db', 'root@db'),
      (r'out=$(ssh box cat /etc/os-release)', 'box'),
      ('timeout 30 ssh box true', 'box'),
      ('ssh -- box', 'box'),
    ]) {
      expect(sshDestination(command), host, reason: command);
    }
  });

  test('ssh for git, files or keys is let be', () {
    for (final command in [
      'ssh -T git@github.com',
      'ssh -T git@gitlab.com',
      'git push origin main',
      'scp a.txt box:/tmp/',
      'rsync -av ./dist box:/srv/',
      'ssh-keygen -t ed25519',
      'ssh-add -l',
      'ssh -V',
      'cat ~/.ssh/config',
      'echo ssh box',
      'grep ssh notes.md',
    ]) {
      expect(sshDestination(command), isNull, reason: command);
    }
  });

  test("the agent's ssh is turned to a terminal by its hook, through the "
      'command', () async {
    final dir = await Directory.systemTemp.createTemp('baocode-agent-');
    addTearDown(() => dir.delete(recursive: true));
    final workspace = Workspace(
      kernels: MockKernels.all,
      projects: const [Project('app', '/tmp/app')],
    );
    final host = AgentHost(workspace);
    await serveAgents(host, directory: dir.path, installSkill: false);
    final environment = host.environmentOf(workspace.create());
    Future<ProcessResult> hook(Map<String, Object?> event) async {
      final process = await Process.start(
        environment[AgentHost.commandVariable]!,
        ['hook', 'pre-tool-use'],
        environment: environment,
      );
      process.stdin.write(jsonEncode(event));
      await process.stdin.close();
      final stdout = await process.stdout.transform(utf8.decoder).join();
      return ProcessResult(process.pid, await process.exitCode, stdout, '');
    }

    final denied = await hook({
      'hook_event_name': 'PreToolUse',
      'tool_name': 'Bash',
      'tool_input': {'command': "ssh jiageng 'uptime'"},
    });
    expect(denied.exitCode, 0);
    final output = jsonDecode('${denied.stdout}') as Map;
    expect(
      output['hookSpecificOutput'],
      containsPair('permissionDecision', 'deny'),
    );
    expect(
      '${output['hookSpecificOutput']['permissionDecisionReason']}',
      contains('pane split --ssh jiageng'),
    );

    for (final event in [
      {
        'tool_name': 'Bash',
        'tool_input': {'command': 'git push'},
      },
      {
        'tool_name': 'Read',
        'tool_input': {'file_path': '/tmp/a'},
      },
    ]) {
      final let = await hook(event);
      expect(let.exitCode, 0);
      expect(let.stdout, isEmpty, reason: '$event');
    }
  });

  test('Claude Code BaoCode can be reached from is told to use terminals '
      'for servers, and hooked; one it cannot, neither', () {
    final reached = ClaudeLaunch(
      cwd: '/tmp/app',
      variables: const {
        AgentHost.commandVariable: '/x/baocode-agent',
        AgentHost.urlVariable: 'http://127.0.0.1:1/k',
      },
    );
    expect(ClaudeLaunch.agentCommandVariable, AgentHost.commandVariable);
    expect(reached.systemPrompt, contains('<servers>'));
    expect(reached.settings['hooks'], ClaudeLaunch.sshHook);
    final prompt = reached
        .arguments[reached.arguments.indexOf('--append-system-prompt') + 1];
    expect(prompt, reached.systemPrompt);

    const apart = ClaudeLaunch(cwd: '/tmp/app');
    expect(apart.systemPrompt, ClaudeLaunch.appendedSystemPrompt);
    expect(apart.settings.containsKey('hooks'), isFalse);
  });

  test("the app's tools are an MCP server over HTTP for each agent, and "
      'pi starts with the extension that reaches it', () async {
    ClaudeSdkTools.register(
      ClaudeSdkTool(
        name: 'echo',
        description: 'Says it back',
        inputSchema: const {'type': 'object'},
        run: (input, call) async => '${input['text']} in ${call.cwd}',
      ),
    );
    addTearDown(() => ClaudeSdkTools.unregister('echo'));
    final dir = await Directory.systemTemp.createTemp('baocode-agent-');
    addTearDown(() => dir.delete(recursive: true));
    final workspace = Workspace(
      kernels: MockKernels.all,
      projects: const [Project('app', '/tmp/app')],
    );
    final host = AgentHost(workspace);
    await serveAgents(host, directory: dir.path, installSkill: false);
    final environment = host.environmentOf(workspace.create());
    // A real client: the test binding's answers every request with 400.
    final client = HttpOverrides.runWithHttpOverrides(
      HttpClient.new,
      _RealHttp(),
    );
    addTearDown(client.close);
    Future<(int, Object?)> post(
      String url,
      Map<String, Object?> message,
    ) async {
      final request = await client.postUrl(Uri.parse(url));
      request.write(jsonEncode(message));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return (response.statusCode, body.isEmpty ? null : jsonDecode(body));
    }

    final mcp = AgentInstructions.mcpUrl(environment)!;
    expect(mcp, '${environment[AgentHost.urlVariable]}/mcp');
    final (_, initialized) = await post(mcp, {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': '2025-06-18'},
    });
    expect(initialized, containsPair('id', 1));
    expect(
      await post(mcp, {
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      }),
      (HttpStatus.accepted, null),
    );
    final (_, listed) = await post(mcp, {
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
    });
    expect([
      for (final tool in (listed! as Map)['result']['tools']) tool['name'],
    ], contains('echo'));
    final (_, called) = await post(mcp, {
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {
        'name': 'echo',
        'arguments': {'text': 'hi'},
      },
    });
    expect((called! as Map)['result']['content'], [
      {'type': 'text', 'text': 'hi in /tmp/app'},
    ]);
    final (_, stranger) = await post(
      '${environment[AgentHost.urlVariable]}x/mcp',
      {'jsonrpc': '2.0', 'id': 4, 'method': 'tools/list'},
    );
    expect((stranger! as Map)['error'], isNotNull);

    // pi: told of terminals, and given the extension written beside the
    // command.
    final arguments = piBaoCodeArguments(environment);
    expect(arguments, [
      '--append-system-prompt',
      AgentInstructions.of(environment),
      '--extension',
      '${dir.path}/$piExtensionFile',
    ]);
    expect(
      File('${dir.path}/$piExtensionFile').readAsStringSync(),
      AgentPiExtension.text,
    );
    expect(piBaoCodeArguments(const {}), isEmpty);
  });

  test('keys as the terminal sends them', () {
    expect(keySequence('Enter'), '\r');
    expect(keySequence('C-c'), '\x03');
    expect(keySequence('ctrl+c'), '\x03');
    expect(keySequence('ctrl-D'), '\x04');
    expect(keySequence('Esc'), '\x1b');
    expect(keySequence('Up'), '\x1b[A');
    expect(keySequence('up', applicationCursor: true), '\x1bOA');
    expect(keySequence('M-b'), '\x1bb');
    expect(keySequence('F5'), '\x1b[15~');
    expect(keySequence('q'), 'q');
    expect(keySequence('中'), '中');
    expect(keySequence('Hyper-x'), isNull);
  });

  test('ssh runs bash with the shell integration, from its command alone', () {
    final arguments = sshArguments('me@server', 'the-nonce');
    expect(arguments.take(3), ['-t', '--', 'me@server']);
    expect(arguments.last, contains('VSCODE_NONCE=the-nonce'));
    expect(arguments.last, startsWith("exec sh -c '"));
    expect(arguments.last, contains(r'exec bash --init-file "$f" -i'));
  });

  test("the command ssh gives the server's shell starts bash reporting its "
      'commands', () async {
    final home = await Directory.systemTemp.createTemp('agent-terminal-');
    addTearDown(() => home.delete(recursive: true));
    final tmp = Directory('${home.path}/tmp')..createSync();
    // Each time: it once read its script from a pipe, which bash now and
    // then found empty.
    for (var i = 0; i < 5; i++) {
      // As sshd runs it: the user's shell, given the command.
      final process = await Process.start(
        '/bin/sh',
        ['-c', sshArguments('server', 'n0nce').last],
        environment: {
          'HOME': home.path,
          'PATH': '/usr/bin:/bin',
          'TMPDIR': tmp.path,
        },
        includeParentEnvironment: false,
      );
      process.stdin.writeln('echo from-the-server');
      process.stdin.writeln('exit');
      await process.stdin.close();
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode;
      final output = '${await stdout}${await stderr}';
      expect(code, 0, reason: output);
      expect(output, contains('from-the-server'));
      expect(output, contains('\x1b]633;A'), reason: output);
      expect(output, contains('\x1b]633;D'), reason: output);
      // Nothing left on the server.
      expect(tmp.listSync(), isEmpty);
    }
  }, skip: Platform.isWindows || !File('/bin/bash').existsSync());

  group('baocode-agent pane', () {
    late Workspace workspace;
    late AgentHost host;
    late AgentThread caller;
    late TerminalService service;
    late List<FakePty> started;
    late List<TerminalInstance> shown;
    late String key;

    setUp(() {
      workspace = Workspace(
        kernels: MockKernels.all,
        projects: const [Project('app', '/tmp/app')],
      );
      started = [];
      service = TerminalService(
        root: '/tmp/app',
        backend: fakeTerminalBackend(started),
      );
      addTearDown(service.dispose);
      shown = [];
      workspace.agentTerminals = (_) => (service: service, show: shown.add);
      host = AgentHost(workspace)
        ..url = 'http://127.0.0.1:4100'
        ..command = '/tmp/bin/baocode-agent';
      host.terminals
        ..quiet = const Duration(milliseconds: 100)
        ..settle = const Duration(milliseconds: 20)
        ..opening = const Duration(milliseconds: 300);
      caller = workspace.create();
      key = host.environmentOf(caller)[AgentHost.urlVariable]!.split('/').last;
    });

    Future<AgentReply> run(List<String> arguments) =>
        host.run(key, ['pane', ...arguments]);

    Map<String, dynamic> decoded(AgentReply reply, {bool ok = true}) {
      expect(reply.ok, ok, reason: reply.text);
      return jsonDecode(reply.text) as Map<String, dynamic>;
    }

    /// Opens a terminal, its shell at a prompt it reports. Caller is p1.
    Future<(FakePty, String)> open([List<String> options = const []]) async {
      final opening = run(['split', ...options]);
      await pumpEventQueue();
      final pty = started.last..emitText(_prompt);
      final reply = await opening;
      final id = decoded(reply)['result']['pane']['pane_id'] as String;
      return (pty, id);
    }

    test('opens a terminal in the panel, on a server over ssh', () async {
      final (pty, id) = await open(['--ssh', 'deploy@web']);
      expect(id, 'p2');
      expect(pty.launch!.executable, 'ssh');
      expect(pty.launch!.arguments.take(3), ['-t', '--', 'deploy@web']);
      expect(service.instances.single.title, 'ssh deploy@web');
      expect(shown, [service.instances.single]);
      final panes = decoded(await run(['list']))['result']['panes'] as List;
      expect(
        panes.any(
          (pane) => pane['pane_id'] == 'p2' && pane['host'] == 'deploy@web',
        ),
        isTrue,
      );

      final refused = await run(['split', '--ssh', '-oProxyCommand=x']);
      expect(refused.ok, isFalse);
    });

    test('runs a command, and tells its output and exit code', () async {
      final (pty, id) = await open();
      final running = run(['run', id, 'ls']);
      await pumpEventQueue();
      expect(pty.written, endsWith('ls\r'));
      pty.emitText(
        'ls\r\n\x1b]633;C\x07a.txt\r\nb.txt\r\n\x1b]633;D;2\x07$_prompt',
      );
      final result = decoded(await running)['result'] as Map;
      expect(result['exit_code'], 2);
      expect(result['output'], contains('a.txt\nb.txt'));
    });

    test('one still running after its timeout is said to be, and waited '
        'for', () async {
      final (pty, id) = await open();
      final running = run(['run', id, 'sleep 9', '--timeout', '50']);
      await pumpEventQueue();
      pty.emitText('sleep 9\r\n\x1b]633;C\x07');
      final result = decoded(await running)['result'] as Map;
      expect(result['running'], isTrue);
      final waiting = run([
        'wait-output',
        id,
        '--match',
        'done-now',
        '--timeout',
        '5000',
      ]);
      await pumpEventQueue();
      pty.emitText('done-now\r\n\x1b]633;D;0\x07$_prompt');
      expect(decoded(await waiting)['result']['type'], 'output_matched');
    });

    test('one done between run giving up and wait is still told', () async {
      final (pty, id) = await open();
      final running = run(['run', id, 'make', '--timeout', '50']);
      await pumpEventQueue();
      pty.emitText('make\r\n\x1b]633;C\x07');
      expect(decoded(await running)['result']['running'], isTrue);
      pty.emitText('built\r\n\x1b]633;D;1\x07$_prompt');
      await pumpEventQueue();
      final waited = decoded(
        await run(['wait-output', id, '--match', 'built', '--timeout', '50']),
      );
      expect(waited['result']['type'], 'output_matched');
      expect(waited['result']['read']['text'], contains('built'));
    });

    test("opens with the prompt drawn, and says when ssh could not", () async {
      final opening = run(['split']);
      await pumpEventQueue();
      final pty = started.last..emitText('\x1b]633;A\x07');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      pty.emitText('user@host \$ \x1b]633;B\x07');
      final opened = decoded(await opening);
      final id = opened['result']['pane']['pane_id'] as String;
      expect(
        decoded(await run(['read', id]))['result']['read']['text'],
        contains('user@host \$'),
      );

      final failing = run(['split', '--ssh', 'nowhere']);
      await pumpEventQueue();
      started.last
        ..emitText('ssh: Could not resolve hostname nowhere\r\n')
        ..exit(255);
      final failed = decoded(await failing, ok: false);
      expect(failed['error']['code'], 'pane_exited');
      expect(failed['error']['message'], contains('p3'));
      expect(failed['error']['message'], contains('255'));
    });

    test('a destructive command is only typed: Enter is the user\'s', () async {
      final (pty, id) = await open();
      final reply = decoded(await run(['run', id, 'sudo rm -rf /srv/old']));
      expect(reply['result']['destructive'], isTrue);
      expect(reply['result']['ran'], isFalse);
      expect(pty.written, contains('sudo rm -rf /srv/old'));
      // Brought in sight again, for the user to see it waits for them.
      expect(shown, hasLength(2));
      expect(pty.written, isNot(contains('\r')));

      pty.emitText('sudo rm -rf /srv/old');
      await pumpEventQueue();
      final enter = await run(['send-keys', id, 'Enter']);
      expect(enter.ok, isFalse, reason: enter.text);
      expect(pty.written, isNot(contains('\r')));
      final typed = await run(['send-text', id, 'rm -r x\n']);
      expect(typed.ok, isFalse);
    });

    test('types and presses keys, and reads the screen', () async {
      final (pty, id) = await open();
      await run(['send-text', id, 'python3']);
      expect(pty.written, endsWith('python3'));
      await run(['send-keys', id, 'enter', 'ctrl+c']);
      expect(pty.written, endsWith('python3\r\x03'));
      pty.emitText('\r\n>>> ');
      await pumpEventQueue();
      final read = decoded(await run(['read', id]));
      expect(read['result']['read']['text'], contains('>>>'));
      expect((await run(['send-keys', id, 'Hyper-x'])).ok, isFalse);
    });

    test('without shell integration, a command is done once the terminal is '
        'quiet', () async {
      final opening = run(['split']);
      await pumpEventQueue();
      final pty = started.last..emitText('server login banner\r\n# ');
      final opened = decoded(await opening);
      expect(
        opened['result']['pane']['state'],
        contains('no shell integration'),
      );
      final id = opened['result']['pane']['pane_id'] as String;
      final running = run(['run', id, 'uptime']);
      await pumpEventQueue();
      pty.emitText('uptime\r\n 10:00 up 3 days\r\n# ');
      final reply = decoded(await running)['result'] as Map;
      expect(reply['guess'], isTrue);
      expect(reply['output'], contains('up 3 days'));
    });

    test('waits for what it is told to', () async {
      final (pty, id) = await open();
      final waiting = run([
        'wait-output',
        id,
        '--regex',
        r'Listening on \d+',
        '--timeout',
        '5000',
      ]);
      await pumpEventQueue();
      pty.emitText('starting\r\nListening on 8080\r\n');
      expect(decoded(await waiting)['result']['type'], 'output_matched');
    });

    test('lists a terminal the user opened, stably, and another agent can '
        'drive it', () async {
      final instance = service.create();
      await pumpEventQueue();
      started.last.emitText(_prompt);
      await pumpEventQueue();

      final listed = decoded(await run(['list']));
      final terminals = (listed['result']['panes'] as List)
          .where((pane) => pane['kind'] == 'terminal')
          .toList();
      expect(terminals, hasLength(1));
      expect(terminals.single['pane_id'], 'p2');
      expect(terminals.single['title'], instance.title);
      expect(
        decoded(await run(['list']))['result']['panes'].toString(),
        listed['result']['panes'].toString(),
      );

      final other = workspace.startAgent(const Project('app', '/tmp/app'));
      final otherKey = host
          .environmentOf(other)[AgentHost.urlVariable]!
          .split('/')
          .last;
      final read = await host.run(otherKey, ['pane', 'read', 'p2']);
      expect(read.ok, isTrue, reason: read.text);
      expect(decoded(read)['result']['read']['pane_id'], 'p2');

      final running = run(['run', 'p2', 'ls']);
      await pumpEventQueue();
      expect(started.last.written, endsWith('ls\r'));
      started.last.emitText(
        'ls\r\n\x1b]633;C\x07ok\r\n\x1b]633;D;0\x07$_prompt',
      );
      expect(decoded(await running)['result']['exit_code'], 0);
    });

    test('a closed terminal is gone', () async {
      final (_, id) = await open();
      service.kill(service.instances.single);
      final read = decoded(await run(['read', id]), ok: false);
      expect(read['error']['code'], 'pane_not_found');
      final panes = decoded(await run(['list']))['result']['panes'] as List;
      expect(panes.any((pane) => pane['kind'] == 'terminal'), isFalse);
    });

    test('close ends it', () async {
      final (pty, id) = await open();
      expect(decoded(await run(['close', id]))['result']['closed'], isTrue);
      expect(service.instances, isEmpty);
      expect(pty.kills, isNotEmpty);
    });

    test('none without a window for them', () async {
      workspace.agentTerminals = null;
      final reply = await run(['split']);
      expect(reply.ok, isFalse);
    });
  });
}
