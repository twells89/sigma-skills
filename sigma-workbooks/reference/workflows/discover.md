# Source Discovery

How to find connections, tables, and column names for use in workbook specs via the Sigma REST API (direct HTTP).

Assumes `$SIGMA_BASE_URL` and `$SIGMA_API_TOKEN` are set in the shell. Use the skill's `scripts/get-token.sh` to populate `$SIGMA_API_TOKEN` — see SKILL.md for details.

## Warehouse Table Sources

For elements with `source.kind: "warehouse-table"`, you need three things:
1. **connectionId** — the UUID of the warehouse connection
2. **path** — the fully-qualified path as an array (e.g., `["DATABASE", "SCHEMA", "TABLE"]`)
3. **Column names** — exact names from the warehouse, used in formulas

### Step 1: Find the Connection

List available connections:

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections"
```

This returns connections with their `connectionId`, `name`, and `type`.

### Step 2: Resolve the Table Path

Ask the user for the fully-qualified table path. Path depth varies by database:

- **Snowflake**: `["DATABASE", "SCHEMA", "TABLE"]`
- **BigQuery**: `["PROJECT", "DATASET", "TABLE"]`
- **Databricks**: `["CATALOG", "SCHEMA", "TABLE"]`
- **Redshift**: `["SCHEMA", "TABLE"]`
- **PostgreSQL / MySQL**: `["SCHEMA", "TABLE"]`

Verify the path resolves on the connection:

```bash
curl -s -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"path": ["SALES_DB", "PUBLIC", "ORDERS"]}' \
  "$SIGMA_BASE_URL/v2/connection/<connection-id>/lookup"
```

Use the verified path in the source definition.

### Step 3: Get Column Names

Ask the user for the column names (or have them query the warehouse directly — `DESCRIBE TABLE`, `INFORMATION_SCHEMA.COLUMNS`, etc.). Use those names verbatim in formulas; do not invent or transform them.

For a warehouse-table source with path `["SALES_DB", "PUBLIC", "ORDERS"]`, the formula for a column is `[ORDERS/order_id]` (last path segment + column name).

## Data Model Sources

For elements with `source.kind: "data-model"`, you need:
- **dataModelId** — the UUID of the data model
- **elementId** — the UUID of the specific element within the data model

Ask the user to supply the `dataModelId` (visible in the Sigma UI URL when viewing a data model). To find elements within the data model, fetch the data model spec and examine the `pages[].elements[]` array.

## Cross-Element Sources

For elements sourced from another element in the same workbook:

```json
{
  "kind": "table",
  "elementId": "other-element-id"
}
```

Use the `id` of the source element. Column references use the source element's `name` field: `[Source Element Name/column_name]`.
