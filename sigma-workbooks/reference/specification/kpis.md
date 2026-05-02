# KPIs

The `kpi-chart` element is a single-value stat card. Typically it points at a table as its source and computes one aggregated value.

## Shape

```json
{
  "id": "total-sales",
  "kind": "kpi-chart",
  "name": "Total sales",
  "source": { "kind": "table", "elementId": "sales-table" },
  "columns": [
    {
      "id": "kpi-val",
      "formula": "Sum([Master/Sales Amount])",
      "format": { "kind": "number", "formatString": "$,.0f" }
    }
  ],
  "value": { "id": "kpi-val" }
}
```

- `kind` — `"kpi-chart"`. (Earlier docs used `"kpi"`; the current value is `"kpi-chart"`.)
- `columns` — define exactly one column (the value you want displayed). More columns are allowed but only `value.id` is rendered.
- `value.id` — the column ID to show in the card.
- `format` on the column controls the displayed format. See `formatting.md`.
- `name` — optional display title on the card.
- `filters` — optional element-level filters (same shape as `tables.md` and `charts.md`). Useful for KPIs scoped to a subset like "Active customers" without re-deriving the source.

```json
"filters": [
  { "id": "active-only", "columnId": "STATUS", "kind": "list", "mode": "include", "values": ["Active"] }
]
```

## Formula qualification

Every KPI sources another element, so the column's formula must use the source's prefix (`[<SourceName>/col]`). A bare `[col]` is only valid for referencing another column defined in this KPI's own `columns[]` array. This is the single most common mistake — see `formulas.md`.

Run `./scripts/validate-spec.sh <spec.json>` before publishing to catch it.

## Known Limitations

- **No delta / comparison field.** The spec does not currently support a "vs. prior period" or "% change" slot on a KPI. To show a comparison, use a chart or stack two KPI elements side-by-side via `layout.md`.
