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

## Linked input tables — UI-authored only (spec is LOSSY)

A linked input table links to a **parent element**; linked columns inherit live
values from the parent (keyed by a primary key), and you add editable entry/calc
columns alongside. **Create these in the UI.** The workbook spec does NOT
faithfully author them.

> **⚠️ Do not author linked input tables via `POST /v2/workbooks/spec` — verified
> broken 2026-06-10.** `GET /spec` *serializes* a linked table (you'll see the
> shape below), but the serialization is **lossy**: re-POSTing that exact spec
> produces an input table whose **inherited columns don't resolve** — every row
> shows **"multiple values"** (the linked column pulls the whole parent column
> instead of the key-correlated value). **Publishing does not fix it.** The
> key-correlation the UI sets up is server-side state that isn't captured in the
> spec. Proven by re-POSTing a known-good UI-built linked table verbatim → broken.
>
> What a POST *can* do: create the element with the **primary key** + **grain**
> (PK rows populate from the parent) + **editable entry columns**. What it
> **cannot** do: make the **inherited/linked columns** resolve. If you need the
> linked context columns to show values, the table must be built/edited in the UI.

The (read-only) serialized shape, for recognition when reading a UI-built one:

```yaml
- id: mBdVfGs8AU
  kind: input-table
  source: { kind: linked, from: dkOft2LaKd }   # parent element id
  inputMode: explore
  columns:
    - { id: 0D1QPVNF7P, key: sx6TLZDS4e }       # PK → parent column id (grain; populates on POST)
    - { id: icab1X9-kO, formula: '[D_STORE/Store Name]' }  # linked col — does NOT resolve via POST
    - { id: EW_Q68X8O0, type: text }            # entry col — works via POST
    - { id: UPDATED_AT }                        # system cols
    - { id: UPDATED_BY }
```

To **read/audit** a UI-built linked table, use the element endpoints (the column
labels show linked columns as `Col (ParentName)`):
`GET /v2/workbooks/{id}/elements` and `…/elements/{id}/columns`.

> **Cross-org note.** On an org without the linked-table feature enabled, a
> linked-table workbook's input-table elements may be **absent** from `GET /spec`
> entirely (only the container serializes). Empty input tables round-trip via the
> spec regardless (see above); only *linked* tables have the authoring gap.

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
