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
- **Hiding the title:** set `name: ' '` (a single space) to render the card with **no title** — e.g. when a Markdown label above the KPI already names it (see `styling.md` KPI-card recipe). Omitting `name` or setting `name: ''` does **not** work: an empty/absent name is stripped and the KPI re-derives its title from the value column, producing a duplicate. Only a single space persists.

For a period-over-period delta (e.g. "vs. prior quarter"), compute it as a **formula column** — `[This Quarter] / [Last Quarter] - 1` against the source — and show it in its own column or a second KPI.

## Value styling

`value` also accepts presentation fields — `fontSize` (number or `"auto"`) and `color` (a hex string or a theme reference `{ kind: "theme", ref: "colors-xxx" }`).

## Formula qualification

Every KPI sources another element, so the column's formula must use the source's prefix (`[<SourceName>/col]`). A bare `[col]` is only valid for referencing another column defined in this KPI's own `columns[]` array. This is the single most common mistake — see `formulas.md`.

Run `./scripts/validate-spec.sh <spec.yaml>` before publishing to catch it.

## `layout`, `comparison`, and `trend` blocks

The OpenAPI exposes three more kpi-chart objects; their spec-authoring support differs (live-verified 2026-06-11):

- `layout` — **round-trips.** `{ anchor: start|middle|end, titleOrient: top|bottom, ... }` positions the card contents. Default values are omitted on readback.
- `value` styling — **round-trips.** `fontSize` (number or `"auto"`), `color`; `fontWeight: bold` reads back omitted (it appears to be the default).
- `comparison` and `trend` (sparkline) — **cannot be created via spec.** Both blocks are silently stripped on POST in every shape probed; the OpenAPI exposes only their *formatting* fields, and the column binding behind them is UI-only state. Configure the comparison/sparkline in the editor; the spec can then style what the UI bound. For a spec-only period-over-period figure, use the formula-column recipe above.
