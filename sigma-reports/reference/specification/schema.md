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

`PUT /v2/reports/{reportId}/spec` requires a complete document and accepts the
current `documentVersion` for optimistic concurrency:

```json
{
  "documentVersion": 7,
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

`documentVersion` is optional in OpenAPI but should be copied from the latest
GET. Sigma then rejects the PUT if another edit advanced the report first.
Do not include `name`, `folderId`, `reportId`, `latestDocumentVersion`,
timestamps, or other GET metadata. PUT creates a new report version and
replaces the complete document. Anything omitted from the document can be
lost.

## Pages

Pages are metadata, not element containers:

```json
{
  "id": "page-1",
  "name": "Statement",
  "type": "page",
  "visibility": "hidden",
  "pageWidth": "standard",
  "backgroundColor": "#FFFFFF",
  "backgroundImage": {
    "source": {
      "kind": "url",
      "url": "https://cdn.example.com/background.png"
    },
    "style": {
      "fit": "cover",
      "horizontalAlign": "center",
      "verticalAlign": "center",
      "tiling": "none"
    }
  }
}
```

The current shared page schema exposes `id`, `name`, `type`, `visibility`,
`pageWidth`, `backgroundColor`, and `backgroundImage`. Report physical size is
controlled by `document.config.pageWidth` and `pageHeight`; do not confuse that
pixel configuration with the shared page metadata field.

`backgroundImage` requires a `source` wrapper. For a URL, use
`{source: {kind: "url", url: "..."}, style: {...}}`; the removed flat
`{url: "..."}` form returns HTTP 400. Preserve uploaded-image source objects
exactly as returned by GET.

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

### Column formulas against a `data-model` source

When an element's `source.kind` is `data-model`, a column formula must name the
data-model element as a prefix — `[<element name>/<column name>]`:

```json
{"formula": "Sum([Order Fact View/Net Revenue])"}
{"formula": "[Order Fact View/Region (CUSTOMER_DIM)]"}
```

A bare `[Net Revenue]` is **not** valid against a `data-model` source, and this
is the most expensive mistake available here because it passes every structural
gate. The offline validator, `POST /v2/reports/spec/verify`, the create call and
the GET readback all succeed; only a PDF export or a per-element compile check
reveals that each column rendered as the literal text `Unknown column "[Net
Revenue]"` or `Circular column reference to [Net Revenue]`. The circular variant
appears when the bare reference happens to match the consuming column's own
display `name`.

Resolve the exposed column names from
`GET /v2/dataModels/{dataModelId}/elements`, whose `entries[].columns` is an
array of name strings. Do not take them from the data model's own spec, which
reports internal source formulas and leaves `name` unset on passthrough columns.
Columns reached through a relationship carry a join-leg suffix that the formula
must reproduce verbatim, parentheses included — `Region (CUSTOMER_DIM)`, not
`Region`.

Reports use the OpenAPI `CommonElement` union. This does not mean every union
member works safely in reports. Apply `support-matrix.md` before authoring.

The shared released shapes use:

- `{columnId: ...}` for map/scalar channel pointers and pivot
  `rowsBy`/`columnsBy` shelf entries;
- arrays for `seriesLineAreaStyle: [{columnId, style}]` and
  `settings.theme.overrides.colorOverrides: [{name, color}]`;
- `verticalAlign: top|center|bottom`;
- KPI `layout.anchor: left|center|right` and
  `layout.verticalAnchor: top|center|bottom`.

`verticalAnchor` is supported but its default value is not echoed back. Sending
`center` round-trips as an absent key, while `top` and `bottom` persist and read
back verbatim. That is default normalization, not a dropped field — do not
"fix" it by removing `verticalAnchor` from the spec.

The legacy `{id: ...}`, keyed-map, and `start|middle|end` forms are rejected by
the current report API.

## Settings

The current shared theme path is `document.settings.theme`, with optional
`name` and `overrides`. The removed document-level `themeName` and
`themeOverrides` keys can be silently dropped; move them under
`settings.theme` before verify or PUT. Settings remain schema-published but
not report/PDF-proven, so preserve readback exactly and follow the support
matrix.

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
update. A live probe resolves the long-standing YAML question: the service will
serve either, and **YAML is what it returns when nothing is requested**.
`GET /v2/reports/{reportId}/spec` with no `Accept` header responds with YAML
(`reportId: ...`); the same call with `Accept: application/json` responds with
JSON. Always send `Accept: application/json` explicitly — the recipes in this
skill do, and a JSON parser fed the unheadered response fails on the first byte.
