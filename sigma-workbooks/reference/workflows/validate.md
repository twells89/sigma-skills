# Workbook Spec Validation

Pre-submit validation. Load before any POST or PUT.

## 1. Run the bundled validator

```bash
./scripts/validate-spec.sh /tmp/workbook-spec.json
```

The validator catches the most common failure: bare bracketed refs (`[column]` without a `/`) that don't match any column defined in the same element's `columns[]` array. Fix everything it reports before continuing. If it exits 0, proceed to the manual pass.

## 2. Manual formula pass

After the validator passes, do a final mechanical pass on every formula in the spec. **Do not skip to submission until every formula has been checked.**

For each column's `formula`:

1. **List every bracketed reference** in the formula. E.g., `Sum([Master/Sales]) - [Cost]` → refs are `Master/Sales` and `Cost`.
2. **For each reference, it must resolve to exactly one of:**
   - A **sibling** — the portion inside the brackets (no `/`) exactly matches a `name` in THIS element's `columns[]` array.
   - A **qualified ref** — contains `/`, and the prefix matches one of:
     - The last segment of the `path` array (if source is `warehouse-table`)
     - Another element's `name` (if source is `table` referencing that element)
     - A join leg's `name`, or the join's top-level `name` for `primarySource` columns (if source is `join`)
3. **If a reference doesn't match either, the formula is wrong.** The most common fix is adding the source prefix — see the wrong/right example at the top of `reference/specification/formulas.md`.

## 3. Final shape checks

Also check for these rarer issues:

- A column's `formula` references a name matching its own `name` field → circular reference.
- A formula references a column name that doesn't exist on the source (re-confirm column names with the user).
- Donut charts have a `holeValue` field (required).
- Layout XML: no `<LayoutElement type="grid">` with children — use `<GridContainer>` for nesting.

## Decoding Cryptic Validation Errors

Server-side validation errors point at a JSON path but don't say what shape was expected. Use the path as the root-cause hint, then check the spec reference file for that feature to compare shapes.

| Error pattern | Most likely cause | Where to look |
|---------------|-------------------|---------------|
| `Invalid kind: pages[0].elements[N], got "..."` | Almost always the element's **inner shape** is wrong for the `controlType`/`kind` it claims, **not** that the kind is unsupported. Sigma's parser picks a schema by `kind` + `controlType` and reports the parent path when the inner match fails. | `reference/specification/controls.md` (slider is the most common trap), or the relevant element file (`charts.md`, `kpis.md`, `tables.md`). |
| `Invalid value: pages[0].elements[N].filters[M], got object` | The field is typed as an array of a specific shape and you sent something that doesn't match. | A working reference workbook (`GET` an existing workbook) for that exact field. |
| `Invalid kind: pages[0].elements[N].columns[M]` | Usually missing `id`, `name`, or `formula`, or `format.kind` mismatched. | `reference/specification/formatting.md`. |
| **Silent bad data** — no error, but the value/element is missing or `null` on readback | (a) Formula with a boolean-operator space bug (`Not(...)` → `null`); (b) layout XML naming an `elementId` that doesn't exist after CREATE remapped IDs; (c) a known round-trip gap (e.g., `number-range` `values`). | `formulas.md` for (a), `layout.md` for (b), `controls.md` for (c). All under `reference/specification/`. |

**General strategy:** the error path names the offending field; the spec reference file for that feature shows the shape. If after checking both you still can't see the mismatch, fetch a known-good reference workbook via `GET /v2/workbooks/<id>/spec` (with `Accept: application/json`) and diff your shape against it.
