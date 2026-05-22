# Other Element Kinds (Divider, Image)

Recipes for the smaller polish elements. For canonical schemas:

```bash
jq '.components.schemas.Divider, .components.schemas.Image' /tmp/sigma-api.json
```

Both elements take very little spec; this file documents the `{{formula}}`-in-URL pattern for image elements (Sigma-specific, not in the OpenAPI in detail) and how they pair with layout XML.

## Divider

A horizontal rule. No data, no source, no styling fields.

```yaml
id: section-rule
kind: divider
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"divider"` |

Use a divider in the layout to separate sections within a page or container. Position it like any other element via `<LayoutElement>` with a thin `gridRow` span (e.g., `gridRow="6 / 7"`).

## Image

Embeds an external image by URL. Hosted images only — uploads aren't supported via the spec.

```yaml
id: logo
kind: image
url: https://cdn.example.com/team-logo.png
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"image"` |
| `url` | yes | Public HTTPS URL. Supports `{{formula}}` references for dynamic image selection |

`url` is the only data field — there's no `alt`, `width`, or `height` in the public spec. Sizing is controlled by the layout grid placement. To make an image dynamic (e.g., per-row icon, per-control logo swap), use a `{{formula}}` in the URL — same `{{ast | fmt}}` syntax used in element titles and the `text` element body.
