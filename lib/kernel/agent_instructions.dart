import 'claude_code/claude_sdk_tools.dart';

/// What BaoCode tells the agents it can be reached from (their process
/// has [commandVariable]) of what it gives them, besides their own prompt:
/// terminals for servers, and the app's tools ([ClaudeSdkTools]).
abstract final class AgentInstructions {
  /// The variable of BaoCode's command for its agents (AgentHost's
  /// `commandVariable`): there for an agent BaoCode can be reached from.
  static const commandVariable = 'BAOCODE_AGENT';

  /// Where the command reaches the app, as that agent (AgentHost's
  /// `urlVariable`).
  static const urlVariable = 'BAOCODE_AGENT_URL';

  /// Has the agent work on servers in a terminal the user watches, not in
  /// its shell.
  static const servers = '''
<servers>
To work on another machine over ssh, use a terminal in BaoCode that the user watches, not ssh in your shell tool: `"\$BAOCODE_AGENT" terminal open --ssh <host>` prints its id (t1, …); then `"\$BAOCODE_AGENT" terminal run t1 '<command>'` runs a command there and prints its output and exit code. The baocode-agents skill has the rest (type, keys, read, wait, close). scp, rsync and git over ssh are fine in your shell.
</servers>''';

  /// Has the agent use the user's browser through BaoCode, not a browser
  /// tool of its own.
  static const browser = '''
<browser>
For the user's browser, use the mcp__baocode__browser_* tools: the tabs the user shares with BaoCode, which they watch in its side panel (browser_tabs lists them, browser_open opens one). Use them rather than any other browser tool (Chrome DevTools, Playwright, …), unless the user asks for that one.
</browser>''';

  /// What an agent other than Claude Code (whose launch says [servers]
  /// itself, and has the tools' instructions from their server) is told:
  /// none where BaoCode cannot be reached from it.
  static String? of(Map<String, String> environment) {
    if (!environment.containsKey(commandVariable)) return null;
    const tabs = 'mcp__${ClaudeSdkTools.server}__browser_tabs';
    return [
      servers,
      if (ClaudeSdkTools.called(tabs) != null) browser,
      if (ClaudeSdkTools.instructions case final text? when text.isNotEmpty)
        text,
    ].join('\n\n');
  }

  /// The app's tools as an MCP server over HTTP, for the agent of
  /// [environment]: none while there are none, or where BaoCode cannot be
  /// reached from it.
  static String? mcpUrl(Map<String, String> environment) =>
      switch (environment[urlVariable]) {
        final url? when ClaudeSdkTools.any => '$url/mcp',
        _ => null,
      };
}
