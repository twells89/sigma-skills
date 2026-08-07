# Workbook Spec — Top-Level Schema

Recipe + reference for the overall shape of the top-level workbook spec object and the `pages` array skeleton. The full schema lives in the OpenAPI:

```bash
jq '.paths."/v2/workbooks/spec".post.requestBody.content."application/json".schema' /tmp/sigma-api.json
```

This file covers what the OpenAPI alone won't tell you: which fields are response-only (ignored on write), the page and ID rules, and a minimal working example. See the per-element and per-source reference files for the pieces that go inside `pages[].elements[]`.

## Top-Level Object

The object passed to `POST /v2/workbooks/spec`. **Everything except `name` / `folderId` / `description` lives inside a `document` wrapper:**

```yaml
name: My Workbook
folderId: <folder-uuid>
description: Optional description
document:
  schemaVersion: 1
  kind: workbook          # informational; ignored on write
  pages: [...]
  layout: |
    <?xml ...?>...
  agents: [...]           # optional — see agents.md
  settings:               # optional — theme + navigation
    theme: { ... }
    navigation: { ... }
```

**Required (outer):** `name`, `folderId`, `document`.
**Optional (outer):** `description`.
**Inside `document`:** `schemaVersion` and `pages` are required; `kind`, `layout`, `agents`, `settings` optional.

> **The wrapper is now documented in the OpenAPI** (confirmed 2026-08-05 against `assets.sigmacomputing.com/openapi/public-rest-api/…`). Older notes in this repo — and the stale Fern docs asset — described a flat `{name, folderId, schemaVersion, pages, layout}` body and treated the wrapper as an undocumented live-API divergence. That gap is closed: spec and live behavior agree, and the wrapped form is canonical. `PUT /v2/workbooks/{id}/spec` sends just `{document: {...}}`.

> **`themeName` / `themeOverrides` moved.** They are no longer `document`-level keys; theming now lives under `document.settings.theme` ("a built-in or org theme by name, plus per-field overrides"), alongside `document.settings.navigation` (page headers, sidebars, tabs). See `styling.md`.

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

### Page `type` — `page`, `modal`, or `drawer`

A page's optional `type` decides whether it's a navigable tab or an overlay. There are **three** variants, and they take different fields:

| `type` | Renders as | Extra fields |
|---|---|---|
| `page` (default) | A normal navigable page/tab | `visibility` |
| `modal` | A centered overlay | `modal`, `actions` |
| `drawer` | An overlay sliding in from a page edge | `drawer`, `actions` |

Only `type: page` accepts `visibility`; only the two overlay types accept `actions`. Both overlays are opened by the **same** `open-overlay` effect via `overlayId` pointing at the overlay **page's** `id` — see `reference/workflows/actions.md` → *Overlays*. **`drawer` is live-verified 2026-08-05** (create + readback round-trip, `type` intact).

The overlay config objects differ:

```yaml
# type: modal
modal:
  width: medium        # x-small | small | medium | large | x-large
  header: { ... }
  footer: { ... }

# type: drawer  — no footer; adds edge + shadow
drawer:
  width: medium        # x-small | small | medium | large | x-large
  position: end        # start | end  (which edge it slides from)
  showShadow: shown    # shown | hidden
  header: { ... }
```

Page-level `actions[]` entries are `{ id, trigger, effects, name?, state? }` where `trigger` ∈ `on-click`, `on-select`, `on-primary-cta-click`, `on-secondary-cta-click`, `on-close` and `state` ∈ `enabled`, `disabled`. The CTA triggers are what wire an overlay's header/footer buttons; `on-close` fires when the overlay dismisses. (Enums read from the OpenAPI; of these only the overlay round-trip itself is live-verified — the individual CTA triggers aren't yet.)

Overlay pages still need their own `<Page>` block in the top-level `layout` XML — see the layout gotcha in `actions.md`.

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
