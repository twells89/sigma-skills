# Charts

Chart elements: `line-chart`, `bar-chart`, `area-chart`, `combo-chart`, `donut-chart`, `region-map`, `point-map`. They share the same skeleton — a `source`, a `columns` array, and axis/value/region pointers that reference column IDs.

## Common Fields

| Field | Required | Notes |
|---|---|---|
| `kind` | yes | `"line-chart"`, `"bar-chart"`, `"area-chart"`, `"combo-chart"`, or `"donut-chart"` |
| `id` | yes | Unique on the page |
| `name` | yes | Display title |
| `source` | yes | Usually `{ "kind": "table", "elementId": "<source-table-id>" }` — see `sources.md` |
| `columns` | yes | Inline column definitions for the chart's own columns |

Every column in `columns` gets an `id`, a `formula`, a `name`, and optional `format` (see `formatting.md`).

Remember: formulas on a chart that sources another element must use the source's prefix (`[<SourceName>/col]`). See `formulas.md`.

---

## Line Chart

```json
{
  "id": "sales-over-time",
  "kind": "line-chart",
  "name": "Sales over time",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-month", "formula": "DateTrunc(\"month\", [Master/Date])", "name": "Month",
      "format": { "kind": "datetime", "formatString": "%b %Y" } },
    { "id": "col-sales", "formula": "Sum([Master/Sales Amount])", "name": "Sales",
      "format": { "kind": "number", "formatString": "$,.0f" } }
  ],
  "xAxis": { "id": "col-month" },
  "yAxis": [{ "id": "col-sales" }]
}
```

- `xAxis` — single `{ id, sort? }`
- `yAxis` — array of `{ id }` (multiple series)
- `xAxis.sort` shape: `{ "by": "<colId>", "direction": "ascending" | "descending" }`

### Color channel

`line-chart` and `bar-chart` accept an optional `color` object that encodes a category column as series color (instead of, or in addition to, a second `yAxis` series).

```json
"color": { "by": "category", "column": "<colId>" }
```

- `by` — `"category"` for categorical encoding by a column.
- `column` — the column ID to encode.

## Bar Chart

Same axis shape as line-chart. Adds `stacking`.

```json
{
  "id": "sales-by-region",
  "kind": "bar-chart",
  "name": "Sales by region",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-region", "formula": "[Master/Store Region]", "name": "Region" },
    { "id": "col-sales",  "formula": "Sum([Master/Sales Amount])", "name": "Sales",
      "format": { "kind": "number", "formatString": "$,.0f" } }
  ],
  "xAxis": { "id": "col-region" },
  "yAxis": [{ "id": "col-sales" }],
  "stacking": "none"
}
```

`stacking`: `"none"` | `"stacked"` | `"100"`

Add a sort to put categories in descending order of a measure:

```json
"xAxis": {
  "id": "col-region",
  "sort": { "by": "col-sales", "direction": "descending" }
}
```

## Area Chart

Same axis shape as line-chart. Adds `stacking`.

```json
{
  "id": "revenue-by-channel",
  "kind": "area-chart",
  "name": "Revenue by channel",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-month",   "formula": "DateTrunc(\"month\", [Master/Date])", "name": "Month" },
    { "id": "col-channel", "formula": "[Master/Channel]", "name": "Channel" },
    { "id": "col-sales",   "formula": "Sum([Master/Sales Amount])", "name": "Sales" }
  ],
  "xAxis": { "id": "col-month" },
  "yAxis": [{ "id": "col-sales" }],
  "stacking": "stacked"
}
```

`stacking`: `"none"` | `"stacked"` | `"100"`.

## Combo Chart

Bars + lines on the same axes. Same skeleton as the others; `yAxis` carries the multiple series and `filters` work the same way.

