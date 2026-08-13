<!--
Auto-generated from SKILL.md by ~/sigma-skills/scripts/sync-targets.rb.
Do not edit by hand — edit SKILL.md and re-run the script.
-->

> Build, register, host, embed, and data-bind a bespoke Sigma custom plugin (@sigmacomputing/plugin) to recreate a source visualization for which Sigma has no native chart/KPI/table equivalent — a radial gauge, a custom heatmap, a sankey, or any bespoke viz kind outside Sigma's native element set. **Use when a source viz has no native Sigma equivalent and should be recreated as a bespoke plugin** — not when a native Sigma chart, KPI, or table kind already covers it (that's the `sigma-workbooks` skill). Covers the full lifecycle: writing the single-file plugin, registering it via `POST /v2/plugins`, hosting it, embedding it in a workbook spec bound to real data, and verifying value parity. Ships a worked example (a radial gauge / "value vs. target" plugin) and the `plugin_embed` emitter. Requires an SIGMA_API_TOKEN — obtain via the sigma-api skill first.

# Sigma Plugin Authoring (Recreate-as-Plugin)

Sigma's native element kinds (`bar-chart`, `kpi-chart`, `table`, `pivot-table`,
`point-map`, …) cover most dashboards. Some source vizzes don't map to any of
them — a radial/semicircle gauge, a calendar heatmap, a sankey, a custom
ring/dial. For those, recreate the viz as a **Sigma custom plugin**
(`@sigmacomputing/plugin`): a single-file web app Sigma hosts inside a
workbook element, wired to real workbook data through an editor-panel
contract you define.

## Scope

The **plugin lifecycle**: build → register → host → embed → bind → verify.
Building the rest of the workbook around the plugin (the data table it reads
from, KPIs/controls alongside it, page layout, the hidden data page) is the
`sigma-workbooks` skill's job — this skill only covers the plugin-specific
pieces. Authoring the underlying data model is `sigma-data-models`.

## Decision: does this viz need a plugin at all?

Before reaching for this skill, confirm there's genuinely no native fit:
check the `sigma-workbooks` skill's chart/KPI/table reference and, if still
unsure, query the OpenAPI's `kind` enum (see that skill's "Consulting the
OpenAPI" section). Only recreate as a plugin when the native surface is a
confirmed miss — plugins carry real lifecycle cost (hosting, registration,
re-registration on URL change) that a native chart doesn't.

**A screenshot, mockup, or Claude design artifact is not itself a reason to
build a plugin.** For a whole dashboard/app artifact, start with
`sigma-workbooks/reference/workflows/from-image.md`. App shell, headers, rails,
cards, buttons, controls, input tables, agents, and ordinary charts should be
native workbook elements. Return here only for an individual bespoke data
visualization whose marks/interactions have no native Sigma equivalent. Do not
rebuild an entire artifact as one HTML plugin merely to get pixel control; that
throws away native filtering, writeback, agent, accessibility, and workbook
composition behavior.

## The recipe

### 1. Build the plugin

Single HTML file, vanilla JS, the SDK loaded via
`<script src="https://unpkg.com/@sigmacomputing/plugin">`. Declare the data
contract with `client.config.configureEditorPanel([...])` — one entry per
variable your embed will bind (an `element` source, one or more `column`
bindings sourced from it, optional `text`/`number` config). Subscribe to the
data, render, and:

- Attach a **`ResizeObserver`** to the render container that fully
  recomputes and redraws on every resize (not CSS-only scaling) — see
  `reference/plugin-lifecycle.md` §5 for why this is non-negotiable.
- Include a **synthetic fallback** so the file renders sensible demo data
  when opened standalone (no Sigma `client`, or incomplete bound data) — see
  §6.

Use `plugins/gauge/index.html` (+ `plugins/gauge/README.md`) as the worked
example — a radial gauge with `source`/`value`/`target`/`format` editor-panel
vars. Copy its structure for a new archetype rather than starting from
scratch.

A plugin doesn't have to be display-only, either: it can be **interactive**
— write back to a control or trigger a workbook action from a click, a
selection, or an edit inside the plugin itself. See `reference/patterns.md`
for the writeback (variable + action-trigger) pattern and
`reference/sdk-api.md` for the full editor-panel config vocabulary and
client/hook API behind it.

### 2. Host it

This is the customer's call, not this skill's — any **persistent** public
static host they already use or prefer (their own S3/CDN, GitHub Pages,
Netlify, Vercel, Cloudflare Pages, …) works identically for registration and
embedding. `localhost` is fine for local dev/preview but is never a shared or
headlessly-rendered result; an ephemeral tunnel (free-tier ngrok, etc.) is
not a substitute for persistence either. **Handoff is the default path** —
hand the user the plugin file and the exact hosting + registration steps for
*their* chosen host; a turnkey automated static deploy is a fast-follow, not
built into this skill yet. Localhost is sufficient to build, preview, and
data-parity-verify the plugin; it is **not** sufficient for Sigma's
server-side rendering (headless screenshots, scheduled exports) — see
`reference/plugin-lifecycle.md` §2 before promising a screenshot.

### 3. Register it

```bash
ruby scripts/register-plugin.rb "<plugin name>" "<hosted URL>" "<description>"
# -> prints the pluginId on success
```

