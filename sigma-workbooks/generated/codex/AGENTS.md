<!--
Auto-generated from SKILL.md by ~/sigma-skills/scripts/sync-targets.rb.
Do not edit by hand — edit SKILL.md and re-run the script.
-->

> Build, edit, and iterate on Sigma workbook specs — the YAML/JSON definition of pages, layout, controls, charts, KPIs, tables, formulas, and sources — by calling the Sigma REST API directly. Use when the user wants to construct a dashboard or workbook from a spec, add or modify pages/elements/controls/ formulas, validate a spec before submission, or iterate on pre-release workbook spec endpoints. Requires an SIGMA_API_TOKEN — obtain via the sigma-api skill first.

# Sigma Workbooks (Build from Spec via REST API)

Build Sigma workbooks programmatically by calling the Sigma REST API directly with `curl`. Every step hits the API over HTTP.

**Auth:** Authenticate via the `sigma-api` skill first to set `$SIGMA_BASE_URL` and `$SIGMA_API_TOKEN`. See `sigma-api` for cloud details.

Use this skill when:
- The user has OAuth credentials and wants to build, edit, or inspect a workbook from a spec.
- Iterating on spec endpoints that aren't in the public docs yet.

Deployment workflows (version control, git-based promotion) are out of scope.

## Reference Index

The reference is feature-sliced — don't read every file up-front. The index below has two parts: **specification** (what a workbook spec IS) and **workflows** (how to take a spec through its lifecycle).

### Specification Index

| File | When to load |
|------|--------------|
| `reference/specification/schema.md` | Always — load before drafting any spec. Top-level shape, required fields, response-only fields to strip. |
| `reference/specification/formulas.md` | Always — load before drafting any spec. Formula syntax, qualification, special characters, the #1 mistake. |
| `reference/specification/sources-warehouse.md` | Always — load before drafting any spec. Warehouse-table source (Snowflake, BigQuery, Databricks, Redshift, Postgres/MySQL). |
| `reference/specification/sources.md` | Reference another chart/table/element, derive from existing element, join, combine tables, data model / semantic-layer source, custom SQL, union, transpose, unpivot. |
| `reference/specification/tables.md` | Table element, tabular data, data grid, spreadsheet-style list. Also element-level filters (top N, limit, rank), groupings (pivot, group by, roll up), and the `pivot-table` element kind. |
| `reference/specification/charts.md` | Chart, graph, visualization, line / bar / column / stacked / grouped / donut / pie / share-of / breakdown. |
| `reference/specification/kpis.md` | KPI, stat, big number, single value, metric card. |
| `reference/specification/controls.md` | Filter, dropdown, picker, multi-select, date range, date picker, text filter, number range, slider. |
| `reference/specification/text.md` | Text element / Markdown block — dashboard titles, descriptions, callouts, prose alongside charts. |
| `reference/specification/others.md` | Divider and image elements — small visual elements for dashboard polish. |
| `reference/specification/formatting.md` | Format, currency, percentage, date format, decimals — column formatting. |
| `reference/specification/layout.md` | Layout, grid, arrange, position, container, dashboard arrangement, layout XML. |
| `reference/specification/example-full.yaml` | A real multi-page reference spec (KPIs, charts, joins, controls, layout) — copy shapes from when in doubt. |

### Workflows Index

| File | When to load |
|------|--------------|
| `reference/workflows/discover.md` | Finding connections, tables, and column names. Load before composing a new spec. |
| `reference/workflows/crud.md` | POST / GET / PUT against the workbook spec endpoints. Load when creating, retrieving, or updating a workbook (covers create-required fields, the GET `Accept: application/json` gotcha, and PUT full-replacement + ID-remap semantics). |
| `reference/workflows/validate.md` | Pre-submit validation. Load before any POST or PUT (`validate-spec.sh` + manual formula checklist + decoding cryptic server errors). |

## Required Workflow

**Follow these steps in order. Do not skip steps.**

> **Schema drift:** if any API call returns an error about the request *shape* ("invalid argument", "unknown field", "missing required field", "unexpected property"), jump to **API schema mismatch** in Troubleshooting before retrying — that's the signal that this skill is out of date.

### Step 0 — Authenticate

