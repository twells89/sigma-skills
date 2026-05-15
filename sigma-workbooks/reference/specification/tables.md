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

### `description`
Optional free-text description shown alongside the table title in the UI. Round-trips verbatim.

```json
"description": "Rows with Annual Salary < 50,000 highlight red; status formula highlights inactive in gray."
```

Only the `table` element kind currently carries a `description` field — `pivot-table` and charts do not.

### `style`
Optional styling on the table element itself.

```json
"style": { "borderRadius": "round", "borderColor": "#E0E0E0", "borderWidth": 1 }
```

### `conditionalFormats`
Optional row/cell coloring rules applied to value cells. Same shape on `table` and `pivot-table`. See the "Conditional Formatting" section at the bottom of this file for the full rule reference.

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
  "name": "Sales by region and quarter",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    { "id": "col-region",  "formula": "[Master/Store Region]" },
    { "id": "col-quarter", "formula": "DateTrunc(\"quarter\", [Master/Date])" },
    { "id": "col-sales",   "formula": "Sum([Master/Sales Amount])" }
  ],
  "rowsBy":    [{ "id": "col-region" }],
  "columnsBy": [{ "id": "col-quarter" }],
  "values":    ["col-sales"]
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"pivot-table"` |
| `source` | yes | Same source kinds as `table` |
| `columns` | yes | Same shape as `table`'s `columns` (id + formula + name + format) |
| `values` | yes | Array of column ID strings — the **measure** columns (cells of the pivot) |
| `rowsBy` | yes (in practice) | Array of `{ "id": "<col-id>" }` objects — columns to roll up on the left axis |
| `columnsBy` | optional | Array of `{ "id": "<col-id>" }` objects — columns to roll out across the top header |
| `name` | no | Display title — accepted even though not in the OpenAPI required list |
| `conditionalFormats` | no | Array of conditional-formatting rules applied to value cells |

**Don't use `rows`, `columns`, `pivotRows`, or `columnGroups` as alternative names** — the API silently accepts those but the element renders incorrectly.

### What happens when you omit `rowsBy`/`columnsBy`

Verified on staging (May 2026): a pivot-table with only `columns` + `values` is accepted by POST and round-trips cleanly, **but at render time it collapses to a single grand-total row** — no dimension breakouts. Sigma does not infer dimensions from non-`values` columns. You must explicitly assign them via `rowsBy`/`columnsBy`.

### Round-trip column reordering

When `rowsBy` / `columnsBy` are present, Sigma preserves the `columns` array order on round-trip. When they are absent (the broken grand-total mode), Sigma reorders columns with values first. Either way, the `values`, `rowsBy`, and `columnsBy` arrays preserve the IDs you submitted.

## Conditional Formatting

Both `table` and `pivot-table` take a `conditionalFormats` array. Each entry is one rule. Three rule types: `single`, `backgroundScale`, `dataBars`.

```json
"conditionalFormats": [
  { "type": "single", "columns": ["col-sal"], "condition": "<", "value": 50000,
    "style": { "color": "#B00020" } },
  { "type": "single", "columns": ["col-status"], "condition": "formula",
    "formula": "[Status] = \"Inactive\"",
    "style": { "backgroundColor": "#D4D4D4" } },
  { "type": "single", "columns": ["col-name"], "condition": "IsNull",
    "style": { "backgroundColor": "#FFE0E0" } },
  { "type": "dataBars",        "columns": ["col-sal"],
    "scheme": ["#A0CBE8", "#1F77B4"] },
  { "type": "backgroundScale", "columns": ["col-ot"],
    "scheme": ["#FFFFFF", "#FDD49E", "#FC8D59", "#B30000"],
    "includeValues": true }
]
```

### `type: "single"` — one condition, one style

| Field | Required | Notes |
|---|---|---|
| `columns` | yes | Array of column IDs the rule applies to. May span several columns at once. |
| `condition` | yes | `"<"`, `">"`, `"="`, `"IsNull"`, `"IsNotNull"`, or `"formula"` |
| `value` | conditional | Required when `condition` is `<`/`>`/`=`. Literal value (number, string). |
| `formula` | conditional | Required when `condition: "formula"`. A Sigma boolean formula evaluated per row — e.g. `"[Status] = \"Inactive\""`. Bare `[col]` refs inside the formula are resolved against the element's own columns. |
| `style` | conditional | `{ "backgroundColor"?: "#RRGGBB", "color"?: "#RRGGBB" }`. Required for value/formula conditions; optional for `IsNull`/`IsNotNull` (a default style is applied). |
| `includeValues` | no | `true` (default) shows the underlying value; `false` blanks the cell. |
| `includeSubtotals` | no | Apply the rule to subtotal rows as well |
| `includeGrandTotals` | no | Apply the rule to grand-total rows as well |

### `type: "backgroundScale"` — gradient over a range

Cells are colored along a multi-stop gradient based on their value's rank within the column's range.

```json
{ "type": "backgroundScale", "columns": ["col-ot"],
  "scheme": ["#FFFFFF", "#FDD49E", "#FC8D59", "#B30000"],
  "includeValues": true,
  "order": "descending" }
```

| Field | Notes |
|---|---|
| `scheme` | Array of CSS colors (hex or `rgb(...)`), bottom-of-scale → top-of-scale. 2 colors = simple gradient; more = piecewise. |
| `order` | `"ascending"` (default, low→high) or `"descending"` (high→low) |
| `includeValues` | `true` keeps the value visible over the colored cell; `false` shows only the color |

### `type: "dataBars"` — horizontal bars inside cells

```json
{ "type": "dataBars", "columns": ["col-sal"],
  "scheme": ["#A0CBE8", "#1F77B4"],
  "includeSubtotals": false }
```

| Field | Notes |
|---|---|
| `scheme` | Two colors: `[negative-color, positive-color]`. If all values are positive, only the second is used. |
| `includeSubtotals` | Default `false`. Bars are drawn on detail rows only unless this is set. |

> **Round-trip gap:** `dataBars` rules drop `includeValues: true` on readback. The bar still renders correctly in the UI but a subsequent `GET` won't include the field. Don't iterate on this — it's cosmetic. (Verified 2026-05.)
