import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/workspace/agent_host.dart';
import 'package:baocode/workspace/agent_server.dart';
import 'package:baocode/workspace/agent_skill.dart';
import 'package:baocode/workspace/chat_grid.dart' show PaneSide;
import 'package:baocode/workspace/workspace.dart';

Map<String, dynamic> _json(AgentReply reply, {bool ok = true}) {
  expect(reply.ok, ok, reason: reply.text);
  return jsonDecode(reply.text) as Map<String, dynamic>;
}

Map<String, dynamic> _result(AgentReply reply) =>
    _json(reply)['result'] as Map<String, dynamic>;

Map<String, dynamic> _error(AgentReply reply) =>
    _json(reply, ok: false)['error'] as Map<String, dynamic>;

void main() {
  test(
    'the command posts its arguments as given, and prints the answer',
    () async {
      final dir = await Directory.systemTemp.createTemp('baocode-agent-');
      addTearDown(() => dir.delete(recursive: true));
      final workspace = Workspace(
        kernels: MockKernels.all,
        projects: const [Project('app', '/tmp/app')],
      );
      final host = AgentHost(workspace);
      await serveAgents(host, directory: dir.path, installSkill: false);
      final caller = workspace.create();
      final environment = host.environmentOf(caller);
      Future<ProcessResult> run(
        List<String> arguments, {
        Map<String, String>? variables,
      }) => Process.run(
        environment[AgentHost.commandVariable]!,
        arguments,
        environment: variables ?? environment,
        includeParentEnvironment: variables == null,
      );

      final current = jsonDecode(
        (await run(['pane', 'current', '--current'])).stdout,
      ) as Map;
      expect(current['result']['pane']['pane_id'], 'p1');
      expect(current['result']['pane']['is_caller'], isTrue);
      expect(environment[AgentHost.paneIdVariable], 'p1');
      final listed = jsonDecode((await run(['pane', 'list'])).stdout) as Map;
      expect(
        (listed['result']['panes'] as List).any(
          (pane) => pane['is_caller'] == true,
        ),
        isTrue,
      );
      const prompt = 'it\'s "quoted" & a=b%20 ünïcode\nand a line';
      final started = await run([
        'agent',
        'start',
        'reviewer',
        '--kind',
        'codex',
        '--no-focus',
        '--',
        prompt,
      ]);
      expect(started.exitCode, 0, reason: '${started.stdout}');
      final startedJson = jsonDecode(started.stdout as String) as Map;
      expect(startedJson['result']['agent']['pane_id'], 'p2');
      expect(startedJson['result']['agent']['name'], 'reviewer');
      final worker = workspace.threads.last;
      expect((worker.session.itemAt(0) as UserMessageItem).text, prompt);

      final unknown = await run(['fly']);
      expect(unknown.exitCode, 1);
      final unknownJson = jsonDecode(unknown.stdout as String) as Map;
      expect(unknownJson['error']['code'], 'unknown_command');
      final outside = await run(['list'], variables: {'PATH': '/usr/bin:/bin'});
      expect(outside.exitCode, 2);
      worker.session.stop();
    },
  );

  late Workspace workspace;
  late AgentHost host;
  late AgentThread caller;
  late String key;

  /// [caller]'s key, as its process is given it.
  String keyOf(AgentThread thread) =>
      host.environmentOf(thread)[AgentHost.urlVariable]!.split('/').last;

  setUp(() {
    workspace = Workspace(
      kernels: MockKernels.all,
      projects: const [Project('app', '/tmp/app')],
    );
    host = AgentHost(workspace)
      ..url = 'http://127.0.0.1:4100'
      ..command = '/tmp/bin/baocode-agent';
    caller = workspace.create();
    key = keyOf(caller);
  });

  test("each agent's process is told where to reach the app, as itself", () {
    final environment = host.environmentOf(caller);
    expect(environment[AgentHost.commandVariable], '/tmp/bin/baocode-agent');
    expect(
      environment[AgentHost.urlVariable],
      startsWith('http://127.0.0.1:4100/'),
    );
    expect(environment[AgentHost.paneIdVariable], 'p1');
    expect(host.environmentOf(caller), environment);
    final other = workspace.startAgent(const Project('other', '/tmp/other'));
    expect(keyOf(other), isNot(key));
    expect(host.environmentOf(other)[AgentHost.paneIdVariable], 'p2');
    // As its session opens, it is given them.
    expect(caller.session.kernelContext.environment, environment);
    // One on another machine could not reach this one's app.
    final remote = workspace.startAgent(
      const Project('remote', 'ssh://server/srv/app'),
    );
    expect(host.environmentOf(remote), isEmpty);
  });

  testWidgets('an agent starts another beside it, waits for it and reads it', (
    tester,
  ) async {
    expect((await host.run('nobody', ['pane', 'list'])).ok, isFalse);
    expect(
      _result(
        await host.run(key, ['pane', 'current', '--current']),
      )['pane']['pane_id'],
      'p1',
    );
    expect(
      (_result(await host.run(key, ['pane', 'list']))['panes'] as List).any(
        (pane) => pane['is_caller'] == true,
      ),
      isTrue,
    );
    expect((await host.run(key, ['agent', 'start'])).ok, isFalse);
    expect(
      _error(
        await host.run(key, ['agent', 'start', 'Reviewer', '--kind', 'codex']),
      )['code'],
      'invalid_request',
    );

    final started = await host.run(key, [
      'agent',
      'start',
      'reviewer',
      '--kind',
      'codex',
      '--no-focus',
      '--',
      'Look',
      'at @lib/a.dart',
    ]);
    expect(started.ok, isTrue, reason: started.text);
    final startedAgent = _result(started)['agent'] as Map;
    expect(startedAgent['pane_id'], 'p2');
    expect(startedAgent['name'], 'reviewer');
    expect(startedAgent['agent_kind'], 'codex');
    final worker = workspace.threads.firstWhere(
      (thread) => thread.kernel == MockKernels.codex,
    );
    // Beside it, the caller still focused; in full access.
    expect(workspace.grid.panes, [caller, worker]);
    expect(workspace.selected, caller);
    expect(worker.session.selected(KernelChoiceKind.permission), 'full');

    final waitingBlocked = host.run(key, [
      'agent',
      'wait',
      'reviewer',
      '--timeout',
      '20000',
    ]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    final blocked = await waitingBlocked;
    expect(_result(blocked)['agent']['agent_status'], 'blocked');
    expect(
      _error(
        await host.run(key, ['agent', 'prompt', 'reviewer', 'more']),
      )['code'],
      'agent_blocked',
    );

    final listed = _result(await host.run(key, ['pane', 'list']));
    final panes = (listed['panes'] as List).cast<Map>();
    expect(
      panes.any((pane) => pane['pane_id'] == 'p1' && pane['is_caller'] == true),
      isTrue,
    );
    expect(
      panes.any(
        (pane) =>
            pane['pane_id'] == 'p2' &&
            pane['name'] == 'reviewer' &&
            pane['agent_status'] == 'blocked' &&
            pane['kind'] == 'agent',
      ),
      isTrue,
    );

    worker.session.answer(const ApprovalAnswer(ApprovalDecision.allowOnce));
    final answered = host.run(key, [
      'agent',
      'wait',
      'reviewer',
      '--timeout',
      '30000',
    ]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    final reply = await answered;
    expect(_result(reply)['agent']['agent_status'], isIn(['idle', 'done']));
    final read = _result(await host.run(key, ['agent', 'read', 'reviewer']));
    expect(read['read']['text'], contains(worker.session.lastReply!));

    expect(
      (await host.run(key, ['agent', 'prompt', 'reviewer', 'Again'])).ok,
      isTrue,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      _result(
        await host.run(key, ['agent', 'send-keys', 'reviewer', 'esc']),
      )['stopped'],
      isTrue,
    );
    final stopped = host.run(key, [
      'agent',
      'wait',
      'reviewer',
      '--timeout',
      '1000',
    ]);
    await tester.pump(const Duration(seconds: 1));
    expect(
      _result(await stopped)['agent']['agent_status'],
      isIn(['idle', 'done']),
    );

    expect(
      _error(
        await host.run(keyOf(worker), [
          'agent',
          'start',
          'nested',
          '--kind',
          'codex',
        ]),
      )['code'],
      'forbidden',
    );
    expect((await host.run(key, ['agent', 'wait', 'missing'])).ok, isFalse);

    expect(
      (await host.run(key, ['agent', 'prompt', 'reviewer', 'Once more'])).ok,
      isTrue,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(worker.session.isStreaming, isTrue);
    expect(
      _result(await host.run(key, ['pane', 'close', 'p2']))['closed'],
      isTrue,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(worker.session.isStreaming, isFalse);
    expect(workspace.grid.panes, [caller]);
    expect(workspace.threads, contains(worker));
    expect(
      _result(await host.run(key, ['pane', 'close', 'p2']))['closed'],
      isFalse,
    );
    expect(
      (_result(await host.run(key, ['agent', 'list']))['agents'] as List).any(
        (agent) => agent['name'] == 'reviewer',
      ),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a user-opened pane is listed, stable, and can be driven', (
    tester,
  ) async {
    expect(
      _result(
        await host.run(key, ['pane', 'current', '--current']),
      )['pane']['pane_id'],
      'p1',
    );
    workspace.startAgent(caller.project);
    final other = workspace.startWorker(
      caller.project,
      MockKernels.codex,
      const <KernelChoiceKind, String>{},
    );
    workspace.openBeside(other, caller, PaneSide.right, focus: false);
    expect(workspace.grid.contains(other), isTrue);
    final otherId = host.paneIdOf(other);

    final listed = _result(await host.run(key, ['pane', 'list']));
    final panes = (listed['panes'] as List).cast<Map>();
    expect(panes, hasLength(2));
    expect(
      panes.any((pane) => pane['pane_id'] == 'p1' && pane['is_caller'] == true),
      isTrue,
    );
    expect(panes.any((pane) => pane['pane_id'] == otherId), isTrue);
    expect(panes.any((pane) => pane['name'] != null), isFalse);
    expect(
      _result(await host.run(key, ['pane', 'list']))['panes'].toString(),
      listed['panes'].toString(),
    );
    expect(
      _result(
        await host.run(keyOf(other), ['pane', 'current', '--current']),
      )['pane']['pane_id'],
      otherId,
    );
    expect(
      (_result(await host.run(keyOf(other), ['pane', 'list']))['panes'] as List)
          .any((pane) => pane['pane_id'] == 'p1'),
      isTrue,
    );

    expect(
      _error(await host.run(key, ['agent', 'prompt', 'p1', 'nope']))['code'],
      'cannot_target_self',
    );
    expect(
      _error(await host.run(key, ['agent', 'wait', 'p1']))['code'],
      'cannot_target_self',
    );
    expect(
      _error(await host.run(key, ['agent', 'send-keys', 'p1', 'esc']))['code'],
      'cannot_target_self',
    );
    expect(
      _error(await host.run(key, ['pane', 'close', 'p1']))['code'],
      'cannot_target_self',
    );
    expect(
      _error(await host.run(key, ['pane', 'run', 'p1', 'ls']))['code'],
      'not_a_terminal',
    );

    final sent = await host.run(key, [
      'agent',
      'prompt',
      otherId,
      'Look at this',
    ]);
    expect(sent.ok, isTrue, reason: sent.text);
    await tester.pump(const Duration(seconds: 1));
    expect(
      _result(
        await host.run(key, ['pane', 'send-keys', otherId, 'ctrl+c']),
      )['stopped'],
      isTrue,
    );
    expect(
      _result(await host.run(key, ['pane', 'close', otherId]))['closed'],
      isTrue,
    );
    expect(workspace.grid.panes, [caller]);
    expect(workspace.threads, contains(other));
    await tester.pump(const Duration(seconds: 5));
  });

  test("list names another project's pane, not sidebar history", () async {
    expect(
      _result(
        await host.run(key, ['pane', 'current', '--current']),
      )['pane']['pane_id'],
      'p1',
    );
    workspace.startAgent(caller.project);
    expect(
      (_result(await host.run(key, ['pane', 'list']))['panes'] as List),
      hasLength(1),
    );

    final foreign = workspace.startAgent(const Project('other', '/tmp/other'));
    workspace.openBeside(foreign, caller, PaneSide.right, focus: false);
    final panes =
        (_result(await host.run(key, ['pane', 'list']))['panes'] as List)
            .cast<Map>();
    expect(panes, hasLength(2));
    expect(
      panes.any(
        (pane) =>
            pane['pane_id'] == host.paneIdOf(foreign) &&
            pane['project'] == 'other',
      ),
      isTrue,
    );
  });

  test('agent start names are unique and not pane ids', () async {
    expect(
      (await host.run(key, [
        'agent',
        'start',
        'reviewer',
        '--kind',
        'codex',
        '--no-focus',
      ])).ok,
      isTrue,
    );
    expect(
      _error(
        await host.run(key, ['agent', 'start', 'reviewer', '--kind', 'codex']),
      )['code'],
      'agent_name_taken',
    );
    expect(
      (await host.run(key, ['agent', 'start', 'p1', '--kind', 'codex'])).ok,
      isFalse,
    );
    expect(
      (await host.run(key, ['agent', 'start', '1bad', '--kind', 'codex'])).ok,
      isFalse,
    );
    final worker = workspace.threads.firstWhere(
      (thread) => thread.kernel == MockKernels.codex,
    );
    final title = worker.title;
    final renamed = await host.run(key, ['agent', 'rename', 'p2', 'writer']);
    expect(_result(renamed)['agent']['name'], 'writer');
    expect(worker.title, title);
    expect(
      (_result(await host.run(key, ['agent', 'get', 'writer']))['agent']
          as Map)['pane_id'],
      'p2',
    );
  });

  testWidgets('agent wait times out at 100s and says to wait again', (
    tester,
  ) async {
    expect(
      (await host.run(key, [
        'agent',
        'start',
        'reviewer',
        '--kind',
        'codex',
        '--no-focus',
        '--',
        'Go',
      ])).ok,
      isTrue,
    );
    final waiting = host.run(key, [
      'agent',
      'wait',
      'reviewer',
      '--until',
      'idle',
    ]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 101));
    final error = _error(await waiting);
    expect(error['code'], 'timeout');
    expect(error['message'], contains('agent wait reviewer'));
  });

  test('the skill names the command and the variable it needs', () {
    final text = AgentSkill.text;
    expect(text, startsWith('---\nname: baocode-agents\n'));
    expect(
      text,
      contains('"\$BAOCODE_AGENT" agent start reviewer --kind codex'),
    );
    expect(text, contains('"\$BAOCODE_AGENT" pane current --current'));
    expect(text, contains(r'test -n "${BAOCODE_AGENT_URL:-}"'));
    expect(text, contains('BAOCODE_PANE_ID'));
    expect(text, contains('--timeout 100000'));
    expect(text, isNot(contains('120000')));
    expect(AgentSkill.stale(null, text), isTrue);
    expect(AgentSkill.stale(text, text), isFalse);
    expect(AgentSkill.stale('my own', text), isFalse);
  });

  test('pane and agent without a subcommand print help', () async {
    expect((await host.run(key, ['help'])).text, AgentHost.usage);
    expect((await host.run(key, ['pane'])).text, AgentHost.paneUsage);
    expect((await host.run(key, ['agent'])).text, AgentHost.agentUsage);
    expect((await host.run(key, ['pane'])).ok, isTrue);
  });
}
