# Module: mcp-tool-governance

## ID

mcp-tool-governance

## Version

1

## Minimum risk profile

standard

## Load when

- MCP server configuration added or changed (server manifests, tool allowlists, transport settings)
- New MCP-governed tools exposed to an agent (databases, APIs, file systems, external services)
- Agent tool-access policy changes (least-privilege scoping, per-tool approval, logging)
- MCP tracing or observability wiring changes (`traceparent` propagation, `_meta` fields)
- A2A delegation topology changes (which agents may delegate tasks to each other)

## Required context

- MCP server inventory in use with version constraints and transport model
- Least-privilege tool scoping for each exposed tool (read vs write, path/database bounds)
- Per-tool approval and logging policy (what is auto-approved, what needs a human gate)
- Trace propagation expectations (W3C Trace Context across MCP `_meta` and coordinator events)
- A2A delegation graph, where applicable (which agents may task each other)

## Approval gates

- New MCP server introduction requires security review
- Widening a tool's scope (read to write, broader paths) requires team approval
- Production MCP credential or transport changes require explicit approval

## Required evidence

- Tool-scope manifest showing each exposed tool with its least-privilege bounds
- Approval record for new servers and scope widenings
- Trace sample showing `traceparent` propagation from coordinator event through MCP `_meta`
- Test run exercising the changed tool surface without scope violations

## Prohibited shortcuts

- Do not expose write-capable tools with read-only justification
- Do not widen tool scope without recording why
- Do not add MCP servers with unvetted install steps or transports silently
- Do not disable tool-access logging to speed up pipelines
- Do not treat A2A-delegated work as exempt from approval gates
