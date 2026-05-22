# Layout

Recipe book for the top-level `layout` XML — when to write it, the two-tag grammar, and the silent-failure traps the OpenAPI doesn't surface. **Default to writing explicit `layout` XML for multi-element workbooks.**

For container elements (the `kind: "container"` JSON placeholders that pair with `<GridContainer>` in this XML), see `containers.md`.

## When to write layout vs. let Sigma auto-arrange

Write explicit `layout` when **any** of these apply:

- The page has **mixed element kinds** (charts + KPIs, controls + charts, text/image/divider polish). Auto-arrange treats them as a vertical stack and gives every element the same height — KPIs end up the size of charts, dividers get huge gutters around them.
- The user asked for specific positioning ("logo on left, title on right", "KPIs across the top", side-by-side charts).
- There's a `kind: "container"` element on the page. Containers without a matching `<GridContainer>` are functionally no-ops.
- The workbook has more than ~4 elements on a page. Auto-arrange becomes a long scroll.

Auto-arrange (omit `layout`) is fine when:

- The page has a single element.
- The page is a uniform stack of tables — auto-arrange produces a reasonable list view.
- The user explicitly says default layout is fine.

If unsure, write the layout. Writing one is cheap (the patterns below are copy-paste); a visually broken dashboard is expensive.

## Two-tag grammar

```xml
<?xml version="1.0" encoding="utf-8"?>
<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="<pageId>">
  <GridContainer elementId="<containerId>" type="grid" gridColumn="1 / 25" gridRow="1 / 4"
                 gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
    <LayoutElement elementId="<childId>" gridColumn="1 / 13" gridRow="1 / 4"/>
  </GridContainer>
  <LayoutElement elementId="<elementId>" gridColumn="1 / 25" gridRow="4 / 16"/>
</Page>
```

Each `<Page id>` matches a `pages[].id`. Each `elementId` matches an element on that page. `gridColumn` / `gridRow` use standard CSS grid line syntax (`start / end`); the default grid is 24 columns wide. One `<Page>` block per workbook page.

## `<GridContainer>` vs `<LayoutElement>` — silent failure trap

> ⚠️ Use `<GridContainer>` for any tag that has children nested inside it. `<LayoutElement type="grid">` with children parses successfully **as a leaf** and the children are silently dropped — no error, the child elements just disappear from the page.

- `<LayoutElement elementId="X" .../>` — **leaf**. Positions a single element. No children.
- `<GridContainer elementId="X" ...>...</GridContainer>` — **container**. Wraps child `<LayoutElement>`s inside its own inner grid.

## `gridTemplateRows`: keep it `"auto"`

> Silent normalization: `gridTemplateRows` is accepted on PUT with any value but normalizes back to `"auto"` on GET. Writing `"1fr"`, `"100px"`, `"repeat(3, 1fr)"` etc. doesn't error — the server drops your value and treats the row track as `"auto"`. Always write `"auto"` explicitly so the round-trip is stable.

### Stacking children inside a container

Because row tracks collapse to `"auto"`, height comes from children, not from the container's `gridTemplateRows`. Two patterns work:

**Side-by-side** — children share the container's row range, differ by `gridColumn`:

```xml
<GridContainer elementId="kpi-row" type="grid"
               gridColumn="1 / 25" gridRow="1 / 4"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="kpi-1" gridColumn="1 / 9"  gridRow="1 / 4"/>
  <LayoutElement elementId="kpi-2" gridColumn="9 / 17" gridRow="1 / 4"/>
  <LayoutElement elementId="kpi-3" gridColumn="17 / 25" gridRow="1 / 4"/>
</GridContainer>
```

**Stacked rows** — children have disjoint `gridRow` spans. The server normalizes the container's outer `gridRow` to encompass its children (e.g., a container declared `1 / 12` with children spanning `1 / 4` and `4 / 12` reads back as `1 / 12`; declare generously and let normalization clamp):

```xml
<GridContainer elementId="header-row" type="grid"
               gridColumn="1 / 25" gridRow="1 / 12"
               gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="title"  gridColumn="1 / 25" gridRow="1 / 4"/>
  <LayoutElement elementId="kpi-1"  gridColumn="1 / 9"  gridRow="4 / 12"/>
  <LayoutElement elementId="kpi-2"  gridColumn="9 / 17" gridRow="4 / 12"/>
  <LayoutElement elementId="kpi-3"  gridColumn="17 / 25" gridRow="4 / 12"/>
</GridContainer>
```

Use stacked rows when you want a section header above a row of charts inside the same container, instead of moving those elements out to the page level.

## After CREATE: IDs reassign

The server remaps external IDs to internal ones on `POST /v2/workbooks/spec`. Before any follow-up `PUT` that touches `layout`, **GET the current spec and use the readback IDs**. Layout `elementId` references must match exactly (case-sensitive) — a mismatch silently drops the element from the page.

See `example-full.yaml` for a real multi-page layout with grid containers.
