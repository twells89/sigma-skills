# Tables

Recipe book for `table` and `pivot-table` elements + style and trap guidance. The full schemas live in the OpenAPI:

```bash
jq '.components.schemas.Table, .components.schemas.PivotTable' /tmp/sigma-api.json
```

The `table` element is the most common element kind and the primary way data enters a workbook — charts, KPIs, and other elements usually point their `source` at a table.

## Basic shape

```yaml
id: sales-table
kind: table
name: Sales Data
source:
  kind: warehouse-table
  connectionId: <conn-uuid>
  path: [DATABASE, SCHEMA, TABLE]
columns:
  - id: col-1
    name: Column Name
    formula: "[TABLE/column_name]"
  - id: col-2
    name: Total
    formula: Sum([Column Name])
order: [col-1, col-2]
```

See `sources.md` for all source kinds and `formulas.md` for the column-reference rules. Every column needs `id`, `name`, `formula`; optional `format` (see `formatting.md`).

`name` accepts either a plain string (shown above) or a title-section object for styled headers — also supports an optional `description` and `noDataText`:

```yaml
name:
  text: Sales Data
  fontSize: 18
  fontWeight: bold
description:
  text: Latest quarter
noDataText: No rows in range
```

The shape mirrors chart titles; fetch `TitleSection` from the OpenAPI for the full styling enum.

## Common optional fields

### `order`

Array of column IDs controlling left-to-right display order. Defaults to declaration order.

### `groupings`

Pivot / aggregation views without changing element kind:

```yaml
groupings:
  - id: by-region
    groupBy: [col-region]
    calculations: [col-total, col-profit]
```

### `filters` (top-N, element-level row filters)

```yaml
filters:
  - id: top-20
    columnId: col-revenue
    kind: top-n
    rankingFunction: rank
    mode: top-n
    rowCount: 20
    includeNulls: when-no-value-is-selected
```

> **`rowCount` takes a number literal only** — it cannot be parametrized by a control. `rowCount: "[TopN]"` is rejected. Control bindings apply to filter **values**, not to structural fields like `rowCount`, `rankingFunction`, `mode`, or `kind`. To vary the cap interactively, duplicate the element per cap.

### `conditionalFormats` — threshold coloring on cells

Apply background/text styling per row based on column values. Four variants — `single`, `backgroundScale`, `fontScale`, `dataBars` — covering threshold rules, gradient scales, font-color scales, and inline data bars. Inspect the OpenAPI for the full operator + style enums:

```bash
jq '.components.schemas.ConditionalFormatSingle, .components.schemas.ConditionalFormatBackgroundScale' /tmp/sigma-api.json
```

**Recipe — red/green threshold coloring on a revenue column:**

```yaml
id: sales-table
kind: table
# ...other table fields...
conditionalFormats:
  - type: single
    columnIds: [col-revenue]
    condition: ">"
    value: 1000
    style:
      backgroundColor: "#22c55e"
  - type: single
    columnIds: [col-revenue]
    condition: "<"
    value: 100
    style:
      backgroundColor: "#ef4444"
```

Condition operators include `=`, `!=`, `>`, `>=`, `<`, `<=`, `IsNull`, `IsNotNull`, `Contains`, `NotContains`, `StartsWith`, `EndsWith`, `Between`, `NotBetween`, and `formula` (arbitrary boolean). Style block supports `backgroundColor`, `color`, `bold`, `italic`, `underline`, and column-level `format` override.

The full array round-trips through GET unchanged, so PUT-based edits are stable.

---

# Pivot tables

The `pivot-table` element is a sibling of `table` for cross-tab analysis — measure cells aggregated across one or more row/column dimensions.

## Shape

```yaml
id: deployments-pivot
kind: pivot-table
name: Deployments by cloud and env
source:
  kind: table
  elementId: deployments-source
columns:
  - id: piv-cloud
    name: Cloud
    formula: "[Deployments/Cloud]"
  - id: piv-env
    name: Environment
    formula: "[Deployments/Environment]"
  - id: piv-count
    name: Deployments
    formula: CountDistinct([Deployments/Deployment UUID])
    format:
      kind: number
      formatString: ",.0f"
values: [piv-count]
rowsBy:
  - id: piv-cloud
columnsBy:
  - id: piv-env
```

`values` holds the measure column IDs (the cells of the pivot). `rowsBy` and `columnsBy` hold the dimension column IDs — each as `[{ id: <col-id> }, ...]`. **Without `rowsBy`/`columnsBy`, the pivot collapses to a single grand-total cell** even though the dimension columns are present in `columns[]`. Sigma does NOT infer placement from non-`values` columns; you must declare it.

> **`columnsBy[].sort` is NOT supported.** PUT returns HTTP 400 `sort shape not supported on columnsBy`. Sigma orders pivot columns by the natural order of the column values (alphabetical for strings, numeric for numbers, chronological for dates / integers used as date-of-year). To control column order, pre-compute an integer sort key column (e.g. `Month()` returns 1-12 and sorts chronologically) and use that instead of a string column. Verified 2026-05-24: `MonthName()` (string) sorted alphabetically until swapped to `Month()` (integer).

## Round-trip quirks

- **Column reordering**: Sigma reorders the `columns` array on round-trip — value columns first, then dimensions — regardless of submission order. GET → edit → PUT will show a non-substantive diff in `columns`. The `values` array preserves IDs, so rendered output is unchanged.
- **Spec docs lied about `rowsBy`/`columnsBy`**: this file previously claimed those fields didn't exist and that UI was required for row/column placement. They do exist (verified 2026-05-24 against a UI-built pivot's `GET .../spec` round-trip) and a spec-only build works end-to-end. The OpenAPI may still be under-documented; trust the round-trip.
