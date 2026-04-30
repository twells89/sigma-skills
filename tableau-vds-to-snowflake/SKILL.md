# Tableau VDS → Snowflake

Extract data from a published Tableau datasource via the VizQL Data Service (VDS) API
and land it in a Snowflake table using a stored procedure + External Access Integration.
Optionally schedule for ongoing refresh with a Snowflake Task.

---

## How it works

```
Tableau Published Datasource
        │
        │  POST /api/v1/vizql-data-service/query-datasource
        │  (auth via PAT + x-tableau-auth header)
        ▼
Snowflake Stored Procedure (Python)
  - signs in to Tableau REST API
  - calls VDS query endpoint
  - creates/replaces target table
  - loads rows via Snowpark
        │
        ▼
Snowflake Table  ──▶  Sigma Workbook
```

The stored procedure runs inside Snowflake via External Access Integration (EAI).
No data touches Claude or the local machine — Snowflake fetches directly from Tableau.

---

## Prerequisites

### Tableau
- A **published** datasource (not embedded in a workbook-only)
- A Personal Access Token (PAT) — name and secret
  - Create at: Tableau Cloud → Account settings → Personal Access Tokens
- The datasource LUID (a UUID) — retrieved via MCP or REST API
- The site's `contentUrl` (e.g. `"dataflow"`)

### Snowflake
- A database and schema to write to (e.g. `TJ.PUBLIC`)
- A role with `CREATE NETWORK RULE`, `CREATE SECRET`, `CREATE INTEGRATION`, `CREATE PROCEDURE`, `CREATE TABLE` privileges
  - In the TSE sandbox: `SNOWFLAKE_SANDBOX_TSE_PUSH_GROUP`
- A running warehouse (e.g. `SIGMA_WH`)
- Snowflake CLI (`snow`) configured with key-pair JWT auth:
  - Config: `~/.snowflake/config.toml`
  - Test: `snow sql -q "SELECT CURRENT_USER()" --connection <conn>`

---

## Phase 1 — Discover the datasource LUID

### Option A: Tableau MCP tool
```
mcp__tableau__list-datasources
```
Returns a list with `id` (the LUID) and `name`. Use the `id` value.

### Option B: Tableau REST API
```bash
bash -c '
AUTH=$(curl -s -X POST "https://{server}/api/3.21/auth/signin" \
  -H "Content-Type: application/json" \
  -d "{\"credentials\": {
    \"personalAccessTokenName\": \"{pat_name}\",
    \"personalAccessTokenSecret\": \"{pat_secret}\",
    \"site\": {\"contentUrl\": \"{site_name}\"}}}")

TOKEN=$(echo "$AUTH" | python3 -c "import sys,re; print(re.search(r\"token=\\\"([^\\\"]+)\\\"\", sys.stdin.read()).group(1))")
SITE_ID=$(echo "$AUTH" | python3 -c "import sys,re; print(re.search(r\"site id=\\\"([^\\\"]+)\\\"\", sys.stdin.read()).group(1))")

curl -s -H "x-tableau-auth: $TOKEN" \
  "https://{server}/api/3.21/sites/$SITE_ID/datasources?pageSize=100" \
  | python3 -c "import sys,re; [print(m[0], m[1]) for m in re.findall(r\"datasource id=\\\"([^\\\"]+)\\\" name=\\\"([^\\\"]+)\\\"\", sys.stdin.read())]"
'
```

> **Auth response is XML**, not JSON. Parse with `re.search(r'token="([^"]+)"', ...)`.
> Do NOT pipe to `jq` — it will fail silently or error.

### Validate a datasource is VDS-queryable
```bash
# Quick test — should return {"data": [...]}
bash -c '
AUTH=$(curl -s -X POST "https://{server}/api/3.21/auth/signin" \
  -H "Content-Type: application/json" \
  -d "{\"credentials\": {\"personalAccessTokenName\": \"{pat_name}\", \"personalAccessTokenSecret\": \"{pat_secret}\", \"site\": {\"contentUrl\": \"{site_name}\"}}}")
TOKEN=$(echo "$AUTH" | python3 -c "import sys,re; print(re.search(r\"token=\\\"([^\\\"]+)\\\"\", sys.stdin.read()).group(1))")
curl -s -X POST "https://{server}/api/v1/vizql-data-service/query-datasource" \
  -H "x-tableau-auth: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"datasource\": {\"datasourceLuid\": \"{luid}\"}, \"query\": {\"fields\": [{\"fieldCaption\": \"{any_field}\"}]}, \"options\": {\"returnFormat\": \"OBJECTS\"}}" \
  | python3 -m json.tool
'
```