Authenticate via the `sigma-api` skill. Then capture the user's `userId` and home folder:

```bash
USER_ID=$(curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/whoami" | jq -r '.userId')

HOME_FOLDER_ID=$(curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/members/$USER_ID" | jq -r '.homeFolderId')
```

### Step 1 — Find Reference Templates

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/templates" | jq .
```

Pick 1–2 templates whose names suggest similar content. **If no relevant templates, pick one at random.** The goal is to study spec structure, not match content exactly.

### Step 2 — Study a Reference Spec

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/json" \
  "$SIGMA_BASE_URL/v2/workbooks/<template-workbook-id>/spec" \
  > /tmp/reference-spec.json
```

Read the file closely — source structure, column ID patterns, formula syntax, element naming. The returned `pages` array is the same structure you'll pass when creating.

### Step 3 — Discover Data Sources

Load `reference/workflows/discover.md` for the full process. Quick summary:

1. `GET /v2/connections` — find the user's connection by name or type.
2. Ask the user for the table path; verify with `POST /v2/connection/<id>/lookup`.
3. Ask the user for the column names (or have them query the warehouse directly).

**Never invent column names** — only use names the user provides.

### Step 4 — Identify Features

Map the user's request to the **Specification Index** above. State the features you identified, then read the listed reference files before drafting.

### Step 5 — Draft the Spec to a Local File

Write the spec JSON to disk (e.g., `/tmp/workbook-spec.json`). Key rules:
- Every element needs a unique `id` and a descriptive `name`.
- Every column needs a unique `id`, a `name`, and a `formula`.
- Follow the column formula rules in `reference/specification/formulas.md` exactly — most errors happen here.
- Start with 1–2 pages. Add more later via update.

For **create**, the file must include top-level `name`, `folderId`, `schemaVersion`, and `pages` (`description` and `layout` are optional). Use the `schemaVersion` returned by the template `GET` in Step 2 — don't hardcode it. Full create / read / update mechanics are in `reference/workflows/crud.md`.

### Step 6 — Validate the Spec

**Run the bundled validator first — do not skip.**

```bash
./scripts/validate-spec.sh /tmp/workbook-spec.json
```

Then do the manual formula pass and final shape checks per `reference/workflows/validate.md`. Fix everything reported before continuing.

### Step 7 — Create the Workbook

```bash
curl -s -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/workbook-spec.json \
  "$SIGMA_BASE_URL/v2/workbooks/spec" > /tmp/create-response.json

WORKBOOK_ID=$(jq -r '.workbookId' /tmp/create-response.json)
cp /tmp/workbook-spec.json "/tmp/workbook-spec-${WORKBOOK_ID}.json"
```

Persist the spec after a successful create (last line above) so it survives the next build, the user can diff or re-POST it, and subsequent `PUT` updates can start from this file. Report **both** the workbook URL **and** the saved spec path.

If creation fails, read the error, fix the spec, re-validate, retry. See `reference/workflows/validate.md` for decoding cryptic errors. Don't give up after one failure.

### Step 8 — Iterate

After initial creation, use `PUT /v2/workbooks/<id>/spec` to add pages or refine the workbook.

