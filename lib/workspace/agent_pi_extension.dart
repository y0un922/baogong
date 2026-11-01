/// The pi extension BaoCode starts its pi agents with (see
/// `piBaoCodeArguments`), written beside the agents' command: pi has the
/// app's tools (`AgentHost.mcp`, over HTTP) as its own, under the names
/// Claude Code and Codex know them by (`mcp__baocode__<name>`), and its
/// ssh in its shell is turned to a terminal of BaoCode's (the command's
/// `hook pre-tool-use`, as Claude Code's).
abstract final class AgentPiExtension {
  static const text = r'''
// BaoCode's tools for pi, and its ssh turned to a terminal the user
// watches. Written by BaoCode as it starts; pi agents BaoCode starts load it.
export default async function (pi: any) {
  const url = process.env.BAOCODE_AGENT_URL;
  if (!url) return;
  let next = 0;

  async function post(message: object, signal?: AbortSignal) {
    return fetch(`${url}/mcp`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", ...message }),
      signal,
    });
  }

  async function call(method: string, params: object = {}, signal?: AbortSignal) {
    const id = ++next;
    const onAbort = () =>
      post({ method: "notifications/cancelled", params: { requestId: id } }).catch(() => {});
    signal?.addEventListener("abort", onAbort, { once: true });
    try {
      const answer: any = await (await post({ id, method, params }, signal)).json();
      if (answer.error) throw new Error(answer.error.message);
      return answer.result;
    } finally {
      signal?.removeEventListener("abort", onAbort);
    }
  }

  // ssh in the shell runs out of the user's sight: BaoCode says why not,
  // and how to work in a terminal instead.
  pi.on("tool_call", async (event: any) => {
    if (event.toolName !== "bash" || typeof event.input?.command !== "string") return;
    try {
      const response = await fetch(url, {
        method: "POST",
        body: new URLSearchParams([
          ["arg", "hook"],
          ["arg", "pre-tool-use"],
          ["stdin", JSON.stringify({ tool_name: "Bash", tool_input: { command: event.input.command } })],
        ]),
      });
      const text = (await response.text()).trim();
      if (!text) return;
      const output = JSON.parse(text).hookSpecificOutput;
      if (output?.permissionDecision === "deny") {
        return { block: true, reason: output.permissionDecisionReason };
      }
    } catch {
      // BaoCode could not say: the command runs.
    }
  });

  let tools: any[];
  try {
    await call("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "pi", version: "1" },
    });
    tools = (await call("tools/list")).tools ?? [];
  } catch {
    return;
  }
  for (const tool of tools) {
    pi.registerTool({
      name: `mcp__baocode__${tool.name}`,
      label: tool.name,
      description: tool.description ?? "",
      parameters: tool.inputSchema ?? { type: "object", properties: {} },
      async execute(_id: string, params: any, signal?: AbortSignal) {
        const result = await call("tools/call", { name: tool.name, arguments: params }, signal);
        const content = (result.content ?? []).map((block: any) =>
          block.type === "image"
            ? { type: "image", data: block.data, mimeType: block.mimeType }
            : { type: "text", text: block.text ?? JSON.stringify(block) },
        );
        if (result.isError) {
          throw new Error(content.map((block: any) => block.text ?? "").join("\n"));
        }
        return { content, details: undefined };
      },
    });
  }
}
''';
}
