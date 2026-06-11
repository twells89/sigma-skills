# Workbook Spec — Top-Level Schema

Recipe + reference for the overall shape of the top-level workbook spec object and the `pages` array skeleton. The full schema lives in the OpenAPI:

```bash
jq '.paths."/v2/workbooks/spec".post.requestBody.content."application/json".schema' /tmp/sigma-api.json
```

This file covers what the OpenAPI alone won't tell you: which fields are response-only (ignored on write), the page and ID rules, and a minimal working example. See the per-element and per-source reference files for the pieces that go inside `pages[].elements[]`.

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

`GET /v2/workbooks/<id>/spec` also returns these server-managed fields. They're **ignored** on write (POST/PUT), so you don't have to strip them before re-submitting a GET response — though it's cleaner to:

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
visibility: shown   # optional: "shown" (default) | "hidden"
```

The `elements` array holds table elements, charts, KPIs, controls, and containers. See the per-element reference files.

`visibility: hidden` keeps the page in the workbook (so other elements can `source` from its tables via `elementId`) but excludes it from the viewer. See `reference/workflows/composition.md` for when to reach for this.

## ID Rules

- Element IDs and column IDs must be unique within their scope.
- Use descriptive kebab-case or short random-looking IDs — both are fine. IDs are internal identifiers, not displayed to users.
- IDs you submit are **preserved verbatim** on `POST` — pages, elements, and columns keep the `id` values you sent, and layout `elementId` references stay valid. You can edit your saved spec and `PUT` it back directly. Layout `elementId` references must match an element `id` on that page exactly (case-sensitive).

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

For a realistic multi-page, multi-element spec, fetch an existing workbook's spec (`GET /v2/workbooks/{id}/spec`, see SKILL.md Steps 1–2) — a live spec is current and reflects real usage. For how much to build for a given request, see `reference/workflows/composition.md`.
