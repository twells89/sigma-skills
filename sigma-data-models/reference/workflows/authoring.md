# Authoring — Judgment Calls When Building a Data Model

Mechanics live in `crud.md`. This file is the "how should I structure this?" guidance for someone composing a new data model from scratch.

## One big model vs. many small ones

A Sigma data model is a graph of elements (tables, derived elements, SQL sources) connected by relationships. There's no hard limit, but readability and load time degrade past ~30–40 elements.

- **One model per analytic domain.** Sales, marketing, ops — each gets its own model. Don't try to fit everything in `Master Model`.
- **Reuse via workbook-level joins** if two domains rarely overlap. A workbook can source columns from two different models on the same page; you don't have to merge them.
- **Split a model** when more than half its elements are unused by any consumer; the unused ones add load time and visual clutter without benefit.

## SQL source vs. warehouse-table source

| Use a `warehouse-table` source when… | Use a `sql` (custom SQL) source when… |
|---|---|
| The table is already shaped the way you want it. | The shape requires a JOIN, UNION, or window function the model can't express directly. |
| You want column-level lineage and CLS to flow naturally. | You're depending on a vendor-specific SQL feature (e.g., Snowflake `MATCH_RECOGNIZE`, BigQuery `STRUCT` flattening). |
| The table is small enough to query live. | A pre-computed view exists in the warehouse and you want to surface it as-is. |
| You want push-down to be obvious to the reader. | Performance demands a materialized intermediate table the model can pin to. |

Default to `warehouse-table`. Reach for `sql` only when you have a concrete reason — every SQL source is one more thing for someone else to debug six months from now.

## Joins in the model vs. joins in workbooks

Both are valid; they have different ergonomics.

**Model-level joins (`relationships`):**
- Pros: every workbook that sources the model gets the joined columns "for free". Lineage and CLS flow consistently.
- Cons: if a workbook only needs one side, the join still executes. Wider blast radius when a key changes.

**Workbook-level joins (`source.kind: "join"`):**
- Pros: scoped to one workbook. No effect on other consumers of the underlying model.
- Cons: every new workbook re-defines the same join. Easy to drift apart over time.

Rule of thumb: **if more than two workbooks need the join, put it in the model.** If it's a one-off (e.g., enriching a dashboard with a temporary cohort table), keep it in the workbook.

## Naming conventions

- **Element names** — natural language, capitalized. `Orders Fact`, `Customer Dimension`, `Daily Sales Snapshot`. The element name shows up everywhere downstream (workbook formulas, lineage views, search) — make it readable.
- **Column display names** — Title Case (`Order Id`, not `ORDER_ID`). The MCP / converter tool handles `SNAKE_CASE → Title Case` automatically; if you're hand-authoring, do it yourself.
- **Metric names** — start with the verb (`Sum of Revenue`, `Average Order Value`, `Active Customer Count`). Avoid bare nouns; they collide with column names.
- **Relationship names** — `<source> to <target>` (`Orders to Customers`). The relationship name appears in formulas as the prefix when referencing the joined table.

## Where to put metrics: model vs. column vs. workbook

| Kind | Lives on… | Use when |
|---|---|---|
| Metric (model-level) | An element's `metrics` array | The aggregation is canonical for that table — `Total Revenue`, `Active Customers`. Should be the same number in every workbook that uses the model. |
| Calculated column (model-level) | An element's `columns` array as a derived formula | Per-row derivation like `Revenue - Cost` or `If([Status]="Active", 1, 0)`. Makes sense to compute once at the model layer if multiple workbooks need it. |
| Workbook calc | The workbook's `columns` on the chart/table | One-off calculation only that workbook cares about. Don't pollute the model with workbook-specific math. |

## Folder & workspace placement

- New colleagues' models default to **`My Documents`** unless told otherwise. That's fine for prototyping.
- Once a model is consumed by a published workbook, move it to a **shared workspace** (e.g., `Marketing Workbooks`, `Operations`) so it's discoverable and grant-controlled. Don't leave production models in someone's home folder.
- Keep "scratch / WIP" models in a separate folder (`Dev`, `Sandbox`) so they're easy to clean up later.
- The `folderId` field on a model spec is required at create time. Use `GET /v2/files?typeFilters=folder` to find folder IDs.

## When to materialize

Materializing a model element pre-computes the result and stores it in the warehouse on a schedule. Consider it when:

- An element's query takes more than ~10s to render in interactive use.
- The same heavy aggregation is consumed by multiple workbooks.
- The underlying tables don't change often (daily snapshot models, monthly metric rollups).

Avoid for:

- Real-time / near-real-time data (materialization adds lag).
- Models still being authored — set up materialization once the shape stabilizes.
- Tiny tables where the query already runs in <1s.

See `crud.md` for the materialization API (`POST /v2/dataModels/{id}:materialize`).

## When stuck on shape

If you're guessing at how a field should look — especially after one or two failed `POST` attempts — **stop guessing and pull a known-working model's spec from the user's workspace**:

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/spec" > /tmp/reference.json
```

Diff against your draft. The canonical shape sitting in the user's workspace beats any guess. See `validate.md` for the full troubleshooting flow.
