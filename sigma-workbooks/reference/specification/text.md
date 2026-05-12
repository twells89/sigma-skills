# Text Elements

The `text` element renders a free-form Markdown block on a page — useful for dashboard titles, descriptions, section headers, callouts, or any prose that sits alongside charts and tables.

## Shape

```json
{
  "id": "text-header",
  "kind": "text",
  "body": "# Sales Overview\n\nA weekly view of revenue, with rankings of the regions driving the most growth.",
  "verticalAlign": "start",
  "overflow": "clip"
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"text"` |
| `body` | yes | Markdown string (subset — see below) |
| `verticalAlign` | no | `"start"` (top, default), `"middle"`, `"end"` (bottom) |
| `overflow` | no | `"clip"` (default) or `"scroll"` |

Note: `text` elements have no `name` or `source` field, unlike most other element kinds.

## Markdown Subset

The `body` field supports a deliberate subset of Markdown plus a few inline-HTML tags:

- Paragraphs and soft / hard line breaks
- Headings: `#`, `##`, `###`
- Bullet and ordered lists
- `**bold**`, `*italic*`, `~~strikethrough~~`
- `[links](https://example.com)`
- Inline HTML: `<u>`, `<sub>`, `<sup>`
- Inline color: `<span style="color: #hex">…</span>` and `<span style="background-color: #hex">…</span>`
- Embedded formulas in `{{double curly braces}}` with optional d3 formatting via pipe — same `{{ast | fmt}}` syntax used by element titles, e.g. `{{Count() | ,.0f}}`

UI-authored features outside this subset (paragraph alignment, p-large/p-small block styles, fontSize, fontFamily, list-item color) round-trip as their closest supported neighbor — they don't error, but they may render differently than the UI showed.

## Bold + Color

A common pattern is bold + color text. Markdown bold and inline `<span>` color are both supported, but Sigma normalizes the **ordering** on round-trip: a `**<span>...</span>**` that you submit reads back as `<span>**...**</span>`. The rendered output is the same; just don't be surprised by the diff.

```markdown
# **<span style="color: #8B0000">Deployments Dashboard</span>**

Filter by **<span style="color: #1E90FF">Created at</span>** to narrow the time window.
```

## Layout Placement

`text` elements participate in the page grid like any other element. Common idioms:

- A page-level title row above a `<GridContainer>`:

  ```xml
  <LayoutElement elementId="text-header" gridColumn="1 / 25" gridRow="1 / 4"/>
  <GridContainer elementId="header-row" type="grid" ...>
    ...
  </GridContainer>
  ```

- Inside a container, on its own row above the chart row (see `layout.md` > "Stacking children inside a container"):

  ```xml
  <GridContainer elementId="header-row" type="grid" gridColumn="1 / 25" gridRow="1 / 12" ...>
    <LayoutElement elementId="text-header"  gridColumn="1 / 25" gridRow="1 / 4"/>
    <LayoutElement elementId="kpi-1"        gridColumn="1 / 9"  gridRow="4 / 12"/>
    <LayoutElement elementId="kpi-2"        gridColumn="9 / 17" gridRow="4 / 12"/>
    <LayoutElement elementId="kpi-3"        gridColumn="17 / 25" gridRow="4 / 12"/>
  </GridContainer>
  ```

- Side-by-side with a control on the same row:

  ```xml
  <GridContainer elementId="header-row" type="grid" ...>
    <LayoutElement elementId="text-header"     gridColumn="1 / 18"  gridRow="1 / 4"/>
    <LayoutElement elementId="ctrl-date-range" gridColumn="18 / 25" gridRow="1 / 4"/>
    ...
  </GridContainer>
  ```
