import 'dart:convert';

import 'agent_host.dart';

/// The skill that tells agents of `baocode-agent` (see [AgentHost]): in
/// Claude Code's skills and the Agent Skills folder Codex and pi read
/// (`~/.agents/skills/`). The user's as any skill is; BaoCode writes it
/// anew only while its [marker] is in it.
abstract final class AgentSkill {
  static const name = 'baocode-agents';

  /// Its line that says BaoCode wrote it; a skill without it is left as
  /// it is.
  static const marker =
      '<!-- Written by BaoCode, which keeps it up to date. '
      'Delete this line to keep your own changes. -->';

  /// Whether [existing] (its file's text, null for none) is to be written
  /// as [text]: none, or BaoCode's and not the same.
  static bool stale(String? existing, String text) =>
      existing == null || (existing.contains(marker) && existing != text);

  static const _description =
      'Start other coding agents (Codex, Claude Code) beside you in BaoCode, '
      'send them work, wait for them and read their answers; and work in '
      'terminals the user watches in BaoCode, on this machine or on a server '
      'over ssh with nothing installed there. Use it whenever you would ssh '
      'to a server (instead of ssh in your shell), when the user asks for '
      'another agent to do something or to work with other agents in BaoCode, '
      'and for a terminal of BaoCode\'s. Requires BAOCODE_AGENT_URL (an agent '
      'BaoCode started).';

  static String get text {
    const command = '"\$${AgentHost.commandVariable}"';
    return '''
---
name: $name
description: ${jsonEncode(_description)}
---
$marker

# Agents in BaoCode

BaoCode runs you in a pane, and can run other coding agents beside you. A pane is either an agent chat in the grid or a terminal in the side panel. The command talks to both.

Before anything else, check that BaoCode started you:

```bash
test -n "\${${AgentHost.urlVariable}:-}"
```

If it is not set, say that you are not running in BaoCode and stop.

## Learn the current CLI

The installed command is the authority for syntax. Begin with:

```bash
$command help
$command pane
$command agent
```

Most control commands print JSON. Read identifiers and state from those responses instead of predicting either one. Errors are JSON `{"error":{"code":"…","message":"…"}}` with exit status 1. Help is plain text.

## IDs and current context

All panes share one id space: `p1`, `p2`, … assigned once for this app run and not reused. BaoCode injects yours at launch:

```bash
printf '%s\\n' "\$${AgentHost.paneIdVariable}"
```

Prefer `--current` when a pane command should target you. `pane current --current` is you; without `--current` it is the focused pane, which may belong to the user.

An agent name such as `reviewer` is an alias for the live agent in that pane. Names must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents. Agent commands accept either the name or the pane id.

Discover live state with:

```bash
$command pane current --current
$command pane list
$command agent list
```

`pane list` is you, agent panes on screen (any project; other projects named on the item), agents you started that are still around, and terminals in this project's side panel. Sidebar history is not listed.

Each pane has `kind` (`agent` or `terminal`), `agent_status` (`idle`, `working`, `blocked`, `done`, `unknown`), `title`, `project`, `is_caller`, and `focused`. `done` means a turn ended and has not been seen; `idle` is the same underlying state after it was seen. `blocked` is waiting for the user's approval. A failed agent is `unknown` with an `error` field.

## Typical flows

Start an agent, wait for it, read what it said:

```bash
$command agent start reviewer --kind codex --no-focus -- "Review lib/auth.dart for bugs"
$command agent prompt reviewer "Now write a test for the bug you found" --wait --timeout 100000
$command agent read reviewer
```

`--wait` waits until `idle`, `done` or `blocked` (default 100s). If the agent is already `blocked`, `prompt` returns `agent_blocked` and sends nothing. If it times out, run `agent wait` again.

Open a terminal, run a command, wait for output, read it:

```bash
$command pane split --current --no-focus --ssh deploy@my-server
$command pane run p2 "systemctl status nginx"
$command pane wait-output p2 --match "active (running)" --timeout 100000
$command pane read p2 --source recent-unwrapped --lines 120
```

`--timeout` is milliseconds (default 100000). A longer `--timeout` must stay under how long your shell lets a command run (Claude Code kills a command at two minutes). If it times out, run `pane wait-output` / `agent wait` again. `pane split --direction right|down` is accepted and ignored: BaoCode terminals live in the side panel, not the grid. `--ssh` opens a shell on that host as ssh reaches it, nothing installed there. Where ssh asks for a password, ask the user to type it in the terminal, then `wait-output` for the prompt.

`pane run` sends the text and Enter, waits until the command is done, and returns `output` and `exit_code`. A command that looks destructive (`rm -r`, `dd`, `mkfs`, `DROP TABLE`, `git push --force`, …) is only typed: the user runs it with Enter, or not. Tell the user why it is needed. `send-text` and `send-keys` do not press Enter on one.

On an agent pane, `pane run` / `send-text` / `wait-output` error and point at the agent commands. `pane read` returns the last answer. `pane send-keys` / `agent send-keys` accept `esc` or `ctrl+c` to stop the turn.

```bash
$command pane send-text p2 "SELECT count(*) FROM users;"
$command pane send-keys p2 enter
$command pane send-keys p2 ctrl+c
$command agent send-keys reviewer esc
```

## Safety

- Use `--no-focus` for background work unless the user asked to switch context.
- Use `--current` or an explicit id. Do not guess ids.
- Parse ids from JSON. Do not derive them from sidebar order or examples.
- Do not close a pane you did not open unless the user explicitly asked.
- You cannot close, prompt, or stop yourself.
- An agent you started cannot start agents of its own.
- They run in full access and do not ask before what they run. Should one still wait for the user's approval, `blocked` says so: tell the user, and wait again.
- Write a prompt that stands on its own: the agent sees none of your conversation.
- The agents work in the same folder as you. Give each a part of its own, and do not change the same files at the same time.
- Check what an agent says it did before relying on it.
- In Codex's sandbox, the command cannot reach BaoCode: run it with escalated permissions (outside the sandbox).
- scp, rsync and git over ssh are fine in your shell. ssh for a login shell is not: use `pane split --ssh`.
''';
  }
}
