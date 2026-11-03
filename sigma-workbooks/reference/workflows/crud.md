# Workbook Spec CRUD

Recipe + traps for POST / GET / PUT against `/v2/workbooks` (create, `?includeContents=true` read, `/contents` update). Load this when creating, retrieving, or updating a workbook.

> **The `/spec` workbook endpoints are deprecated.** `POST /v2/workbooks`, `POST /v2/workbooks` with `dryRun: true`, `GET`/`PUT /v2/workbooks/{id}/spec` (and the matching `/v2/reports/...` endpoints) still respond but are flagged deprecated in OpenAPI 2.0.0+20261030. Use `POST /v2/workbooks` (with `dryRun: true` to validate), `GET /v2/workbooks/{id}?includeContents=true`, and `PUT /v2/workbooks/{id}/contents`. The **data-model** `/v2/dataModels/spec` endpoints are **not** deprecated — leave them alone.

```bash
jq '.paths."/v2/workbooks".post, .paths."/v2/workbooks/{workbookId}".get, .paths."/v2/workbooks/{workbookId}/contents".put' /tmp/sigma-api.json
```

The endpoints are straightforward; the spec value is in calling out the **non-obvious behaviors**: YAML works but must be requested explicitly (this skill prefers it for human readability), PUT being full-replacement (anything you omit is dropped), server-managed fields being ignored rather than rejected on write, and the document being **wrapped under `contents`, not flat** (below).

Every call includes `-H "Authorization: Bearer $SIGMA_API_TOKEN"`. Auth comes from the `sigma-api` skill.

## The body is wrapped under `contents`

`schemaVersion`, `kind`, flat `elements`, metadata-only `pages`, `overlays`,
`panels`, `layout`, `settings`, and `agents` nest under `contents`; `name`,
`folderId`, `description`, and response metadata stay outside it. A flat body
gets HTTP 400. `contents` is byte-identical to what the deprecated `/spec`
endpoints called `document` (live readbacks match exactly), so a spec saved
from the old endpoints only needs the wrapper key renamed.

`scripts/wb-rep.rb` and `scripts/lib/code_rep.rb` keep the on-disk artifact
under `document` and re-key to `contents` at the API boundary
(`Sigma::CodeRep.create_body` / `update_body`), so older saved specs and reps
keep working.

## Endpoints

```bash
# VALIDATE — same body as CREATE plus `dryRun: true`; nothing is persisted.
# Valid -> HTTP 200 {dryRun: true, workbookId: null, warnings: [...]} (no `valid`
# key). Invalid -> HTTP 400 {dryRun: true, valid: false, errors: [{summary}]}
# with paths like `contents.elements[0]: Invalid kind: ...`.
# (Replaces POST /v2/workbooks/spec/verify.)
curl -s -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/workbook-spec-dryrun.yaml \
  "$SIGMA_BASE_URL/v2/workbooks"

# CREATE — POST the spec, response is the workbook envelope (workbookId,
# workbookUrlId, url, path, latestVersion, ...). There is no `success` key.
# YAML works in both directions when you ask for it. `--data-binary`
# preserves the multiline body byte-for-byte (`-d` strips newlines, breaking YAML).
curl -s -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/workbook-spec.yaml \
  "$SIGMA_BASE_URL/v2/workbooks"

# GET — retrieve the current document. `includeContents=true` is required for
# `contents`; add `&documentVersion=N` for an older version. The default
# response is JSON, so send Accept: application/yaml for YAML. The response is
# {workbookId, name, url, path, latestVersion, documentVersion, ..., contents: {...}};
# it has `path` instead of `folderId`.
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/yaml" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>?includeContents=true"

# UPDATE — PUT replaces the entire document. Send ONLY {contents: {...}}
# (plus an optional documentVersion) — not name/folderId; the workbook id in
# the URL is what's being updated. A stale documentVersion -> HTTP 400
# {code: "stale_document_settings"}: re-GET, re-apply the edit, retry.
curl -s -X PUT -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/workbook-spec-put-body.yaml \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/contents"
```

If you'd rather work in JSON, swap `application/yaml` → `application/json` and `--data-binary @file.yaml` → `-d @file.json` on each call. Sigma accepts both (OpenAPI declares only JSON; YAML request and response bodies were verified live 2026-11-03). YAML is the recommended default for this skill because workbook specs are human-reviewable artifacts and YAML diffs cleanly in PRs.

## Required Fields on CREATE

The POST body must include:

- `name` (string) — outer level
- `folderId` (string — usually the user's `homeFolderId`) — outer level
- `contents.schemaVersion` (number — use the value returned by `GET /v2/workbooks/<reference-workbook-id>?includeContents=true`, do NOT hardcode it)
- `contents.kind: workbook`
- `contents.elements` (flat array; required even when empty)
- `contents.pages` (metadata array; no nested elements)

Optional in OpenAPI: `description` (outer), `dryRun` (outer), `contents.overlays`,
`contents.panels`, `contents.settings`, `contents.agents`, and
`contents.layout`. This skill requires layout whenever elements is non-empty.

```yaml
name: Sales Dashboard
folderId: <homeFolderId>
description: Sales overview dashboard
contents:
  schemaVersion: 1
  kind: workbook
  elements: [...]
  pages: [...]
  layout: |
    <?xml version="1.0" encoding="utf-8"?>
    ...
```

The server rejects a spec whose `schemaVersion` doesn't match what the current API expects, hence the rule against hardcoding it — always read it back from a recent reference GET.

The CREATE response is the workbook envelope (in YAML when you send `Accept: application/yaml`):

```yaml
workbookId: <uuid>
workbookUrlId: <urlId>
name: Sales Dashboard
url: https://app.sigmacomputing.com/<org>/workbook/<urlId>
path: My Documents
latestVersion: 1
```

There is **no `success` key** any more (the deprecated `/spec` create returned `{success: true, workbookId}`); check the HTTP status and read `workbookId`.

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

The PUT endpoint replaces the entire `contents` — partial updates are not supported. Always:

1. GET the current document first (`?includeContents=true`) and note its `documentVersion`.
2. Edit inside `contents` — preserving `elements`, `pages`, `overlays`,
   `panels`, `layout`, `settings`, and `agents`.
3. PUT the **full** `contents` object back — just `{contents: {...}}` (optionally with `documentVersion` from step 1 so a concurrent edit fails with `stale_document_settings` instead of being overwritten), not the outer `name`/response-only fields the GET also returned.

If you skip the GET and submit a partial `contents`, anything you didn't include is gone.

## IDs Are Preserved on CREATE

The `id` values you send in `POST /v2/workbooks` — for pages, elements, and columns — are **preserved verbatim**. Layout `elementId` attributes, control bindings, and cross-element `source` references that name your IDs all stay valid after create. You can edit your saved spec and `PUT` it back directly (re-wrapped as `{contents: {...}}` — see below); `GET` the current spec first only when you don't have your latest copy on hand.

## Response-Only Fields to Strip

`GET /v2/workbooks/<id>?includeContents=true` returns extra server-managed fields at the **outer level** (alongside `name`, not inside `contents`) — `workbookId`, `workbookUrlId`, `url`, `path`, `latestVersion`, `documentVersion`, `ownerId`, etc. (the deprecated `/spec` read returned `folderId` and `latestDocumentVersion`; the current read returns `path` and `latestVersion` instead and **no `folderId`** — look the parent folder up with `GET /v2/files/<id>` → `parentId` if you need it). Since PUT only accepts `{contents: {...}}` (plus `documentVersion`) anyway (see *The body is wrapped under `contents`*, above), these never go on the wire for an update — there's nothing to strip once you're sending just the `contents` object. See `reference/specification/schema.md` for the canonical list.

## Iteration Pattern

```bash
# Get current document (ask for YAML explicitly — the default is JSON) — full
# response shape: {workbookId, name, url, path, ..., documentVersion,
# contents: {schemaVersion, kind, elements, pages, overlays, panels, layout,
# settings, agents}}
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/yaml" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>?includeContents=true" \
  > /tmp/current-spec.yaml

# If you also want the HTTP status (e.g. for trace logging), keep streams
# separate: write the body via -o, send the status to stdout via -w.
# NEVER combine `-w "...%{http_code}..."` with `> body.yaml` — that mixes
# status text into the body file and corrupts the YAML.
curl -s -o /tmp/current-spec.yaml -w "%{http_code}\n" \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/yaml" \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>?includeContents=true"

# Edit /tmp/current-spec.yaml on disk (edit inside .contents), then extract
# ONLY the contents object for the PUT body — sending the outer name/
# response-only fields alongside it risks an "unexpected property" 400.
# Add documentVersion to make a concurrent edit fail instead of being overwritten:
yq '{"contents": .contents, "documentVersion": .documentVersion}' /tmp/current-spec.yaml > /tmp/current-spec-put.yaml
curl -s -X PUT -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/yaml" \
  -H "Accept: application/yaml" \
  --data-binary @/tmp/current-spec-put.yaml \
  "$SIGMA_BASE_URL/v2/workbooks/<workbook-id>/contents" | yq .

# Refresh the saved copy (full GET shape) so the next edit starts from the latest spec
cp /tmp/current-spec.yaml "/tmp/workbook-spec-<workbook-id>.yaml"
```
