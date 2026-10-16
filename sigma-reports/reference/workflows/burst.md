# Burst a Report: One Copy per Recipient

Bursting renders the same report once per value of a control (a store, an
account, a cost center) and delivers each copy to that value's owner. In the
report code representation this is not a separate feature: it is a report
control that filters every data source, plus one export or schedule per
control value.

The worked example in
[`examples/store-operating-report/`](../../examples/store-operating-report/)
implements this end to end for 57 stores.

## Evidence

| Step | State | Evidence |
|---|---|---|
| Single-select list control that filters custom-SQL sources | Live-proven 2026-10-16 | verify, create, PUT, readback, populated PDF per store |
| `POST /v2/reports/{id}/export` with `parameters: {control-id: value}` | Live-proven 2026-10-16 | three stores exported; headline values matched warehouse SQL |
| `POST /v2/reports/{id}/schedules` with `configV2.controlValues` | Schema-derived | bodies drafted from the OpenAPI, not created |

Create schedules only after the user approves a specific recipient list. A
schedule sends real email on its cron; never create one against sample or
unverified addresses.

## 1. Design the burst key into the data layer

- Every source the visible pages read must carry the burst key column
  (`store_id`). Put the sources on a hidden data page.
- Compute peer or company comparisons inside the SQL with window functions.
  The control filters the SQL result, so values computed before the filter
  (region averages, ranks) still see every row.
- Add a separate, unfiltered list source for the control's values. Use a
  display label that is unique; names can repeat across keys
  (`ST001 · New York Main` and `ST056 · New York Main`).
- Resolve the recipient in SQL with an explicit fallback, and expose it on the
  page (for example "Delivered to …") so a wrong recipient is visible in the
  PDF.

## 2. Author the control

```json
{
  "id": "ctl-store-el",
  "kind": "control",
  "controlId": "store",
  "controlType": "list",
  "name": "Store",
  "source": {
    "kind": "source",
    "source": {"kind": "table", "elementId": "src-stores"},
    "columnId": "src-stores-store_id",
    "displayColumnId": "src-stores-store_label"
  },
  "selectionMode": "single",
  "value": "ST001",
  "filters": [
    {"source": {"kind": "table", "elementId": "src-summary"}, "columnId": "src-summary-store_id"},
    {"source": {"kind": "table", "elementId": "src-daily"}, "columnId": "src-daily-store_id"}
  ]
}
```

- Add one `filters[]` entry per data source, pointing at that source's key
  column ID. Do not make the control filter its own value source.
- Place the control on the hidden data page so it stays out of the PDF.
- `GET /v2/reports/{id}/spec` returns this control as
  `{"controlType": "synced"}` with no source or filters, and the local
  validator rejects `synced`. Keep the authored document as the source of
  truth and rebuild PUT bodies from it, never from the readback. Confirm the
  control survived with `GET /v2/reports/{id}/controls`, which lists
  `{"name": "store", "valueType": "text"}`.

## 3. Prove each copy before scheduling

```bash
curl -s -X POST -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"format":{"type":"pdf","layout":"portrait"},"parameters":{"store":"ST015"}}' \
  "$SIGMA_BASE_URL/v2/reports/<report-id>/export"
# → {"jobComplete": false, "queryId": "..."}; poll until the body is a PDF:
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/query/<query-id>/download" -o st015.pdf
```

Export a representative sample, for example one key per tier or segment plus
one that exercises the recipient fallback. For each, compare the headline
numbers against a direct warehouse query and read every page.

## 4. Draft one schedule per value

The schedules API takes one `controlValues` map per schedule, so a burst is N
schedules:

```json
{
  "target": [{"email": "test-inbox@example.com"}],
  "schedule": {"cronSpec": "0 7 2 * *", "timezone": "America/New_York"},
  "configV2": {
    "title": "New York Main (ST001) — Monthly Store Operating Report",
    "messageBody": "Attached is last month's operating report.",
    "exportAttachments": [{"formatOptions": {"type": "PDF", "layout": "portrait"}}],
    "conditionOptions": {"type": "always"},
    "controlValues": {"store": {"type": "text", "value": "ST001"}}
  }
}
```

Draft every body locally in test mode first, with all targets set to one review
inbox and the intended recipient noted in the message. Switch to real targets
only after sign-off. `draft-burst-schedules.rb` in the example does both.

An alternative that needs no schedules is an on-demand loop: export each key
with `parameters`, download the PDFs, and hand them to the customer's own
delivery system.