This calls `PluginRegister.register_or_get`, which is idempotent (safe to
re-run) and already handles the two registration gotchas that will otherwise
cost you a debugging session — a masked HTTP 404 that can accompany a
*successful* register, and a 403 that means registration is org-admin-gated
in this org (fall back to handoff, don't retry blindly). Full detail in
`reference/plugin-lifecycle.md` §1.

### 4. Embed it, bound to data

Emit the workbook-spec plugin element with the shared emitter — **don't
hand-write this JSON**:

`PluginEmbed.build(id:, plugin_id:, source_element_id:, bindings:, extra_config: {})` (`scripts/plugin_embed.rb`)

`bindings` maps each editor-panel column var to a `columnId` (e.g.
`{"value" => "actual", "target" => "target"}`); `extra_config` is any other
non-binding config (e.g. `{"format" => ".0%"}`). The emitter coerces every
value to a bare string and emits the correct `config.source` shape — see
`examples/gauge-embed.json` for a full output and
`reference/plugin-lifecycle.md` §3 for *why* string-coercion matters (the
failure mode is a silent, misleadingly generic error).

Put the plugin's `source` data element on its own **hidden page** if it
shouldn't be user-visible — `visibleAsSource:false` alone does not hide it
(§4). Then hand the finished element off to the `sigma-workbooks` skill's
normal create/update flow (`POST`/`PUT /v2/workbooks/spec`).

### 5. Verify

- **Data parity (hard gate).** Export the plugin's bound element
  (`source.elementId`) via the standard workbook export flow and assert the
  values match the source/warehouse. Works regardless of hosting.
- **Visual (best-effort).** Screenshot the workbook only when the plugin is
  publicly hosted — on localhost, skip this honestly rather than faking a
  render.

## Reference Index

| File | When to load |
|------|--------------|
| `reference/plugin-lifecycle.md` | **Always, before registering or embedding.** The full verified-gotcha reference: masked-404/403 registration, `url` set-once, hosting/localhost boundary, bare-string config shape, hidden backing page, `ResizeObserver`, synthetic fallback. |
| `reference/sdk-api.md` | **Before writing a plugin's editor-panel config or its data/variable/action wiring.** The authoring-surface lookup: every editor-panel config type (`element`, `column`, `text`, `variable`, `action-trigger`, …), the config-value-by-type table, the vanilla-client-vs-React-hook side-by-side, the column-oriented element data shape, and defensive date parsing. |
| `reference/patterns.md` | **When the plugin needs to do more than display** — JSON settings, edit-mode gating, the variable + action-trigger writeback pattern, dynamic editor-panel reconfiguration, variable-value unwrapping, action-effects, and multi-column roles. Includes a worked (not yet live-verified) click-to-filter writeback recipe. |
| `plugins/gauge/index.html` + `plugins/gauge/README.md` | The worked example plugin (radial gauge, value vs. target) — copy/adapt its structure for a new archetype. |
| `examples/gauge-embed.json` | A `PluginEmbed.build` output exemplar — the exact embed shape to match. |

## Framework choice

This skill's worked example (`plugins/gauge/`) is a dependency-free single
HTML file — the SDK loaded via a CDN `<script>` tag, no build step. That's
the right default for a focused recreate-as-plugin: fast to iterate,
nothing to bundle, easy to hand off for hosting. For a larger, more
interactive plugin (several writeback fields, a real component tree, a
bespoke settings UI), a bundled React+TypeScript scaffold is a reasonable
alternative starting point instead of hand-rolling one — for example
[neil-oliver/sigma-plugin-template](https://github.com/neil-oliver/sigma-plugin-template),
a community scaffold. That's a pointer, not an endorsement or a
vendored dependency — this skill doesn't ship or maintain it.

## Cross-Skill References

- **The rest of the workbook** (the data table the plugin reads from, KPIs
  and controls alongside it, page layout, hidden pages, create/update/PUT
  mechanics) → `sigma-workbooks` skill.
- **The underlying data model** the bound element sources from →
  `sigma-data-models` skill.
- **Auth, base URL, token refresh** → defer to the `sigma-api` skill (either client credentials or interactive browser login yields the `SIGMA_API_TOKEN` this skill needs).

## Troubleshooting

**`Invalid kind:"plugin"` on workbook create/update.** This is Sigma's masked
error for a malformed plugin element — almost always a `config` value that
isn't a bare string (an object/column-ref shape slipped in somewhere other
than `source`). Re-emit via `PluginEmbed.build` rather than hand-editing. See
`reference/plugin-lifecycle.md` §3.

**Registration seems to fail but the plugin exists.** Don't trust a non-2xx
`POST /v2/plugins` response alone — confirm via `GET /v2/plugins` by name (or
just use `register-plugin.rb`, which already does this). See §1.

**403 registering the plugin.** Org-admin-gated in this org. Hand off the
built bundle + exact steps to someone with admin credentials; don't drop the
viz or fabricate a `pluginId`.

**Plugin looks fine at first load, then clips/garbles on resize.** Missing or
incomplete `ResizeObserver` handling — it must fully recompute geometry from
the container's current box, not rely on CSS/viewBox scaling alone. See §5.

**Need a screenshot but only have `localhost`.** Sigma's server-side render
can't reach it. Report the gate as skipped (not passed) and note a public
host is needed for that check specifically — data-parity is unaffected. See
§2.
