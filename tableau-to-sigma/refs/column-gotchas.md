# Column Naming Gotchas

## The slash problem

Sigma uses `/` as the source-prefix separator in formula references: `[TableName/ColumnName]`.
If a column's `name` field itself contains `/`, every formula that references it becomes unresolvable.

**Tableau display names that contain slashes (common):**
- "Country/Region" → rename to `"Country"`
- "State/Province" → rename to `"State"`

**Rule:** Before writing the data model spec, rename any column whose `name` contains `/`.
Do it once in the data model; all downstream workbook formulas inherit the clean name.

## Tableau display names ≠ warehouse column names

Tableau stores a human-readable "display name" that is almost never the actual Snowflake column name.

| Tableau display | Snowflake column |
|---|---|
| Sub-Category | SUB_CATEGORY |
| Country/Region | COUNTRY_REGION |
| Order Date | ORDER_DATE |
| Customer Name | CUSTOMER_NAME |

**Rule:** Always fetch actual column names from the Sigma connection API:
```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections/tables/<urlId>/columns" \
  | jq '[.entries[] | {name, dataType}]'
```

Never infer warehouse column names from Tableau display names.

## Sub-Category hyphen

"Sub-Category" is a valid column `name` in the data model spec. Hyphens are fine.
The formula reference `[Orders/Sub-Category]` works correctly.

## Cascading failures

If one column formula is invalid, the entire element (table) fails — not just that column.
The error message names the specific bad ref. Fix only that ref and retry; don't rebuild the whole element.

## Column ID format

Column IDs in a data model spec can be any unique string. The server reassigns them on POST, so your
IDs are just for cross-referencing within the JSON file you're writing. Short readable IDs like
`"col-sales"` or `"met-profit-ratio"` are fine.

## Metrics vs columns

Metrics are aggregate formulas that live alongside columns but reference column names without a table prefix:
```json
{"id": "met-sales", "formula": "Sum([Sales])", "name": "Total Sales"}
```
Note: `[Sales]` not `[ORDERS/Sales]` — within the same element, bare refs work.

## YAML response from spec endpoints

`POST /v2/dataModels/spec` and `POST /v2/workbooks/spec` return **YAML**, not JSON.
Piping to `jq` causes `parse error: Invalid numeric literal`.

Parse with Ruby:
```bash
ruby -r yaml -r json -r date -e \
  "puts JSON.pretty_generate(YAML.safe_load(STDIN.read, permitted_classes:[Date,Time]))"
```
