# Styling — designed-looking dashboards from spec alone

Recipe library for moving a workbook from "default auto-arrange" to "looks designed." Every pattern below is built from fields that already exist in the workbook spec — no external CSS, no theme JSON, no UI editing required.

The recipes were extracted from a 2026-05-29 design experiment that built 6 versions of the same dashboard (default → polished) and compared screenshots via the `/v2/workbooks/{id}/export` PNG endpoint. The findings caught two silent-failure bugs (see `charts.md` donut section) and 4 undocumented container `style` knobs (see `containers.md`).

---

## What "designed" looks like via spec

You can ship a dashboard that looks legitimately professional from the spec by stacking five patterns:

1. **Branded hero header strip** — full-width container with a dark background and a colored Markdown title sitting inside.
2. **KPI cards** — each KPI inside its own white container with rounded corners + a thin border + a colored Markdown category label.
3. **Section headers** — Markdown `##` text elements between groups of elements.
4. **Categorical chart colors** — `color.scheme` on bar/line/area/combo (not donut/pie — those use the workbook theme).
5. **Number formatting on everything** — `$,.2s` for KPI values (yields `$103k`), `$,.0f` for table cells, never raw numbers.

If you do all five, the dashboard reads as designed. Skip any one and it reads as "the LLM didn't try."

---

## Vetted color palette

Use this Tailwind-derived modern palette unless the customer has specified branding:

```
Primary blue:   #3B82F6
Green:          #10B981
Amber:          #F59E0B
Red:            #EF4444
Purple:         #8B5CF6
Cyan:           #06B6D4

Dark surface:   #0F172A   (slate-900 — hero header bg)
Muted text:     #94A3B8   (slate-400 — subtitle text on dark bg)
Card border:    #E2E8F0   (slate-200 — subtle 1px on white cards)
Card bg:        #FFFFFF
Page bg:        (Sigma default — don't override)
```

Apply consistently: the same blue (`#3B82F6`) for the "primary metric" KPI label and the primary bar chart; green for "growth" metrics; amber/red for "warning" / "negative" only.

---

## Recipe 1 — Hero header strip

A dark, full-width strip at the top with a bold white title and a muted subtitle.

```yaml
elements:
  - id: hero
    kind: container
    style:
      backgroundColor: "#0F172A"
      borderRadius: round
  - id: title
    kind: text
    body: |
      # <span style="color: #FFFFFF">Orders Overview</span>
      <span style="color: #94A3B8">Net revenue, order mix, and channel performance — last full period</span>
```

```xml
<GridContainer elementId="hero" type="grid"
               gridColumn="1 / 25" gridRow="1 / 5"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="title" gridColumn="1 / 25" gridRow="1 / 5"/>
</GridContainer>
```

Notes:
- Title color via Markdown `<span style="color: #...">`. Sigma's `text` element supports inline span colors but no `fontSize` / `fontFamily` overrides.
- For an edge-to-edge image background instead of a solid color, swap `backgroundColor` for `backgroundImage` and add `padding: none` (`backgroundColor` + `padding: none` is also valid — it just blocks `border*`).

---

## Recipe 2 — KPI card row

Three (or four) KPIs in styled white cards, each with a colored category label above the value.

```yaml
elements:
  - id: kpi-net-box
    kind: container
    style:
      backgroundColor: "#FFFFFF"
      borderRadius: round
      borderColor: "#E2E8F0"
      borderWidth: 1
  - id: kpi-net-label
    kind: text
    body: |
      <span style="color: #3B82F6">**NET REVENUE**</span>
  - id: kpi-net
    kind: kpi-chart
    # omit `name:` — the colored label above stands in for the title
    source:
      elementId: master
      kind: table
    columns:
      - id: kpi-nr-val
        formula: Sum([Master/Net Revenue])
        format:
          kind: number
          formatString: "$,.2s"    # renders as "$103k"
    value:
      id: kpi-nr-val
```

```xml
<GridContainer elementId="kpi-net-box" type="grid"
               gridColumn="1 / 9" gridRow="5 / 12"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="kpi-net-label" gridColumn="1 / 25" gridRow="1 / 3"/>
  <LayoutElement elementId="kpi-net"       gridColumn="1 / 25" gridRow="3 / 8"/>
</GridContainer>
```

Repeat the container + label + KPI triple for each metric, switching the label color (green for growth, purple for averages, amber for trailing-indicator metrics). Three across at columns `1/9`, `9/17`, `17/25` is the standard layout.

> **Omit `name:` on each KPI** if you're using a colored Markdown label above it. The element's `name` always renders as its own title; with the label, you get a duplicate. There's no `showTitle: false` field.

---

## Recipe 3 — Section header

A heading row between groups of elements. Tighter than a hero, looser than a chart.

```yaml
- id: section-charts
  kind: text
  body: |
    ## Revenue breakdown
```

```xml
<LayoutElement elementId="section-charts" gridColumn="1 / 25" gridRow="12 / 14"/>
```

