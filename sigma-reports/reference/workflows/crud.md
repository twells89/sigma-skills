# Report Code Representation CRUD

All calls require `Authorization: Bearer $SIGMA_API_TOKEN`. The current OpenAPI
declares JSON bodies and responses for the report spec endpoints.

## Verify without persistence

Use the create envelope with the verify endpoint:

```bash
curl -sf -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-spec.json \
  "$SIGMA_BASE_URL/v2/reports/spec/verify"
```

Make this the default live probe. It does not create a report.

## Create

Creating is persistent and the current API has no report DELETE endpoint. Get
explicit approval for the destination folder before calling:

```bash
curl -sf -X POST \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-spec.json \
  "$SIGMA_BASE_URL/v2/reports/spec" \
  > /tmp/report-create.json
```

The success response contains `success` and `reportId`. Save the submitted
representation under a report-ID-specific path immediately.

Live-confirmed 2026-08-11: create returned HTTP 200 with
`{"success":true,"reportId":"..."}` after the same envelope returned
`{"valid":true}` from verify.

## Retrieve

```bash
curl -sf \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Accept: application/json" \
  "$SIGMA_BASE_URL/v2/reports/<report-id>/spec" \
  > /tmp/report-<report-id>-before.json
```

Keep the complete response as the rollback record. It includes outer metadata
and the report `document`.

## Update

PUT is full replacement and creates a new report version. Send exactly one
outer property, `document`:

```bash
jq '{document: .document}' /tmp/report-edited.json \
  > /tmp/report-put.json

ruby scripts/validate-spec.rb --mode update /tmp/report-put.json

curl -sf -X PUT \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary @/tmp/report-put.json \
  "$SIGMA_BASE_URL/v2/reports/<report-id>/spec" \
  > /tmp/report-update-response.json
```

Before PUT:

1. GET the latest representation and preserve its version metadata.
2. List the report's pages, elements, and controls through their inventory
   endpoints.
3. Compare inventory IDs with the representation.
4. Stop if inventory content is absent from `document`; GET can be lossy.
5. Preserve every page, panel, element, source, formula, setting, and layout
   entry not intentionally changed.
6. Validate the update body locally.
7. Assemble a create envelope around the edited document and call verify.

After PUT, GET again and compare normalized documents. Export the affected
pages as PDF and inspect them.

Live-confirmed 2026-08-11: PUT returned HTTP 200, retained the report ID, and
advanced `documentVersion`/`latestDocumentVersion` from 1 to 2. Header/footer
panels, element IDs, and pixel layout survived readback unchanged.

## No automated cleanup assumption

Do not design tests around create-then-delete. The current OpenAPI exposes GET
on `/v2/reports/{reportId}` but no DELETE operation. Reuse a designated manual
test report only when the user has approved that persistent resource.
