# KPIs

Recipe for `kpi-chart` — the single-value stat card. For the canonical schema:

```bash
jq '.components.schemas.KpiChart' /tmp/sigma-api.json
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
  id: kpi-val
```

- `columns` — define exactly one column (the value you want displayed). More columns are allowed but only `value.id` is rendered.
- `value.id` — the column ID to show in the card.
- `format` on the column controls the displayed format. See `formatting.md`.

## Formula qualification

Every KPI sources another element, so the column's formula must use the source's prefix (`[<SourceName>/col]`). A bare `[col]` is only valid for referencing another column defined in this KPI's own `columns[]` array. This is the single most common mistake — see `formulas.md`.

Run `./scripts/validate-spec.sh <spec.yaml>` before publishing to catch it.

## Known Limitations

- **No delta / comparison field.** The spec does not currently support a "vs. prior period" or "% change" slot on a KPI. To show a comparison, use a chart or stack two KPI elements side-by-side via `layout.md`.
