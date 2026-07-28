# Gauge plugin (value vs. target)

A single-file, vanilla-JS Sigma custom plugin (`@sigmacomputing/plugin`) that
renders a radial (semicircle) gauge — a value swept against a target, colored
red/amber/green (RAG) by how close it is. It exists to recreate source vizzes
(a QuickSight/Power BI-style gauge, a "% to target" indicator, …) for which
Sigma has no native chart kind, as part of WS2's `recreate-as-plugin`
disposition.

Clean-room, generic data only — the file has no customer names or data. When
there's no Sigma host (opened directly in a browser) or the bound data is
incomplete, it falls back to a synthetic `value: 82, target: 100` so it always
previews standalone.

## Editor-panel bindings

This is the contract other WS2 machinery (`shared/lib/plugin_embed`, the
gap-scan/emitter) binds to — **do not rename these fields**:

| name     | type                          | meaning                              |
|----------|-------------------------------|---------------------------------------|
| `source` | `element`                     | the bound data element                |
| `value`  | `column` (source: `source`)   | the current value                     |
| `target` | `column` (source: `source`)   | the target/goal                       |
| `format` | `text`                        | optional number-format hint for labels|

`format` supports a lightweight subset: a string containing `%` renders a
percentage (`.1%` → 1 decimal place); a string like `.2f` fixes 2 decimals;
`d`/`int` rounds to an integer; anything else (including blank) falls back to
a locale-grouped number.

## Design notes

- **`ResizeObserver` on the render container → full redraw.** This is the
  fix for the #1 "wonky plugin" failure mode: a plugin that only lets
  CSS/viewBox scaling handle resize ends up with illegible text or a clipped
  arc at small panel widths. Every resize here recomputes stroke width, font
  size, and arc geometry from the container's actual box and re-renders from
  scratch (not an incremental patch).
- **Synthetic fallback (`synth()`)** renders whenever `client` is unavailable
  or the bound `value`/`target` columns don't resolve to a non-empty row, so
  the plugin is always previewable outside a workbook.
- Single file, single responsibility: read `{value, target}`, draw the arc.
  No dependencies beyond the Sigma plugin SDK (loaded via
  `<script src="https://unpkg.com/@sigmacomputing/plugin">`).

## Register + embed

1. **Host** the file somewhere Sigma's render server can reach — a public
   static host (for headless PNG export to work) or `localhost` for local
   preview/dev (data-parity still works either way; only the headless
   screenshot needs a public host).
2. **Register** the plugin:
   ```ruby
   Sigma.request(:post, '/v2/plugins',
     body: JSON.generate(name: 'Gauge (value vs. target)',
                          description: 'Recreate-as-plugin radial gauge',
                          url: PLUGIN_URL, type: 'element'))
   # A masked HTTP 404 can accompany a SUCCESSFUL register — always confirm
   # by name via GET /v2/plugins, never trust the POST status alone.
   ```
   The `url` is set-once per registration; re-register (or use the update
   path, if available in your org) to change it. A 403 means registration is
   org-admin-gated in that org.
3. **Embed** the registered plugin in a workbook spec element, bound to a
   data element. Every `config` value must be a **bare string** — the
   object/`{kind:"column"}` form is silently rejected (masked as
   `Invalid kind:"plugin"`):
   ```json
   {
     "id": "gauge-el",
     "kind": "plugin",
     "pluginId": "<the registered pluginId>",
     "config": {
       "source": { "kind": "element", "elementId": "tbl-src" },
       "value": "actual",
       "target": "target"
     }
   }
   ```
   `scripts/plugin_embed.rb` (`PluginEmbed.build`) emits exactly this shape from
   `{value: colId, target: colId}` bindings.
4. **Bind** `tbl-src` to a data element carrying the value + target columns
   (put it on a separate hidden page — `visibleAsSource:false` alone does
   not remove it from layout).
