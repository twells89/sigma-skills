---
name: tableau-to-sigma
description: >-
  Convert a Tableau datasource or workbook into a Sigma data model and matching
  dashboard. Use when the user has a Tableau datasource, TDS file, or Tableau
  workbook and wants to recreate it in Sigma. Covers column discovery, data
  model creation via REST API, and dashboard layout generation using Ruby.
user-invocable: true
---

# Tableau → Sigma Conversion

Convert a Tableau datasource into a Sigma data model, then build a Sigma workbook
that mirrors the Tableau dashboard layout as closely as possible.

**Read before starting:**
- `refs/column-gotchas.md` — column naming rules and special-character landmines
- `refs/data-model-spec.md` — data model JSON schema, element format, relationship format
- `refs/workbook-layout.md` — Ruby layout generation (mandatory), multi-series chart patterns

---

## Prerequisites

### Sigma credentials

Run the setup script once. It stores credentials in `~/.claude/settings.json` so
they are loaded automatically into every future session:

```bash
ruby scripts/setup.rb
```

Then open a new Claude Code session (or run `! source ~/.claude/settings.json`)
so the env vars are live. Every script validates they exist and aborts with a
clear message if they are missing.

Required env vars:
- `SIGMA_BASE_URL` — e.g. `https://aws-api.sigmacomputing.com`
- `SIGMA_CLIENT_ID`
- `SIGMA_CLIENT_SECRET`

### Tableau access

The Tableau MCP tools (`mcp__tableau__*`) are used for metadata retrieval and
must already be authenticated in the session. Direct Tableau PAT auth via curl
frequently returns 401 — always prefer MCP.

---

## Phase 1 — Discover the Tableau datasource structure

### 1a. Find the datasource

```
mcp__tableau__search-content   terms="<datasource name>"   filter.contentTypes=["datasource"]
mcp__tableau__list-datasources
```

### 1b. Find workbooks sourced from it

```
mcp__tableau__search-content   terms="<datasource name>"   filter.contentTypes=["workbook"]
```

### 1c. Get workbook views

```
mcp__tableau__get-workbook   workbookId="<luid>"
```

Returns the list of views (sheets) with their `id` and `name`. Record all view IDs.

### 1d. Retrieve view images

`get-view-image` requires a warm VizQL session. The root cause of most 401s is
**session contention**: firing many requests simultaneously causes them to compete
for the same VizQL session, and most fail — regardless of whether the cache is warm
or whether the view has been visited in a browser. Browser visits are not required.

**The reliable pattern — warm solo, then image solo, one view at a time:**

Step 1 — warm the view:
```
mcp__tableau__get-view-data   viewId="<id1>"
```
Step 2 — immediately fetch the image for that same view before starting the next:
```
mcp__tableau__get-view-image   viewId="<id1>"   format="PNG"   width=1400   height=900
```
Step 3 — repeat for each remaining view.

If `get-view-data` returns 401, skip that view entirely — the image will also fail.

> **Do not fire all views in a parallel batch.** Even if `get-view-data` succeeds in
> a parallel batch, a concurrent `get-view-image` in the same batch will still 401
> due to session contention. Process views one at a time.

Use the images to understand:
- How many KPIs are in the header row and what they measure
- Which chart types are used (bar, line, scatter, map, small multiples)
- The rough grid layout of each page (columns × rows)

Sigma spec supports: `bar-chart`, `line-chart`, `kpi`, `pie`, `donut`, `table`, `pivot-table`, `control`, `divider`, `container`.

Does **not** support via spec API: maps, scatter charts, small multiples / trellis, bullet, gantt, dual-axis / combo charts (UI feature only — no spec kind).
Approximate with: bar charts (for maps and scatter), multi-series line charts (for small multiples), two side-by-side charts (for dual-axis).

Reference lines (average/target lines overlaid on charts) have no equivalent in the spec API — drop them silently.

Control types supported: `list`, `date-range`, `text`, `text-area`, `segmented`, `number`, `number-range`, `slider`, `range-slider`, `top-n`.
See `refs/workbook-layout.md` for full control element spec patterns.

---

## Phase 2 — Discover actual warehouse column names

> **This step is mandatory. Do not skip it or infer column names from Tableau.**

