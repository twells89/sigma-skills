# Charts

Chart elements: `line-chart`, `bar-chart`, `donut-chart`. This file is a **recipe book** for chart specs and the style choices that go with each kind. The OpenAPI is the source of truth for every field — chart schemas are inlined behind their `kind` discriminator, so fetch one by its kind:

```bash
# Swap `bar-chart` for any kind: line-chart, area-chart, combo-chart, scatter-chart, donut-chart, pie-chart
jq --arg k bar-chart 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
```

The field lists below are curated, not exhaustive — use the recipe above to discover the full shape of any field.

All three share the same skeleton: a `source`, a `columns` array, and axis/value pointers that reference column IDs. Formulas on a chart that sources another element must use the source's prefix (`[<SourceName>/col]`) — see `formulas.md`.

---

## Line chart (revenue over time)

```yaml
id: sales-over-time
kind: line-chart
name: Sales over time
source:
  kind: table
  elementId: sales-table
columns:
  - id: col-month
    name: Month
    formula: DateTrunc("month", [Master/Date])
    format:
      kind: datetime
      formatString: "%b %Y"
  - id: col-sales
    name: Sales
    formula: Sum([Master/Sales Amount])
    format:
      kind: number
      formatString: "$,.0f"
xAxis:
  columnId: col-month
yAxis:
  columnIds:
    - col-sales
```

- `xAxis` — single `{ columnId, sort?, format? }`
- `yAxis` — single `{ columnIds: [<colId>, ...], format? }`. On any cartesian chart, a `columnIds` entry may be an object `{ columnId, type }` (`type`: `bar` | `line` | `area` | `scatter`) to set that series' shape — most useful on `combo-chart`
- `xAxis.sort` shape: `{ by: <colId>, direction: ascending | descending }`
- Optional `format` on each axis configures title, labels, marks, and scale — it's inlined on `xAxis.format` / `yAxis.format`; inspect it via the kind recipe above rather than transcribing the whole object

## Bar chart (revenue by category)

Same axis shape as line-chart. Adds `stacking`.

```yaml
id: sales-by-region
kind: bar-chart
name: Sales by region
source:
  kind: table
  elementId: sales-table
columns:
  - id: col-region
    name: Region
    formula: "[Master/Store Region]"
  - id: col-sales
    name: Sales
    formula: Sum([Master/Sales Amount])
    format:
      kind: number
      formatString: "$,.0f"
xAxis:
  columnId: col-region
  sort:
    by: col-sales
    direction: descending
yAxis:
  columnIds:
    - col-sales
stacking: none
```

`stacking`: `none` | `stacked` | `normalized` (the percent-stacked variant — `"100"` is rejected by the API; live-verified 2026-06-11).

## Bar chart with custom category colors

`bar-chart` accepts an optional `color` channel with three variants:

```yaml
# Single fixed color
color:
  by: single
  value: "#3b82f6"

# One color per category (positional — see below)
color:
  by: category
  column: col-region
  scheme: ["#3b82f6", "#ef4444", "#10b981", "#f59e0b"]

# Continuous scale across a measure
color:
  by: scale
  column: col-sales
  scheme: ["#fef3c7", "#fbbf24", "#dc2626"]
  domain: { min: 0, max: 10000, mid: 5000 }   # `mid` is optional; its presence makes the gradient diverging, otherwise sequential
```

**Recipe — pin specific categories to specific colors:**

`scheme` is a **positional** array: Sigma assigns colors to categories in the order they appear on the axis, not by category name. To pin Electronics → blue, Apparel → red, Home → green, control the sort order alongside the color array:

```yaml
kind: bar-chart
name: Revenue by category
columns:
  - id: col-cat
    name: Category
    formula: "[Sales/Product Category]"
  - id: col-sales
    name: Revenue
    formula: Sum([Sales/Revenue])
    format:
      kind: number
      formatString: "$,.0f"
xAxis:
  columnId: col-cat
  sort:
    by: col-cat
    direction: ascending
yAxis:
  columnIds:
    - col-sales
color:
  by: category
  column: col-cat
  scheme: ["#3b82f6", "#ef4444", "#10b981"]
```

For category-by-name binding rather than position, use a derived column with an `If(...)` that emits the categories in a known order, then sort by that order.

## Donut

Uses `value` and `color` instead of `xAxis` / `yAxis`.

```yaml
id: sales-by-family
kind: donut-chart
name: Sales by product family
source:
  kind: table
  elementId: sales-table
columns:
  - id: col-family
    name: Family
    formula: "[Master/Product Family]"
  - id: col-sales
    name: Sales
    formula: Sum([Master/Sales Amount])
    format:
      kind: number
      formatString: "$,.0f"
value:
  id: col-sales
color:
  id: col-family
  sort:
    by: col-sales
    direction: descending
```

