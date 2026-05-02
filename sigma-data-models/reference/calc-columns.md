# Calculated Columns

Calculated columns are columns whose value is derived from a formula rather than read from the warehouse. They live in the same `columns` array as warehouse columns on an element.

## Shape

```json
{
  "id": "<short-id>",
  "name": "Profit",
  "formula": "[Revenue] - [Cost]"
}
```

A calc column has no warehouse-column ID prefix — its `id` is a generated short alphanumeric, not `inode-<22>/COL`. The `formula` is what makes it a calc column.

## Formula references

- **Within the same element** — bare `[Column Name]` (case-sensitive, must match a column's `name` field on the same element).
- **Cross-element** — `[Element Name/Column Name]`. The element name is the source element's `name`.
- **From a warehouse-table source** — `[TABLE_NAME/Column Display Name]` where `TABLE_NAME` is the last segment of the source's `path` (uppercase, as it appears in the warehouse).

A calc column **cannot reference itself**, even transitively — the server rejects circular references.

## Window functions don't work in DM element calc columns

`CountOver`, `SumOver`, `RowNumberOver`, `RankOver`, and other window-style functions silently fail when used as a formula on a calculated column **inside a data model element**. The column's `error` flag flips on without a clear UI signal, and any downstream chart that references the column blanks out.

This is independent of the underlying SQL — the same formula works fine in a workbook calc column on most element types, but **not** on a workbook master table that's sourced from a data model (the workbook table inherits the DM-side restriction).

### Workarounds

| If you need… | Do this |
|---|---|
| A running total or rank by group on warehouse data | Push the calculation to a `sql` source — write the window function in SQL once, expose the result as a regular warehouse column. |
| A row-number-by-group at view time | Move the calc to a workbook-level table that's **not** sourced from the DM (i.e., sources directly from warehouse-table). Window functions are allowed in those contexts. |
| A simple cumulative metric | Express it as a metric on the model with `Sum / Count / etc.` — metrics aggregate across rows, which gets you most of what `SumOver` would. |

### Side effect to know about

When a calc column on a DM element is set to an unsupported formula and the model is saved via API, **the element's column IDs may be reassigned** on the next read. Always re-`GET` the spec after a save before composing any update — don't trust your last-known IDs.

## Common errors

- **"Invalid column reference"** — bare `[col]` where a prefix was needed, or a misspelling. Re-check column names against the source via `discover.md`.
- **Column shows `error` icon, formula looks fine** — likely a window function. Try a simpler aggregation; if that works, the window function is the issue.
- **Chart that references this column blanks out** — the calc column is in error state. Fix the formula; the chart will recover on the next render.

See `formulas.md` (in the `sigma-workbooks` skill) for the full formula language reference, including the function list. The data-model side uses the same formula syntax with the constraints noted here.
