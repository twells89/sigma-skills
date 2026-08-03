# Map Elements (geography-map, point-map, region-map)

Three map visualizations. They share the standard element envelope — `source` and `columns` (each `{ id, formula }`), plus the same `color` channel as charts (`by: single | category | scale`) — and differ only in how the geography is bound. Pull the full shape (including `mapStyle`, `legend`, `tooltip` sub-objects) from the spec:

```bash
jq --arg k region-map 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
# swap k for geography-map / point-map
```

The distinctive binding per kind (the part worth knowing up front):

- **geography-map** — `geography: { id: <columnId> }`, a single column of GeoJSON geometries. Optional `featureStyle: { opacity, pointSize }` (uniform mark-style override, not per-feature despite the name) and `tooltipFormat: { columnNames: shown | hidden }` (hover-tooltip column-name visibility, distinct from the `tooltip` array above).
- **point-map** — `latitude: { id }` + `longitude: { id }`; optional `size: { id }` makes it a bubble map.
- **region-map** — `region: { id, regionType }`. `regionType` ∈ `country`, `us-state`, `us-county`, `us-zipcode`, `us-cbsa`, `us-postal-place`, `ca-province`; the region column's values must match it.

**Shape gotcha:** `geography` / `latitude` / `longitude` / `size` / `region` are **single `{ id }` objects**, but `label` and `tooltip` are **arrays** of `{ id }`.

**Channel-exclusivity gotcha:** a column can sit on only one channel. Binding the same column to both `size` and `color` is a 400 — `Column 'X' is referenced from both 'size' and 'color'` (live-verified 2026-06-26 on `point-map`). To size **and** color by the same measure, add a second column with the same formula and bind one to each — or drop `color`.

```yaml
id: sales-by-state
kind: region-map
source:
  kind: warehouse-table
  connectionId: <YOUR_CONNECTION_ID>
  path: [DB, SCHEMA, SALES]
columns:
  - { id: col-state, formula: "[STATE]" }
  - { id: col-rev,   formula: "Sum([REVENUE])" }
region: { id: col-state, regionType: us-state }
color:  { by: scale, column: col-rev }
```