---

## Phase 2 — Set up Snowflake objects

Run these once per target database/schema. Replace `TJ.PUBLIC` throughout.

### 2a. Network rule + secret + EAI

Write to `/tmp/vds_setup.sql`:

```sql
USE ROLE <your_role>;
USE DATABASE <db>;
USE SCHEMA <schema>;

CREATE OR REPLACE NETWORK RULE tableau_api_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('<tableau_server_host>');   -- e.g. '10ay.online.tableau.com'

CREATE OR REPLACE SECRET tableau_pat_secret
  TYPE = GENERIC_STRING
  SECRET_STRING = '{"pat_name": "<pat_name>", "pat_secret": "<pat_secret>"}';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION tableau_vds_eai
  ALLOWED_NETWORK_RULES = (<db>.<schema>.tableau_api_rule)
  ALLOWED_AUTHENTICATION_SECRETS = (<db>.<schema>.tableau_pat_secret)
  ENABLED = TRUE;
```

```bash
snow sql --connection <conn> -f /tmp/vds_setup.sql
```

### 2b. Stored procedure

Write to `/tmp/vds_proc.sql`:

```sql
USE ROLE <your_role>;
USE DATABASE <db>;
USE SCHEMA <schema>;

CREATE OR REPLACE PROCEDURE query_tableau_vds(
  server_url      STRING,
  site_name       STRING,
  datasource_luid STRING,
  target_table    STRING,
  fields_json     STRING
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
EXTERNAL_ACCESS_INTEGRATIONS = (tableau_vds_eai)
SECRETS = ('pat_creds' = <db>.<schema>.tableau_pat_secret)
HANDLER = 'run'
AS $$
import _snowflake
import requests
import json
import re

def run(session, server_url, site_name, datasource_luid, target_table, fields_json):
    creds = json.loads(_snowflake.get_generic_secret_string('pat_creds'))

    # Sign in — Tableau returns XML
    signin = requests.post(
        f'{server_url}/api/3.21/auth/signin',
        headers={'Content-Type': 'application/json'},
        json={'credentials': {
            'personalAccessTokenName': creds['pat_name'],
            'personalAccessTokenSecret': creds['pat_secret'],
            'site': {'contentUrl': site_name}
        }},
        timeout=30
    )
    signin.raise_for_status()
    token = re.search(r'token="([^"]+)"', signin.text).group(1)

    # Query VDS
    resp = requests.post(
        f'{server_url}/api/v1/vizql-data-service/query-datasource',
        headers={'x-tableau-auth': token, 'Content-Type': 'application/json'},
        json={
            'datasource': {'datasourceLuid': datasource_luid},
            'query': {'fields': json.loads(fields_json)},
            'options': {'returnFormat': 'OBJECTS'}
        },
        timeout=60
    )
    resp.raise_for_status()
    rows = resp.json()['data']

    if not rows:
        return 'No rows returned'

    # Sanitize column names to UPPER_SNAKE_CASE
    orig_cols = list(rows[0].keys())
    safe_cols = [re.sub(r'[^A-Z0-9_]', '_', c.upper()) for c in orig_cols]
    col_defs  = ', '.join(f'{c} VARIANT' for c in safe_cols)

    session.sql(f'CREATE OR REPLACE TABLE {target_table} ({col_defs})').collect()

    from snowflake.snowpark import Row
    sf_rows = [Row(**dict(zip(safe_cols, [row[c] for c in orig_cols]))) for row in rows]
    df = session.create_dataframe(sf_rows)
    df.write.mode('overwrite').save_as_table(target_table)

    return f'Loaded {len(rows)} rows into {target_table}'
$$;
```

```bash
snow sql --connection <conn> -f /tmp/vds_proc.sql
```

---

## Phase 3 — Run the load

Build the `fields_json` array from the datasource's fields. Each field is one of:
- `{"fieldCaption": "Category"}` — dimension (no aggregation)
- `{"fieldCaption": "Sales", "function": "SUM", "fieldAlias": "Total Sales"}` — measure

Supported `function` values: `SUM`, `AVG`, `MEDIAN`, `COUNT`, `COUNTD`, `MIN`, `MAX`.
Use `mcp__tableau__get-datasource-metadata` to list available field captions.

