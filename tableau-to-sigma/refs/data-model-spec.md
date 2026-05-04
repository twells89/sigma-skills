# Data Model Spec Reference

## Endpoint

```
POST /v2/dataModels/spec
```

**Not** `/v2/workbooks/spec`. These create completely different object types.

## Top-level shape

```json
{
  "name": "My Data Model",
  "folderId": "<folder-id>",
  "schemaVersion": 1,
  "pages": [
    {
      "id": "page-1",
      "name": "Page 1",
      "elements": [ ... ]
    }
  ]
}
```

## Element shape (warehouse-table)

```json
{
  "id": "orders-el",
  "kind": "table",
  "name": "Orders",
  "source": {
    "connectionId": "<connection-id>",
    "kind": "warehouse-table",
    "path": ["SCHEMA", "CATALOG", "TABLE_NAME"]
  },
  "columns": [
    {"id": "col-sales", "name": "Sales", "formula": "[TABLE_NAME/SALES]"}
  ],
  "order": ["col-sales"],
  "metrics": [
    {"id": "met-sales", "formula": "Sum([Sales])", "name": "Total Sales",
     "format": {"kind": "number", "formatString": "$,.2f", "currencySymbol": "$"}}
  ],
  "relationships": [ ... ]
}
```

### Column formula prefix rule

The prefix in a column formula is the **last segment of the `path` array**, exactly as written:
- `path: ["CSA", "Tableau Test", "ORDERS"]` → prefix is `ORDERS`
- Formula: `"[ORDERS/SALES]"`

### Metric formula rule

Metrics reference column `name` values (not IDs) without a table prefix:
- `"Sum([Sales])"` — references the column named "Sales" in the same element
- Never `"Sum([ORDERS/Sales])"` inside a metric

## Relationships

Relationships belong on the **source** element, not the target. They link a source column to a target column on another element.

```json
"relationships": [
  {
    "id": "rel-orders-people",
    "targetElementId": "<target-element-id>",
    "keys": [
      {
        "sourceColumnId": "<source-col-id>",
        "targetColumnId": "<target-col-id>"
      }
    ],
    "name": "Orders to People"
  }
]
```

- `targetElementId` — the `id` of the element being joined to
- `sourceColumnId` / `targetColumnId` — the `id` values of the specific join key columns
- Multiple keys supported for composite joins
- One relationship per join pair; n-way joins use multiple relationship entries

## Denormalizing dim columns onto a fact element — use `Lookup()`, not bare refs

Relationships enable query-time joins, but they do **not** auto-resolve cross-element references inside calc-column formulas. A formula like `[Customer Dim/Region]` on an `Order Fact` calc column compiles cleanly, GET round-trips it, and `describe` reports the column type as `text` — but every row returns `NULL`. There is no error.

To pull a dim column onto a fact element, use `Lookup()`:

```json
{
  "id": "of-region",
  "name": "Region",
  "formula": "Lookup([Customer Dim/Region], [Customer Key], [Customer Dim/Customer Key])"
}
```

`Lookup(<value-from-other-element>, <local-key>, <other-element-key>)`. The local key column (`[Customer Key]`) must already exist on the fact element. The other-element columns are referenced with the standard `[Element Name/Column Name]` prefix.

Use this pattern whenever the workbook needs to slice the fact by a dim attribute (Region, Category, Tier, etc.) — denormalize once on the data-model element so the workbook master table sees a flat row.

**Null-tolerance for Tableau-style ELSE catches:** Tableau's `IF x >= 5000 THEN "Platinum" … ELSE "Bronze"` collapses NULL `x` into the ELSE branch (`NULL >= 5000` is NULL → falls through). Sigma's `If(NULL >= ..., ...)` returns NULL, not the false-arm — so orphan-joined rows where the lookup returns NULL produce a NULL bucket instead of joining the default category. To match Tableau, wrap the lookup: `Coalesce(Lookup([Customer Dim/Customer Value Tier], ...), "Bronze")`. Equivalent fix: `If(Coalesce([Lifetime Revenue], -1) >= 5000, ...)` if computing the bucket directly from the looked-up base column.

## Format objects

```json
{"kind": "number", "formatString": "$,.2f", "currencySymbol": "$"}   // currency
{"kind": "number", "formatString": ",.0f"}                           // integer
{"kind": "number", "formatString": ",.2%"}                           // percent
```

## Response

The POST response is **YAML** and contains only `success` and `dataModelId` — **no element IDs**.

```bash
ruby -r yaml -r date -e \
  "d=YAML.safe_load(File.read('/tmp/dm-response.yaml'),permitted_classes:[Date,Time]); \
   puts 'dataModelId: ' + d['dataModelId'].to_s"
```

Record the `dataModelId`, then **immediately GET the spec** to retrieve server-assigned element IDs:

```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/dataModels/<dataModelId>/spec" \
  -o /tmp/dm-get.yaml

ruby -r yaml -r date - <<'EOF'
require 'date'
d = YAML.safe_load(File.read('/tmp/dm-get.yaml'), permitted_classes: [Date, Time])
puts "dataModelId: #{d['dataModelId']}"
d['pages'].each do |pg|
  puts "page: #{pg['id']} #{pg['name']}"
  (pg['elements'] || []).each { |e| puts "  elementId: #{e['id']}  name: #{e['name']}" }
end
EOF
```

## Workbook source reference to a data model element

```json
{
  "kind": "data-model",
  "dataModelId": "<dataModelId>",
  "elementId": "<server-assigned-element-id>"
}
```

The `elementId` here is the element ID from the data model response, **not** the ID you assigned in the spec.

## Validation checklist before POSTing

1. No column `name` contains `/`
2. Column formula prefix matches last segment of `path`, exact case
3. Metric formulas use bare column refs (no table prefix)
4. Relationship `targetElementId` matches an element `id` defined in the same spec
5. Relationship key column IDs match column `id` values in their respective elements
6. `order` array contains exactly the column IDs defined in `columns`
