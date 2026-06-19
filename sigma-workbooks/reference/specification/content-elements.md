# Content Elements (text, image, divider, embed)

The non-data-bound elements — prose, images, rules, and embedded URLs. None take a `source`. Pull any kind's exact shape from the spec:

```bash
jq --arg k text 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
# swap k for image / divider / embed
```

These position in the page grid via `<LayoutElement>` like any other element — see `layout.md`.

## text

A Markdown block — titles, descriptions, section headers, callouts. Required `id`, `kind`, `body`; optional `verticalAlign` (`start` / `middle` / `end`) and `overflow` (`clip` / `scroll`). No `name`, no `source`.

```yaml
id: text-header
kind: text
body: |
  # Sales Overview

  A weekly view of revenue, with the regions driving the most growth.
```

(YAML's `|` block scalar keeps the body readable.)

### `body`: Markdown + inline styling

`body` is Markdown plus a small set of inline HTML for styling. Standard Markdown: paragraphs, `**bold**`, `*italic*`, headings (`#`, `##`, `###`), bullet / ordered lists, `[links](https://example.com)`, and `{{formula}}` / `{{ast | fmt}}` segments (same syntax as element titles, e.g. `{{Count() | ,.0f}}`).

Inline styling via HTML — all round-trip through the spec and render:

- **Color / background:** `<span style="color: #8B0000">` and/or `background-color` — **hex values** (`#rgb` / `#rrggbb`).
- **Font size:** `<span style="font-size: 24px">`.
- **Font family:** `<span style="font-family: Georgia">` — a single family name that starts with a letter and contains only letters, numbers, spaces, underscores, or dashes. **No comma-separated fallback lists** — `"Georgia, serif"` is rejected.
- **Paragraph block styles:** `<p class="p-large">…</p>` and `<p class="p-small">…</p>`.
- **Alignment:** `<p style="text-align: center">…</p>` (also `left` / `right`).

A single `<span>` can combine properties (e.g. color + font-size). If a value violates its rule, the API rejects the whole `body` with a specific message naming the field — read it and fix the value.

Common pattern — bold + color (both supported):

```markdown
# **<span style="color: #8B0000">Deployments Dashboard</span>**
```

## image

Embeds an external image by URL (hosted only — no uploads). Required `id`, `kind`, `url`; `url` supports `{{formula}}` references for dynamic selection. `alt`, `link`, and a `style` block exist too — pull the shape from the recipe. Sizing comes from the layout grid, not the element.

```yaml
id: logo
kind: image
url: https://cdn.example.com/logo.png
```

## divider

A rule for separating sections. Required `id`, `kind`; optional `direction` (`horizontal` / `vertical`), `align`, and `style` (`color` / `width` / `strokeStyle`).

```yaml
id: section-rule
kind: divider
```

## embed

Renders an external URL inline — a hosted report, form, video, etc. Required `id`, `kind`, `url`; `url` supports `{{formula}}` references.

```yaml
id: embed-report
kind: embed
url: https://example.com/report
```

## plugin (2026-06-18 release)

Embeds a **custom Sigma plugin** as a page element. Required `id`, `kind`, `pluginId`; optional `displayName`, `style`, and a plugin-defined `config`.

```yaml
id: my-histogram
kind: plugin
pluginId: 6cdf51c1-dda0-4f99-aa08-5c72804020bb   # the plugin's registered UUID
displayName: Histogram                            # optional label
style: { backgroundColor: "#101826" }             # optional element background (see notes)
config:                                            # plugin-defined bindings + settings
  source: { kind: element, elementId: master }     # bind an element as the data source
  valueColumn: { kind: column, columnId: m-netprof, source: source }
  chartType: Frequency
  binMethod: "Auto (Sturges)"
  binCount: "10"
```

- **Data bindings** inside `config`: `{ kind: element, elementId }` selects a source element; `{ kind: column, columnId, source }` selects one of its columns (`{ kind: column, columnIds: [...], source }` for several); `source: source` points at the `config.source` element. A plugin can also read a control's value — bind the control the same way the plugin's input expects.
- **`config` is half-opaque** — bare **literals** (strings/booleans/string-arrays) pass through unvalidated and are handed to the plugin at render time (a literal round-tripping does **not** mean Sigma supports it). But **`kind`-tagged references are resolved and validated**: a `{kind: element, ...}` / `{kind: column, ...}` / `{kind: control, ...}` pointing at something that doesn't exist is a hard 400 (`Dependency not found`). The literal keys are per-plugin — harvest them from a working spec.
- **Element background:** use element-level `style.backgroundColor` (same shape as a container `style`) — a plugin renders on its own white canvas otherwise, which looks wrong inside a dark theme. A bare top-level `background` key is stripped.
- **Discover available plugins with `GET /v2/plugins`** ("List custom plugins", paginated `pageSize`/`pageToken`; needs `Accept: application/json`). Each entry is `{ pluginId, name, description, url, devUrl, type }` — list them to pick the right `pluginId` instead of guessing. A **bogus `pluginId` is not validated at POST** (200, then renders as a broken "missing plugin"), so always source it from `/v2/plugins`. The endpoint returns id + name only — the per-plugin **`config` shape** still has to come from a workbook spec that uses the plugin (or the plugin's source). See `twells89/sigma-workbook-spec-findings` finding #27 + Plugin-ID catalog.