```bash
snow sql --connection <conn> -q "
USE ROLE <your_role>;
USE DATABASE <db>;
USE SCHEMA <schema>;
USE WAREHOUSE <wh>;

CALL query_tableau_vds(
  'https://<server>',
  '<site_name>',
  '<datasource_luid>',
  '<db>.<schema>.<TABLE_NAME>',
  '[
    {\"fieldCaption\": \"Category\"},
    {\"fieldCaption\": \"Sales\", \"function\": \"SUM\", \"fieldAlias\": \"Total Sales\"}
  ]'
);
"
```

Then verify:
```bash
snow sql --connection <conn> -q "SELECT * FROM <db>.<schema>.<TABLE_NAME> LIMIT 10;"
```

---

## Phase 4 — Schedule with a Snowflake Task (optional)

```sql
CREATE OR REPLACE TASK refresh_tableau_data
  WAREHOUSE = <wh>
  SCHEDULE = 'USING CRON 0 6 * * * America/Los_Angeles'   -- daily at 6am PT
AS
  CALL query_tableau_vds(
    'https://<server>',
    '<site_name>',
    '<datasource_luid>',
    '<db>.<schema>.<TABLE_NAME>',
    '[{"fieldCaption": "Category"}, {"fieldCaption": "Sales", "function": "SUM", "fieldAlias": "Total Sales"}]'
  );

-- Tasks start suspended; resume to activate
ALTER TASK refresh_tableau_data RESUME;
```

Check task history:
```sql
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(task_name => 'refresh_tableau_data'))
ORDER BY scheduled_time DESC LIMIT 10;
```

---

## Column types

The stored procedure stores all columns as `VARIANT` (Snowflake semi-structured type).
This avoids type-mismatch errors for numbers returned as floats by VDS.

To cast to typed columns for downstream use:
```sql
CREATE OR REPLACE VIEW <db>.<schema>.<TABLE_NAME>_TYPED AS
SELECT
  CATEGORY::VARCHAR   AS CATEGORY,
  TOTAL_SALES::FLOAT  AS TOTAL_SALES
FROM <db>.<schema>.<TABLE_NAME>;
```

---

## Finding fields available on a datasource

Use the MCP metadata tool:
```
mcp__tableau__get-datasource-metadata  datasourceLuid="<luid>"
```

Or query VDS metadata endpoint directly:
```bash
curl -s -X POST "https://<server>/api/v1/vizql-data-service/read-metadata" \
  -H "x-tableau-auth: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"datasource": {"datasourceLuid": "<luid>"}}' | python3 -m json.tool
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `404` on `/api/v1/sites/.../datasources/.../query` | Wrong VDS URL — the Tableau docs example uses this but the real endpoint is different | Use `/api/v1/vizql-data-service/query-datasource` with `datasource.datasourceLuid` in body |
| `401` on VDS query | Token expired (PAT tokens last ~hours) or wrong `x-tableau-auth` header name | Re-authenticate and retry; confirm header is `x-tableau-auth` not `Authorization` |
| `json.decoder.JSONDecodeError` parsing auth response | Tableau signin returns XML, not JSON | Parse with `re.search(r'token="([^"]+)"', response.text)` |
| EAI creation error: "Network rule not found" | Fully-qualified name required | Use `<db>.<schema>.tableau_api_rule` in the `ALLOWED_NETWORK_RULES` list |
| Procedure error: "secret not found" | Secret must be fully qualified in procedure DDL | Use `<db>.<schema>.tableau_pat_secret` in `SECRETS = (...)` |
| `requests.exceptions.ConnectionError` in procedure | EAI not attached to the procedure, or network rule host mismatch | Verify `EXTERNAL_ACCESS_INTEGRATIONS = (tableau_vds_eai)` is in the CREATE PROCEDURE DDL; confirm host in network rule exactly matches the Tableau server hostname |
| VDS returns `{"error": "datasource not found"}` | Datasource LUID is wrong or datasource was deleted/moved | Re-fetch LUID via `mcp__tableau__list-datasources` |
| Columns with spaces get `_` substitution | `re.sub(r'[^A-Z0-9_]', '_', c.upper())` replaces spaces and special chars | Expected — use a typed view (see Column types section) to rename back if needed |
| Task runs but table is empty | PAT expired (PATs have a max TTL) | Rotate PAT in Tableau Cloud → update secret: `ALTER SECRET tableau_pat_secret SET SECRET_STRING = '...'` |
