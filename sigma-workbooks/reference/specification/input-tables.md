# Input tables

Input tables are workbook elements that support **structured data entry** —
forecasting, what-if, manual augmentation — and write the entered values back to
the warehouse. Use them when the user wants to *type or upload data*, not just
read it. Other elements (tables, charts, KPIs) can then source from the input
table, and a data model can read it through a warehouse view.

> Element kind: `input-table`. Requires a **write-enabled connection**
> (`GET /v2/connections` → `writeAccess: true`). Data is written to `SIGDS_`-
> prefixed tables in the connection's write schema (don't query/modify those
> directly — see "Reading the data" below).

## Three types

| Type | What it is | Source shape |
|---|---|---|
| **Empty** | Blank table; rows added/typed/pasted from scratch | `source: { kind: empty, connectionId }` |
| **CSV** | Pre-populated from a CSV upload, then editable | created from an upload (UI); element is otherwise an empty-style input table |
| **Linked** | Child of a parent element; inherits linked columns (incl. a primary key) and adds entry columns alongside live source data | `source: { kind: linked, from: <parentElementId> }` |

## Empty input table — spec shape (round-trips via `/spec`)

This is the part you can author and reliably read through the workbook spec
(`POST`/`GET /v2/workbooks/spec`). Verified on real workbooks.

```yaml
- id: forecastInput
  kind: input-table
  name: Forecast Entry          # the element TITLE — persists in the spec
  source:
    kind: empty
    connectionId: cb2f5180-…    # MUST be writeAccess: true
  inputMode: explore            # 'explore' (editable) | 'view'
  tableStyle:                   # same customization family as table elements…
    preset: presentation
  sort:                         # …including sort
    - columnId: QT9HNFOBOY
      direction: descending
      nulls: last
  columns:
    - id: REGION                # data-entry columns carry a `type`
      type: text
    - id: MONTH_DATE
      type: datetime
    - id: CATEGORY_CODE
      type: number
    - id: BILLABLE
      type: checkbox
    - id: FORECAST_AMOUNT
      type: number
    - id: ID                    # system columns: NO `type` (Sigma auto-manages)
    - id: CREATED_AT
    - id: CREATED_BY
    - id: UPDATED_AT
    - id: UPDATED_BY
```

**Titles & customizations** (the recently-added surface): the element `name` is
the visible title and it round-trips; `tableStyle` and `sort` round-trip too —
treat an empty input table like a `table` element for styling. Column-level
**data validation** (single/multi-select dropdowns), **column protection**, and
**data-entry permissions** are configured in the UI and are **not** in the
element spec.

**Column types:** `text`, `number`, `datetime`, `checkbox`. System columns —
`ID` (Row ID) and the row-edit-history set `CREATED_AT/CREATED_BY/UPDATED_AT/
UPDATED_BY` — auto-populate and take no `type`.

## Linked input tables

A linked input table links to a **parent element** (any element — a table, a
data-model-sourced element, even another input table). Linked columns inherit live
values from the parent; you add your own entry and calc columns alongside. It
round-trips through `/spec` (on orgs where the feature is enabled) — verified shape:

```yaml
- id: mBdVfGs8AU
  kind: input-table
  source:
    kind: linked
    from: dkOft2LaKd            # the PARENT element id this links to
  inputMode: explore
  sort:                         # customizations (sort/tableStyle/name) round-trip
    - columnId: 0D1QPVNF7P
      direction: ascending
      nulls: connection-default
  columns:
    - id: 0D1QPVNF7P
      key: sx6TLZDS4e           # PRIMARY KEY — `key` = the PARENT column id that
                                #   provides the row identifier
    - id: icab1X9-kO
      formula: '[D_STORE/Store Name]'   # LINKED column — inherits live parent value
    - id: EW_Q68X8O0
      type: text                # OWN entry column (editable)
    - id: UPDATED_AT            # system edit-history columns (no type)
    - id: UPDATED_BY
```

The three column forms in a linked input table:

- **Primary key** — `{ id, key: <parentColumnId> }`. `key` references the parent
  element's column id and provides the row identifier. **Must reference static
  parent values** — don't use `RowNumber()`/computed keys (they break referential
  integrity when rows shift).
- **Linked column** — `{ id, formula: '[Parent Element/Column]' }`. Inherits live
  parent values via the cross-element reference convention (see `sources.md` →
  `table`); not editable.
- **Own entry / calc column** — `{ id, type: text|number|datetime|checkbox }` for
  data entry, or a `formula` for a calc column. Editable.

> **Feature flag + cross-org caveat (verified 2026-06-10).** Linked input tables
> are gated. On an org where the feature is **enabled**, they author and round-trip
> through `/spec` exactly as above. On an org **without** it, a linked-table
> workbook's input-table elements were *absent* from `GET /spec` (only the
> surrounding container serialized) — there, fall back to the `/elements`
> endpoints below to read them. Empty input tables round-trip regardless.

## Reading an input table's data & structure

`SIGDS_` write-back tables aren't directly queryable. To read the data, create a
**warehouse view** for the input table (UI: input-table element → *Warehouse
views → Create new*), then `SELECT … FROM <db>.<schema>.<view>`.

To inspect an input table's **structure regardless of `/spec`** (handy when the
linked-table feature flag is off, or for a quick column dump), use the element
endpoints:

```bash
# list every element (incl. input tables hidden from /spec)
GET /v2/workbooks/{workbookId}/elements
GET /v2/workbooks/{workbookId}/pages/{pageId}/elements
# column-level detail: labels, formulas (linked refs show as [Parent/Col]), types
GET /v2/workbooks/{workbookId}/elements/{elementId}/columns
```

## Gotchas

1. **Data is invisible until Publish.** A query of an input table before the
   workbook is published returns **0 rows** — the query layer reads the published
   version. Publish, then re-query.
2. **Write connection required** — a `kind: empty` source on a non-write
   connection fails.
3. **System columns take no `type`** — adding one breaks the column.
4. **For data-entry migrations** (Excel/planning models) the end-to-end pattern is
   input table → publish → warehouse view → data model `FROM` that view. The
   `excel-to-sigma` skill covers it in depth.