Tableau display names ("Sub-Category", "Country/Region") are NOT the same as
Snowflake warehouse column names ("SUB_CATEGORY", "COUNTRY_REGION"). Using the
wrong names produces "dependency not found" errors at publish time.

Fetch a token once now — it's valid for ~1 hour and covers all curl calls in Phases 2–5:

```bash
eval "$(scripts/get-token.sh)"
```

> **Token persistence in multi-command blocks:** `eval` sets env vars in the current
> shell. If you need to combine eval and curl in a single `bash -c '...'` block, keep
> them in the same invocation. Never use `TOKEN=$(eval "$(scripts/get-token.sh)")` —
> the `$()` creates a subshell where the exported var dies immediately.

### 2a. Find the connection

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections" | jq '[.entries[] | {name, connectionId}]'
```

### 2b. Find the table inode/urlId

Search by name, or use the Sigma MCP tool:

```
mcp__sigma-mcp-v2__search   query="<table name>"
```

The search result includes a `urlId` or `inodeId` for the table.

### 2c. Fetch actual column names

Run all tables in parallel — one curl per table, all at the same time:

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections/tables/<urlId1>/columns"

curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections/tables/<urlId2>/columns"
```

> **Response key is `entries`, not `columns`.** Parse with `.get('entries', [])`, not `.get('columns', [])`.
> Using `columns` returns an empty list silently — no error, just missing data.

These are the **exact** column names to use in data model element formulas:
`[TABLE_NAME/Column Name]`.

---

## Tableau → Sigma formula translation

Tableau calculated fields do not map 1:1 to Sigma formulas. Always translate before writing element specs.

| Tableau | Sigma | Notes |
|---|---|---|
| `COUNTD([Order ID])` | `CountDistinct([Order ID])` | |
| `COUNTIF([Segment]="Consumer", [Order ID])` | `Count(If([Segment] = "Consumer", [Order ID], Null))` | `CountIf()` does not exist in Sigma |
| `ZN([Sales])` | `IfNull([Sales], 0)` | |
| `IIF(cond, a, b)` | `If(cond, a, b)` | |
| `IF ISNULL([X]) THEN ... END` | `If(IsNull([X]), ...)` | |
| `DATETRUNC("month", [Order Date])` | `DateTrunc("month", [Order Date])` | same semantics, Sigma uses camelCase |
| `DATEDIFF("day", [Start], [End])` | `DateDiff("day", [Start], [End])` | |
| `{ FIXED [Customer] : SUM([Sales]) }` | No direct equivalent — pre-aggregate in the data model or use a lookup join | LOD expressions have no spec API equivalent |
| `WINDOW_SUM(SUM([Sales]))` | No direct equivalent — Sigma table calculations run in the UI, not the spec | |
| `RUNNING_SUM(SUM([Sales]))` | No direct equivalent | |

> **`CountIf` trap:** This is the most common formula error. Tableau's `COUNTIF` maps naturally to what looks like `CountIf()` in Sigma — but `CountIf()` does not exist. The correct translation is always `Count(If(condition, column, Null))`. An invalid formula silently produces an "Invalid function" query error at render time, not at spec POST time.

---

## Phase 3 — Build the data model spec

Write the spec to `/tmp/<name>-datamodel-spec.json`. Full schema is in
`refs/data-model-spec.md`.

### Critical rules

1. **Endpoint**: `POST /v2/dataModels/spec` — NOT `/v2/workbooks/spec`.
   These create completely different objects.

2. **Column name special characters** — read `refs/column-gotchas.md` fully.
   Key rule: rename any column whose `name` field contains `/` before saving
   the spec. "Country/Region" → `"name": "Country"`, "State/Province" → `"name": "State"`.
   Slashes in column names break formula references in every downstream workbook.

3. **Element name = formula prefix**. The `name` field on a data model element
   (e.g. `"name": "Orders"`) becomes the prefix in all workbook formulas that
   reference it: `[Orders/Sales]`. Choose clean, stable names.

4. **Relationships go on the source element**, not the target. See `refs/data-model-spec.md`
   for the exact shape.

5. **Column formulas use the warehouse table name as prefix**:
   - Path `["CSA", "Tableau Test", "ORDERS"]` → prefix is `ORDERS`
   - Formula: `"[ORDERS/Column Name]"`

