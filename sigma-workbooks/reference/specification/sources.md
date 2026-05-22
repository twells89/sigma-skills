# Sources (non-warehouse)

Recipe book for source kinds other than `warehouse-table`. For canonical schemas:

```bash
jq -r '.components.schemas | keys[] | select(test("Source"))' /tmp/sigma-api.json
jq '.components.schemas.JoinSource, .components.schemas.SqlSource, .components.schemas.DataModelSource' /tmp/sigma-api.json
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

## join

Joins multiple warehouse tables into one logical source. Specify a `primarySource` and an array of `joins`. Each join has `left`, `right`, `columns` (the join keys), `name` (used as the prefix in column formulas — `[<name>/column]`), and `joinType`.

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

`joinType` values: `inner`, `left-outer`, `right-outer`, `full-outer`, `cross`.

**Column formula prefixes with joins** — see `formulas.md` for the full rules:
- Primary-source columns use the **join's top-level `name`**: `[Sales Star/Order Number]`
- Joined-table columns use the **join leg's `name`**: `[Sales/Cust Key]`
- Warehouse path segments are **not** used as prefixes inside a join.

### When to reach for `join` instead of `Lookup()`

If you're tempted to define a column on element A as `Lookup([B/Field], [A.key], [B.key])` **and then group a chart by that column**, stop — switch A's source to a `join` instead. Sigma's chart rollup engine can only aggregate against one external relation per query, and a `Lookup()` used as a *grouping dimension* counts as a second one. The failure mode is brutal:

- POST + readback both say `[ok]`.
- `verify-workbook` (compile-check) returns `[ok]`.
- The chart renders with a **single row** whose dim value is the literal string `"Rollup cannot reference more than one external relation"`. No error anywhere in the response — Sigma silently substitutes the error message for the dim value.

`Lookup()` is still fine when the looked-up column feeds a **scalar measure** (numerator / denominator inside an aggregate). The failure is specifically `Lookup` → `xAxis.columnId` / `rowsBy` / `color.column` / any grouping role.

Fix: make A a `join` source with the other table as a join leg, then reference the field as `[<join-leg-name>/Field]` directly. Single relation, one query, clean rollup.

Verified 2026-05-22 on the `Employee Overview` workbook (`50fcece5-...`): a Top-10 chart grouped by `Lookup([Employees/Full Name], [Employee Id], [Employees/Employee Id])` on `time_master` blanked out with the error-string dim. Switching `time_master.source` to a `join` (TIME_ENTRIES left-outer EMPLOYEES on Employee Id) and rewriting the grouping column to `[Employee/First Name] & " " & [Employee/Last Name]` produced the real top-10 names.

## Other Source Kinds

These exist but are less common; model the shape off an existing workbook's spec via `GET /v2/workbooks/<id>/spec`:

- `sql` — custom SQL query
- `union` — combines two or more sources row-wise. See below.
- `transpose` — transposes rows/columns

## union

Combines two or more warehouse-table or element sources into a single source whose columns are explicitly mapped via `matches[]`.

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