`holeValue` is optional. When set, it references one of the donut's columns by ID — that column's aggregated value drives the hole label/render — not a literal number. **It must be a different column than `value.id`** — a column can only sit on one channel at a time, and the API rejects the collision with a 400 (`Column 'X' is referenced from both 'value' and 'holeValue'`). For a center label that shows the same metric, add a second column with the same formula:

```yaml
holeValue:
  id: col-sales-hole    # distinct column, e.g. formula: Sum([Master/Sales Amount])
```

Related donut-only fields (all round-trip): `innerRadius` (hole size as a ratio of the outer radius, default 0.6) and `hole.value` styling (`fontWeight`, `color`, `visibility`) for the center label.

## Element-level filters (Top-N, etc.)

Charts take the same `filters` array as tables — the top-N example in `tables.md` applies to `bar-chart`, `line-chart`, and `donut-chart` without changes.

Top 10 regions by `Sales` on a bar chart:

```yaml
filters:
  - id: top-10
    columnId: col-sales
    kind: top-n
    rankingFunction: rank
    mode: top-n
    rowCount: 10
    includeNulls: when-no-value-is-selected
```

`rowCount` takes a number literal — it cannot be bound to a control (see `controls.md`, "Where Control Bindings Apply").

## Cartesian-only optional features

These apply to `bar-chart`, `line-chart`, `area-chart`, `scatter-chart`, and `combo-chart`. Use the kind recipe at the top of this file to read the full operator and styling enums for any of them.

### `refMarks` — reference lines and bands

```yaml
refMarks:
  - type: line
    axis: series              # axis = x-axis, series = primary y, series2 = secondary y
    value: { type: formula, formula: "Avg([Master/Sales])" }   # see value shape below
    line: { color: "#ef4444", width: 2 }
    label: { visibility: shown, text: "Threshold" }            # visibility REQUIRED
  - type: band
    axis: series
    value: { type: formula, formula: "800" }
    endValue: { type: formula, formula: "1200" }               # required for bands
```

> **`value` must be the wrapped object `{ type: formula, formula: "<expr>" }`** — verified live 2026-06-15. A bare number/string (`value: 1000`) and `{ type: static, value: 1000 }` are both rejected with the opaque `refMarks[0]: Invalid value: object`. A **constant** is expressed as a formula string, e.g. a 45% target line: `value: { type: formula, formula: "0.45" }`. `label.visibility` must be `shown` (omitting it, or `hidden`, also trips `Invalid value: object`).

### `trendlines` — regression overlays

```yaml
trendlines:
  - columnId: col-sales       # which series to fit
    model: linear             # linear | quadratic | polynomial | exponential | logarithmic | power
    line: { color: "#336699", width: 2 }
    label: { visibility: shown, text: "Sales trend" }
```

Trendlines are rejected when the chart has no `xAxis`, uses stacking on bar/area/combo, or has a `color` channel — discover those constraints by submitting and reading the error.

### `dataLabel` — value labels on marks

```yaml
dataLabel:
  labels: shown               # shown | hidden
  labelDisplay: all            # auto | minimum | maximum | min-max | all
  valueFormat: percent
  totals: { display: shown }
```

For `combo-chart`, optional `seriesDataLabel` is a map keyed by layer shape (`bar`, `line`, `area`, `scatter`) with per-shape overrides:

```yaml
seriesDataLabel:
  bar: { labelDisplay: maximum }
  line: { labelDisplay: all }
```

## Combo charts (mixed series + secondary axis)

A `combo-chart` mixes bar/line/area/scatter series on one plot. Set each series' shape with the `{ columnId, type }` form on `yAxis.columnIds`, and put series that need a different scale on the secondary axis `yAxis2`. **`yAxis2.columnIds` must be a subset of `yAxis.columnIds`** — list the column on both, with `yAxis2` marking which series render against the right axis (a `yAxis2` entry missing from `yAxis` is a 400: `'X' is not listed on yAxis.columnIds`):

```yaml
kind: combo-chart
xAxis:
  columnId: col-month
yAxis:                          # ALL series live here, each with its shape
  columnIds:
    - { columnId: col-revenue, type: bar }
    - { columnId: col-margin-pct, type: line }
yAxis2:                         # subset of yAxis.columnIds that renders on the right axis
  columnIds:
    - col-margin-pct
  format:
    visibility: shown           # set to `hidden` to hide the axis (no other fields on that branch)
```

Per-series styling is keyed by layer shape (`bar` / `line` / `area` / `scatter`):

- `seriesLineAreaStyle` — stroke/fill, curve, and area opacity for line/area layers
- `seriesPointStyle` — marker shape/size for points
- `seriesDataLabel` — per-shape data-label overrides (above)

Chart-wide fallbacks `barStyle`, `lineAreaStyle`, `pointStyle`, and `gap` also exist. Inspect the kind recipe for the full sub-field set of any of these.

