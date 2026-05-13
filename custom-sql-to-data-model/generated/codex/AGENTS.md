<!--
Auto-generated from SKILL.md by ~/sigma-skills/scripts/sync-targets.rb.
Do not edit by hand — edit SKILL.md and re-run the script.
-->

> Scan Sigma workbooks for custom SQL elements and convert them into proper Sigma data models using the SQL-to-Sigma MCP converter. Use when you want to find ad-hoc SQL in workbooks and promote it to a reusable data model.

# Custom SQL → Data Model

Scan all workbooks for elements sourced from raw SQL (`source.kind: "sql"`),
build a Sigma data model spec for each workbook, POST it, then optionally
repoint the source workbook to use the new data model.

---

## Prerequisites

Required env vars: `SIGMA_BASE_URL`, `SIGMA_CLIENT_ID`, `SIGMA_CLIENT_SECRET`

Always chain the token eval with `&&` so the token is live for all subsequent
commands in the same block:

```bash
eval "$(bash scripts/get-token.sh)"
```

> Tokens expire after ~1 hour. Re-run if you see `Token missing or malformed`.

---

## Phase 1 — Scan workbooks for custom SQL

```bash
eval "$(bash scripts/get-token.sh)" && ruby scripts/scan-workbooks.rb
```

Reads every workbook spec in the org, finds all elements where
`source.kind == "sql"`, and writes `/tmp/custom-sql-manifest.json`.

Each entry in the manifest:

```json
{
  "workbook_id":   "25e21c63-...",
  "workbook_name": "Custom Sql Test",
  "folder_id":     "57e59735-...",
  "element_id":    "6YSI-SjSmz",
  "element_name":  "Customer Dim SQL",
  "connection_id": "cb2f5180-...",
  "sql":           "select * from CSA.TJ.CUSTOMER_DIM",
  "column_count":  18
}
```

`folder_id` comes directly from the source workbook's own spec — it is always
a real folder and is where the new data model will be placed.

Review the findings and confirm with the user which to convert before proceeding.

---

## Phase 2 — Build the data model spec

### One data model per workbook

Group all SQL elements from the same workbook into **one data model** with one
page per element. Do not create a separate data model per element — that
produces unnecessary fragmentation.

### Try the converter first

For each SQL element, call:

```
mcp__sigma-data-model__convert_sql_to_sigma
  statements    = [{"name": "<element_name>", "sql": "<sql>"}]
  connection_id = "<connection_id from manifest>"
  database      = ""
  schema        = ""
```

`database` and `schema` can be left empty — the converter infers them from
the SQL (e.g. `CSA.TJ.CUSTOMER_DIM` → database `CSA`, schema `TJ`).

### What the converter produces

| SQL type | Converter output | Action |
|---|---|---|
| `SELECT *` or `SELECT cols` from one table | Single `warehouse-table` element, no columns | Fetch columns — see below |
| `SELECT` with JOINs | Multiple `warehouse-table` elements + relationships | Use as-is |
| `SELECT` with aggregates (GROUP BY) | Elements + `metrics` array | Check child usage — see note below |
| CTEs (`WITH ...`) | Element with `path: ["CTE_NAME"]` — fake table | Discard — build manually |
| Subqueries / implicit joins | `Custom SQL` element | Use as-is |

> **Aggregated SQL with GROUP BY**: The warehouse-table + metrics approach only
> exposes GROUP BY dimensions as direct columns; aggregate expressions are placed
> in the `metrics` array. If child workbook elements reference ALL output columns
> (including aggregates) as direct column references — not as metrics — the DM
> page must use a `sql` source instead. Build it manually with the full SQL and
> enumerate all output columns explicitly. Symptom: child element `describe` shows
> missing columns or the workbook PUT fails with dependency errors on metric columns.

### Column formula rules — read carefully

Column `formula` is **always required** — the API rejects columns with a missing formula field.

| Source kind | Formula inside the DM element | Formula in workbook referencing the DM |
|---|---|---|
| `warehouse-table` | `[TABLE_NAME/Column Name]` | `[DM Element Name/Column Name]` |
| `sql` | `[Custom SQL/SQL_ALIAS]` | `[DM Element Name/Column Display Name]` |

