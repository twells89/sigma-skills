# Charts

Chart elements: `line-chart`, `bar-chart`, `area-chart`, `combo-chart`, `donut`. They share the same skeleton — a `source`, a `columns` array, and axis/value pointers that reference column IDs.

## Common Fields

| Field | Required | Notes |
|---|---|---|
| `kind` | yes | `"line-chart"`, `"bar-chart"`, `"area-chart"`, `"combo-chart"`, or `"donut"` |
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
  "kind": "donut",
  "name": "Sales by product family",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-family", "formula": "[Master/Product Family]", "name": "Family" },
    { "id": "col-sales",  "formula": "Sum([Master/Sales Amount])", "name": "Sales",
      "format": { "kind": "number", "formatString": "$,.0f" } }
  ],
  "value":     { "id": "col-sales" },
  "color":     { "id": "col-family",
                 "sort": { "by": "col-sales", "direction": "descending" } },
  "holeValue": 0.5
}
```

**Required:** `holeValue` (0.0 = pie, 1.0 = all hole). Donut specs without it are rejected.

## Element-Level Filters (Top-N, etc.)

Charts take the same `filters` array as tables — the top-N example in `tables.md` applies to `bar-chart`, `line-chart`, `area-chart`, `combo-chart`, `donut`, and `kpi-chart` without changes. Use this to cap a chart to the top N categories by some measure.

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

- No `scatter` element kind.
- No delta / comparison field on `kpi-chart` (see `kpis.md`).

For `text` (free-form rich text) and `divider` (visual separator) elements, see `layout.md`.
