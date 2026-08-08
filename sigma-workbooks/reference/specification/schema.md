# Workbook Spec — Top-Level Schema

The live compiled OpenAPI is authoritative:

```bash
jq '.components.schemas.CreateWorkbookSpec' /tmp/sigma-api.json
```

## Canonical wrapped shape

```yaml
name: My Workbook
folderId: <folder-uuid>
description: Optional description
document:
  schemaVersion: 1
  kind: workbook
  elements: [...]  # required flat array
  pages: [...]     # required metadata only
  overlays: [...]  # optional modal/drawer metadata
  panels: [...]    # optional workbook panel metadata
  layout: |        # required by this skill whenever elements is non-empty
    <?xml version="1.0" encoding="utf-8"?>
    ...
  settings:
    theme: { ... }
    navigation: { ... }
  agents: [...]
```

POST requires outer `name`, `folderId`, and `document`. The live document
schema requires `schemaVersion`, `kind`, `elements`, and `pages`. PUT accepts
exactly `{document: {...}}`; never send `name`, `folderId`, or response metadata
beside it.

> Elements are not nested in pages, overlays, or panels. `document.elements` is
> the single literal element array. Placement in `document.layout` is the source
> of truth for page, overlay, panel, container, repeated-container, and tab
> membership. The API rejects `pages[].elements` and rejects an unplaced element.

### Settings

`document.settings.theme` replaces the removed `themeName` /
`themeOverrides` pair:

```yaml
settings:
  theme:
    name: Dark
    overrides:
      categoricalScheme: ["#2563EB", "#F97316", "#10B981"]
  navigation:
    position: side
    pageHeader:
      visibility: shown
```

Theme and navigation sub-fields evolve; inspect `CreateWorkbookSpec` before
using an unfamiliar option. See `styling.md` for the richer theme recipes and
`layout.md` for navigation/header/sidebar guidance.

## Pages

Pages are metadata only:

```yaml
- id: overview
  name: Overview
  type: page              # optional; defaults to page
  visibility: hidden      # optional, or the allowlist object below
  pageWidth: full
  backgroundColor: "#F8FAFC"
  backgroundImage:
    source:
      kind: url
      url: https://cdn.example.com/background.png
    style:
      fit: cover
      horizontalAlign: center
      verticalAlign: center
      tiling: none
```

The live page schema exposes `id`, `name`, `type`, `visibility`, `pageWidth`,
`backgroundColor`, and `backgroundImage`; it does not expose `elements`.
`backgroundImage.source` is either `{kind: url, url}` or an uploaded-image
reference from a readback. Container and chart background images retain their
own element-specific `{url: ...}` shape; do not transpose the page wrapper onto
those element kinds.

Restricted visibility:

```yaml
visibility:
  kind: specific-users-and-teams
  assignments:
    users: [<user-id>]
    teams: [<team-id>]
```

## Overlays

Modal and drawer definitions live in `document.overlays`, not in `pages`.
Their content still lives in flat `document.elements`; a layout `<Page>` block
whose `id` equals the overlay id assigns content to it.

```yaml
overlays:
  - id: detail-modal
    type: modal
    name: Detail
    modal:
      width: medium
      header: { title: Details }
      footer: { primaryCta: { text: Done } }
  - id: filter-drawer
    type: drawer
    name: Filters
    drawer:
      width: medium
      position: end
      showShadow: shown
      header: { title: Filters }
```

Overlay actions and open/close effects are in `reference/workflows/actions.md`.

## Panels

`document.panels` is the metadata collection for workbook panels such as
header/sidebar surfaces. Panel content is also selected by layout placement,
not a nested element list. Panel variants have different configuration fields;
read the live `panels` property before authoring one and preserve unknown panel
metadata on round trip.

## Response-only fields

GET can return these outer server-managed fields:

- `workbookId`, `url`
- `documentVersion`, `latestDocumentVersion`
- `ownerId`, `createdBy`, `updatedBy`, `createdAt`, `updatedAt`

They are not part of a PUT body.

## ID and layout rules

- Page, overlay, panel, element, action, and column IDs must be unique in their
  documented scopes.
- IDs submitted on POST are preserved.
- Every layout `elementId` must match a flat `document.elements[].id`.
- Every element must be placed exactly where intended in layout. Do not infer
  ownership from array adjacency.

## Minimal working example

```yaml
name: Sales Dashboard
folderId: <folder-uuid>
document:
  schemaVersion: 1
  kind: workbook
  elements:
    - id: sales-table
      kind: table
      name: Sales Data
      source:
        kind: warehouse-table
        connectionId: <connection-uuid>
        path: [SALES_DB, PUBLIC, ORDERS]
      columns:
        - id: col-order-id
          name: Order ID
          formula: "[ORDERS/ORDER_ID]"
        - id: col-amount
          name: Amount
          formula: "[ORDERS/AMOUNT]"
  pages:
    - id: overview
      name: Overview
  layout: |
    <?xml version="1.0" encoding="utf-8"?>
    <Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="overview">
      <Element elementId="sales-table" gridColumn="1 / 25" gridRow="1 / 20"/>
    </Page>
```

Raw warehouse names are accepted in warehouse-table formulas. Sigma may
canonicalize them on POST or preserve the raw spelling. Always GET the saved
spec and use the returned form for later edits; Custom SQL aliases and join
keys follow special rules documented in `formulas.md` and `sources.md`.
