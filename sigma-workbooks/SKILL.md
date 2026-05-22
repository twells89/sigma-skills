---
name: sigma-workbooks
description: >-
  Build, edit, and iterate on Sigma workbook specs — the JSON definition you
  POST to /v2/workbooks/spec, covering pages, layout, controls, charts, KPIs,
  tables, formulas, and sources. The Sigma OpenAPI is the source of truth for
  every shape and field; this skill adds navigation, style guidance, and
  proven recipes for effective dashboards. Use when the user wants to
  construct a dashboard from a spec, add or modify pages / elements /
  controls / formulas, validate a spec before submission, or work through
  the workbook spec lifecycle programmatically. Requires an SIGMA_API_TOKEN
  — obtain via the sigma-api skill first.
---

# Sigma Workbooks (Spec via REST API)

This skill helps you build effective Sigma workbooks by **navigating the Sigma OpenAPI** and applying **style guidance + proven recipes** beyond what the OpenAPI alone teaches.

## Scope

The workbook **spec** — the JSON you POST to `/v2/workbooks/spec` defining pages, elements, sources, formulas, and layout. Lifecycle around the workbook (embeds, grants, materialization schedules, bookmarks, sharing) is a separate API surface and out of scope here.

## Sources of truth

1. **Sigma OpenAPI** — canonical schema for every request/response shape and field.
   `https://help.sigmacomputing.com/openapi/sigma-computing-public-rest-api.json`
2. **Existing workbooks on the user's org** — concrete working specs, accessible via `GET /v2/workbooks/{id}/spec`.

Everything in this skill is commentary, style guidance, and recipes layered on top of those two sources. **When this skill and the OpenAPI disagree, the OpenAPI wins.** When a feature exists in the OpenAPI but isn't covered here, fetch the OpenAPI and use what it documents.

## Consulting the OpenAPI

Fetch once per session and inspect with `jq`. Always do this for features the skill doesn't cover, or whenever you suspect a field shape has changed:

```bash
curl -sf https://help.sigmacomputing.com/openapi/sigma-computing-public-rest-api.json > /tmp/sigma-api.json

# Workbook spec POST request body
jq '.paths."/v2/workbooks/spec".post.requestBody.content."application/json".schema' /tmp/sigma-api.json

# An element kind's full shape (replace with the schema name from the OpenAPI)
jq '.components.schemas.BarChart' /tmp/sigma-api.json
jq '.components.schemas.KpiChart' /tmp/sigma-api.json
jq '.components.schemas.Container' /tmp/sigma-api.json

# A source kind's full shape
jq '.components.schemas.JoinSource' /tmp/sigma-api.json
jq '.components.schemas.WarehouseTableSource' /tmp/sigma-api.json

# List every schema name (useful when you don't know the right name)
jq -r '.components.schemas | keys[]' /tmp/sigma-api.json | grep -i <hint>
```

`WebFetch` works for the JSON too. Either path is fine.

**Why bother:** the API ships new fields and element variants regularly; the skill lags. If you're drafting a spec and aren't sure whether a feature you want exists, the OpenAPI tells you in seconds. If you're between this skill's last update and the API's current state, the OpenAPI is the disambiguator.

## Auth

Authenticate via the `sigma-api` skill first to populate `$SIGMA_BASE_URL` and `$SIGMA_API_TOKEN`.

## Recommended Workflow

These are guidelines, not mandates — but they prevent the failure modes that show up most often when drafting from scratch.

> **Schema drift signal:** an error about request *shape* (`invalid argument`, `unknown field`, `missing required field`, `unexpected property`) usually means this skill is stale on that detail. Fetch the OpenAPI and compare; the canonical shape is there.

### Step 0 — Authenticate, capture user identity

```bash
USER_ID=$(curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/whoami" | jq -r '.userId')

HOME_FOLDER_ID=$(curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/members/$USER_ID" | jq -r '.homeFolderId')
```

If the user provided a **target image** (a screenshot, mockup, or PDF of a dashboard they want reproduced), pause here and load `reference/workflows/from-image.md` — it adds explicit observation, description, and validation steps that have to happen *before* normal data discovery. The standard workflow alone tends to produce workbooks with the right vibe but the wrong shape when the input is visual.

### Step 1 — Find a reference workbook to study

