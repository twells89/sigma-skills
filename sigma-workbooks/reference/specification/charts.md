# Charts

Chart elements: `line-chart`, `bar-chart`, `donut-chart`. This file is a **recipe book** for chart specs and the style choices that go with each kind. For full schemas, fetch the OpenAPI:

```bash
jq '.components.schemas.LineChart, .components.schemas.BarChart, .components.schemas.DonutChart' /tmp/sigma-api.json
```

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
- `yAxis` — single `{ columnIds: [<colId>, ...], format? }`; for `combo-chart`, entries may be `{ columnId, type }` for per-series shape
- `xAxis.sort` shape: `{ by: <colId>, direction: ascending | descending }`
- Optional `format` on each axis configures title, labels, marks, and scale — fetch `CartesianAxisFormat` from the OpenAPI for the full shape

**Verified axis `format` shapes** (UI-built workbook readback 2026-05-22):

```yaml
xAxis:
  columnId: <id>
  format:
    marks: tick                   # toggle tick marks
    scale:
      type: time                  # time (datetime axis) | linear | log
      zero: false

yAxis:
  columnIds: [<id>]
  format:
    scale:
      type: log                   # linear (default) | log
      domain: { min: 500000, max: 1000000 }   # explicit bounds
      zero: true                  # include zero baseline
```

**Per-column number format lives on the column entry, NOT on the axis.** Verified shape:

```yaml
columns:
  - id: <id>
    formula: '[Metrics/Total Revenue]'
    format:
      kind: number                # number | datetime | percent
      formatString: "$,.2f"       # d3-format syntax
      currencySymbol: "$"
```

So configuring "Total Revenue should display as `$1,234,567.00`" is done on the column, not via `yAxis.format`. The axis `format` only controls scale type, domain, ticks, and zero.

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

`stacking`: `none` | `stacked` | `normalized` (the percent-stacked / scaled-to-100% variant). The OpenAPI `BarChart.stacking` enum is exactly `none|stacked|normalized`; `"100"` is **rejected** ("Invalid value: string").

`orientation`: **horizontal bars** are set with `orientation: horizontal` on the element. The field accepts **only `"horizontal"`** — a **vertical** bar chart (the default) is expressed by **omitting** the field; sending `orientation: vertical` is rejected with `invalid_request`. The `xAxis`(category)/`yAxis`(value) binding is identical in both orientations — the flag only flips rendering (in horizontal, the category renders on the vertical axis and the value bar extends horizontally). Note Sigma may *default* a single-series bar to horizontal on GET, so set it explicitly when you need a specific orientation. (Verified via `/v2/workbooks/{id}/spec` PUT round-trip 2026-06-02.)

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
  domain: [0, 5000, 10000]
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

`holeValue` is optional. When set, it references one of the donut's columns by ID — that column's aggregated value drives the hole label/render — not a literal number.

> ⚠️ **`holeValue.id` MUST be a different column from `value.id`.** If they match, the API returns 200 OK but the entire donut element is dropped from the spec on readback and the chart renders as a tiny gray ring with no slices or legend. Add a second column with its own aggregation (typically a count next to a sum) and point `holeValue.id` at that. The Sigma UI implicitly enforces this rule — it always inserts a second column when the user toggles "show value in hole."

```yaml
columns:
  - id: col-family
    formula: "[Master/Product Family]"
  - id: col-sales
    formula: Sum([Master/Sales Amount])
  - id: col-orders                              # extra column for the hole
    formula: CountDistinct([Master/Order Id])
value:
  id: col-sales
holeValue:
  id: col-orders                                # MUST differ from value.id
```

> **Slice colors are NOT customizable via spec on donut/pie.** The donut/pie `color` object only accepts `{id, sort}` — no `scheme`. POSTing `color.scheme: [hex, ...]` returns 200 OK but the scheme is silently stripped on GET and the chart renders with Sigma's default palette. `scheme` is **bar-chart-only**. If you need branded slice colors, set the workbook-level theme in the UI (not yet exposed in the spec API as of 2026-05-29).

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

These apply to `bar-chart`, `line-chart`, `area-chart`, `scatter-chart`, and `combo-chart`. Fetch the full schemas for the operator and styling enums:

```bash
jq '.components.schemas.ReferenceMark, .components.schemas.Trendline, .components.schemas.DataLabel' /tmp/sigma-api.json
```

### `refMarks` — reference lines and bands

