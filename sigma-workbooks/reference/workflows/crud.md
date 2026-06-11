# Workbook Spec CRUD

Recipe + traps for POST / GET / PUT against `/v2/workbooks/spec`. Load this when creating, retrieving, or updating a workbook.

```bash
jq '.paths."/v2/workbooks/spec".post, .paths."/v2/workbooks/{workbookId}/spec".get, .paths."/v2/workbooks/{workbookId}/spec".put' /tmp/sigma-api.json
```

The endpoints are straightforward; the spec value is in calling out the **non-obvious behaviors**: YAML is the default content type (this skill prefers it for human readability), PUT being full-replacement (anything you omit is dropped), and server-managed fields being ignored rather than rejected on write.

Every call includes `-H "Authorization: Bearer $SIGMA_API_TOKEN"`. Auth comes from the `sigma-api` skill.

## Endpoints

```bash
# CREATE — POST the spec, response includes workbookId.
# YAML by default on both directions. `--data-binary` preserves the
# multiline body byte-for-byte (`-d` strips newlines, breaking YAML).
curl -s -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/workbook-spec.yaml \
  "$SIGMA_BASE_URL/v2/workbooks/spec"

# GET — retrieve current spec (YAML by default)
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec"

# UPDATE — PUT replaces the entire spec.
curl -s -X PUT -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/workbook-spec.yaml \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec"
```

If you'd rather work in JSON, swap `application/yaml` → `application/json` and `--data-binary @file.yaml` → `-d @file.json` on each call. Sigma accepts both. YAML is the recommended default for this skill because workbook specs are human-reviewable artifacts and YAML diffs cleanly in PRs.

## Required Fields on CREATE

The POST body must include:

- `name` (string)
- `folderId` (string — usually the user's `homeFolderId`)
- `schemaVersion` (number — use the value returned by `GET /v2/workbooks/<reference-workbook-id>/spec`, do NOT hardcode it)
- `pages` (array — at least one page with at least one element)

Optional: `description`, `layout` (top-level layout XML).

```yaml
name: Sales Dashboard
folderId: <homeFolderId>
description: Sales overview dashboard
schemaVersion: 1
pages: [...]
```

The server rejects a spec whose `schemaVersion` doesn't match what the current API expects, hence the rule against hardcoding it — always read it back from a recent reference GET.

The CREATE response shape (in YAML, the default):

```yaml
success: true
workbookId: <uuid>
```

Extract `workbookId` with `yq -r '.workbookId' /tmp/create-response.yaml` (or `jq` if you switched to JSON content types).

## Persisting the Spec

After a successful CREATE, copy the spec to a workbook-keyed path so it survives the next build, the user can diff or re-POST it, and subsequent PUTs can start from it:

```bash
WORKBOOK_ID=$(yq -r '.workbookId' /tmp/create-response.yaml)
cp /tmp/workbook-spec.yaml "/tmp/workbook-spec-${WORKBOOK_ID}.yaml"
```

After a successful PUT, refresh the saved copy from the file you just submitted so it tracks server state:

```bash
cp /tmp/current-spec.yaml "/tmp/workbook-spec-<workbook-id>.yaml"
```

Report **both** the workbook URL **and** the saved spec path.

## UPDATE Is Full Replacement (No Diffs)

The PUT endpoint replaces the entire spec — partial updates are not supported. Always:

1. GET the current spec first.
2. Edit the file on disk.
3. PUT the **full** payload back.

If you skip the GET and submit a partial spec, anything you didn't include is gone.

## IDs Are Preserved on CREATE

The `id` values you send in `POST /v2/workbooks/spec` — for pages, elements, and columns — are **preserved verbatim**. Layout `elementId` attributes, control bindings, and cross-element `source` references that name your IDs all stay valid after create. You can edit your saved spec and `PUT` it back directly; `GET` the current spec first only when you don't have your latest copy on hand.

## Response-Only Fields to Strip

`GET /v2/workbooks/<id>/spec` returns extra server-managed fields. When you take a GET response and PUT it back (the standard update flow), the server **ignores** them — you don't have to strip them, though it's cleaner to. See `reference/specification/schema.md` for the canonical list.

## Iteration Pattern

```bash
# Get current spec (YAML by default)
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec" \
  > /tmp/current-spec.yaml

# If you also want the HTTP status (e.g. for trace logging), keep streams
# separate: write the body via -o, send the status to stdout via -w.
# NEVER combine `-w "...%{http_code}..."` with `> body.yaml` — that mixes
# status text into the body file and corrupts the YAML.
curl -s -o /tmp/current-spec.yaml -w "%{http_code}\n" \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec"

# Edit /tmp/current-spec.yaml on disk, then:
curl -s -X PUT -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/current-spec.yaml \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/spec" | yq .

# Refresh the saved copy so the next edit starts from the latest spec
cp /tmp/current-spec.yaml "/tmp/workbook-spec-<workbook-id>.yaml"
```