### More cartesian options

Each of these is a top-level key on cartesian charts; one-liner here, full sub-fields via the kind recipe at the top of this file.

- `orientation: horizontal` on `bar-chart` — horizontal bars. Omit for the default vertical bars.
- `trellis: { column, row, share?, tileSize? }` — **styles a UI-configured trellis only.** `tileSize` and the `column`/`row` guide styling (`labels`, `border`, `title`) round-trip, but the facet *column binding* cannot be set via spec — `columnId`/`id` inside `column`/`row` are silently stripped (live-verified 2026-06-11). Configure the facets in the editor; the spec can then style them.
- `legend: { visibility, position, ... }` — legend placement and styling.
- `tooltip: { columnNames?, multiSeries?, valueFormat? }` — hover-tooltip content. Support is config-dependent (live-verified 2026-06-11): `columnNames` round-trips broadly; `multiSeries` round-trips on line charts but is silently stripped on bar-with-color; `valueFormat` is rejected or stripped in most configurations. Verify the readback after setting anything beyond `columnNames`.

(Trendlines and `refMarks` are covered above.)

## Scatter

A `scatter-chart` is **measure-vs-measure**, one point per dimension value — fundamentally different from `bar-chart`. The trap (verified the hard way): if you put an aggregate measure (`Sum(...)`) directly on `xAxis`/`yAxis` of a scatter sourced from a flat table, Sigma's scatter axis is a *grouping* axis, so the aggregate evaluates **per row** and every point collapses to one x. A spec like this **POSTs cleanly but renders wrong** — POST success does NOT prove a correct scatter.

The correct shape binds the scatter to a **grouping**: source a table element that groups by the point dimension and pre-computes the x/y/(size) aggregates, then point the scatter at that grouping with `source.groupingId` and reference the grouped columns with raw refs. (Verified against a UI-built scatter, 2026-06-15.)

```yaml
# 1) a (hidden) grouped source table: one row per point dimension
- id: scatter-src
  kind: table
  name: Rep Performance            # unique name — raw refs resolve as [Rep Performance/Col]
  source: { kind: table, elementId: master }
  columns:
    - { id: g-rep, name: Sales Rep, formula: "[Data/Sales Rep Name]" }
    - { id: g-mpct, name: Margin %, formula: "(Sum([Data/Revenue])-Sum([Data/Cost]))/Sum([Data/Revenue])" }
    - { id: g-rev,  name: Revenue,  formula: "Sum([Data/Revenue])" }
    - { id: g-qty,  name: Quantity, formula: "Sum([Data/Quantity])" }
  groupings:
    - { id: grp-rep, groupBy: [g-rep], calculations: [g-mpct, g-rev, g-qty] }
  visibleAsSource: false
# 2) the scatter binds to that grouping; columns are RAW refs to the grouped values
- id: scatter
  kind: scatter-chart
  name: Sales vs Margin by Sales Rep
  source: { kind: table, elementId: scatter-src, groupingId: grp-rep }
  columns:
    - { id: s-rep,  formula: "[Rep Performance/Sales Rep]" }
    - { id: s-mpct, formula: "[Rep Performance/Margin %]" }
    - { id: s-rev,  formula: "[Rep Performance/Revenue]" }
    - { id: s-qty,  formula: "[Rep Performance/Quantity]" }
  xAxis: { columnId: s-mpct }       # x = a measure (Margin %)
  yAxis: { columnIds: [s-rev] }     # y = a measure (Revenue)
  color: { by: category, column: s-rep }   # point identity — one mark per rep
  size:  { id: s-qty }              # optional bubble size; note `size.id`, NOT size.columnId
```

`color` always takes the `{ by: single|category|scale, column, ... }` form (see "Bar chart with custom category colors") — a bare `{ id }` / `{ columnId }` is rejected. **Validate a scatter by querying it for >1 distinct x**, not by POST status alone.

## Other chart kinds

Per the OpenAPI, these are all valid `kind` values; documented examples for the most common are above. The shape mirrors the `bar-chart`/`line-chart` pattern (`source`, `columns`, `xAxis`, `yAxis`). Inspect any of them with the kind recipe at the top of this file:

- `area-chart`, `combo-chart` — same shape as `bar-chart`/`line-chart`, just a different `kind` (and `combo-chart` adds the series configs above).
- `scatter-chart` — **NOT the same as bar-chart.** It is measure-vs-measure with the dimension as the point identity, and it must bind to a **grouping** or every point collapses to one x. See the Scatter section below.
- `pie-chart` — like `donut-chart` (`value` + `color`), but without the donut-only `hole` / `holeValue` / `innerRadius` / `trellis` keys.
- `pivot-table` — uses `values` instead of `yAxis`; useful for cross-tab analysis. See `tables.md`.

For element-level reference of `kind: "text"` (free-form Markdown blocks), see `content-elements.md`.
