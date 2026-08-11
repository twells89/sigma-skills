# Report Code Representation Schema

The compiled OpenAPI is authoritative for the current envelope:

```bash
jq '.paths."/v2/reports/spec".post.requestBody.content."application/json".schema' \
  /tmp/sigma-openapi.json
```

## Create and verify envelope

`POST /v2/reports/spec` and `POST /v2/reports/spec/verify` take the same wrapped
JSON shape:

```json
{
  "name": "Quarterly Statement",
  "folderId": "<folder-id>",
  "description": "Optional outer description",
  "document": {
    "schemaVersion": 1,
    "kind": "report",
    "config": {
      "margin": 48,
      "pageHeight": 1056,
      "pageWidth": 816
    },
    "elements": [],
    "pages": [{"id": "page-1", "name": "Page 1"}],
    "panels": [],
    "layout": "<Page id=\"page-1\"></Page>"
  }
}
```

Required outer fields are `name`, `folderId`, and `document`. Required
document fields are `schemaVersion`, `kind`, `elements`, and `pages`. This
skill requires explicit layout when elements are non-empty.

Use a `schemaVersion` returned by a recent report GET. Do not infer it from a
workbook or hardcode the value shown in examples.

## Update envelope

`PUT /v2/reports/{reportId}/spec` accepts only a complete document wrapper:

```json
{
  "document": {
    "schemaVersion": 1,
    "kind": "report",
    "config": {},
    "elements": [],
    "pages": [],
    "panels": [],
    "layout": "..."
  }
}
```

Do not include `name`, `folderId`, `reportId`, versions, timestamps, or other
GET metadata. PUT creates a new report version and replaces the complete
document. Anything omitted from the document can be lost.

## Pages

Pages are metadata, not element containers:

```json
{
  "id": "page-1",
  "name": "Statement",
  "type": "page",
  "visibility": "hidden",
  "pageWidth": "standard",
  "backgroundColor": "#FFFFFF"
}
```

The current shared page schema exposes `id`, `name`, `type`, `visibility`,
`pageWidth`, `backgroundColor`, and `backgroundImage`. Report physical size is
controlled by `document.config.pageWidth` and `pageHeight`; do not confuse that
pixel configuration with the shared page metadata field.

Keep report pages at or below the documented 1,000-page limit. The local
validator rejects larger documents.

## Report configuration

`document.config` is report-specific:

- `pageWidth`: page width in pixels
- `pageHeight`: page height in pixels
- `margin`: page margin in pixels

Values must be finite and non-negative where applicable. Page width and height
must be positive and no larger than 10,000 pixels. A margin must leave a
positive content area.

## Header and footer panels

Report panels are not workbook panels:

```json
{
  "id": "statement-header",
  "type": "header",
  "title": "Statement header",
  "pages": ["page-1"],
  "config": {
    "height": 64,
    "backgroundColor": "#F5F7FA"
  }
}
```

- `type` is `header` or `footer`, never workbook `sidebar`.
- `pages` contains IDs of report pages that receive the panel.
- `config.height` is in pixels.
- Panel content remains in flat `document.elements` and is assigned by a
  matching `<Panel>` layout root.
- A page can have at most one header and one footer assignment.

## Flat elements

All literal elements live in `document.elements`. Pages and panels never have
nested `elements` arrays. Every element has a unique ID and is placed exactly
once in layout.

Reports use the OpenAPI `CommonElement` union. This does not mean every union
member works safely in reports. Apply `support-matrix.md` before authoring.

## GET metadata

GET returns outer report identity, ownership, timestamps, URL, and document
version metadata in addition to `document`. Preserve the full GET response as
a backup, but extract only `document` for PUT.

The exact response fields can evolve. Inspect:

```bash
jq '.paths."/v2/reports/{reportId}/spec".get.responses."200".content."application/json".schema' \
  /tmp/sigma-openapi.json
```

## Media type

The current OpenAPI declares `application/json` for create, verify, read, and
update. Some narrative documentation mentions YAML, but that contradiction has
not been established as a safe report contract. Use JSON until a live probe
proves otherwise.
