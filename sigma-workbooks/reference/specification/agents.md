# Agents & chat — the workbook AI agent

A Sigma workbook can carry a **spec-authorable AI agent** that end users chat with
inside the workbook. It is easy to miss: it is **not a page element** — it's a
**workbook-top-level `agents:[]` array**, a sibling of `pages`/`layout`/`themeName`.
An element-kind scan of `pages[].elements[]` alone will never find it and can wrongly
conclude "not authorable." The agent is *surfaced* on a page via a small `chat`
element that just references the agent's id.

> **Not in the compiled/public OpenAPI as of this writing.** Unlike most of this
> skill's surface, `agents[]` / `dataSources` / `tools` / the `chat` element kind
> do not appear in the compiled OpenAPI asset this skill points to (see
> `SKILL.md`'s *Sources of truth*) — this shape was recovered by live POST +
> GET-readback + render probing on a test org, not read off a schema. Treat field
> names as verified-by-example, not exhaustive; if you need a field not listed
> here, confirm it against a live workbook readback before relying on it.

## Shape

```yaml
name: My Workbook
schemaVersion: 1
folderId: <folderId>
agents:
  - id: ag-analyst
    name: Analyst
    instructions: >-
      You are an analyst for this dataset. Answer questions about revenue,
      orders, and trends over time. Be concise and quantitative; cite the
      numbers you used.
    dataSources:
      - kind: table
        elementId: src          # an element id already in this workbook's pages
pages:
  - id: pg
    name: Overview
    elements:
      - id: src
        kind: table
        # ...
      - id: chat
        kind: chat
        agentId: ag-analyst     # the AGENT's `id` above, not an element id
```

| Field (agent entry) | Required | Notes |
|---|---|---|
| `id` | yes | The agent's handle — referenced by `chat.agentId`, not an element id. |
| `name` | yes | Display name shown in the chat UI. |
| `instructions` | yes | System-prompt-style guidance: role, scope, tone. |
| `dataSources` | yes | Array of `{ kind: table, elementId: <id> }` — one entry per element (table/pivot/etc.) the agent may query. Maps 1:1 to the elements it can see; it cannot see elements not listed here. |
| `tools` | — | **Omit entirely for a read-only analyst** (see below). Present only on a write/action agent. Four `kind`s — see *Tool kinds* below. |
| `description` | — | Free-text description of the agent. |
| `greeting` | — | The chat's opening message. **An object, not a string** — see below. Omit for Sigma's default greeting. |

### `greeting` — the chat's first message

`greeting` is a **two-variant object**. Passing a bare string is a 400
(`document.agents[0].greeting: Invalid value: string`):

```yaml
greeting:                        # fixed text
  mode: static
  message: Hi! Ask me anything about this quarter's pipeline.
```

```yaml
greeting:                        # the agent writes its own opener at open time
  mode: generated
  prompt: Greet the user and summarize the biggest change in the data.
```

Both `message` and `prompt` support `{{formula}}` references. **Live-verified
2026-08-05:** both variants pass `/verify` and round-trip; the `static` message
was additionally confirmed *rendering* in the chat element on a PNG export of the
created workbook.

The `chat` page element is minimal: `{ id, kind: "chat", agentId }` — no other
fields observed. Lay it out like any other element (`gridColumn`/`gridRow` via
`<LayoutElement>`), typically in a sidebar rail next to the dashboard body.

## Read-only analyst vs. write/action agent

**Read-only analyst — the common case.** The agent entry **omits the `tools` key
entirely** — not `tools: []`. An empty-but-present `tools` array is a different
(untested) shape; the verified read-only shape is the key's total absence. It can
only read the elements named in `dataSources` and answer questions about them.

**Write/action agent — adds `tools`.** Each tool gives the agent an action it can
invoke (function-calling style), described to the agent via `name`/`description`
so it knows when to call it:

```yaml
agents:
  - id: ag-planner
    name: Planner
    instructions: You help log review notes against this dataset.
    dataSources:
      - kind: table
        elementId: src
    tools:
      - toolId: log-note
        kind: action
        name: Log a review note
        description: >-
          Call this to record a review note from the conversation. Pass the
          note text as the `note` input.
        steps:
          - kind: effect
            effect: insert-rows
            table: annotations          # an input-table element id (see actions.md)
            values:
              an-note:
                type: agent-input
                inputName: note         # the agent supplies this at call time
```

`value: { type: "agent-input", inputName }` is the tool-call analog of the
`type: "control"` / `type: "constant"` value shapes an `insert-rows` effect takes
from a button (see `reference/workflows/actions.md`) — instead of pulling from a
control's current value or a hard-coded constant, the value comes from an argument
the agent fills in when it decides to call the tool, keyed by `inputName`.

### `requiresApproval` — gate a tool behind a confirmation

An `action` tool also accepts `requiresApproval: true`, which makes the agent ask
the user before executing. **Round-trips verified 2026-08-05.** Set it on anything
that writes: an agent that can silently `delete-rows` is a support ticket.

```yaml
tools:
  - toolId: log-note
    kind: action
    name: Log a review note
    description: Records a review note.
    requiresApproval: true
    steps: [ ... ]
```

## Tool kinds

`tools[]` has **four** `kind`s, not just `action`:

| `kind` | Fields | Status |
|---|---|---|
| `action` | `toolId`, `name`, `description`, `steps`, `requiresApproval?` | **Live-verified** (create + readback) |
| `mcp-connector` | `toolId`, `name`, `connectorId` | Shape accepted; needs a real connector — see below |
| `warehouse-agent` | `toolId`, `description`, `connectionId`, `path` | Not exercised (no such agent in the test org) |
| `search-service` | `toolId`, `description`, `connectionId`, `path` | Not exercised (no such service in the test org) |

`mcp-connector` lets a workbook agent call an external MCP tool by `connectorId`.
A syntactically valid but fake `connectorId` is rejected with `invocable inodes are
not supported by this host: '<id>'` — i.e. the **shape parses** and the id is
resolved against real org inodes, so this needs an actual registered connector to
verify end to end. `warehouse-agent` and `search-service` both take a
`connectionId` + `path` pair (a warehouse-side agent/service), same as a
warehouse-table path.

### `steps[]` — `effect` or `sequence`

An `action` tool's `steps[]` accepts two kinds. `{ kind: effect, ... }` inlines any
of the effect shapes from `reference/workflows/actions.md` (plus an optional `name`
for display). The other is a **reference** to a saved workbook action sequence:

```yaml
steps:
  - kind: sequence
    sequenceId: <existing action sequence id>
    name: Run the reset sequence      # optional display name
```

> **You cannot define a sequence from spec — only reference one.** There is **no**
> top-level `sequences` array in the workbook spec (confirmed against the compiled
> OpenAPI: top-level keys are `name`, `folderId`, `schemaVersion`, `kind`, `pages`,
> `layout`, `themeName`, `themeOverrides`, `agents`, `description`). A
> `sequenceId` that isn't already in the workbook is rejected at verify time:
> `agents[0].tools[0].steps[0].sequenceId: references unknown action sequence
> 'seq-1'`. So `kind: sequence` is only usable against a sequence created in the
> UI — for spec-authored workbooks, inline the effects with `kind: effect` instead.
> (This refines the blanket "action sequences are unsupported" claim: they are not
> *authorable*, but they are *referenceable*.)

> **Scope note:** the write/action agent shape above documents a live-verified
> *pattern* — it is not independently exercised end-to-end in this pass (no
> automated test drives an agent into actually invoking a tool).
> `Richness.agent`'s `tools:` parameter passes an already-shaped array through
> **verbatim** (never reshapes it) for exactly this reason: confirm any non-trivial
> tool/step shape against a live POST + readback before shipping it, same discipline
> as any other agent-input shape in this doc.

## Org-feature gate + graceful degrade

Sigma's AI-agent feature is an **org-level toggle**. On an org where it's off,
posting `agents:[]` + a `chat` element either renders nothing useful or fails —
there's no reliable single error signature to detect this from the spec alone.
**Don't gate on trial-and-error in a shared build.** The safe pattern:

1. If you know (from asking the user, or a prior probe on that org) that AI agents
   are enabled, use `agents[]` + `chat` as above.
2. If you don't know, or you know they're **off**, degrade to a **static text
   element** with a short list of sample prompts instead of a live chat — e.g.:

   ```yaml
   - id: chat-fallback
     kind: text
     body: |
       **Ask about this data** (AI agents aren't enabled on this org)

       Try asking your Sigma admin to enable workbook AI agents, then re-add a
       live chat panel here. Sample questions this dataset can answer:
       - "What was revenue last month vs. the month before?"
       - "Which region had the most orders?"
   ```

Never POST a `chat` element as a cosmetic stand-in when you haven't confirmed the
org supports it — that's the "faked surface" this skill's docs never do. The
fallback text element is the honest alternative, not a workaround to make the
gated feature look implemented.

## Cross-links

- `scripts/lib/richness.rb` — `Richness.agent(id:, name:, instructions:,
  data_source_ids:, tools: [])` builds the `agents[]` entry (`data_source_ids`
  maps to `dataSources`; empty `tools:` is omitted from the emitted Hash,
  matching the read-only shape above). `Richness.chat(id:, agent_id:)` builds
  the page element. Both are gated behind `Richness::SURFACES[:agent]`; a
  NO-GO flip returns `{opt_in: true, id:}` rather than emitting an unverified
  shape.
- `reference/workflows/actions.md` — the `insert-rows`/`clear-control`/
  `set-control-value` effect shapes a write-agent's tool `steps[]` reuses, and
  the append-only-log input-table pattern a logging tool typically targets.
