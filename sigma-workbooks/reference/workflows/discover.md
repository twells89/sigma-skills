# Source Discovery

Recipe for finding connections, tables, and column names — *and probing actual column values before writing predicates against them*.

```bash
jq '.paths."/v2/connections", .paths."/v2/connection/{connectionId}/lookup", .paths."/v2/connections/tables/{tableId}/columns"' /tmp/sigma-api.json
```

Assumes `$SIGMA_BASE_URL` and `$SIGMA_API_TOKEN` are set in the shell. Use the `sigma-api` skill's `scripts/get-token.sh` to populate `$SIGMA_API_TOKEN` — see SKILL.md for details.

## Verify values before writing predicates

If your task involves a predicate that filters on a categorical column — `CountIf([Transaction Type] = "sale")`, `If([Status] = "active", ...)`, `If([Tier] = "Gold", ...)` — you need to verify the actual distinct values *before* writing the formula. Guessing literals leads to predicates that match zero rows, dashboards that render all zeros, and `verify-workbook.sh` reporting success because the SQL compiled fine.

A column named `TRANSACTION_TYPE` rarely contains exactly `"sale"` and `"return"` — it might be `"Purchase"` and `"Return"`, or `1`/`0`, or something else entirely. A single `SELECT DISTINCT` resolves the question. Verify by whatever means you have at hand:

- An MCP server connected to the warehouse (Snowflake, BigQuery, Databricks, Sigma, etc.) — call its query tool with `SELECT DISTINCT "<col>" FROM <table>` and read the values back.
- A SQL CLI or warehouse client the user can run — paste the results into the conversation.
- Just ask the user. *"Before I write the formula, what values does the `Transaction Type` column contain?"* costs nothing and often saves a broken dashboard.

The principle is verification, not any specific tool. Pick the cheapest path your environment supports.

**Raw warehouse column names work directly in Sigma spec formulas.** `[F_SALES/TRANSACTION_TYPE]` is accepted by the spec API and compiles to the same column reference as `[F_SALES/Transaction Type]`. Use whatever form your verification source returns — no transformation step required.

### If you're using the Sigma MCP server

The Sigma MCP server adds workspace-level discovery on top of plain value probing: `search` across workbooks / data models / tables by topic, `describe` of existing Sigma elements, awareness of pre-built metrics on data models. See [Use the Sigma MCP server](https://help.sigmacomputing.com/docs/use-sigma-mcp-server) for setup.

One footgun specific to the Sigma MCP's `query` tool: the SQL `FROM` clause uses a fixed identifier pattern based on `query.type`:

| `query.type` | FROM clause shape |
|---|---|
| `"connection"` | `FROM "connection"."<inodeId>"` |
| `"datamodel"` | `FROM "datamodel"."<elementId>"` |
| `"workbook"` | `FROM "workbook"."<elementId>"` |

The first identifier is a **literal string** — `"connection"`, `"datamodel"`, or `"workbook"` — not the human-readable connection name. Don't write `FROM "Sigma Sample Database"."<inode>"`; the server rejects it. The DDL that `describe` returns shows the correct shape verbatim.

## Warehouse Table Sources

For elements with `source.kind: "warehouse-table"`, you need three things:
1. **connectionId** — the UUID of the warehouse connection
2. **path** — the fully-qualified path as an array (e.g., `["DATABASE", "SCHEMA", "TABLE"]`)
3. **Column names** — exact names from the warehouse, used in formulas

**Prefer a pre-existing MCP tool when you have one.** If an MCP is connected, discover through it: the **Sigma MCP** (`search` / `describe` across connections, tables, and data models) or a **warehouse-native MCP** (Snowflake, BigQuery, Databricks, …) querying `INFORMATION_SCHEMA`. The REST endpoints below are the universal fallback when no MCP is available — they cover all three and need no extra setup.

### Step 1: Find the Connection

List available connections:

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections"
```

This returns connections with their `connectionId`, `name`, and `type`.

### Step 2: Resolve the Table Path and Capture the `inodeId`

Ask the user for the fully-qualified table path, **or browse the connection tree yourself** (below). Path depth varies by database:

- **Snowflake**: `["DATABASE", "SCHEMA", "TABLE"]`
- **BigQuery**: `["PROJECT", "DATASET", "TABLE"]`
- **Databricks**: `["CATALOG", "SCHEMA", "TABLE"]`
- **Redshift**: `["SCHEMA", "TABLE"]`
- **PostgreSQL / MySQL**: `["SCHEMA", "TABLE"]`

**Browse instead of guessing.** If an MCP is connected, browse through it first — the **Sigma MCP** (`search`) or a **warehouse-native MCP** (Snowflake, BigQuery, …) is the easiest way to find a table. As a no-MCP fallback, `GET /v2/connections/paths` lists every database / schema / table across the org's connections. Each entry is `{ connectionId, path, urlId }` — the endpoint takes only `page`/`limit` (no connection filter), so filter by `connectionId` client-side:

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections/paths?limit=1000" \
  | jq -r --arg c "<connection-id>" \
      '.entries[] | select(.connectionId == $c) | select(.path | length == 3) | .path | join(".")'
```

(Adjust the `length` filter to your path depth — `3` for Snowflake/BigQuery/Databricks, `2` for Redshift/Postgres/MySQL. Paginate via `page`/`limit` on large connections. The response carries no `inodeId` — capture that from `lookup` next.)

Verify the path resolves and capture the `inodeId` — Step 3 needs it:

```bash
INODE_ID=$(curl -sf -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"path": ["SALES_DB", "PUBLIC", "ORDERS"]}' \
  "$SIGMA_BASE_URL/v2/connection/<connection-id>/lookup" \
  | jq -r '.inodeId')
```

Use the verified path in the source definition.

### Step 3: Discover Column Names via the API

Use the `inodeId` from Step 2 to list the table's columns directly — no need to ask the user or have them query the warehouse:

```bash
curl -sf -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections/tables/$INODE_ID/columns" \
  | jq '.entries[] | {name, type}'
```

Each entry has `name`, `type`, `description`, and `visibility`. Use the `name` value verbatim in formulas — do not invent or transform it.

Public docs: <https://help.sigmacomputing.com/reference/listconnectiontablecolumns>.

If the call fails (rare — connector quirks, permissions), fall back to asking the user for column names or having them run `DESCRIBE TABLE` / `INFORMATION_SCHEMA.COLUMNS` against the warehouse.

For a warehouse-table source with path `["SALES_DB", "PUBLIC", "ORDERS"]`, the formula for a column is `[ORDERS/order_id]` (last path segment + column name).

## Data Model Sources

For elements with `source.kind: "data-model"`, you need:
- **dataModelId** — the UUID of the data model
- **elementId** — the UUID of the specific element within the data model

Ask the user to supply the `dataModelId` (visible in the Sigma UI URL when viewing a data model). To find elements within the data model, fetch the data model spec and examine the `pages[].elements[]` array.

## Cross-Element Sources

For elements sourced from another element in the same workbook:

```yaml
kind: table
elementId: other-element-id
```

Use the `id` of the source element. Column references use the source element's `name` field: `[Source Element Name/column_name]`.