Use these between (a) KPI row and chart row, (b) chart row and detail table, (c) any two thematically distinct chunks. Two per dashboard is usually enough — more than that and the page reads as fragmented.

---

## Recipe 4 — Divider before the detail table

Between the high-level charts and the "drill down to raw rows" table, a horizontal rule sets the visual separation cleanly.

```yaml
- id: divider-1
  kind: divider
```

```xml
<LayoutElement elementId="divider-1" gridColumn="1 / 25" gridRow="26 / 27"/>
```

A 1-row span. The `divider` element is a first-class kind, not a hack — see `others.md`.

---

## Recipe 5 — Categorical chart colors

For bar / line / area / combo charts, pin slice colors to the vetted palette:

```yaml
- id: chart-by-status
  kind: bar-chart
  source:
    elementId: master
    kind: table
  columns:
    - id: bs-status
      formula: '[Master/Order Status]'
    - id: bs-rev
      formula: Sum([Master/Net Revenue])
      format:
        kind: number
        formatString: "$,.0f"
  xAxis:
    columnId: bs-status
    sort:
      by: bs-rev
      direction: descending
  yAxis:
    columnIds: [bs-rev]
  color:
    by: category
    column: bs-status
    scheme: ["#3B82F6", "#F59E0B", "#EF4444"]
```

`scheme` is positional — pin colors to category sort order, not to category names. Sort by the value descending to get "biggest bar = primary blue, smaller = warning amber/red."

> **Donut and pie do NOT accept `scheme`.** The field is silently stripped on those chart kinds; they always use Sigma's default palette. To customize donut/pie slice colors, set the workbook theme in the UI. See `charts.md` donut section for the verified gotchas.

---

## Recipe 6 — Number formatting

Every value gets a `format` block. The four most useful:

| Format string | Output |
|---|---|
| `"$,.2s"` | `$103k` — compact, perfect for KPI tiles |
| `"$,.0f"` | `$103,247` — full precision, table cells |
| `",.0f"` | `1,234` — count with thousands separator |
| `",.2%"` | `12.34%` — percentage |

```yaml
columns:
  - id: kpi-val
    formula: Sum([Master/Revenue])
    format:
      kind: number
      formatString: "$,.2s"
```

See `formatting.md` for the full d3-format / strftime reference.

---

## Putting it together — page composition pattern

The 24-column grid layout that pulls all six recipes into one dashboard:

```
Row 1-5      Hero header (full width)
Row 5-12     KPI tile 1 | KPI tile 2 | KPI tile 3   (each 8 cols wide)
Row 12-14    Section header — "Revenue breakdown"
Row 14-26    Donut / pie  | Bar chart                (each 12 cols wide)
Row 26-27    Divider
Row 27-29    Section header — "Order details"
Row 29-37    Detail table (full width)
```

XML:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="page-1">

  <GridContainer elementId="hero" type="grid"
                 gridColumn="1 / 25" gridRow="1 / 5"
                 gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <LayoutElement elementId="title" gridColumn="1 / 25" gridRow="1 / 5"/>
  </GridContainer>

  <GridContainer elementId="kpi-net-box" type="grid"
                 gridColumn="1 / 9" gridRow="5 / 12"
                 gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <LayoutElement elementId="kpi-net-label" gridColumn="1 / 25" gridRow="1 / 3"/>
    <LayoutElement elementId="kpi-net"       gridColumn="1 / 25" gridRow="3 / 8"/>
  </GridContainer>
  <!-- two more KPI containers at 9/17 and 17/25 -->

  <LayoutElement elementId="section-charts"   gridColumn="1 / 25"  gridRow="12 / 14"/>
  <LayoutElement elementId="chart-by-channel" gridColumn="1 / 13"  gridRow="14 / 26"/>
  <LayoutElement elementId="chart-by-status"  gridColumn="13 / 25" gridRow="14 / 26"/>

  <LayoutElement elementId="divider-1"      gridColumn="1 / 25" gridRow="26 / 27"/>
  <LayoutElement elementId="section-detail" gridColumn="1 / 25" gridRow="27 / 29"/>
  <LayoutElement elementId="master"         gridColumn="1 / 25" gridRow="29 / 37"/>
</Page>
```

---

## Things that are NOT designable via spec (as of 2026-05-29)

Don't waste a round-trip trying to set these — the spec API silently drops them.

- **Chart tooltip customization** (spec-findings #10)
- **Trellis / small-multiples layout** (spec-findings #11)
- **Donut / pie slice colors** (spec-findings #22)
- **KPI title color or "hide title" toggle** — `name` always renders as a black title
- **Element title font size / font family** — the `name` field has no `style` sibling
- **Workbook-level palette / theme** via spec (open question in spec-findings)
- **Chart `tooltip` / `trellis*` fields** (UI-only)

If a customer needs slice color branding on donut/pie, set the workbook theme in the UI after the spec is posted.