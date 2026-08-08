# Layout

Recipe book for `document.layout` XML. Layout is required by this skill whenever
`document.elements` is non-empty because it is the sole source of truth for
page, overlay, panel, container, repeated-container, and tab organization.

> ⚠️ **`layout` is a sibling of `pages` — NOT a property nested under a page.** Its value is one XML string containing one `<Page id="…">` block per page (the `id` ties each block to a `pages[].id`). Putting `layout:` *inside* a `pages[]` entry is **silently ignored**: POST/PUT still returns `success: true`, but Sigma discards it and auto-arranges every page into a single stacked column. Verified 2026-06-16 — when correctly placed alongside `pages` it applies on both `POST` (create) and `PUT`; when nested under a page it's dropped on both. The failure is invisible until you render the page or GET the spec back: a readback that shows self-closing `<Container .../>` tags with the children hoisted out as stacked siblings (and every element spanning `1 / 13`) means your authored layout was discarded. **Where `pages`/`layout` live has moved (2026-08-04 correction):** live create/verify now nests both inside a `document` wrapper (`document: {schemaVersion, kind, pages, layout}`), with only `name`/`folderId` staying outside it — not flat top-level siblings of `name`/`folderId` as this note previously said. See `reference/workflows/validate.md` §1 for the full story. See `schema.md` for the top-level object shape.

Container *elements* (the `kind: "container"` JSON placeholders that pair with `<Container>` in this XML) are covered in **Container elements** below.

## Layout policy

Always write explicit layout for authored workbooks. In particular:

- The page has **mixed element kinds** (charts + KPIs, controls + charts, text/image/divider polish). Auto-arrange treats them as a vertical stack and gives every element the same height — KPIs end up the size of charts, dividers get huge gutters around them.
- The user asked for specific positioning ("logo on left, title on right", "KPIs across the top", side-by-side charts).
- There's a `kind: "container"` element on the page. Containers without a matching `<Container>` are functionally no-ops.
- The workbook has more than ~4 elements on a page. Auto-arrange becomes a long scroll.

Although the OpenAPI marks the string optional, the current API rejects a flat
element that has no placement. Do not rely on auto-arrange, and do not derive
membership from the order of `document.elements`.

## Two-tag grammar

Live GET specs and `/verify` use `<Element>` for leaves and `<Container>` for
nested grids (confirmed 2026-08-08). Emit those exact names.
`<LayoutElement>` is not a synonym on the wire—it causes HTTP 400.
`<GridContainer>` is likewise a legacy captured-artifact alias, not authoring
syntax. Local parsers may read those aliases only to migrate old snapshots.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="<pageId>">
  <Container elementId="<containerId>" type="grid" gridColumn="1 / 25" gridRow="1 / 4"
                 gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <Element elementId="<childId>" gridColumn="1 / 13" gridRow="1 / 4"/>
  </Container>
  <Element elementId="<elementId>" gridColumn="1 / 25" gridRow="4 / 16"/>
</Page>
```

Each `<Page id>` matches a `document.pages[].id`, `document.overlays[].id`, or
`document.panels[].id`. Each `elementId` matches a flat
`document.elements[].id`; placing it beneath a block is what assigns it there.
`gridColumn` / `gridRow` use CSS grid line syntax and pages use 24 columns.

## `<Container>` vs `<Element>`

- `<Element elementId="X" .../>` — **leaf**. Positions a single element; no children.
- `<Container elementId="X" ...>...</Container>` — **container**. Wraps child `<Element>`s in its own inner grid.

Use `<Container>` for any tag with nested children — a `<Element>` only renders as a leaf.

## Container elements

A `kind: "container"` entry in `document.elements[]` is a grouping placeholder
— a labeled section, branded background, or KPI row. It renders only through a
matching `<Container>`. Containers expose `style` (background color, border,
corner radius, padding), top-level `backgroundImage`, and child spacing:
`elementGap` (`shown` / `hidden`) plus `spacing`
(`small` / `medium` / `large`). Pull the current schema before using additional
fields.

```bash
jq --arg k container 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
```

```yaml
- id: header
  kind: container
  style: { backgroundColor: "#0B3D91" }