Any existing workbook on the user's org doubles as a template. List and pick one with similar content:

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks?limit=50" | jq '.entries[] | {workbookId, name}'
```

If no relevant workbook exists, pick any — the goal is studying spec structure, not matching content. If the org has no workbooks at all, draft from scratch using the OpenAPI shapes + this skill's recipes.

### Step 2 — Study the reference spec

YAML is the canonical format for workbook specs in this skill — easier to read, diff, and review than JSON. Sigma's API accepts both (`Content-Type: application/yaml` or `application/json`); `Accept: application/yaml` is the default on `GET /v2/workbooks/<id>/spec`. Use `yq` to inspect spec YAML the same way you'd use `jq` on JSON.

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<reference-workbook-id>/spec" \
  > /tmp/reference-spec.yaml
```

Look at source structure, column ID patterns, formula syntax, element naming, layout XML idioms. The `pages` array shape is exactly what you'll POST when creating. Capture the `schemaVersion` here — don't hardcode it.

### Step 3 — Discover data sources

Load `reference/workflows/discover.md`. Quick summary:

1. `GET /v2/connections` — find the user's connection by name or type.
2. Ask the user for the table path; verify with `POST /v2/connection/<id>/lookup`.
3. Discover columns directly via `GET /v2/connections/tables/{inodeId}/columns` (full mechanics in `reference/workflows/discover.md`). Only fall back to asking the user when the endpoint doesn't return what's needed.

**Never invent column names** — only use names returned by the API or supplied by the user.

### Step 4 — Identify features and load only what you need

Map the user's request to the **Reference Index** below. State the features you identified, then read the listed reference files before drafting. **If the user asks for a feature this skill doesn't cover**, fetch the OpenAPI and inspect the relevant schema.

### Step 5 — Draft the spec to a local file

Write the spec YAML to disk (e.g., `/tmp/workbook-spec.yaml`). YAML is preferred over JSON in this skill — easier to read, diff, and comment for human review. The API accepts either; pick YAML unless something downstream specifically needs JSON. Key rules:

- Every element needs a unique `id` and a descriptive `name`.
- Every column needs a unique `id`, a `name`, and a `formula`.
- Follow the formula reference rules in `reference/specification/formulas.md` exactly — most spec errors happen here.
- **Write explicit `layout` XML for multi-element workbooks.** Auto-arrange (omitting `layout`) is acceptable only for single-element pages or a uniform stack of tables. See `reference/specification/layout.md` for the rubric.
- Start with 1–2 pages. Add more later via update.

For **create**, the file must include top-level `name`, `folderId`, `schemaVersion`, and `pages`. `description` is optional. `layout` is technically optional but expected for multi-element workbooks. Use the `schemaVersion` returned by the reference-workbook `GET` in Step 2 — don't hardcode it. Full CRUD mechanics are in `reference/workflows/crud.md`.

### Step 6 — Validate the spec

**Run the bundled validator first — do not skip.**

```bash
./scripts/validate-spec.sh /tmp/workbook-spec.yaml
```

Then do the manual formula pass and final shape checks per `reference/workflows/validate.md`. Fix everything reported before continuing.

### Step 7 — Create the workbook

```bash
curl -s -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/workbook-spec.yaml \
  "$SIGMA_BASE_URL/v2/workbooks/spec" > /tmp/create-response.yaml

WORKBOOK_ID=$(yq -r '.workbookId' /tmp/create-response.yaml)
cp /tmp/workbook-spec.yaml "/tmp/workbook-spec-${WORKBOOK_ID}.yaml"
```

Persist the spec after a successful create so subsequent `PUT` updates can start from it. Report **both** the workbook URL **and** the saved spec path.

If creation fails, read the error, fix the spec, re-validate, retry. See `reference/workflows/validate.md` for decoding cryptic errors.

### Step 7b — Verify the workbook actually compiles

**Do not skip.** A successful POST is necessary but not sufficient — Sigma accepts specs whose formulas don't resolve, then surfaces the failures at query time by embedding the error as a string literal in the compiled SQL (`'Unknown column "[X]"'`, `'Circular column reference to [Y]'`). Affected elements render empty in the UI. Only Sigma's compiler knows whether your formula references actually resolve.

```bash
./scripts/verify-workbook.sh "$WORKBOOK_ID"
```

If any element reports `[FAIL]`, fix the column formulas in the spec (most often a missing source prefix, a self-referencing column, or a friendly-name mismatch with the warehouse — see `reference/specification/formulas.md`), `PUT` the corrected spec, and re-verify.

### Step 8 — Iterate

After initial creation, use `PUT /v2/workbooks/<id>/spec` to add pages or refine the workbook.