**Key rules:**
- Inside a `sql` DM element, the formula prefix is always the literal string `Custom SQL` —
  never the element's own `name` field. `name` is only used by elements referencing it from outside.
- Workbook formulas reference DM columns by **display name** (the column's `name` field),
  not by the server-assigned column `id`. Display names are stable across DM PUTs;
  column IDs are reassigned every time you PUT the spec.

```python
# Column object for a sql source element
def col(sql_alias, display=None):
    title = display or sql_alias.replace("_", " ").title()
    return {"id": sql_alias, "name": title, "formula": f"[Custom SQL/{sql_alias}]"}
```

### SELECT * — converter produces no columns

When the converter returns a `warehouse-table` element with no columns:

**Step 1** — Find the table's inodeId:
```
mcp__sigma-mcp-v2__search
  query       = "<TABLE_NAME>"   (last segment, e.g. "CUSTOMER_DIM")
  entityTypes = ["table"]
```

**Step 2** — Get column names from the DDL:
```
mcp__sigma-mcp-v2__describe
  object = {"type": "table", "inodeId": "<inodeId>"}
```

**Step 3** — Build columns using `warehouse-table` format:
```python
columns = [
    {"id": col_name, "formula": f"[CUSTOMER_DIM/{col_name}]", "name": col_name.replace('_', ' ').title()}
    for col_name in column_names_from_ddl
]
spec['pages'][0]['elements'][0]['columns'] = columns
spec['pages'][0]['elements'][0]['order']   = [c['id'] for c in columns]
```

### CTEs — discard converter output, build manually

When the converter returns `path: ["CTE_NAME"]`, the CTE name is being used as
a fake warehouse table path. This will never resolve. Discard the converter
output entirely and build a `sql` element by hand:

```json
{
  "id": "my-element",
  "name": "RFM Customer Analysis",
  "kind": "table",
  "source": {
    "kind": "sql",
    "connectionId": "<connection_id>",
    "statement": "<full CTE SQL here>"
  },
  "columns": [
    {"id": "CUSTOMER_KEY", "name": "Customer Key", "formula": "[Custom SQL/CUSTOMER_KEY]"},
    {"id": "CUSTOMER_NAME", "name": "Customer Name", "formula": "[Custom SQL/CUSTOMER_NAME]"}
  ],
  "order": ["CUSTOMER_KEY", "CUSTOMER_NAME"]
}
```

Enumerate the output columns from the final `SELECT` of the CTE.

### Set folderId

Always set `folderId` from the manifest entry before writing the spec file:

```python
import json
spec = json.load(open('/tmp/<name>-datamodel-spec.json'))
spec['folderId'] = '<folder_id from manifest>'
json.dump(spec, open('/tmp/<name>-datamodel-spec.json', 'w'), indent=2)
```

---

## Phase 3 — POST the data model

```bash
eval "$(bash scripts/get-token.sh)" && \
curl -s -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/<name>-datamodel-spec.json \
  "$SIGMA_BASE_URL/v2/dataModels/spec" \
  | ruby -r yaml -r json -r date -e "
    d = YAML.safe_load(STDIN.read, permitted_classes: [Date, Time])
    if d['dataModelId']
      puts 'SUCCESS  dataModelId: ' + d['dataModelId'].to_s
      d['pages']&.each { |p| p['elements']&.each { |e| puts \"  elementId: #{e['id']}  name: #{e['name']}\" } }
    else
      puts 'ERROR: ' + d.inspect
    end
  "
```

> Response is YAML — never pipe to `jq`.

Record the `dataModelId` and server-assigned element IDs.

---

## Phase 4 — Validate with MCP tools

Always validate before declaring success. Describe every element to check for
schema errors, then query each one to confirm data flows end-to-end.

### Describe all elements

```
mcp__sigma-mcp-v2__describe
  object = {"type": "datamodel", "dataModelId": "<dataModelId>"}
```

Then for each element listed:

```
mcp__sigma-mcp-v2__describe
  object = {"type": "datamodel-element", "dataModelId": "<dataModelId>", "elementId": "<elementId>"}
```

A healthy element returns a `CREATE TABLE` DDL with all columns and their
formulas. An element with broken column references returns an error or empty schema.

### Query each element

```
mcp__sigma-mcp-v2__query
  query = {
    "type": "datamodel",
    "dataModelId": "<dataModelId>",
    "sql": "SELECT <col1>, <col2> FROM \"datamodel\".\"<elementId>\" LIMIT 3"
  }
```

Column identifiers in the SQL must be the server-assigned column IDs from the
`describe` DDL (the quoted identifiers, e.g. `"tJw4NSd3yp"`), not display names.

If all elements describe and query cleanly, proceed to Phase 5.

---

## Phase 5 — Repoint the source workbook

Replaces each workbook element's raw SQL source with a reference to the new
data model. **This step is mandatory** — the DM is only useful if the workbook
actually references it.

### Identify root vs. child elements

Before patching, determine which workbook elements are **root** SQL elements
(source.kind = "sql") and which are **child** elements (source.elementId pointing
to a root SQL element). Only root elements get repointed to the DM. Child elements
stay sourced from the workbook root elements — do NOT repoint them to the DM.

```ruby
# Collect root SQL element IDs
root_ids = Set.new
spec['pages'].each do |page|
  page['elements'].each do |el|
    root_ids << el['id'] if el.dig('source', 'kind') == 'sql'
  end
end

# Child elements: source.elementId is a root SQL element
child_parent = {}  # child_id => parent root element_id
spec['pages'].each do |page|
  page['elements'].each do |el|
    parent = el.dig('source', 'elementId')
    child_parent[el['id']] = parent if parent && root_ids.include?(parent)
  end
end
```

### Unnamed SQL elements and the "Custom SQL" formula prefix

If a root SQL element has no `name` field (or name = ""), Sigma defaults to
`"Custom SQL"` as the formula prefix for all child elements that reference it.
When you repoint the root element and give it a real name, all child element
column formulas must be updated from `[Custom SQL/...]` to `[New Name/...]`.

```ruby
conversions = {
  '<root_element_id>' => {
    dataModelId: '<dataModelId>',
    elementId:   '<server-assigned-element-id>',
    elementName: 'Order Summary'   # new unique name — replaces "Custom SQL" prefix
  }
}

spec['pages'].each do |page|
  page['elements'].each do |el|
    conv = conversions[el['id']]
    if conv
      # Root element → repoint to DM
      el['name']   = conv[:elementName]
      el['source'] = {
        'kind'        => 'data-model',
        'dataModelId' => conv[:dataModelId],
        'elementId'   => conv[:elementId]
      }
      (el['columns'] || []).each do |col|
        sql_alias = col['id']
        display   = sql_alias.split('_').map(&:capitalize).join(' ')
        col['formula'] = "[#{conv[:elementName]}/#{display}]"
      end

    elsif child_parent[el['id']]
      # Child element → update formula prefix only (do NOT change source)
      parent_id = child_parent[el['id']]
      parent_conv = conversions[parent_id]
      next unless parent_conv
      new_prefix = parent_conv[:elementName]
      (el['columns'] || []).each do |col|
        col['formula'] = col['formula']&.gsub('[Custom SQL/', "[#{new_prefix}/")
      end
    end
  end
end
```

### Formula rule for workbook → DM references

```
[DM Element Name/Column Display Name]
```

- Prefix = the DM element's `name` field (e.g. `RFM Customer Analysis`)
- Suffix = the column's display `name` in the DM (e.g. `Customer Key`)
- **Not** the column's server-assigned `id` — those change on every DM PUT

```bash
eval "$(bash scripts/get-token.sh)" && \
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbookId>/spec" \
  > /tmp/wb-spec.yaml
```

```ruby
require 'yaml'; require 'json'; require 'date'
spec = YAML.safe_load(File.read('/tmp/wb-spec.yaml'), permitted_classes: [Date, Time])

# Map each workbook sql element to its new data model source
conversions = {
  '<element_id_from_manifest>' => {
    dataModelId: '<dataModelId>',
    elementId:   '<server-assigned-element-id>',
    elementName: '<DM element name, e.g. RFM Customer Analysis>'
  }
}

spec['pages'].each do |page|
  page['elements'].each do |el|
    conv = conversions[el['id']]
    next unless conv

    el['source'] = {
      'kind'        => 'data-model',
      'dataModelId' => conv[:dataModelId],
      'elementId'   => conv[:elementId]
    }

    # Rewrite formulas: workbook references DM columns by display name
    (el['columns'] || []).each do |col|
      sql_alias = col['id']  # workbook column id is the SQL alias
      display   = sql_alias.split('_').map(&:capitalize).join(' ')
      col['formula'] = "[#{conv[:elementName]}/#{display}]"
    end
  end
end

%w[workbookId url ownerId createdBy updatedBy createdAt updatedAt latestDocumentVersion].each { |k| spec.delete(k) }
spec['pages'].each { |p| p.delete('layout') }

File.write('/tmp/wb-updated.json', JSON.pretty_generate(spec))
```

```bash
curl -s -X PUT \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/wb-updated.json \
  "$SIGMA_BASE_URL/v2/workbooks/<workbookId>/spec" \
  | ruby -r yaml -r json -r date -e "
    d = YAML.safe_load(STDIN.read, permitted_classes: [Date, Time])
    puts d['workbookId'] ? 'SUCCESS' : 'ERROR: ' + d.inspect
  "
```

After PUT, validate the workbook elements too:

```
mcp__sigma-mcp-v2__describe
  object = {"type": "workbook-element", "workbookId": "<workbookId>", "elementId": "<elementId>"}

mcp__sigma-mcp-v2__query
  query = {"type": "workbook", "workbookId": "<workbookId>",
           "sql": "SELECT <cols> FROM \"workbook\".\"<elementId>\" LIMIT 3"}
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Token missing or malformed` | Token expired between commands | Re-run `eval "$(bash scripts/get-token.sh)"` — always chain with `&&` |
| `Invalid array: ...columns, got undefined` | Converter returned no columns (SELECT * case) | Fetch columns via `mcp__sigma-mcp-v2__describe` on the table and add them manually |
| `formula: Invalid string: undefined` | Column missing `formula` field | Every column needs `formula` — `[Custom SQL/SQL_ALIAS]` for sql, `[TABLE/COL]` for warehouse-table |
| `Circular column reference` | Formula used the column's own display name with no prefix | Use `[Custom SQL/SQL_ALIAS]` — bare `[Display Name]` self-references the column |
| `Unknown column '[ALIAS]'` | Bare alias with no prefix | Add the `Custom SQL` prefix: `[Custom SQL/ALIAS]` |
| `dependency not found: formula reference 'element name/col'` | Used element's own name as formula prefix inside the element | Inside a sql element, always use `[Custom SQL/...]`, never `[ElementName/...]` |
| `document parent must be a folder` | `folderId` points to a workbook or data model, not a folder | Use `folder_id` from the scan manifest — taken from the workbook's own `folderId`, always a real folder |
| Converter returns `path: ["CTE_NAME"]` | Converter treated CTE name as a warehouse table path | Discard converter output; build a `source.kind: "sql"` element manually with the full SQL |
| `Column '[Element/id]' does not exist` after DM PUT | DM PUT reassigned column IDs — old IDs are stale | Workbook formulas must use display names not IDs: `[Element Name/Column Display Name]` |
| `dataModelId` missing from response | POST failed silently | Check the full response for a `message` field with schema errors |
| `schemaVersion` error on workbook PUT | Field was stripped | Keep `schemaVersion` in the PUT body — it is required |
| Multiple separate data models created | Each SQL element treated as its own model | Group all elements from one workbook into one data model, one page per element |
| Child elements break after Phase 5 (`[Custom SQL/col]` dependency not found) | Root element was renamed but child formulas still use `[Custom SQL/...]` prefix | Update child element column formulas: replace `[Custom SQL/` with `[New Name/` |
| Child elements sourced from DM instead of workbook table | Child elements were incorrectly repointed to the DM | Only root SQL elements get DM sources; child elements keep `source.elementId` pointing to the root workbook element |
| Metric columns missing on child elements referencing aggregated SQL | Warehouse-table + metrics approach; child references aggregate as a direct column | Rebuild the DM page as a `sql` source element with all output columns enumerated explicitly |
