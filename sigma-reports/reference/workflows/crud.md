# Report Code Representation CRUD

All calls require `Authorization: Bearer $SIGMA_API_TOKEN`. The current OpenAPI
declares JSON bodies and responses for the report endpoints.

> **The `/spec` report endpoints are deprecated** (OpenAPI 2.0.0+20261030):
> `POST /v2/reports/spec`, `POST /v2/reports/spec/verify`, and
> `GET`/`PUT /v2/reports/{reportId}/spec`. Their replacements are `POST /v2/reports`
> (create; `dryRun: true` validates), `GET /v2/reports/{reportId}?includeContents=true`,
> and `PUT /v2/reports/{reportId}/contents`. The document key changes from
> `document` to `contents`; the content is otherwise byte-identical. Data-model
> `/v2/dataModels/spec` is **not** deprecated. The local authoring file
> (`{name, folderId, document}` from `scaffold-report.rb`) keeps `document`; the
> `jq` steps below re-key it for the wire.

## Verify without persistence

Use the create envelope with `dryRun: true` on the create endpoint:

```bash
jq -c '{name, folderId, description, contents: .document, dryRun: true}
       | with_entries(select(.value != null))' \
  /tmp/report-spec.json > /tmp/report-dryrun-body.json

curl -s -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-dryrun-body.json \
  "$SIGMA_BASE_URL/v2/reports"
```

Make this the default live probe. It does not create a report. Valid input
returns HTTP 200 `{"dryRun":true,"reportId":null,"warnings":[...],...}` (there is
no `valid` key); invalid input returns HTTP 400
`{"dryRun":true,"valid":false,"errors":[{"summary":"contents.kind: ..."}],"warnings":[]}`
— omit `curl -f` so the error body is not discarded.

## Create

Creating is persistent and the current API has no report DELETE endpoint. Get
explicit approval for the destination folder before calling:

```bash
jq -c '{name, folderId, description, contents: .document}
       | with_entries(select(.value != null))' \
  /tmp/report-spec.json > /tmp/report-create-body.json

curl -sf -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-create-body.json \
  "$SIGMA_BASE_URL/v2/reports" \
  > /tmp/report-create.json
```

The success response is the report envelope (`reportId`, `reportUrlId`, `url`,
`path`, `latestVersion`, ...) with no `success` key. Save the submitted
representation under a report-ID-specific path immediately.

Live-confirmed 2026-08-11 on the deprecated `/spec` endpoints: create returned
HTTP 200 with `{"success":true,"reportId":"..."}` after the same envelope
returned `{"valid":true}` from verify. On 2026-11-03 the replacement
`POST /v2/reports` dry-run returned HTTP 200 for a valid document and HTTP 400
`valid: false` for an invalid one.

## Retrieve

```bash
curl -sf \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/json" \
  "$SIGMA_BASE_URL/v2/reports/<report-id>?includeContents=true" \
  > /tmp/report-<report-id>-before.json
```

Keep the complete response as the rollback record. It includes outer metadata
(`reportId`, `path`, `latestVersion`, `documentVersion`, ...) and the report
`contents`. `includeContents=true` is required; without it the response has no
document. The default response is JSON (the deprecated `/spec` read defaulted
to YAML), but the `Accept: application/json` header above keeps it explicit.
Add `&documentVersion=<n>` to read an older version.

## Update

PUT is full replacement and creates a new report version. Send `contents` and
the `documentVersion` from the latest GET:

```bash
jq '{contents: .contents, documentVersion: .documentVersion}' \
  /tmp/report-edited.json \
  > /tmp/report-put.json

ruby scripts/validate-spec.rb --mode update /tmp/report-put.json

curl -sf -X PUT \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-put.json \
  "$SIGMA_BASE_URL/v2/reports/<report-id>/contents" \
  > /tmp/report-update-response.json
```

Before PUT:

1. GET the latest representation and preserve `documentVersion`.
2. List the report's pages, elements, and controls through their inventory
   endpoints.
3. Compare inventory IDs with the representation.
4. Stop if inventory content is absent from `contents`; GET can be lossy.
5. Preserve every page, panel, element, source, formula, setting, and layout
   entry not intentionally changed.
6. Validate the update body locally.
7. Assemble a create envelope around the edited document and run the `dryRun: true` check.

The current OpenAPI makes `documentVersion` optional, but omitting it removes
the optimistic-concurrency guard. Include it unless intentionally forcing the
latest complete document over concurrent edits. A stale version fails with
HTTP 400 `code: "stale_document_settings"` and must be resolved by GET,
reapplying the intended edit, and repeating validation; do not blindly retry
without reconciling.

After PUT, GET again and compare normalized documents. Export the affected
pages as PDF and inspect them:

```bash
ruby scripts/render-report.rb "<report-id>" /tmp/report-render --layout portrait
```

Live-confirmed 2026-08-11: PUT returned HTTP 200, retained the report ID, and
advanced `documentVersion`/`latestDocumentVersion` from 1 to 2 (the current
read returns `latestVersion` instead of `latestDocumentVersion`). Header/footer
panels, element IDs, and pixel layout survived readback unchanged.

## No automated cleanup assumption

Do not design tests around create-then-delete. The current OpenAPI exposes GET
on `/v2/reports/{reportId}` but no DELETE operation. Reuse a designated manual
test report only when the user has approved that persistent resource.
