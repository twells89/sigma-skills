# Validate — Pre-Submit Checklist & Troubleshooting

Run through this before every `POST /v2/dataModels/spec` and `PUT /v2/dataModels/<id>/spec`. Most failures are catchable here.

## Pre-submit checklist

- [ ] `name` and `folderId` are set (required at create time).
- [ ] `schemaVersion` is the value returned by `GET /v2/dataModels/<reference-id>/spec` — never hardcoded.
- [ ] Every element has a unique `id` and a descriptive `name`.
- [ ] Every column has a unique `id` and a `formula`.
- [ ] Warehouse-table column IDs follow `inode-<22-char>/<COLUMN_NAME_UPPER>` format.
- [ ] Generated short IDs (10-char alphanumeric) are unique within their scope.
- [ ] Every formula reference matches an existing column or element name **case-sensitively** — `[ORDERS/Order Id]` ≠ `[orders/order id]`.
- [ ] No `IsIn(...)` calls. (Sigma's formula language has no `IsIn` — see `../formulas` cross-link in the workbook skill, or use chained `or` instead.)
- [ ] No `CountOver` / `SumOver` / `RowNumberOver` in **DM element calculated columns** — they silently fail. See `../calc-columns.md` for workarounds.
- [ ] If `relationships[]` is set, every `targetElementId` exists in `pages[].elements[].id`.
- [ ] If joining a new element to an existing one in an UPDATE, the existing element's ID is the **server-assigned internal ID** (from a fresh `GET`), not your external draft ID. See `crud.md` "mixed-ID rule."
- [ ] Response-only fields (`dataModelId`, `url`, `documentVersion`, `latestDocumentVersion`, `ownerId`, `createdBy`, `updatedBy`, `createdAt`, `updatedAt`) are stripped from the request body.

## Decode common errors

| Error | Likely cause |
|---|---|
| `400 Invalid argument` / `unknown field` / `unexpected property` | Schema drift between this skill and the live API. Fetch the OpenAPI (`https://help.sigmacomputing.com/openapi/sigma-computing-public-rest-api.json`) and diff field names. |
| `400 Invalid column reference` | Bare `[col]` used where `[TABLE/col]` was needed, or the column name is misspelled. |
| `400 Invalid element ID` (in relationships) | An UPDATE that mixes external and internal IDs. The existing element ID must come from `GET`. |
| `403 Forbidden` | Credential lacks "Create, edit, and publish data models" permission, or "Can edit" on the destination folder. Ask your Sigma admin. |
| `409 Conflict` (`inode_archived`) | The target file is archived. Restore via `PATCH /v2/files/<id>` with `{"restore": true}`, then retry. |

## When stuck — pull a known-working model

If a fix doesn't work after one or two attempts, **stop iterating and pull the spec of a real, working data model in the user's workspace**:

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels/<workingModelId>/spec" > /tmp/reference-spec.json
```

Diff your draft against `/tmp/reference-spec.json`. Real working specs encode all the constraints the docs may omit. Match the working shape rather than guessing.

To find candidate models:

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels?limit=200" | jq '.entries[] | select(.path | startswith("Production")) | {dataModelId, name}'
```

Pick one that uses the same source kind / relationship style / metric pattern as your draft.

## After CREATE — IDs reassign

The server remaps your external IDs to internal ones on `POST`. **Before any follow-up `PUT`** that adds to or modifies the model, GET the current spec and use the IDs from the readback. See `crud.md` for the full ID-remap behavior.

## Manual smoke-test in the UI

After a successful CREATE or UPDATE, open the model in the Sigma UI. Check:

- All expected elements appear in the model panel.
- Relationships are drawn as expected.
- A sample query (preview a column) returns rows, not an error icon.
- Metrics show the right formula in the metric editor.

A spec that POSTs cleanly can still render broken — the manual check catches that.
