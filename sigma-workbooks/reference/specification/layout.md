# Layout

The optional top-level `layout` field is an XML string that positions elements on each page using a CSS-grid-like model. Omit `layout` to get Sigma's default auto-layout. Provide it for precise multi-element dashboard composition.

## Shape

```xml
<?xml version="1.0" encoding="utf-8"?>
<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="<pageId>">
  <GridContainer elementId="<containerId>" type="grid" gridColumn="1 / 25" gridRow="1 / 4"
                 gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <LayoutElement elementId="<childId>" gridColumn="1 / 13" gridRow="1 / 4"/>
  </GridContainer>
  <LayoutElement elementId="<elementId>" gridColumn="1 / 25" gridRow="4 / 16"/>
</Page>
```

Key points:
- Each `<Page id>` must match a `pages[].id`.
- Each `<LayoutElement elementId>` or `<GridContainer elementId>` must match an element on that page.
- `gridColumn` / `gridRow`: standard CSS grid line syntax (`start / end`). The default grid is 24 columns wide.
- Multiple `<Page>` blocks at the top level, one per workbook page.

## `<GridContainer>` vs `<LayoutElement>`

> ⚠️ **Silent failure:** use `<GridContainer>` for any tag that has child layout elements nested inside it. `<LayoutElement type="grid">` with children **parses successfully as a leaf node and the children are silently dropped** — no error is returned, the elements just don't appear on the page. Every container that wraps other elements must be a `<GridContainer>`.

Put another way:
- `<LayoutElement elementId="X" .../>` — **leaf**. Positions a single element. No children.
- `<GridContainer elementId="X" ...>...</GridContainer>` — **container**. Wraps child `<LayoutElement>`s inside its own inner grid.

## `gridTemplateRows`: keep it `"auto"`

> **Silent normalization:** `gridTemplateRows` is accepted on `PUT` with any value but is normalized back to `"auto"` on `GET`. Writing `gridTemplateRows="1fr"` (or `"100px"`, `"repeat(3, 1fr)"`, etc.) on a `<Page>` or `<GridContainer>` doesn't error, but the server drops your value and treats the row track as `"auto"`. Always write `"auto"` explicitly — it's the only value that survives the round-trip.

### The children-span-outer-row-range idiom

Because row tracks collapse to `"auto"`, height comes from children, not from the container's `gridTemplateRows`. The working pattern (used throughout `example-full.yaml` and the public App Distribution template): have each child `<LayoutElement>` span the **full outer row range** of its `<GridContainer>`, and let the children stack themselves via their own `gridColumn` placement.

```xml
<GridContainer elementId="header-row" type="grid"
               gridColumn="1 / 25" gridRow="1 / 4"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="kpi-1" gridColumn="1 / 9"  gridRow="1 / 4"/>
  <LayoutElement elementId="kpi-2" gridColumn="9 / 17" gridRow="1 / 4"/>
  <LayoutElement elementId="kpi-3" gridColumn="17 / 25" gridRow="1 / 4"/>
</GridContainer>
```

Note: outer `gridRow="1 / 4"` matches the `gridRow="1 / 4"` on every child — they all span the container's full row range. Don't try to slice rows with children using `1 / 2`, `2 / 3`, etc.; rely on columns for placement and let `"auto"` size the height from content.

## Container Elements

A `kind: "container"` element on a page declares a layout target — the matching `<GridContainer elementId="..." ...>` in the layout XML is what positions children inside it.

```json
{ "id": "header-row", "kind": "container" }
```

A container can also carry inline `style` for visual treatment (background, border):

```json
{
  "id": "header-row",
  "kind": "container",
  "style": {
    "backgroundColor": "var(--colors-borderNeutral)",
    "borderRadius": "round",
    "borderColor": "#E5E7EB",
    "borderWidth": 0
  }
}
```

`style` accepts CSS color literals, theme variables (`var(--colors-*)`), and the same `borderRadius` / `borderColor` / `borderWidth` shape used on `table` elements (see `tables.md`).

## Text and Divider Elements

Two simple non-data elements that live in `pages[].elements`:

### Text

Free-form rich text block.

```json
{
  "id": "section-title",
  "kind": "text",
  "body": "## Workforce Operations Overview\n\nKPIs for the current period.",
  "verticalAlign": "top"
}
```

- `body` — Markdown-flavored content.
- `verticalAlign` — `"top"` | `"middle"` | `"bottom"`.

### Divider

Visual separator.

```json
{
  "id": "div-1",
  "kind": "divider",
  "align": "center",
  "style": { "color": "#E0E0E0", "thickness": 1 }
}
```

- `align` — `"left"` | `"center"` | `"right"`.
- `style` — line color and thickness.

## After CREATE: IDs Reassign

The server remaps external IDs to internal ones on `POST /v2/workbooks/spec`. **Before any follow-up `PUT` that touches `layout`**, GET the current spec and use the IDs from the readback. `elementId` references in the XML must match exactly (case-sensitive) — a mismatch silently drops the element from the page.

See `example-full.yaml` for a real multi-page layout with grid containers.