### Validate before posting

```bash
python3 -c "
import json, re, sys
spec = json.load(open('/tmp/spec.json'))
errors = []
for page in spec.get('pages', []):
    for el in page.get('elements', []):
        kind = el.get('kind', '')
        name = el.get('name', el.get('id', '?'))
        cols = el.get('columns', []) + el.get('metrics', [])
        el_col_names = {c['name'] for c in cols}

        # Bare formula refs without a source prefix
        for col in cols:
            for ref in re.findall(r'\[([^\]]+)\]', col.get('formula', '')):
                if '/' not in ref and ref not in el_col_names:
                    errors.append(f'{name}: bare ref [{ref}] has no match')

        # KPI must have value field
        if kind == 'kpi' and 'value' not in el:
            errors.append(f'{name}: kpi missing value field')

        # bar-chart and line-chart must use yAxis, not measures
        if kind in ('bar-chart', 'line-chart'):
            if 'measures' in el:
                errors.append(f'{name}: use yAxis not measures for {kind}')
            if 'yAxis' not in el:
                errors.append(f'{name}: {kind} missing yAxis')

        # pivot-table rows/columnGroups/values must be string arrays
        if kind == 'pivot-table':
            for field in ('rows', 'columnGroups', 'values'):
                arr = el.get(field, [])
                if arr and isinstance(arr[0], dict):
                    errors.append(f'{name}: pivot-table {field} must be string array not object array')

for e in errors: print('ERROR:', e)
sys.exit(len(errors))
"
```

---

## Phase 4 — POST the data model

```bash
curl -s -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/<name>-datamodel-spec.json \
  "$SIGMA_BASE_URL/v2/dataModels/spec"
```

> **Response format is YAML, not JSON.** Do NOT pipe to `jq`. Parse with Ruby:
>
> ```bash
> ruby -r yaml -r json -e \
>   "puts JSON.pretty_generate(YAML.safe_load(STDIN.read, permitted_classes:[Date,Time]))"
> ```

The response contains the `dataModelId` and the server-assigned element IDs.
Record them — you need them for the workbook source references.

On error: read `refs/column-gotchas.md` → fix the offending column formula → retry.

---

## Phase 5 — Build the Sigma workbook

### 5a. Write the workbook spec

Source elements in the workbook from the data model:

```json
{
  "id": "master",
  "kind": "table",
  "name": "Master",
  "source": {
    "kind": "data-model",
    "dataModelId": "<dataModelId>",
    "elementId": "<elementId from data model>"
  },
  "columns": [
    { "id": "c-sales", "formula": "[Orders/Sales]", "name": "Sales" }
  ]
}
```

Column formulas in the master table use the data model element's `name` as prefix
(`[Orders/Sales]`, not the element ID).

Charts and KPIs on content pages source the master table element and use ITS
`name` as prefix:

```json
{
  "kind": "kpi",
  "source": { "kind": "table", "elementId": "master" },
  "columns": [
    { "formula": "Sum([Master/Sales])" }
  ]
}
```

For multi-series line charts (approximating Tableau small multiples):
```json
{ "formula": "Sum(If([Master/Segment] = \"Consumer\", [Master/Sales], Null))", "name": "Consumer" }
```

See `refs/workbook-layout.md` for full chart patterns.

### 5b. POST the workbook spec

```bash
curl -s -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/workbook-spec.json \
  "$SIGMA_BASE_URL/v2/workbooks/spec" -o /tmp/wb-response.yaml

# Parse the YAML response — never pipe directly to jq
ruby -r yaml -r json -r date -e \
  "d=YAML.safe_load(File.read('/tmp/wb-response.yaml'),permitted_classes:[Date,Time]); \
   puts 'workbookId: ' + d['workbookId'].to_s"
```

> **IDs are reassigned on POST.** The element IDs you wrote in the spec are NOT
> preserved. Always GET the spec back immediately after creation to retrieve the
> real IDs before building layout XML.

### 5c. GET the spec back and extract real IDs

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbookId>/spec" \
  > /tmp/current-spec.yaml

