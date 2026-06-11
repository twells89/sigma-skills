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
