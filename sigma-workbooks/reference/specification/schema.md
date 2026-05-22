# Workbook Spec — Top-Level Schema

Recipe + reference for the overall shape of the top-level workbook spec object and the `pages` array skeleton. The full schema lives in the OpenAPI:

```bash
jq '.paths."/v2/workbooks/spec".post.requestBody.content."application/json".schema' /tmp/sigma-api.json
```

This file covers what the OpenAPI alone won't tell you: which fields are response-only (must be stripped before re-POSTing), the ID-reassignment trap on CREATE, and a minimal working example. See the per-element and per-source reference files for the pieces that go inside `pages[].elements[]`.

## Top-Level Object

The object passed to `POST /v2/workbooks/spec`:

```yaml
name: My Workbook
folderId: <folder-uuid>
description: Optional description
schemaVersion: 1
pages: [...]
layout: |
  <?xml ...?>...
```

**Required:** `name`, `folderId`, `schemaVersion`, `pages`.
**Optional:** `description`, `layout`.

Use the `schemaVersion` returned by `GET /v2/workbooks/<reference-workbook-id>/spec` in Step 2 of the workflow — don't hardcode it. The server will reject a spec whose `schemaVersion` doesn't match what the API expects.

## Response-Only Fields

`GET /v2/workbooks/<id>/spec` also returns these — they **must be stripped** before using the spec as a create/update body. Sending unknown top-level fields will be rejected:

- `workbookId`
- `url`
- `documentVersion`
- `latestDocumentVersion`
- `ownerId`
- `createdBy`
- `updatedBy`
- `createdAt`
- `updatedAt`

## Pages

`pages` is the core of the spec. Each page:

```yaml
id: page-1
name: Overview
elements: [...]
```

The `elements` array holds table elements, charts, KPIs, controls, and containers. See the per-element reference files.

## ID Rules

- Element IDs and column IDs must be unique within their scope.
- Use descriptive kebab-case or short random-looking IDs — both are fine. IDs are internal identifiers, not displayed to users.
- **Critical:** on `POST`, the server reassigns external IDs to internal ones. For any follow-up `PUT` (especially layout XML updates), GET the current spec first and use the IDs from the readback. Layout `elementId` references must match the current internal IDs exactly (case-sensitive).

## Minimal Working Example

The smallest spec that creates a workable workbook:

```yaml
name: Sales Dashboard
folderId: <folder-uuid>
schemaVersion: 1
pages:
  - id: page-1
    name: Overview
    elements:
      - id: sales-table
        kind: table
        name: Sales Data
        source:
          kind: warehouse-table
          connectionId: <conn-uuid>
          path: [SALES_DB, PUBLIC, ORDERS]
        columns:
          - id: col-order-id
            name: Order ID
            formula: "[ORDERS/order_id]"
          - id: col-amount
            name: Amount
            formula: "[ORDERS/amount]"
          - id: col-revenue
            name: Revenue
            formula: "[ORDERS/revenue]"
          - id: col-cost
            name: Cost
            formula: "[ORDERS/cost]"
          - id: col-date
            name: Date
            formula: "[ORDERS/order_date]"
          - id: col-total
            name: Total Amount
            formula: Sum([Amount])
          - id: col-profit
            name: Profit
            formula: "[Revenue] - [Cost]"
```

Note how:
- `[ORDERS/order_id]` references a warehouse column (table prefix required).
- `Sum([Amount])` references the "Amount" column defined in the same element (no prefix).
- `[Revenue] - [Cost]` references two other columns in the same element by their `name` field.

For a realistic multi-page, multi-element spec with KPIs, charts, joins, controls, and layout, see `example-full.yaml`.
