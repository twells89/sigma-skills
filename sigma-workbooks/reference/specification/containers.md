# Containers

Recipe book for `kind: "container"` elements — the placeholders that group other elements via layout XML. For full schema:

```bash
jq '.components.schemas.Container' /tmp/sigma-api.json
```

A container is the visual grouping primitive: a labeled section, a branded header strip, a row of KPIs treated as a unit. It pairs with a matching `<GridContainer elementId="...">` in the layout XML (see `layout.md`) — the spec declares the container exists; the XML positions it and its children.

## Minimal shape

```yaml
id: header-row
kind: container
```

The container declared in the page's `elements` array does nothing on its own. You **must** also reference it from layout XML or it doesn't render. This pairing is the whole reason `kind: "container"` exists.

## Styling fields

Containers support an optional `backgroundImage` and an optional `style` block for visual treatment.

### `backgroundImage` — image filling the container

```yaml
id: hero
kind: container
backgroundImage:
  url: https://cdn.example.com/hero.jpg
  style:
    fit: cover
    horizontalAlign: middle
    verticalAlign: middle
    tiling: none
```

`backgroundImage` is an **object**, not a string. `url` is the only required field on it. The optional `style` block:

- `fit`: `contain` | `cover` | `none` | `scale-down` | `stretch`
- `horizontalAlign`: `start` | `middle` | `end`
- `verticalAlign`: `start` | `middle` | `end`
- `tiling`: `none` | `repeat`

The full shape round-trips through GET unchanged; PUT-based edits are stable. URL supports `{{formula}}` references if you need the image to switch based on a control value (see `others.md` image element notes for the syntax).

### `style` block — solid color, border, etc.

A sibling `style` field on the container handles non-image visual treatment (background color, border radius, etc.). Shape varies; inspect via:

```bash
jq '.components.schemas.Container.properties.style' /tmp/sigma-api.json
```

## Recipe — branded section header

A common pattern: a top strip with a logo image on the left, a Markdown title on the right, sitting on a colored background.

```yaml
elements:
  - id: header
    kind: container
    style:
      backgroundColor: "#0B3D91"
  - id: logo
    kind: image
    url: https://cdn.example.com/logo.png
  - id: title
    kind: text
    body: |
      # Q4 Sales
      Weekly snapshot of revenue and growth
  # ...other page elements...
```

Paired layout XML places logo and title side-by-side inside the header container:

```xml
<GridContainer elementId="header" type="grid"
               gridColumn="1 / 25" gridRow="1 / 6"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="logo"  gridColumn="1 / 6"  gridRow="1 / 6"/>
  <LayoutElement elementId="title" gridColumn="6 / 25" gridRow="1 / 6"/>
</GridContainer>
```

## Recipe — KPI on top of a background image

```yaml
- id: hero
  kind: container
  backgroundImage:
    url: https://picsum.photos/1200/300
    style:
      fit: cover
- id: revenue-kpi
  kind: kpi-chart
  # ...kpi fields...
```

```xml
<GridContainer elementId="hero" type="grid"
               gridColumn="1 / 25" gridRow="1 / 8"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="revenue-kpi" gridColumn="1 / 25" gridRow="1 / 8"/>
</GridContainer>
```

Note: overlapping `gridRow` ranges between siblings inside one container don't compose into a z-axis stack — the server normalizes overlapping rows into adjacent rows on readback. For "element on top of image" semantics, put the KPI **inside** the container that owns the background image; the background spans the container's full extent and the child element sits on top of it naturally.

## When to skip containers

If you don't need a visual grouping (no shared background, no logical section), put elements directly on the page and position them with `<LayoutElement>` in the page-level layout XML. A container that holds a single element is usually overkill.
