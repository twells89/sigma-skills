# Other Element Kinds (Divider, Image)

Small visual elements that take very little spec, useful for dashboard polish.

## Divider

A horizontal rule. No data, no source, no styling fields.

```json
{
  "id": "section-rule",
  "kind": "divider"
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"divider"` |

Use a divider in the layout to separate sections within a page or container. Position it like any other element via `<LayoutElement>` with a thin `gridRow` span (e.g., `gridRow="6 / 7"`).

## Image

Embeds an external image by URL. Hosted images only — uploads aren't supported via the spec.

```json
{
  "id": "logo",
  "kind": "image",
  "url": "https://cdn.example.com/team-logo.png"
}
```

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique on the page |
| `kind` | yes | Always `"image"` |
| `url` | yes | Public HTTPS URL. Supports `{{formula}}` references for dynamic image selection |

`url` is the only data field — there's no `alt`, `width`, or `height` in the public spec. Sizing is controlled by the layout grid placement. To make an image dynamic (e.g., per-row icon, per-control logo swap), use a `{{formula}}` in the URL — same `{{ast | fmt}}` syntax used in element titles and the `text` element body.
