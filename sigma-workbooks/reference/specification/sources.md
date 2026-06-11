# Sources (non-warehouse)

Recipe book for source kinds other than `warehouse-table`. For the canonical schema of any source kind, pull it by its `kind` value (`warehouse-table`, `sql`, `table`, `data-model`, `join`, `union`, `transpose`):

```bash
jq --arg k join 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
```

Every element with columns has a `source` that defines where its data comes from. This file focuses on the **patterns** and **formula-prefix conventions** for each non-warehouse source kind — the parts the OpenAPI alone won't teach.

**For warehouse-table** — the most common source — see the dedicated `sources-warehouse.md`. It's loaded by default because nearly every workbook uses it.

**For discovery** (finding connection IDs, paths, data model IDs, element IDs) see `reference/workflows/discover.md`.

---

## table (cross-element reference)

Sources another element in the same workbook. This is the most common source kind for charts, KPIs, and derived tables.

```yaml
kind: table
elementId: <id of another element on some page>
```

Column formulas reference that element's columns using its `name`:
- Element named "Sales Table" → `[Sales Table/Revenue]`

## data-model

References an element from an existing data model. **Prefer this source kind when the user's org has relevant data models** — it inherits the data model's joins, filters, and column-level security, which is usually closer to what the user wants than re-deriving from raw warehouse tables. Discover available models with `GET /v2/dataModels`; if none are relevant, fall back to `warehouse-table` rather than trying to manufacture a model.

```yaml
kind: data-model
dataModelId: <data-model-uuid>
elementId: <element-uuid within that model>
```

Optionally add `groupingId` to apply one of the model element's groupings.

## join

Joins multiple sources into one logical source via an array of `joins`. Each leg (`primarySource`, `left`, `right`) can be any source kind, so warehouse tables, other elements, and data-model elements can be joined interchangeably.

Only `joins` (with each entry's `left`, `right`, `columns`) is required. `primarySource` is optional — if omitted, Sigma infers it as the source that appears on the left of some join but never on the right. Each join's `name` (used as the formula prefix — `[<name>/column]`; defaults to the right source's name) and `joinType` (defaults to inner) are also optional.

```yaml
kind: join
name: Sales Star
primarySource:
  kind: warehouse-table
  connectionId: <conn-uuid>
  path: [DB, SCHEMA, F_POS]
joins:
  - name: Sales
    joinType: left-outer
    left:
      kind: warehouse-table
      connectionId: <conn-uuid>
      path: [DB, SCHEMA, F_POS]
    right:
      kind: warehouse-table
      connectionId: <conn-uuid>
      path: [DB, SCHEMA, F_SALES]
    columns:
      - left: "[Order Number]"
        right: "[Order Number]"
```

Each entry in a join's top-level `columns[]` is a join-key pair (`left`/`right`, with an optional `op` for non-equi joins) — a different shape from an element's `columns[]` (see below). Pull `joinType` values and the column-pair shape from the spec via the recipe at the top.

**Column formula prefixes with joins** — see `formulas.md` for the full rules:
- Primary-source columns use the **join's top-level `name`**: `[Sales Star/Order Number]`
- Joined-table columns use the **join leg's `name`**: `[Sales/Cust Key]`
- Warehouse path segments are **not** used as prefixes inside a join.

## sql

A custom SQL query against a connection — `kind: sql` with `connectionId` + `statement`. Pull the shape from the spec via the recipe.

## transpose

Pivots a source's rows and columns. Needs a `source` (any source kind) plus a direction config — `row-to-column` (pivot wider) or `column-to-row` (unpivot longer), each with its own fields. Pull the per-direction shape from the spec via the recipe.

## Element `columns[]` vs. join `columns[]`

Two unrelated things share the name. An element's `columns[]` is its **output columns** (each a `formula`); a join source's top-level `columns[]` is its **join keys** (`left`/`right` pairs). Don't conflate them.

## union

Combines two or more sources (`warehouse-table`, `table`, or `data-model`) into a single source whose columns are explicitly mapped via `matches[]`.

```yaml
kind: union
name: All Sales
sources:
  - kind: warehouse-table
    connectionId: <conn-uuid>
    path: [DB, SCHEMA, JULY_SALES]
  - kind: warehouse-table
    connectionId: <conn-uuid>
    path: [DB, SCHEMA, AUGUST_SALES]
matches:
  - outputColumnName: Order ID
    sourceColumns:
      - '[Order ID]'   # column from the first source
      - '[Order ID]'   # column from the second source
  - outputColumnName: Sales
    sourceColumns:
      - '[Sales]'
      - '[Sales]'
```

`sourceColumns` is an array aligned to `sources` — one entry per source, in order. `outputColumnName` becomes the column users see and the name your element formulas reference.

**Set `name` explicitly.** Formula prefixes for the consuming element use the union's `name`, e.g. `[All Sales/Order ID]`. If you omit `name`, Sigma assigns `"Union of N Sources"`; if your element also defines a column whose `name` matches an `outputColumnName`, a bare `[Order ID]` formula becomes a circular self-reference and the SQL fails to compile. See `formulas.md` > Union source.
