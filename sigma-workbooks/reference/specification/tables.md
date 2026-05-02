# Tables

The `table` element displays data in tabular format — the most common element kind and the primary way data enters a workbook. Charts, KPIs, and other elements usually point their `source` at a table.

## Basic Shape

```json
{
  "id": "sales-table",
  "kind": "table",
  "name": "Sales Data",
  "source": {
    "kind": "warehouse-table",
    "connectionId": "<conn-uuid>",
    "path": ["DATABASE", "SCHEMA", "TABLE"]
  },
  "columns": [
    { "id": "col-1", "formula": "[TABLE/column_name]", "name": "Column Name" },
    { "id": "col-2", "formula": "Sum([Column Name])",   "name": "Total" }
  ],
  "order": ["col-1", "col-2"]
}
```

See `sources.md` for all source kinds (warehouse-table, join, data-model, etc.) and `formulas.md` for the column reference rules.

## Optional Fields

### `order`
Array of column IDs controlling left-to-right display order. If omitted, columns appear in declaration order.

```json
"order": ["col-order-id", "col-amount", "col-profit"]
```

### `groupings`
Pivot / aggregation views. Each grouping has an `id`, a `groupBy` list of column IDs, a `calculations` list of column IDs, and an optional inner `sort`.

```json
"groupings": [
  {
    "id": "by-region",
    "groupBy": ["col-region"],
    "calculations": ["col-total", "col-profit"],
    "sort": [
      { "columnId": "col-total", "direction": "descending", "nulls": "connection-default" }
    ]
  }
]
```

`sort[].nulls` — `"first"` | `"last"` | `"connection-default"` (defer to the warehouse connection's null-ordering setting).

### `style`
Optional styling on the table element itself.

```json
"style": { "borderRadius": "round", "borderColor": "#E0E0E0", "borderWidth": 1 }
```

### `filters`
Element-level row filters. Top-N is the most common variant:

```json
"filters": [
  {
    "id": "top-20",
    "columnId": "col-revenue",
    "kind": "top-n",
    "rankingFunction": "rank",
    "mode": "top-n",
    "rowCount": 20,
    "includeNulls": "when-no-value-is-selected"
  }
]
```

`includeNulls` accepts `"never"`, `"always"`, or `"when-no-value-is-selected"`.

`rankingFunction` accepts `"rank"`, `"dense-rank"`, or `"row-number"`.

`kind: "list"` filters use `mode: "include"` or `"exclude"` and a `values` array of literals (e.g. `"values": ["Active"]`).

> **`rowCount` takes a number literal only** — it cannot be parametrized by a control. `"rowCount": "[TopN]"` or any other control-reference shape is rejected. Control bindings apply to **filter values**, not to structural fields like `rowCount`, `rankingFunction`, `mode`, or `kind`. Same goes for the equivalent `filters` block on charts (see `charts.md`). To vary the cap interactively today, duplicate the element per cap.

## Columns

Every column needs `id`, `name`, and `formula`. Optional: `format` (see `formatting.md`), `hidden`.

```json
{
  "id": "col-revenue",
  "name": "Revenue",
  "formula": "[ORDERS/revenue]",
  "format": { "kind": "number", "formatString": "$,.0f" },
  "hidden": true
}
```

`hidden: true` keeps the column in the element (so other formulas and charts can reference it) but suppresses it from the rendered table.

**Formula rules** — see `formulas.md`. The single most common mistake is a bare `[col]` reference when a source prefix is required.

## Pivot Table

`kind: "pivot-table"` is a tabular cross-tab variant. Same source/columns shape as `table`, with row/column/value role assignments.

```json
{
  "id": "sales-pivot",
  "kind": "pivot-table",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-region",  "formula": "[Master/Store Region]" },
    { "id": "col-quarter", "formula": "DateTrunc(\"quarter\", [Master/Date])" },
    { "id": "col-sales",   "formula": "Sum([Master/Sales Amount])" }
  ],
  "rowsBy":    ["col-region"],
  "columnsBy": ["col-quarter"],
  "values":    ["col-sales"]
}
```

- `rowsBy` — column IDs that become row headers.
- `columnsBy` — column IDs that become column headers (cross-tab dimension).
- `values` — column IDs (typically aggregations) shown in the cells.
- `conditionalFormats` — optional array of conditional-formatting rules applied to value cells.
