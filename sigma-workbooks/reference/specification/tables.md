# Tables

Recipe book for `table`, `pivot-table`, and `input-table` elements + style and trap guidance. The full schemas live in the OpenAPI — fetch any element kind by its `kind` value:

```bash
jq --arg k pivot-table 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
```

Swap `pivot-table` for `table` or `input-table` to inspect the others.

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

For the `table` kind, `name` is a plain string. The styled title-section object (with `text`, styling, and `noDataText`) applies to `pivot-table` and `input-table` — see those sections below.

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

> `conditionalFormats` is **not** a `table` field — it lives on `pivot-table` and `input-table` only (see below). Adding it to a `kind: table` element is rejected.

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
    sort:
      direction: descending
```

`values` (required) is the measure column array — the cells of the pivot. `rowsBy` and `columnsBy` place dimension columns explicitly on the row and column shelves; each item is `{ id, sort? }`, where `sort` is `{ direction: ascending | descending, by?, aggregation? }` (`by` can be a column ID or `"row-count"`). Columns not listed on either shelf still render as available dimensions.

## `conditionalFormats` — threshold coloring on cells

Available on `pivot-table` and `input-table`. Apply background/text styling per cell based on column values. Variants include `single`, `backgroundScale`, `fontScale`, and `dataBars` — covering threshold rules, gradient scales, font-color scales, and inline data bars. Inspect the OpenAPI for the full operator + style enums (use the `conditionalFormats` property on either kind's schema).

**Recipe — red/green threshold coloring on a revenue column:**

```yaml
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

---

# Input tables

The `input-table` element is an editable table — users type values directly into cells, backed by a provisioned warehouse table. Required fields: `id`, `kind`, `source`, `inputMode`.

`inputMode` controls who can edit and where:

- `edit` — workbook editors only, in draft mode
- `explore` — users with explore permission or greater, in published view
- `view` — all users, in published view

`source` is one of:

- `{ kind: empty, connectionId: <YOUR_CONNECTION_ID> }` — provisions a fresh, blank warehouse table.
- `{ kind: linked, from: <elementId> }` — rows are linked to another element; the connection is inherited, and editable rows are matched to source rows by the `key` columns.

`columns[]` items come in four shapes (each also accepts optional `name`, `description`, `hidden`, `format`):

- **System column** — `{ id }` where `id` ∈ `ID`, `CREATED_AT`, `CREATED_BY`, `UPDATED_AT`, `UPDATED_BY`. Protocol-managed; type is fixed.
- **Key column** — `{ id, key }` binding to a source column on `source.from` (linked tables; `key` is immutable once created).
- **Editable data column** — `{ id, type }` where `type` ∈ `text`, `number`, `datetime`, `checkbox`.
- **Formula column** — `{ id, formula }` for a computed column.

```yaml
id: feedback-input
kind: input-table
name: Manual feedback
inputMode: edit
source:
  kind: empty
  connectionId: <YOUR_CONNECTION_ID>
columns:
  - id: ID
  - id: customer
    type: text
  - id: score
    type: number
  - id: flagged
    type: checkbox
  - id: score-bucket
    formula: If([score] >= 8, "Promoter", "Other")
```

`input-table` also supports `filters`, `conditionalFormats` (see above), `sort`, `summary`, and the styled title-section `name`/`noDataText`. Fetch the full schema with the `kind`-form recipe at the top of this doc.
