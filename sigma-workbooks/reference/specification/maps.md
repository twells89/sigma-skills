# Map Elements (geography-map, point-map, region-map)

Three map visualizations. They share the standard element envelope — `source` and `columns` (each `{ id, formula }`), plus the same `color` channel as charts (`by: single | category | scale`) — and differ only in how the geography is bound. Pull the full shape (including `mapStyle`, `legend`, `tooltip` sub-objects) from the spec:

```bash
jq --arg k region-map 'first(.. | objects | select((.allOf? and any(.allOf[]?; .properties?.kind?.enum==[$k])) or .properties?.kind?.enum==[$k]))' /tmp/sigma-api.json
# swap k for geography-map / point-map
```

The distinctive binding per kind (the part worth knowing up front):

- **geography-map** — `geography: { id: <columnId> }`, a single column of GeoJSON geometries.
- **point-map** — `latitude: { id }` + `longitude: { id }`; optional `size: { id }` makes it a bubble map.
- **region-map** — `region: { id, regionType }`. `regionType` ∈ `country`, `us-state`, `us-county`, `us-zipcode`, `us-cbsa`, `us-postal-place`, `ca-province`; the region column's values must match it.

**Shape gotcha:** `geography` / `latitude` / `longitude` / `size` / `region` are **single `{ id }` objects**, but `label` and `tooltip` are **arrays** of `{ id }`.

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