```json
{
  "id": "revenue-and-units",
  "kind": "combo-chart",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-month",   "formula": "DateTrunc(\"month\", [Master/Date])" },
    { "id": "col-revenue", "formula": "Sum([Master/Sales Amount])" },
    { "id": "col-units",   "formula": "Sum([Master/Units])" }
  ],
  "xAxis": { "id": "col-month" },
  "yAxis": [{ "id": "col-revenue" }, { "id": "col-units" }]
}
```

## Donut

Uses `value` and `color` instead of `xAxis` / `yAxis`.

```json
{
  "id": "sales-by-family",
  "kind": "donut-chart",
  "name": "Sales by product family",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-family", "formula": "[Master/Product Family]", "name": "Family" },
    { "id": "col-sales",  "formula": "Sum([Master/Sales Amount])", "name": "Sales",
      "format": { "kind": "number", "formatString": "$,.0f" } }
  ],
  "value": { "id": "col-sales" },
  "color": { "id": "col-family",
             "sort": { "by": "col-sales", "direction": "descending" } }
}
```

`holeValue` is optional. The donut renders fine without it (verified May 2026). When set, it must reference a column ID — not a literal float (`"holeValue": 0.5` is rejected with `Invalid object: number`):

```json
"holeValue": { "id": "col-sales-hole" }
```

> **Watch out — silent element drop.** If `holeValue.id` equals `value.id` (i.e., they reference the same column), the POST succeeds but the entire donut element is silently dropped from the saved spec. Define a **second column** with a distinct ID (same formula is fine) and point `holeValue` at it:
>
> ```json
> "columns": [
>   { "id": "col-family",     "formula": "[Master/Family]" },
>   { "id": "col-sales",      "formula": "Sum([Master/Sales Amount])" },
>   { "id": "col-sales-hole", "formula": "Sum([Master/Sales Amount])" }
> ],
> "value":     { "id": "col-sales" },
> "color":     { "id": "col-family" },
> "holeValue": { "id": "col-sales-hole" }
> ```

## Element-Level Filters (Top-N, etc.)

Charts take the same `filters` array as tables — the top-N example in `tables.md` applies to `bar-chart`, `line-chart`, `area-chart`, `combo-chart`, `donut-chart`, and `kpi-chart` without changes. Use this to cap a chart to the top N categories by some measure.

Top 10 regions by `Sales` on a bar chart:

```json
{
  "id": "top-regions",
  "kind": "bar-chart",
  "name": "Top 10 regions",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-region", "formula": "[Master/Store Region]", "name": "Region" },
    { "id": "col-sales",  "formula": "Sum([Master/Sales Amount])", "name": "Sales",
      "format": { "kind": "number", "formatString": "$,.0f" } }
  ],
  "xAxis": { "id": "col-region", "sort": { "by": "col-sales", "direction": "descending" } },
  "yAxis": [{ "id": "col-sales" }],
  "stacking": "none",
  "filters": [
    {
      "id": "top-10",
      "columnId": "col-sales",
      "kind": "top-n",
      "rankingFunction": "rank",
      "mode": "top-n",
      "rowCount": 10,
      "includeNulls": "when-no-value-is-selected"
    }
  ]
}
```

`rowCount` takes a number literal — it cannot be bound to a control (see `controls.md`, "Where Control Bindings Apply").

## Known Unsupported Features

- No `scatter` element kind. Use `scatter-chart` (see Other Chart Kinds below).
- No delta / comparison field on `kpi-chart` (see `kpis.md`). To show a comparison, stack two `kpi-chart` elements side-by-side via `layout.md` or use a chart.

## Other Chart Kinds

These are all valid `kind` values per the OpenAPI; documented examples for the most common are above. The shape mirrors the `bar-chart`/`line-chart` pattern (`source`, `columns`, `xAxis`, `yAxis`):

- `area-chart`, `combo-chart`, `scatter-chart` — same shape as `bar-chart`/`line-chart`, just a different `kind`.
- `pie-chart` — same shape as `donut-chart` (`value` + `color`).
- `pivot-table` — uses `values` instead of `yAxis`; useful for cross-tab analysis.

