# Metrics

Metrics are aggregate measures defined in the `metrics` array of a table element. They standardize common calculations so workbook authors don't need to rewrite them.

## Referencing a data-model metric from a workbook

Data-model metrics do flow into workbook elements that source the corresponding
data-model element. The formula reference uses Sigma's reserved metric namespace:

```yaml
source:
  kind: data-model
  dataModelId: <data-model-id>
  elementId: <element-id-that-exposes-the-metric>
columns:
  - id: total-revenue
    name: Total Revenue
    formula: "[Metrics/Total Revenue]"
```

Use the metric's **name**, not its ID. `[Base/Total Revenue]`,
`[Base/metric-revenue]`, and `[<data-model-element-name>/Total Revenue]` are
column references, not metric references, and fail with `Dependency not found`
when no such column exists.

After creating or updating the data model, GET the model spec and confirm the
metric is still present before authoring workbook references. A table element
that gives a metric the exact same name as one of its columns can be accepted
on write but return without its metrics on readback; rename the metric (preferred)
or keep the workbook aggregation inline until readback confirms it.

## Metric

```json
"metrics": [
  {
    "id": "metric-revenue",
    "formula": "Sum([Price])",
    "name": "Total Revenue"
  },
  {
    "id": "metric-unique-skus",
    "formula": "CountDistinct([Sku Number])",
    "name": "Unique Products"
  }
]
```

## Metric schema

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Short alphanumeric ID |
| `formula` | string | yes | Sigma aggregate formula |
| `name` | string | no | Display name |
| `description` | string | no | |
| `format` | Format object | no | See [formatting.md](formatting.md) |
| `timeline` | Timeline object | no | See below |

## Metric timeline

> **`dateColumnId`:** Use the column's ID as defined in the same spec. The API resolves this cross-reference at submission time — if you submit with an inode column ID (e.g., `"inode-5FCsrDpnzcdw5YYJRBbY6l/DATE"`), the returned spec will show the server-assigned column ID. The timeline will be present and correct in the returned spec.

Add a `timeline` object to a metric to enable time-series trend tracking.

```json
{
  "id": "metric-revenue",
  "formula": "Sum([Price])",
  "name": "Revenue",
  "timeline": {
    "dateColumnId": "<column-id-of-date-column>",
    "truncation": "month",
    "comparison": {
      "comparisonPeriod": "year",
      "direction": "higher-is-better"
    }
  }
}
```

**`truncation` values:** `"year"`, `"quarter"`, `"month"`, `"week-starting-sunday"`, `"week-starting-monday"`, `"day"`, `"hour"`, `"minute"`

**`comparisonPeriod` values:** `"year"`, `"quarter"`, `"month"`, `"week"`, `"day"`

**`direction` values:** `"higher-is-better"`, `"lower-is-better"`
