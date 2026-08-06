# Workbook Spec Validation

Validation runs in three phases: **dry-run** (section 1) hits Sigma's own compiler with zero persistence, catching most reference/schema errors before a real workbook exists; **pre-submit** (sections 2–4) is a fast offline backstop over the spec text; **post-create** (section 5) catches what only manifests once live data and a real query are involved. All three matter — silent compilation failures are the largest hidden failure mode.

Load this file before any POST or PUT.

## 1. Dry-run: `POST /v2/workbooks/spec/verify` (Beta)

```bash
./scripts/wb-rep.rb verify /tmp/workbook-spec.yaml
```

`/v2/workbooks/spec/verify` is a private Beta endpoint. Runs the same validation as a real create/update — including whether every `[Source/column]` reference actually resolves — but persists nothing. Prints `valid: true`, or `valid: false` plus each failure's `errors[].summary` (exit code mirrors this: 0 valid, 1 invalid). Do this first: most reference/schema mistakes get caught right here instead of surviving to a real create. It can't catch anything that only manifests against live data — that's what section 5 is for. Pass it a normal flat spec file, same as you'd hand `push`/`import` — `wb-rep.rb verify` handles the envelope described in the note below for you.

> **Envelope note (2026-08-04, corrects an earlier 2026-08-03 note that misdiagnosed this):** as of this writing, `/v2/workbooks/spec/verify` — and the real `POST /v2/workbooks/spec` create endpoint right alongside it, plus `PUT /v2/workbooks/{id}/spec` and `GET /v2/workbooks/{id}/spec` — require the request/response body wrapped as `{name, folderId, document: {schemaVersion, kind: "workbook", pages, layout}}` (PUT sends just `{document: {...}}`), not the flat `{name, folderId, schemaVersion, pages, layout}` shape this codebase assumed before this fix. This is **not** `/verify` drifting from its own documented schema in isolation — every workbook-spec endpoint moved together, away from what their shared OpenAPI text still documents (that OpenAPI asset is confirmed stale on this exact point — see `SKILL.md`'s *Sources of truth*). **Docs fixed as of this pass:** `reference/specification/schema.md` (the canonical top-level shape), `reference/workflows/crud.md`, `SKILL.md`'s create/iterate steps, and this repo's other spec examples (`example-full.yaml`, `comparative-kpi-card.yaml`, `agents.md`, `styling.md`) now document the wrapped shape. On-disk rep files (`workbook.yaml`, `.sigma/snapshot.yaml`) are intended to **stay flat by design** — the wrapping/unwrapping is meant to happen only at the API boundary, right after a GET and right before a POST/PUT, so a rep directory's flat files are not themselves a bug. Whether every `wb-rep.rb` write/read path (`push`/`pull`/`import`/`assemble`, not just `verify`) actually implements that boundary wrapping is tracked as a companion script fix — check `scripts/wb-rep.rb` directly (or its test suite) before trusting a specific subcommand against a live org. The data-model surface (`/v2/dataModels/.../spec`, `scan-data-models.rb`) is unaffected by any of this and stays flat.
>
> This isn't resting on the live probe alone anymore: Sigma's own stable per-endpoint reference pages corroborate it independently — `https://help.sigmacomputing.com/reference/create-workbook-spec` and `https://help.sigmacomputing.com/reference/verify-workbook-spec` both currently show the request body as `{name, folderId, document: {schemaVersion, kind, pages, layout}}`, and `https://help.sigmacomputing.com/reference/update-workbook-spec` (PUT against an existing workbook) shows just `{document: {...}}`. Unlike a content-addressed docs asset, these paths don't rotate on a docs redeploy, so this citation stays checkable going forward — re-fetch the same URLs to confirm the envelope requirement is still (or no longer) in force.

## 2. Run the bundled validator

```bash
./scripts/validate-spec.sh /tmp/workbook-spec.yaml
```

The validator catches the most common failure: bare bracketed refs (`[column]` without a `/`) that don't match any column defined in the same element's `columns[]` array. Fix everything it reports before continuing. If it exits 0, proceed to the manual pass.

## 3. Manual formula pass

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

## 4. Final shape checks

Also check for these rarer issues:

- A column's `formula` references a name matching its own `name` field → circular reference.
- A formula references a column name that doesn't exist on the source (re-confirm column names with the user).
- Donut charts require `value.id` (the measure) and `color.id` (the slice dimension) — **not** `value.columnId`. `holeValue` is **optional**; if set it must reference a *different* column than `value.id` (see `reference/specification/charts.md`).
- Layout XML: no `<LayoutElement type="grid">` with children — use `<GridContainer>` for nesting.

## 5. Post-create verification (do not skip)

`POST /v2/workbooks/spec` (unlike the dry-run in section 1) is generous once real data is behind it: a formula can resolve fine against the schema but still fail *at query time*, and Sigma surfaces that by embedding the error as a string literal in the compiled SQL:

```sql
select V_44 "Total Revenue" from (select 'Unknown column "[ORDER_TOTAL]"' V_44) Q1
select V_11 "Quarter" from (select distinct 'Circular column reference to [Quarter]' V_11 ...) Q1
```

The UI renders these elements as empty. Section 1's dry-run catches most bad references before you ever create anything — but it validates the representation with zero persistence, so anything that only shows up once a real query runs against live data still needs this step.

After every CREATE and after every PUT that touches columns or formulas, run:

```bash
./scripts/verify-workbook.sh <workbookId>
```

It hits `GET /v2/workbooks/<id>/elements/<eid>/query` for each element and reports any whose SQL contains the error markers above. Treat a non-zero exit the same as a failed POST — fix the spec and re-PUT.

The most common causes of post-create failure:

- **Bare warehouse refs.** `Sum([ORDER_TOTAL])` instead of `Sum([ORDERS/ORDER_TOTAL])`. The single biggest trap; see `reference/specification/formulas.md`.
- **Friendly-name mismatch.** The columns endpoint returns raw warehouse names (`V userId`, `UNIT PRICE`); formulas need Sigma's normalized friendly names (`V User Id`, `Unit Price`). Sigma is permissive at POST and normalizes casing for many simple cases, but won't rescue all of them. When in doubt, GET the spec back after a successful create — Sigma's readback shows the canonical names — and use those for any subsequent PUT.
- **Circular reference.** A column named `Quarter` with formula `[Quarter]` — easy to write when copying warehouse column names verbatim into a sibling-reference position. Rename one side.

## Decoding Cryptic Validation Errors

Server-side validation errors point at a JSON path but don't say what shape was expected. Use the path as the root-cause hint, then check the spec reference file for that feature to compare shapes.

| Error pattern | Most likely cause | Where to look |
|---------------|-------------------|---------------|
| `Invalid kind: pages[0].elements[N], got "..."` | Almost always the element's **inner shape** is wrong for the `controlType`/`kind` it claims, **not** that the kind is unsupported. Sigma's parser picks a schema by `kind` + `controlType` and reports the parent path when the inner match fails. | `reference/specification/controls.md` (slider is the most common trap), or the relevant element file (`charts.md`, `kpis.md`, `tables.md`). |
| `Invalid value: pages[0].elements[N].filters[M], got object` | The field is typed as an array of a specific shape and you sent something that doesn't match. | A working reference workbook (`GET` an existing workbook) for that exact field. |
| `Invalid kind: pages[0].elements[N].columns[M]` | Usually missing `id`, `name`, or `formula`, or `format.kind` mismatched. | `reference/specification/formatting.md`. |
| **Silent bad data** — no error, but the value/element is missing or `null` on readback | (a) A boolean-operator formula written as a function call (`Not(...)` instead of `Not ...`) — parses successfully but evaluates to `null` per row; (b) layout XML naming an `elementId` that doesn't exist on the page (typo or wrong id). | `formulas.md` for (a), `layout.md` for (b). All under `reference/specification/`. |

**General strategy:** the error path names the offending field; the spec reference file for that feature shows the shape. If after checking both you still can't see the mismatch, fetch a known-good reference workbook via `GET /v2/workbooks/<id>/spec` (with `Accept: application/json`) and diff your shape against it.