For element-level reference of `kind: "text"` (free-form Markdown blocks), see `text.md`.

## Maps

Two map kinds are spec-supported. Both use the standard `source` + `columns` skeleton and reference column IDs from `columns` in their geometry/encoding fields.

### `region-map` — choropleth (filled regions)

```json
{
  "id": "employees-by-state",
  "kind": "region-map",
  "name": "Employees by State",
  "source": { "kind": "table", "elementId": "master" },
  "columns": [
    { "id": "rm-state", "formula": "[Master/State]",              "name": "State" },
    { "id": "rm-count", "formula": "Count([Master/Employee ID])", "name": "Employees" }
  ],
  "region": { "id": "rm-state", "regionType": "us-state" },
  "label":  [{ "id": "rm-count" }]
}
```

| Field | Required | Shape | Notes |
|---|---|---|---|
| `region` | yes | `{ id, regionType }` | `id` references a column in `columns`; the column's values are looked up against the named region set |
| `label` | no | `[{ id }, …]` | Values rendered inside each region. Almost always the measure column. |
| `tooltip` | no | `[{ id }, …]` | Extra columns shown on hover |
| `color` | no | `{ "by": "category", "column": "<colId>" }` | Categorical fill. `column` **must differ** from `region.id` — API rejects reuse: *"Column X is referenced from both 'region' and 'color'"*. `by: "value"` is rejected; the default value-based heat shading is automatic when `color` is omitted. |
| `size` | — | silently dropped | Choropleths don't size |

Valid `regionType` values (verified via POST round-trip):

- `us-state` — 50 US states + DC
- `us-county` — US counties
- `us-zipcode` — US ZIP codes (**not** `us-zip`)
- `us-cbsa` — US Core-Based Statistical Areas (**not** `us-msa`)
- `country` — country names / ISO codes

Rejected: `us-zip`, `us-msa`, `us-congressional-district`, `world-country`, `state`, `province`, `continent` — all surface as `region.regionType: Invalid value: string` on POST.

### `point-map` — lat/long bubbles

```json
{
  "id": "stores",
  "kind": "point-map",
  "name": "Stores",
  "source": { "kind": "table", "elementId": "master" },
  "columns": [
    { "id": "p-lat",  "formula": "[Master/Lat]",          "name": "Lat" },
    { "id": "p-lng",  "formula": "[Master/Long]",         "name": "Long" },
    { "id": "p-sz",   "formula": "Sum([Master/Revenue])", "name": "Revenue" },
    { "id": "p-cat",  "formula": "[Master/Region]",       "name": "Region" }
  ],
  "latitude":  { "id": "p-lat" },
  "longitude": { "id": "p-lng" },
  "size":      { "id": "p-sz" },
  "color":     { "by": "category", "column": "p-cat" },
  "label":     [{ "id": "p-sz" }]
}
```

| Field | Required | Shape |
|---|---|---|
| `latitude`  | yes | `{ id }` (object, not array) |
| `longitude` | yes | `{ id }` |
| `size`  | no | `{ id }` — bubble size encodes a measure |
| `color` | no | `{ "by": "category", "column": "<colId>" }` — `by: "value"` is rejected; category coloring only |
| `label` | no | `[{ id }, …]` |

> **One channel per column.** A column referenced from one map channel cannot also appear in another channel. Putting the same column ID on `size` and `label` (or `region` and `color`, etc.) is rejected with *"Column X is referenced from both 'size' and 'label'; a column can only be on one channel at a time"*. Workaround: add a second column to `columns` with the same formula but a distinct `id`, and reference each ID from a different channel.

### Invalid map kinds

The API rejects `bubble-map`, `geo-map`, `heat-map`, `choropleth-map`, `us-map`, and `map` with `Invalid kind`. Use `region-map` or `point-map`.