```

- **Element on a background image:** to place an element *on top of* a container's `backgroundImage`, make it a **child** of that container in the layout XML — the background spans the container and the child sits on top.
- **Background shape:** container/chart backgrounds use their element schema's
  top-level `backgroundImage: {url: ...}` shape, sibling to `style`. Page
  backgrounds use `backgroundImage: {source: {kind: url, url: ...}, style: ...}`.
- **Spacing:** `style.padding` accepts only `none` or omission on a container;
  values such as `small` are rejected. Use `elementGap`/`spacing` for
  child-to-child rhythm; do not fake spacing with empty text elements.
- **When to skip:** with no shared background or logical grouping, position elements directly with `<Element>`. A container around a single element is usually overkill.

## `repeated-container` — cards that repeat once per source row

A **repeated container** is a first-class element kind: one card (or list row)
rendered once per row of a source. The element and its `<Container>` layout are
spec-authorable; use an unbound/plain child when probing the rest of the
contract. Dynamic row binding currently has the API regression documented
below and must stay gated.

```yaml
- id: rc
  kind: repeated-container
  source: { kind: table, elementId: bt-stars }   # or warehouse-table / data-model / sql / …
  arrangement: list          # list | grid   (default grid)
  cardSize: small            # x-small | small | medium | large | x-large
  cardStyle:
    backgroundColor: "#EEF2F7"
    borderRadius: round      # square | round | pill
  noDataText: No rows yet