# Extract page/element ID map with Ruby
ruby -r yaml -r date - <<'EOF'
require 'date'
spec = YAML.safe_load(File.read('/tmp/current-spec.yaml'), permitted_classes: [Date, Time])
spec['pages'].each do |page|
  puts "\n#{page['id']} : #{page['name']}"
  page['elements'].each { |e| printf "  %-24s %-14s %s\n", e['id'], e['kind'], e['name'] }
end
EOF
```

### 5d. Build layout XML with Ruby — MANDATORY

**Never hand-write layout XML.** Always use `scripts/build-layout.rb` or write
an equivalent Ruby script. See `refs/workbook-layout.md` for the full pattern
and grid sizing guide.

```bash
ruby scripts/build-layout.rb \
  --spec /tmp/current-spec.yaml \
  --output /tmp/workbook-with-layout.json
```

### 5e. PUT the spec with layout

Build the PUT body from the GET YAML spec — strip read-only fields before writing:

```ruby
spec = YAML.safe_load(File.read('/tmp/current-spec.yaml'), permitted_classes: [Date, Time])
spec['pages'].each { |p| p.delete('layout') }
spec['layout'] = layout_xml_string
%w[workbookId url ownerId createdBy updatedBy createdAt updatedAt latestDocumentVersion].each { |k| spec.delete(k) }
# Keep: name, documentVersion, folderId, schemaVersion, pages, layout
File.write('/tmp/workbook-with-layout.json', JSON.pretty_generate(spec))
```

Then PUT:

```bash
curl -s -X PUT \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/workbook-with-layout.json \
  "$SIGMA_BASE_URL/v2/workbooks/<workbookId>/spec"
```

PUT preserves existing element IDs. Only newly added elements get new IDs.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Invalid function` or chart renders empty with no data | `CountIf()` used — function does not exist in Sigma | Replace `CountIf(cond, col)` with `Count(If(cond, col, Null))` |
| `dependency not found: formula reference 'orders/country region'` | Column named "Country/Region" has slash — unresolvable in formulas | Rename column to "Country" in the data model spec; re-POST |
| `dependency not found: formula reference 'orders/state province'` | Same slash issue with "State/Province" | Rename to "State" |
| All columns on a table fail together | One bad formula poisons the whole element | Find the specific failing ref in the error message; fix only that column |
| `jq: parse error: Invalid numeric literal` | Sigma spec endpoints return YAML, not JSON | Parse with `ruby -r yaml -r json` instead |
| `401` on `get-view-image` after solo `get-view-data` succeeded | Rare transient failure | Retry `get-view-image` solo immediately — no concurrent requests |
| `401` on `get-view-image` despite `get-view-data` succeeding in same parallel batch | Session contention — concurrent requests compete for the same VizQL session | Retry the image solo with no other concurrent view requests |
| `401` on both `get-view-data` and `get-view-image` | View uses a data connection the API token can't reach | Skip this view; it's inaccessible via MCP regardless of technique |
| Batch `get-view-data` returns mostly 401s | Session contention from parallel requests — not a cache issue | Switch to solo warm → solo image, one view at a time |
| `429` on Tableau view image | Rate limited | Wait and retry the specific view |
| Column fetch returns empty list | Response key is `entries`, not `columns` | Use `.get('entries', [])` when parsing column API responses |
| PUT returns `invalid_request` with no field named | Read-only metadata fields included in PUT body | Strip `workbookId`, `url`, `ownerId`, `createdBy`, `updatedBy`, `createdAt`, `updatedAt`, `latestDocumentVersion` from the PUT body |
| PUT returns `Invalid 1: schemaVersion, got undefined` | `schemaVersion` was stripped from PUT body | Keep `schemaVersion` in the PUT body — it is required |
| Layout PUT rejected, some elements not visible | `elementId=""` in layout XML from nil Ruby variable | Guard fallback element lookups: use `(le(id, ...) if id)` and `.compact` |
| Layout has elements stacked vertically | No layout XML provided, or layout uses wrong IDs | GET spec after POST to get real IDs; rebuild layout with Ruby |
| Empty containers visible on page | Container elements in spec but not referenced as `<GridContainer>` in layout XML | Add them to layout as `<GridContainer>` wrapping their child KPIs |
| Wrong endpoint — workbook created instead of data model | Called `/v2/workbooks` instead of `/v2/dataModels/spec` | Delete the workbook; re-POST to the correct endpoint |