> **Critical: IDs get reassigned on CREATE.** External `id` values in the POST are mapped to internal IDs and those internal IDs are what live references (especially the `layout` XML's `elementId` attributes) must use. Before **any** follow-up PUT, always GET the current spec first and use the readback IDs. See `reference/workflows/crud.md` for full details.

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/json" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec" \
  > /tmp/current-spec.json

# Edit /tmp/current-spec.json, then:
curl -s -X PUT -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/current-spec.json \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec" | jq .

cp /tmp/current-spec.json "/tmp/workbook-spec-<workbook-id>.json"
```

### Step 9 — Report Back

Report the workbook URL and the saved spec path. **Do not tack on a generic "improvement ideas" or "next steps" coda.** Match the response to what was asked.

Surface follow-up items only when they're load-bearing, and name them concretely:

- **Tradeoffs you made during the build** — dropped a chart, simplified a formula, skipped a control because the shape wasn't in the reference.
- **Obvious gaps revealed by the column list** — e.g., the user asked for "sales by region" and the table has a `region_tier` column that would make the breakdown richer. One sentence, named.
- **Known round-trip / normalization caveats that affect what the user will see** — e.g., `number-range` `values` won't round-trip (see `reference/specification/controls.md`).

If none apply, just report the URL + spec path and stop.

## Quick Formula Rules

See `reference/specification/formulas.md` for the full reference. The critical rules:

**Outside the element** — use `[SourceName/column_name]`:
- Warehouse table source: `SourceName` = last segment of the `path` array (e.g., `[ORDERS/Revenue]`)
- Another element: `SourceName` = that element's `name`
- Join legs: prefix by the leg's `name`, or by the join's top-level `name` for `primarySource` columns

**Inside the same element** — use `[column_name]` (no prefix):
- References a column defined in this element by its `name` field.
- A column cannot reference itself (circular reference error).

## Example

User: "Build me a sales dashboard from the ORDERS table in our Snowflake connection. Here's my client ID and secret."

1. Authenticate via `sigma-api` (export env, `eval "$(.../get-token.sh)"`).
2. `GET /v2/whoami` → userId. `GET /v2/members/<userId>` → homeFolderId.
3. `GET /v2/templates` — find a sales template.
4. `GET /v2/workbooks/<templateId>/spec` (with `Accept: application/json`) → study structure.
5. Discover: `GET /v2/connections` → Snowflake; ask user for ORDERS table path and column names.
6. Write `/tmp/workbook-spec.json` with `name`, `folderId`, `pages` — table sourced from ORDERS, columns for the discovered fields, a date control.
7. `./scripts/validate-spec.sh /tmp/workbook-spec.json`.
8. `POST /v2/workbooks/spec` → returns `workbookId`. Copy spec to `/tmp/workbook-spec-<workbookId>.json`.
9. Share **both** the workbook URL **and** the saved spec path.

## Troubleshooting

### API schema mismatch (possibly stale skill)

If a request fails with **"invalid argument"**, **"unknown field"**, **"unexpected property"**, **"missing required field"**, **"unrecognized parameter"**, or a 400 about request *shape* rather than data — the API has likely evolved since this skill was written.

In order:

1. **Tell the user.** Print:

   > ⚠️ This error looks like a schema mismatch between this skill and the current Sigma API. The skill may be out of date — try updating it:
   >
   > ```
   > /plugin update sigma-computing@sigma-computing
   > ```
   >
   > I'll try to work around it in the meantime by consulting the live Sigma API docs.

2. **Fetch the current OpenAPI spec:** `https://help.sigmacomputing.com/openapi/sigma-computing-public-rest-api.json`. Use `WebFetch` (preferred) or:

   ```bash
   curl -sf https://help.sigmacomputing.com/openapi/sigma-computing-public-rest-api.json \
     | jq '.paths."/v2/workbooks/spec"'
   ```

3. **Diff** the live spec vs. the skill's assumed shape — renamed fields, new required fields, removed fields, type changes.

4. **One automated retry** with the corrected shape. If it succeeds, tell the user exactly what changed and still recommend they run the plugin update.

5. **If the endpoint isn't in the public spec**, skip step 3, surface the raw error, and recommend waiting for a skill update.

6. **Do not loop.** One retry, then stop.

### 401 Unauthorized

Token missing or expired. Re-authenticate via `sigma-api`. If still failing, verify credentials and base URL.

### 403 Forbidden on workbook create

The credentials authenticated but aren't permitted to create workbooks here. Ask your Sigma admin to confirm the credential's permissions and folder access.

### "Invalid column reference" or formula errors on creation

The most common issue. A bare `[column_name]` was used where `[TABLE/column_name]` is needed. See `reference/specification/formulas.md` for the full rules and `reference/workflows/validate.md` for the manual checklist.

### "Unknown column" errors

The column name in the formula doesn't match what the warehouse actually has. Re-confirm the column names with the user (or have them query the warehouse) and use those names verbatim.

### `jq` not installed

`brew install jq` (macOS) or `apt install jq` (Debian/Ubuntu).

### Cryptic validation errors / silent bad data

See `reference/workflows/validate.md` for the full triage table (mapping `Invalid kind: pages[0].elements[N]...` style errors to the right spec file).