```

Required: `id`, `kind`, `source`. `source` takes the usual union — `table` (another element, via `elementId`), `warehouse-table`, `data-model`, `sql`, `join`, `union`, `csv-table`, `metric-view`, `semantic-view`, `transpose`. Optional: `arrangement`, `cardSize`, `cardGap` / `cardSpacing`, `elementGap` / `elementSpacing`, `scroll` (`vertical` | `horizontal` | `none`), `filters`, `sort`, `noDataText`, `style`, `cardStyle`.

### Binding children to the row — the derived name

The card's children are ordinary `text` / `image` entries in
`document.elements[]`, placed inside the container in layout. They reference the
current row through a **derived** name:

```
{{[<source element's `name`> repeated container/<Column name>]}}
```

So a source element named `Star Events` yields
`{{[Star Events repeated container/Repo Name]}}`. Columns are referenced by
their `name`, not their `id`.

> **Known API regression (live 2026-08-08):** that exact, correctly derived
> target is present in existing GET readbacks, proving it is a real
> representation. However, both `/v2/workbooks/spec/verify` and
> `POST /v2/workbooks/spec` currently reject a replay with
> `Dependency not found: 'Star Events repeated container/Repo Name'`. Do not
> mark bound repeated-container authoring green until both paths accept it.
> `scripts/probe-release-contract.rb` keeps a plain child in its main
> create/readback and runs this binding as a separate strict expected-regression
> check.
>
> The virtual target is synthesized and therefore is not declared in
> `document.elements[]`; local dangling-reference checks must not reject it.
> Using the repeated-container element id, such as `[rc/<column>]`, is still
> incorrect.

### Layout XML

Use a plain `<Container>`; there is **no** `<RepeatedContainer>` tag. Children go inside it as `<Element>`s:

```xml
<Container elementId="rc" type="grid" gridColumn="1 / 24" gridRow="36 / 54"
               gridTemplateColumns="repeat(12, 1fr)" gridTemplateRows="auto">
  <Element elementId="card-title" gridColumn="1 / 3"  gridRow="1 / 3"/>
  <Element elementId="card-sub"   gridColumn="3 / 13" gridRow="1 / 3"/>
</Container>
```

- **Use `<Container>` for repeated containers too.** There is no
  `<RepeatedContainer>` node. Legacy `<GridContainer>` / `<LayoutElement>`
  aliases are read-only compatibility syntax; authored layout uses
  `<Container>` / `<Element>`.
- Sigma normalizes the card's inner grid to **12** columns (`gridTemplateColumns="repeat(12, 1fr)"`) and rewrites `type` to `"grid"` on readback, whatever you send.
- `arrangement: grid` is the default and is **dropped** from the readback; `arrangement: list` persists. Don't read its absence as a lost field.

### Caveat on older captured specs

A spec captured **before** this element kind existed will contain the styled child elements and their `{{[… repeated container/…]}}` bindings but **no** `repeated-container` element — so replaying it gives you the cards' contents without the repeat. That's a stale fixture, not an API limitation: re-capture from the current API, or add the `repeated-container` element by hand.

## Tabbed containers

A `kind: "tabbed-container"` element packs several views into one region — switchable tabs instead of a long vertical scroll or extra pages. Unlike the `kind: "container"` placeholder above, it's a real element with its own JSON shape, not a bare grouping wrapper.

**It IS spec-authorable** — verified working end-to-end via spec `POST`/`PUT`, not the UI-only construct a stale note elsewhere may claim.

**JSON element** (`document.elements[]`) — `tabs[]` entries are labels only:

```yaml
- id: tc
  kind: tabbed-container
  tabs:
    - name: Overview
    - name: Detail
  tabBar:
    alignment: start
```

The actual content for each tab is ordinary flat elements; layout places them.

**Layout XML** — a `<TabbedContainer>` wraps one `<Tab>` per label. `<Tab>` children map to `tabs[]` **by position** (1st `<Tab>` = 1st label; `<Tab>` carries no `name` attribute):

```xml
<TabbedContainer elementId="tc" type="tabbed-container" gridColumn="1 / 25" gridRow="7 / 60">
  <Tab gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <Element elementId="overview-chart" gridColumn="1 / 25" gridRow="1 / 12"/>
  </Tab>
  <Tab gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <Element elementId="detail-table" gridColumn="1 / 25" gridRow="1 / 12"/>
  </Tab>
</TabbedContainer>
```

Two `<Tab>`s, two elements (`overview-chart`, `detail-table`) each declared once
in `document.elements[]`; `<Tab>` order ties them to the labels above.

- **Gotcha (verified):** inside a `<Tab>`, use **bare `<Element>` children only** — never nest a `<Container>` inside a `<Tab>`. A `<Tab>` is already a mini-grid (its own `gridTemplateColumns` / `gridTemplateRows`), so elements position directly in it; a nested `<Container>` scrambles tab render order.
- **When to use it:** several views that are alternates of each other (a summary + a detail table, one view per region/segment) rather than sequential reading — pack them into one region instead of a long scroll or extra pages.
- **Building it:** hand-authoring the position-mapped `<Tab>` block is error-prone. Use `Composition.tabbed_container(id:, tabs:, grid_column:, grid_row:, tab_bar_alignment: 'start')` in `scripts/lib/composition.rb` — `tabs:` is `[{name:, inner:}]`, where `inner` is the tab's bare-`<Element>` XML (built with `Composition.band`/`Composition.le` or by hand). It returns `{element:, layout:}`, ready to add to `document.elements[]` and `document.layout`.

## `gridTemplateRows`: always `"auto"`

Row tracks are always `"auto"` — write `gridTemplateRows="auto"`. Height comes from the children, not from the row track.

### Stacking children inside a container

Because row tracks collapse to `"auto"`, height comes from children, not from the container's `gridTemplateRows`. Two patterns work:

**Side-by-side** — children share the container's row range, differ by `gridColumn`:

```xml
<Container elementId="kpi-row" type="grid"
               gridColumn="1 / 25" gridRow="1 / 4"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <Element elementId="kpi-1" gridColumn="1 / 9"  gridRow="1 / 4"/>
  <Element elementId="kpi-2" gridColumn="9 / 17" gridRow="1 / 4"/>
  <Element elementId="kpi-3" gridColumn="17 / 25" gridRow="1 / 4"/>
</Container>
```

**Stacked rows** — children have disjoint `gridRow` spans within the container's row range:

```xml
<Container elementId="header-row" type="grid"
               gridColumn="1 / 25" gridRow="1 / 12"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <Element elementId="title"  gridColumn="1 / 25" gridRow="1 / 4"/>
  <Element elementId="kpi-1"  gridColumn="1 / 9"  gridRow="4 / 12"/>
  <Element elementId="kpi-2"  gridColumn="9 / 17" gridRow="4 / 12"/>
  <Element elementId="kpi-3"  gridColumn="17 / 25" gridRow="4 / 12"/>
</Container>
```

Use stacked rows when you want a section header above a row of charts inside the same container, instead of moving those elements out to the page level.

## Element height heuristics — give tables room to breathe

A table element's `gridRow` span controls how many data rows are visible before it scrolls. The recurring mistake is **under-sizing tables** — a detail/raw-row table given a 5–8 row span shows only ~2 data rows, which defeats the point of a "see the underlying data" table. Size by role:

- **Detail / raw-row tables** (the bottom-of-page "drill into the data" table): give a **tall** span — **~14–20 grid rows** (e.g. `gridRow="32 / 50"`). The user should see 6–10+ rows without scrolling. When a detail table is the last element on the page, err on the side of *too tall* — trailing whitespace below it is cheaper than a cramped 2-row table.
- **Summary / aggregated tables** (a handful of grouped rows): size to roughly the row count + header, ~6–10 grid rows.
- **KPIs**: short — ~5–6 rows; they're a single number.
- **Charts**: ~8–12 rows so axes and labels aren't crushed.

Heights are relative grid units (tracks are `auto`), so these are rules of thumb, not pixels — but the asymmetry holds: **tables are the element most often made too short.** If you're unsure, render the page (PNG export) and count visible rows.

## Page backgrounds and width

Pages contain metadata only. In addition to `id`, `name`, `type`, and
`visibility`, the live schema exposes `pageWidth`, `backgroundColor`, and
`backgroundImage`:

- **`visibility`** — set to `hidden` to hide the page from end users. Omit for a visible page.
- **`backgroundImage`** — page images wrap the source as
  `{source: {kind: url, url}, style: {...}}`; this differs from the current
  container/chart `{url: ...}` shape.

```yaml
document:
  pages:
    - id: overview
      name: Overview
      visibility: hidden
      backgroundColor: "#F8FAFC"
      backgroundImage:
        source:
          kind: url
          url: https://cdn.example.com/bg.jpg
        style:
          fit: cover
          tiling: none
```

## Layout `elementId` references

Each layout `elementId` must match a flat `document.elements[].id` exactly.
An element is assigned to a page/container solely by where that reference
appears. Unplaced elements and references to undeclared IDs are validation
errors.

## Panels, headers, sidebars, and navigation

`document.panels` stores panel metadata; panel content is placed by a
`<Page id="<panel-id>">` layout block just like overlay content. Preserve panel
metadata from readback and consult the live `panels` schema for the current
header/sidebar variants.

Workbook chrome is configured separately under `document.settings.navigation`.
It controls built-in page headers, page tabs, and sidebar navigation; the
`kind: navigation` canvas element is an independent in-layout menu. Use
settings navigation for workbook-wide chrome and a navigation element when the
menu must occupy a grid region or provide curated destinations.

To study real grid-container idioms, fetch an existing multi-page workbook's spec (`GET /v2/workbooks/{id}/spec`, see SKILL.md Steps 1–2). The OpenAPI doesn't model the `layout` XML string, so a live spec is the way to see production layout.
