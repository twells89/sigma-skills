# Input tables — operational guide

> **Spec shape lives in `tables.md`** (the "Input tables" section there covers
> `inputMode`, `source` kinds, and the four column shapes). This file is the
> operational supplement: what has to be true *around* the spec for an input
> table to actually work, and how to read the data back.

Input tables are workbook elements that support **structured data entry** —
forecasting, what-if, manual augmentation — and write the entered values back to
the warehouse. Use them when the user wants to *type or upload data*, not just
read it. Other elements (tables, charts, KPIs) can then source from the input
table, and a data model can read it through a warehouse view.

## Requirements & lifecycle

1. **Write-enabled connection required.** `source: { kind: empty, connectionId }`
   must point at a connection with `writeAccess: true` (`GET /v2/connections`).
   A non-write connection fails at POST. Linked tables (`kind: linked`) inherit
   the parent's connection.
2. **Data lands in `SIGDS_`-prefixed tables** in the connection's write schema.
   Don't query or modify those directly — see "Reading the data" below.
3. **Data is invisible until Publish.** A query of an input table before the
   workbook is published returns **0 rows** — the query layer reads the
   published version. Publish, then re-query.
4. **System columns take no `type`** (`ID`, `CREATED_AT`, `CREATED_BY`,
   `UPDATED_AT`, `UPDATED_BY`) — adding one breaks the column.

## Three types

| Type | What it is | Source shape |
|---|---|---|
| **Empty** | Blank table; rows added/typed/pasted from scratch | `source: { kind: empty, connectionId }` |
| **CSV** | Pre-populated from a CSV upload, then editable | created from an upload (UI); element is otherwise an empty-style input table |
| **Linked** | Child of a parent element; key columns bind rows to the parent, entry/formula columns sit alongside | `source: { kind: linked, from: <parentElementId> }` + `{ id, key }` columns |

**Linked tables are spec-authorable** — `source.kind: linked` + `from` + key
columns POST and round-trip cleanly (re-verified 2026-06-11, including a
cross-element formula column). Earlier API versions (pre the 2026-06-11
release) serialized linked tables lossily — inherited columns re-POSTed as
"multiple values" — and on orgs without the feature flag they were dropped from
`/spec` entirely. If a linked table's inherited columns misbehave after a POST,
suspect an older org/API before suspecting the spec.

UI-only remains UI-only: column-level **data validation** (single/multi-select
dropdowns — "coming soon" in the spec), **column protection**, and
**data-entry permissions** are configured in the UI and are not in the element
spec.

## Reading an input table's data & structure

`SIGDS_` write-back tables aren't directly queryable. To read the data, create a
**warehouse view** for the input table (UI: input-table element → *Warehouse
views → Create new*), then `SELECT … FROM <db>.<schema>.<view>`.

To inspect an input table's **structure regardless of `/spec`** (handy on older
orgs where linked tables are hidden from `/spec`, or for a quick column dump),
use the element endpoints (linked columns label as `Col (ParentName)`):

```bash
# list every element (incl. input tables hidden from /spec on older orgs)
GET /v2/workbooks/{workbookId}/elements
GET /v2/workbooks/{workbookId}/pages/{pageId}/elements
# column-level detail: labels, formulas (linked refs show as [Parent/Col]), types
GET /v2/workbooks/{workbookId}/elements/{elementId}/columns
```

## Migration pattern

For data-entry migrations (Excel/planning models) the end-to-end pattern is
input table → publish → warehouse view → data model `FROM` that view. The
`excel-to-sigma` skill covers it in depth.