> **Verified 2026-05-24 against sigma-skill-recon test #1.** `value` is a **wrapped object**, NOT a bare number. POST with `value: 1000` returns HTTP 400 `Invalid value: object`. Use `{type: constant, value: <n>}` or `{type: formula, formula: <expr>}`. `axis: "series"` is the measure (Y) axis; `axis: "series2"` is combo-chart's secondary axis; `axis: "axis"` is the X axis.

```yaml
refMarks:
  - type: line
    axis: series              # axis | series | series2
    value:                    # wrapped object — bare number rejected
      type: constant
      value: 1000
    label:
      visibility: shown
      text: Threshold
  - type: line
    axis: series
    value:
      type: formula
      formula: Avg([Sales])
    label: { visibility: shown }
  - type: band                # band: shape unverified — wait for a UI-built readback
    axis: series
    value: { type: constant, value: 800 }
    endValue: { type: constant, value: 1200 }
```

`value.type: "column"` (with `columnId`) is also rejected — wrap the column ref in a formula instead. `line: { color, width }` may be accepted on POST but is not present on UI-built readbacks; treat as unverified.

### `trendlines` — regression overlays

```yaml
trendlines:
  - columnId: col-sales       # which y-axis measure to fit
    model: linear             # linear (verified); quadratic | polynomial | exponential | logarithmic | power per OpenAPI
    label: { visibility: shown }    # toggles the model-name label
    value: { visibility: shown }    # toggles the equation / R² readout
    caption: {}                     # optional caption object
```

**Canonical shape** (verified 2026-05-22 against a UI-built workbook readback): `label` and `value` are **separate visibility toggles**, not a single `{visibility, text}` object. `caption` is its own object. `line: { color, width }` is *not* present in the canonical readback — it may be accepted on POST but is not the default; treat as unverified until round-tripped. Only `model: linear` is end-to-end verified.

Trendlines are rejected when the chart has no `xAxis`, uses stacking on bar/area/combo, or has a `color` channel — discover those constraints by submitting and reading the error.

### `dataLabel` — value labels on marks

```yaml
dataLabel:
  labels: shown               # shown | hidden — the only required field
  labelDisplay: all-points    # optional: all-points | maximum | min-max | ...
  valueFormat: percent        # optional
  totals: { display: shown }  # optional
```

**Canonical default** (verified 2026-05-22 against a UI-built workbook readback): when the user just enables "show data labels" with no further customization, Sigma writes only `{ labels: shown }` — every other field is optional and absent. Add the optional fields only when the user actually customized them, otherwise omit them to match the canonical default.

For `combo-chart`, optional `seriesDataLabel` is a map keyed by layer shape (`bar`, `line`, `area`, `scatter`) with per-shape overrides:

```yaml
seriesDataLabel:
  bar: { labelDisplay: maximum }
  line: { labelDisplay: all-points }
```

## Other chart kinds

Per the OpenAPI, these are all valid `kind` values; documented examples for the most common are above. The shape mirrors the `bar-chart`/`line-chart` pattern (`source`, `columns`, `xAxis`, `yAxis`):

- `area-chart`, `combo-chart`, `scatter-chart` — same shape as `bar-chart`/`line-chart`, just a different `kind`. For specifics, inspect the OpenAPI schema directly:
  ```bash
  jq '.components.schemas.AreaChart, .components.schemas.ComboChart, .components.schemas.ScatterChart' /tmp/sigma-api.json
  ```
  **combo-chart dual-axis (verified 2026-05-22):** Dual-axis combo charts persist via the bare-string-vs-object form of `yAxis.columnIds`. Bare-string entries go to the **primary (left)** axis; `{columnId, type}` object-form entries go to the **secondary (right)** axis with the given mark type. The right axis auto-scales by default. `yAxis.format` governs the left axis only — how to customize the right-axis scale (log/min/max/zero) is unverified.
- `pie-chart` — same shape as `donut-chart` (`value` + `color`).
- `pivot-table` — uses `values` instead of `yAxis`; useful for cross-tab analysis. See `tables.md`.

## Known unsupported features

- **No delta / comparison field on `kpi-chart`** (see `kpis.md`). To show period-over-period change, stack two `kpi-chart` elements side-by-side via `layout.md` or use a chart with explicit comparison columns.

For element-level reference of `kind: "text"` (free-form Markdown blocks), see `text.md`.
