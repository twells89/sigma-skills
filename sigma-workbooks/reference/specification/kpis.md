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
- `comparison` and `trend` (sparkline) — **cannot be *created* via spec.** The OpenAPI exposes only their *formatting* fields (shape, colors, interpolation, label) — **neither block carries the date/series binding** that actually drives the sparkline or the period delta, and `kpi-chart` has no `groupings` or dimension field to supply one. That binding is **UI-only state, and `GET /v2/workbooks/{id}/spec` does not surface it.** Configure the trend (date) and comparison in the editor; the spec can then carry formatting overrides on top of what the UI bound. For a spec-only period-over-period *figure*, use the formula-column recipe above.

  Behavior on POST/readback differs by block (verified 2026-06-24):
  - `trend` — **accepted and persists** on readback, but **inert without a UI binding** — it renders nothing on its own.
  - `comparison` and a column-level `columns[].sparkline` — **stripped** on readback.

  > ⚠️ **A widely-shared recipe does *not* work:** `trend: {shape: line}` + a `DateTrunc("month")` column + a date-range filter on it does **not** render a sparkline. Tested six ways on 2026-06-24 (date column present; date-range filter; a pre-grouped month time-series as the KPI source; the date column inside the KPI; column-level `sparkline`; and an exact copy of a *working* UI-bound KPI's columns) — every one rendered the value alone, no sparkline. The KPI returns the **grand total**, confirming no date column ever creates the series a sparkline needs.
  >
  > **How to tell a UI-bound trend from a spec one:** a converted KPI that shows a live sparkline + comparison in the UI (e.g. an `↑/↓ % · this vs last period` line) returns **no** `trend`/`comparison`/`sparkline` in its spec — only leftover `DateTrunc` and raw-date columns the editor added when the trend was bound. Re-POSTing those exact columns renders only the number. The series/period binding lives outside the spec. (Our own Looker converter says as much — `build_workbook.py` warns "Sigma KPI spec has no comparison/delta slot … set it in the UI".)
