# Workbook Spec CRUD

POST / GET / PUT against the workbook spec endpoints. Load this when creating, retrieving, or updating a workbook.

Every call includes `-H "Authorization: Bearer $SIGMA_API_TOKEN"`. Auth comes from the `sigma-api` skill.

## Endpoints

```bash
# CREATE — POST the spec, response includes workbookId
curl -s -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/workbook-spec.json \
  "$SIGMA_BASE_URL/v2/workbooks/spec"

# GET — retrieve current spec (always send Accept: application/json)
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/json" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec"

# UPDATE — PUT replaces the entire spec
curl -s -X PUT -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/workbook-spec.json \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec"
```

## Required Fields on CREATE

The POST body must include:

- `name` (string)
- `folderId` (string — usually the user's `homeFolderId`)
- `schemaVersion` (number — use the value returned by `GET /v2/workbooks/<template-id>/spec`, do NOT hardcode it)
- `pages` (array — at least one page with at least one element)

Optional: `description`, `layout` (top-level layout XML).

```json
{
  "name": "Sales Dashboard",
  "folderId": "<homeFolderId>",
  "description": "Sales overview dashboard",
  "schemaVersion": 1,
  "pages": [...]
}
```

The server rejects a spec whose `schemaVersion` doesn't match what the current API expects, hence the rule against hardcoding it — always read it back from a recent template GET.

The CREATE response shape is `{"success": true, "workbookId": "..."}`. Extract `workbookId` to construct the workbook URL or drive subsequent updates.

## GET Returns YAML by Default

`GET /v2/workbooks/<id>/spec` responds with `application/yaml` unless you send `Accept: application/json`. If you pipe the response into `jq` without that header and it chokes, the response is YAML, not JSON — add the header.

## Persisting the Spec

After a successful CREATE, copy the spec to a workbook-keyed path so it survives the next build, the user can diff or re-POST it, and subsequent PUTs can start from it:

```bash
WORKBOOK_ID=$(jq -r '.workbookId' /tmp/create-response.json)
cp /tmp/workbook-spec.json "/tmp/workbook-spec-${WORKBOOK_ID}.json"
```

After a successful PUT, refresh the saved copy from the file you just submitted so it tracks server state:

```bash
cp /tmp/current-spec.json "/tmp/workbook-spec-<workbook-id>.json"
```

Report **both** the workbook URL **and** the saved spec path.

## UPDATE Is Full Replacement (No Diffs)

The PUT endpoint replaces the entire spec — partial updates are not supported. Always:

1. GET the current spec first (with `Accept: application/json`).
2. Edit the file on disk.
3. PUT the **full** payload back.

If you skip the GET and submit a partial spec, anything you didn't include is gone.

## ID Remapping on CREATE

> **Critical:** the `id` values you sent in `POST /v2/workbooks/spec` — for pages, elements, columns — are **not** preserved verbatim. The server maps them to internal IDs and **those internal IDs** are what live references (especially the `layout` XML's `elementId` attributes) must use.

Before **any** follow-up `PUT`, always `GET` the current spec first and use the IDs from the readback. If you PUT a layout XML that references your original external IDs, elements will silently not appear.

The same caveat applies to any cross-reference — control bindings, element source references that name another element by ID, etc. After the initial CREATE, the source of truth for IDs is whatever the server returned, not what you submitted.

## Response-Only Fields to Strip

`GET /v2/workbooks/<id>/spec` returns extra server-managed fields. When you take a GET response and PUT it back (the standard update flow), the server will silently ignore most of them, but it's cleaner to strip them. See `reference/specification/schema.md` for the canonical list.

## Iteration Pattern

```bash
# Get current spec (Accept: application/json — default is YAML)
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/json" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec" \
  > /tmp/current-spec.json

# Edit /tmp/current-spec.json on disk, then:
curl -s -X PUT -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/current-spec.json \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec" | jq .

# Refresh the saved copy so the next edit starts from the latest spec
cp /tmp/current-spec.json "/tmp/workbook-spec-<workbook-id>.json"
```