> **Critical: IDs get reassigned on CREATE.** External `id` values in the POST are mapped to internal IDs and those internal IDs are what live references (especially the `layout` XML's `elementId` attributes) must use. Before **any** follow-up PUT, always GET the current spec first and use the readback IDs. See `reference/workflows/crud.md` for full details.

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec" \
  > /tmp/current-spec.yaml

# Edit /tmp/current-spec.yaml, then:
curl -s -X PUT -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/current-spec.yaml \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec" | yq .

cp /tmp/current-spec.yaml "/tmp/workbook-spec-<workbook-id>.yaml"
./scripts/verify-workbook.sh "<workbook-id>"
```

### Step 9 — Report back

Report the workbook URL and the saved spec path. **Do not tack on generic "improvement ideas" or "next steps."** Match the response to what was asked.

Surface follow-up items only when they're load-bearing, and name them concretely:

- **Tradeoffs you made during the build** — dropped a chart, simplified a formula, skipped a control because the shape wasn't in your reference.
- **Obvious gaps revealed by the column list** — e.g., the user asked for "sales by region" and the table has a `region_tier` column that would make the breakdown richer. One sentence, named.
- **Known round-trip / normalization caveats that affect what the user will see** — e.g., `number-range` `values` won't round-trip (see `reference/specification/controls.md`).

If none apply, just report the URL + spec path and stop.

## Reference Index

The reference is feature-sliced — don't read every file up-front. The index has three sections: **elements** (the visual / interactive pieces), **sources** (where each element gets its data), and **cross-cutting** (formulas, layout, formatting, validation, CRUD).

### Elements

| File | When to load |
|------|--------------|
| `reference/specification/tables.md` | Table element, tabular data, data grid, spreadsheet-style list. Also element-level filters (top N, limit, rank), groupings (pivot, group by), the `pivot-table` element kind, and `conditionalFormats` (threshold-based cell coloring). |
| `reference/specification/charts.md` | Chart, graph, visualization, line / bar / column / stacked / grouped / donut / pie / share-of / breakdown. Includes the `color` channel on bar-chart. |
| `reference/specification/kpis.md` | KPI, stat, big number, single value, metric card. |
| `reference/specification/controls.md` | Filter, dropdown, picker, multi-select, date range, date picker, text filter, number range, slider. |
| `reference/specification/text.md` | Text element / Markdown block — dashboard titles, descriptions, callouts, prose alongside charts. |
| `reference/specification/containers.md` | Container element — placeholder + `backgroundImage` styling. Used together with layout XML's `<GridContainer>` to group elements. |
| `reference/specification/others.md` | Divider and image elements — small visual elements for dashboard polish. |

### Sources

| File | When to load |
|------|--------------|
| `reference/specification/sources-warehouse.md` | Always — load before drafting any spec. Warehouse-table source (Snowflake, BigQuery, Databricks, Redshift, Postgres/MySQL). |
| `reference/specification/sources.md` | Reference another chart/table/element, derive from existing element, join, combine tables, data model / semantic-layer source, custom SQL, union, transpose, unpivot. |

### Cross-cutting

| File | When to load |
|------|--------------|
| `reference/specification/schema.md` | Always — load before drafting any spec. Top-level shape, required fields, response-only fields to strip. |
| `reference/specification/formulas.md` | Always — load before drafting any spec. Formula syntax, qualification, special characters, the #1 mistake. |
| `reference/specification/formatting.md` | Format, currency, percentage, date format, decimals — column formatting. |
| `reference/specification/layout.md` | **Always load for multi-element workbooks.** Layout XML, GridContainer/LayoutElement, auto-arrange fallback rules, when to write explicit layout vs. omit. |
| `reference/specification/example-full.yaml` | A real multi-page reference spec (KPIs, charts, joins, controls, layout) — copy shapes from when in doubt. |

### Workflows

| File | When to load |
|------|--------------|
| `reference/workflows/discover.md` | Finding connections, tables, and column names. Load before composing a new spec. |
| `reference/workflows/crud.md` | POST / GET / PUT against the workbook spec endpoints. Load when creating, retrieving, or updating a workbook. |
| `reference/workflows/validate.md` | Pre-submit + post-create validation. Load before any POST or PUT. |
| `reference/workflows/from-image.md` | The user supplied a target image (screenshot, mockup, BI-tool export) to reproduce. Load *before* discovery — it adds explicit observation and validation steps. |

## Quick Formula Rules

The single most common spec error is bare `[column_name]` references to warehouse columns. Full rules in `reference/specification/formulas.md`. Skeleton:

**Outside the element** — use `[SourceName/column_name]`:
- Warehouse-table source: `SourceName` = last segment of the `path` array (e.g., `[ORDERS/Revenue]`)
- Another element: `SourceName` = that element's `name`
- Join legs: prefix by the leg's `name`, or by the join's top-level `name` for `primarySource` columns

**Inside the same element** — use `[column_name]` (no prefix):
- References a column defined in this element by its `name` field.
- A column cannot reference itself (circular reference error).

## Example walkthrough

User: *"Build me a sales dashboard from the ORDERS table in our Snowflake connection."*

1. Authenticate via `sigma-api` (export env, `eval "$(.../get-token.sh)"`).
2. `GET /v2/whoami` → userId. `GET /v2/members/<userId>` → homeFolderId.
3. `GET /v2/workbooks?limit=50` — find a workbook whose name suggests similar content.
4. `GET /v2/workbooks/<reference-workbook-id>/spec` → YAML by default; study structure, capture `schemaVersion`.
5. Discover: `GET /v2/connections` → Snowflake; `POST /v2/connection/<id>/lookup` for the path; `GET /v2/connections/tables/<inodeId>/columns` for column names.
6. Write `/tmp/workbook-spec.yaml` with `name`, `folderId`, `schemaVersion`, `pages`, and (for multi-element) `layout` XML — table sourced from ORDERS, columns for the discovered fields, a date control, layout XML positioning KPIs over a chart.
7. `./scripts/validate-spec.sh /tmp/workbook-spec.yaml`.
8. `POST /v2/workbooks/spec` with `Content-Type: application/yaml` → returns `workbookId`. Copy spec to `/tmp/workbook-spec-<workbookId>.yaml`.
9. `./scripts/verify-workbook.sh <workbookId>` — confirm every element compiles cleanly.
10. Share **both** the workbook URL **and** the saved spec path.

## Troubleshooting

### "I don't see this field in the skill"

Fetch the OpenAPI. The skill documents stable, common surface area; the API has more. See **Consulting the OpenAPI** above.

### API schema mismatch (skill is stale)

If a request fails with **"invalid argument"**, **"unknown field"**, **"unexpected property"**, **"missing required field"**, **"unrecognized parameter"**, or a 400 about request *shape* rather than data — the API has evolved since this skill was written.

In order:

1. **Tell the user.** Print:

   > ⚠️ This error looks like a schema mismatch between this skill and the current Sigma API. The skill may be out of date — consider updating it via whichever channel you installed it through. I'll consult the live OpenAPI in the meantime.

2. **Fetch the current OpenAPI** (see **Consulting the OpenAPI** above).

3. **Diff** the live schema vs. what the skill assumed — renamed fields, new required fields, removed fields, type changes.

4. **One automated retry** with the corrected shape. If it succeeds, tell the user exactly what changed and still recommend they run the plugin update.

5. **Do not loop.** One retry, then stop.

### 401 Unauthorized

Token missing or expired. Re-authenticate via `sigma-api`. If still failing, verify credentials and base URL.

### 403 Forbidden on workbook create

The credentials authenticated but aren't permitted to create workbooks here. Ask the user's Sigma admin to confirm the credential's permissions and folder access.

### "Invalid column reference" or formula errors on creation

The most common spec issue. A bare `[column_name]` was used where `[TABLE/column_name]` is needed. See `reference/specification/formulas.md` for the full rules and `reference/workflows/validate.md` for the manual checklist.

### "Unknown column" errors

The column name in the formula doesn't match what the warehouse actually has. Re-confirm the column names via `GET /v2/connections/tables/{inodeId}/columns` (raw warehouse names) and the readback (`GET /v2/workbooks/<id>/spec`, which shows Sigma's normalized friendly names). Use those names verbatim.

### `jq` or `yq` not installed

`jq` is used for OpenAPI inspection (the OpenAPI is JSON). `yq` is used for workbook-spec inspection (specs are YAML).

- `jq`: `brew install jq` (macOS) or `apt install jq` (Debian/Ubuntu).
- `yq`: `brew install yq` (macOS), `apt install yq` (Debian/Ubuntu), or `pip install yq` (Python wrapper around jq with identical syntax — use this if you already know jq).

### Cryptic validation errors / silent bad data

See `reference/workflows/validate.md` for the full triage table (mapping `Invalid kind: pages[0].elements[N]...` style errors to the right spec file).
