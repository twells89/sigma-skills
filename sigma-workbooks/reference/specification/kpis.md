# KPIs

Recipe for `kpi-chart` — the single-value stat card. For the canonical schema:

```bash
jq --arg k kpi-chart 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
```

Typically a KPI points at a table as its source and computes one aggregated value.

## Shape

```yaml
id: total-sales
kind: kpi-chart
name: Total sales
source:
  kind: table
  elementId: sales-table
columns:
  - id: kpi-val
    formula: Sum([Master/Sales Amount])
    format:
      kind: number
      formatString: "$,.0f"
value:
  columnId: kpi-val
```

- `columns` — define exactly one column (the value you want displayed). More columns are allowed but only the bound `value.columnId` is rendered.
- `value.columnId` — REQUIRED. The column ID to show in the card.
- `format` on the column controls the displayed format. See `formatting.md`.
- **Hiding the title (avoid the duplicate-title trap):** a KPI derives its visible title from the element `name` **and, when that is absent, from the bound value column's `name`.** So *omitting the element `name` is not enough* — the value column's name still renders as a title. This is the #1 KPI mistake: pairing a colored Markdown category label above the KPI (see `styling.md` KPI-card recipe) with a KPI whose value column has a real name like `Net Revenue` → you get **two** stacked titles ("NET REVENUE" label + "Net Revenue" title + the number). To show only the label + number, set the **value column's** `name: ' '` (a single space). `name: ''` (empty) or omitting it gets stripped and the title re-derives — only a single space persists. (If you instead want the KPI's own title and no separate label, skip the Markdown label and give the value column a real `name`.)

For a period-over-period delta (e.g. "vs. prior quarter"), compute it as a **formula column** — `[This Quarter] / [Last Quarter] - 1` against the source — and show it in its own column or a second KPI.

## Value styling

`value` also accepts presentation fields — `fontSize` (number or `"auto"`) and `color` (a hex string or a theme reference `{ kind: "theme", ref: "colors-xxx" }`).

## Formula qualification

Every KPI sources another element, so the column's formula must use the source's prefix (`[<SourceName>/col]`). A bare `[col]` is only valid for referencing another column defined in this KPI's own `columns[]` array. This is the single most common mistake — see `formulas.md`.

Run `./scripts/validate-spec.sh <spec.yaml>` before publishing to catch it.

## `layout`, `comparison`, and `trend` blocks

The OpenAPI exposes three more kpi-chart objects; their spec-authoring support differs (live-verified 2026-06-11, re-verified 2026-06-24):

- `layout` — **round-trips.** `{ anchor: start|middle|end, titleOrient: top|bottom, ... }` positions the card contents. Default values are omitted on readback.
- `value` styling — **round-trips.** `fontSize` (number or `"auto"`), `color`; `fontWeight: bold` reads back omitted (it appears to be the default).
- `comparison` and `trend` (sparkline) — **did not render from spec in this org / the current public API (verified 2026-06-24); treat as UI-bound here, possibly org/version-dependent.** The public OpenAPI exposes only their *formatting* fields (shape, colors, interpolation, label) — **neither block carries the date/series binding** that drives the sparkline or the period delta, and `kpi-chart` has no `groupings` or dimension field to supply one. In this org that binding is **UI-only state, and `GET /v2/workbooks/{id}/spec` does not surface it.** Safe path: build the KPI via spec, then bind the trend (date) and comparison in the editor; the spec carries formatting overrides on top. For a guaranteed spec-only period-over-period *figure*, use the formula-column recipe above.

  Behavior on POST/readback differs by block (verified 2026-06-24):
  - `trend` — **accepted and persists** on readback, but **inert without a UI binding** — it renders nothing on its own here.
  - `comparison` and a column-level `columns[].sparkline` — **stripped** on readback. (A second team independently reports `comparison` is "best-effort — survives on some KPIs, stripped on others; finish in the UI if it drops" — i.e. don't rely on it round-tripping.)

  > ⚠️ **The widely-shared sparkline recipe did not reproduce here.** `trend: {shape: line}` + a `DateTrunc("month")` column + a date-range filter on it rendered **no** sparkline — tested ~8 ways on 2026-06-24, including the full documented recipe (a pre-grouped month time-series source, the month column in the KPI, **and both `mode: between` and the relative `mode: last … unit: month`**), column-level `sparkline`, and an exact copy of a *working* UI-bound KPI's columns. Every one rendered the value alone (the **grand total** — no date column ever created the series). Notably, the documented shape that filters a KPI on a `DateTrunc` month column **living on the source** (not in the KPI's own `columns`) is **rejected outright** by this API (`Dependency not found`). A KPI render that shows a live spark in the UI returns **no** `trend`/`sparkline` in its spec — only leftover `DateTrunc`/raw-date columns the editor added.
  >
  > **Open question — likely an org/version difference.** Another environment reports these *do* build from spec and render a stable sparkline. I could not reproduce that on this org/public API across the configs above, and the schema exposes no series binding — so until a workbook **built purely from spec and never opened in the editor** is shown to render a sparkline, treat spec sparklines as unsupported here and finish them in the UI. (Our own Looker converter agrees — `build_workbook.py` warns "Sigma KPI spec has no comparison/delta slot … set it in the UI".)

### Give a trend/comparison KPI enough height (or you won't *see* the sparkline)

A KPI stacks **title → value → comparison line → sparkline**, and Sigma **drops the lower items first** when the tile is too short — the sparkline goes before the comparison, which goes before the value. A plain value KPI is fine at ~5 grid rows (below that the title hides — see `styling.md`), but **a KPI carrying a sparkline + comparison needs noticeably more — budget ~8+ grid rows (~240px+)**, taller for long titles.

This is a **render-loop trap**: if you bind a sparkline but lay the tile out short, the export PNG shows only the number, and it's easy to wrongly conclude "the spark didn't build." When a sparkline you configured doesn't appear in the render, **first grow the element's `gridRow` span and re-export** before assuming it failed. (Exporting a single element with `pixelHeight` only scales the output canvas — it does **not** reproduce this layout-height clipping; you have to actually give the element more rows in the page layout.)
