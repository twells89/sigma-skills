# Workbook Layout Reference

Layout is always generated with Ruby. Never hand-write layout XML.

## Grid system

Sigma uses a 24-column CSS grid. Rows are numbered from 1 and use span-style notation:
- `gridColumn="1 / 25"` — full width (columns 1 through 24)
- `gridColumn="1 / 13"` — left half
- `gridColumn="13 / 25"` — right half
- `gridRow="1 / 7"` — rows 1 through 6 (6 units tall)

Row heights are relative units (auto). KPIs are ~6 units tall, charts 12-18 units.

## Layout XML structure

The layout is a **single top-level field on the workbook spec** — NOT a per-page field.
It is one XML string containing all pages concatenated, each identified by the server-assigned page ID.

```json
{
  "name": "My Workbook",
  "layout": "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<Page type=\"grid\" ...>...</Page>\n<Page ...>...</Page>",
  "pages": [
    {"id": "Hn2bYOjeRL", "name": "Overview", "elements": [...]},
    {"id": "gAPPHE3kaD", "name": "Product",  "elements": [...]}
  ]
}
```

**Critical:** Do NOT set `layout` on individual page objects. The API silently ignores per-page
layout fields — the workbook will appear unstyled even though PUT returns `success: true`.
Strip any `layout` key from page objects before writing the PUT body.

### Page tag — required attributes

Each page in the layout XML must use this exact format, with the server-assigned page `id`:

```xml
<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="Hn2bYOjeRL">
  ...
</Page>
```

A bare `<Page>` tag without `type`, `gridTemplateColumns`, `gridTemplateRows`, and `id` is ignored.

### LayoutElement — for plain elements (charts, tables, KPIs)

```xml
<LayoutElement elementId="abc123" gridColumn="1 / 25" gridRow="1 / 7"/>
```

### GridContainer — for container elements that wrap children

```xml
<GridContainer elementId="container-id" type="grid"
  gridColumn="1 / 25" gridRow="1 / 9"
  gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto">
  <LayoutElement elementId="kpi-1-id" gridColumn="1 / 7" gridRow="1 / 9"/>
  <LayoutElement elementId="kpi-2-id" gridColumn="7 / 13" gridRow="1 / 9"/>
  <LayoutElement elementId="kpi-3-id" gridColumn="13 / 19" gridRow="1 / 9"/>
  <LayoutElement elementId="kpi-4-id" gridColumn="19 / 25" gridRow="1 / 9"/>
</GridContainer>
```

**Critical:** Container elements MUST use `<GridContainer>`, not `<LayoutElement type="grid">`.
Using `<LayoutElement>` for a container causes empty containers to appear in the published workbook.

**Critical — inner KPI row spans must match the container outer span.** `gridTemplateRows="auto"`
does NOT fill available container height — rows size to content minimum. A KPI at `gridRow="1 / 2"`
inside an 8-row container renders as a tiny sliver with truncated names. Always set the inner
`gridRow` end value equal to the container's outer end value (e.g., container at `1 / 9` → KPIs
at `1 / 9`).

## Ruby helpers

```ruby
require 'yaml'
require 'date'
require 'json'

def gc(eid, c0, c1, r0, r1, inner)
  "<GridContainer elementId=\"#{eid}\" type=\"grid\" " \
  "gridColumn=\"#{c0} / #{c1}\" gridRow=\"#{r0} / #{r1}\" " \
  "gridTemplateColumns=\"repeat(24, 1fr)\" gridTemplateRows=\"auto\">\n#{inner}\n</GridContainer>"
end

def le(eid, c0, c1, r0, r1)
  "  <LayoutElement elementId=\"#{eid}\" gridColumn=\"#{c0} / #{c1}\" gridRow=\"#{r0} / #{r1}\"/>"
end

# page_id is the server-assigned page ID (e.g. "Hn2bYOjeRL"), NOT the page name
def page_xml(page_id, *children)
  header = "<Page type=\"grid\" gridTemplateColumns=\"repeat(24, 1fr)\" gridTemplateRows=\"auto\" id=\"#{page_id}\">"
  [header, *children, "</Page>"].join("\n")
end
```

## Typical page layout: 4 KPIs + line chart + 2 bar charts

```ruby
# Read the current spec (server-assigned IDs required)
spec = YAML.safe_load(File.read('/tmp/current-spec.yaml'), permitted_classes: [Date, Time])

# Find the Overview page and extract element IDs by name
overview = spec['pages'].find { |p| p['name'] == 'Overview' }
els = overview['elements'].each_with_object({}) { |e, h| h[e['name']] = e['id'] }

container_id  = els['KPI Row']        # container element
kpi1_id       = els['Total Sales']
kpi2_id       = els['Total Profit']
kpi3_id       = els['Profit Ratio']
kpi4_id       = els['Sales per Customer']
line_id       = els['Monthly Sales by Segment']
bar1_id       = els['Monthly Sales by Category']
bar2_id       = els['Sales by Ship Mode']

# Container spans outer rows 1-9 (8 units). Inner KPIs MUST span rows 1-9 to fill the container.
# Using 1/2 here would render KPIs as a tiny sliver — names invisible.
kpi_inner = [
  le(kpi1_id,  1,  7, 1, 9),
  le(kpi2_id,  7, 13, 1, 9),
  le(kpi3_id, 13, 19, 1, 9),
  le(kpi4_id, 19, 25, 1, 9)
].join("\n")

overview_layout = "<Page>\n" \
  "#{gc(container_id, 1, 25, 1, 9, kpi_inner)}\n" \
  "#{le(line_id,  1, 25,  9, 22)}\n" \
  "#{le(bar1_id,  1, 13, 22, 34)}\n" \
  "#{le(bar2_id, 13, 25, 22, 34)}\n" \
  "</Page>"
```

## Row sizing guide

| Content | Typical row span |
|---|---|
| KPI row container (single row of KPIs) | 8–9 outer rows |
| KPI row container (two rows of KPIs) | 12–14 outer rows |
| Wide line/area chart | 13 rows |
| Bar chart (half-width) | 12–13 rows |
| Data table | 15–20 rows |

> **Critical — KPI inner row span must equal the container outer span.**
> `gridTemplateRows="auto"` inside a GridContainer does NOT expand rows to fill
> the container height. If your KPIs use `gridRow="1 / 2"` inside a container
> that spans 6 outer rows, the KPIs render as a tiny sliver — names invisible,
> values barely readable.
>
> **Rule:** inner `gridRow` end value must match the container's outer row span.
> Container at `gridRow="1 / 9"` (8 outer rows) → KPIs inside at `gridRow="1 / 9"`.
>
> For two rows of KPIs in one container (container outer `1 / 13`):
> - First row: inner `gridRow="1 / 7"` (6 inner units)
> - Second row: inner `gridRow="7 / 13"` (6 inner units)

## Multi-series chart patterns

### Small multiples / trellis → multi-series line chart

Tableau "small multiples" have no direct Sigma equivalent. Approximate with a single line chart,
one series per segment value:

```json
{
  "kind": "line-chart",
  "name": "Monthly Sales by Segment",
  "columns": [
    {"id": "ov-date", "formula": "DateTrunc(\"month\", [Master/Order Date])", "name": "Month"},
    {"id": "ov-cons", "formula": "Sum(If([Master/Segment] = \"Consumer\", [Master/Sales], Null))", "name": "Consumer"},
    {"id": "ov-corp", "formula": "Sum(If([Master/Segment] = \"Corporate\", [Master/Sales], Null))", "name": "Corporate"},
    {"id": "ov-home", "formula": "Sum(If([Master/Segment] = \"Home Office\", [Master/Sales], Null))", "name": "Home Office"}
  ],
  "yAxis": [{"id": "ov-cons"}, {"id": "ov-corp"}, {"id": "ov-home"}],
  "xAxis": {"id": "ov-date"}
}
```

`yAxis` (not `measures`) is the correct field for both `line-chart` and `bar-chart`. Using `measures` causes the API to reject the request with `"Invalid array: ...yAxis, got undefined"`.

`xAxis` is the canonical x-axis field for both `bar-chart` and `line-chart`. `dimension` is accepted by the API but is not the canonical form. Prefer `xAxis` for both.

```json
{
  "kind": "bar-chart",
  "xAxis": {"id": "bar-city"},
  "yAxis": [{"id": "bar-sales"}]
}
```

```json
{
  "kind": "line-chart",
  "xAxis": {"id": "lc-month"},
  "yAxis": [{"id": "lc-sales"}]
}
```

All `yAxis` entries are shown as separate series.

**No `color` channel on `bar-chart` or `line-chart`.** The API does not support a `color` field on these types. To encode color by category, add a separate `yAxis` series per category using an `If()` formula:

```json
{ "id": "cons", "formula": "Sum(If([Master/Segment] = \"Consumer\", [Master/Sales], Null))", "name": "Consumer" },
{ "id": "corp", "formula": "Sum(If([Master/Segment] = \"Corporate\", [Master/Sales], Null))", "name": "Corporate" }
```

**Bar chart stacking.** Add `"stacking"` to control how multiple `yAxis` series are rendered:

```json
{
  "kind": "bar-chart",
  "stacking": "stacked",
  "xAxis": {"id": "bar-region"},
  "yAxis": [{"id": "bar-cons"}, {"id": "bar-corp"}]
}
```

`stacking` values: `"none"` (default, grouped), `"stacked"` (absolute), `"100"` (100% stacked).

### Area chart

Same spec as `line-chart` with `"kind": "area-chart"`. Supports `stacking` with the same values:

```json
{
  "kind": "area-chart",
  "columns": [
    {"id": "a-date",    "formula": "DateTrunc(\"month\", [Master/Order Date])", "name": "Month"},
    {"id": "a-revenue", "formula": "Sum([Master/Sales])", "name": "Revenue"}
  ],
  "xAxis": {"id": "a-date"},
  "yAxis": [{"id": "a-revenue"}],
  "stacking": "none"
}
```

### Combo chart (bar + line overlay)

Uses `"kind": "combo-chart"`. All `yAxis` entries default to bars. Add `"type": "line"` to any
entry to render that series as a line instead:

```json
{
  "kind": "combo-chart",
  "columns": [
    {"id": "c-channel", "formula": "[Master/Channel]",     "name": "Channel"},
    {"id": "c-rev",     "formula": "Sum([Master/Revenue])", "name": "Revenue"},
    {"id": "c-orders",  "formula": "Count([Master/OrderId])", "name": "Orders"}
  ],
  "xAxis": {"id": "c-channel"},
  "yAxis": [
    {"id": "c-rev"},
    {"id": "c-orders", "type": "line"}
  ]
}
```

Only `"type": "line"` has been observed. Omitting `type` defaults to bar.

### Scatter chart

Uses `"kind": "scatter-chart"` with the same `xAxis`/`yAxis` shape. Assign a measure to each axis:

```json
{
  "kind": "scatter-chart",
  "columns": [
    {"id": "s-profit", "formula": "Sum([Master/Profit])", "name": "Profit"},
    {"id": "s-sales",  "formula": "Sum([Master/Sales])",  "name": "Sales"},
    {"id": "s-cat",    "formula": "[Master/Category]",    "name": "Category"}
  ],
  "xAxis": {"id": "s-sales"},
  "yAxis": [{"id": "s-profit"}]
}
```

### Map → bar chart

Sigma spec does not support geographic maps. Approximate "Sales by State" as a bar chart sorted descending:

```json
{
  "kind": "bar-chart",
  "name": "Sales by City",
  "columns": [
    {"id": "bar-city",  "formula": "[Master/City]",       "name": "City"},
    {"id": "bar-sales", "formula": "Sum([Master/Sales])", "name": "Sales"}
  ],
  "yAxis": [{"id": "bar-sales"}],
  "xAxis": {"id": "bar-city", "sort": {"by": "bar-sales", "direction": "descending"}}
}
```

## Visual formatting properties NOT available via spec API

The following properties are **UI-only** — the API silently drops any field you add for these,
and they do not appear in GET responses even after being set in the UI. Apply them manually in
the chart editor after publish.

| Property | Set via spec? | How to apply post-publish |
|---|---|---|
| Bar chart orientation (horizontal vs vertical) | No | Chart editor → Properties → Chart type → Horizontal icon |
| Axis label rotation (0°, 45°, 90°) | No | Chart editor → Format → X-axis → Label rotation |
| Chart color palette | No | Chart editor → Properties → Color |
| Font size / axis title | No | Chart editor → Format tab |

**`"orientation": "horizontal"` is silently accepted but ignored.** Do not include it — it does nothing.

## Element kinds supported

| Sigma kind | Tableau equivalent |
|---|---|
| `kpi-chart` | Big number / scorecard |
| `line-chart` | Line chart, small multiples (approximated) |
| `area-chart` | Area chart (filled line) |
| `bar-chart` | Bar chart, horizontal bar, histogram, map (approximated) |
| `combo-chart` | Dual-axis / combination chart (bar + line) |
| `scatter-chart` | Scatter / bubble chart |
| `pie` | Pie chart |
| `donut` | Donut / ring chart |
| `table` | Crosstab, text table |
| `pivot-table` | Pivot / crosstab |
| `control` | Dashboard filter, parameter (all types — see Control elements below) |

Not supported: map, bullet chart, gantt, small multiples / trellis.

## Element-type field requirements

### KPI elements

> **`kpi-chart`, not `kpi`.** The API rejects `"kind": "kpi"` with `"Invalid kind: 'kpi'"`.

KPI elements require a `value` field referencing one column ID:

```json
{
  "kind": "kpi-chart",
  "columns": [{"id": "k-sales", "formula": "Sum([Master/Sales])", "name": "Total Sales", "format": {"kind": "number", "formatString": "$,.0f"}}],
  "value": {"id": "k-sales"}
}
```

Omitting `value` causes `"Invalid object: ...value, got undefined"`.

### Column format reference

Every column can carry an optional `format` object. Common patterns:

**Number formats** (`kind: "number"`, d3-format strings):

| `formatString` | Example output |
|---|---|
| `"$,.0f"` | $1,234 |
| `"$,.2f"` | $1,234.56 |
| `",.0f"` | 1,234 |
| `",.2%"` | 12.34% |

**Datetime formats** (`kind: "datetime"`, strftime strings):

| `formatString` | Example output |
|---|---|
| `"%Y-%m-%d"` | 2026-04-21 |
| `"%b %Y"` | Apr 2026 |
| `"%B %Y"` | April 2026 |
| `"%Y-%m-%d %H:%M"` | 2026-04-21 14:30 |

```json
{"id": "col-date", "formula": "DateTrunc(\"month\", [Master/Order Date])", "name": "Month",
 "format": {"kind": "datetime", "formatString": "%b %Y"}}
```

### Pivot table elements

Use `rowsBy`, `columnsBy`, and `values`. **Do NOT use `rows` or `columnGroups`** — the API accepts them silently but the pivot does not render correctly.

- `values`: array of **string** column IDs
- `rowsBy`: array of **objects** `{"id": "col-id"}` — row groupings (left axis)
- `columnsBy`: array of **objects** `{"id": "col-id"}` — column pivots (top axis)

```json
{
  "kind": "pivot-table",
  "columns": [
    {"id": "pcy-cat",   "formula": "[Master/Category]",                        "name": "Category"},
    {"id": "pcy-year",  "formula": "DateTrunc(\"year\", [Master/Order Date])",  "name": "Year"},
    {"id": "pcy-month", "formula": "DateTrunc(\"month\", [Master/Order Date])", "name": "Month"},
    {"id": "pcy-sales", "formula": "Sum([Master/Sales])",                       "name": "Sales"}
  ],
  "values":    ["pcy-sales"],
  "rowsBy":    [{"id": "pcy-cat"}, {"id": "pcy-year"}],
  "columnsBy": [{"id": "pcy-month"}]
}
```

**`conditionalFormats`** — Conditional formatting on pivot-table columns. Two supported types:

`dataBars` — renders colored bars proportional to cell values:

```json
{
  "conditionalFormats": [{
    "type": "dataBars",
    "columns": ["pcy-sales", "pcy-profit"],
    "scheme": ["#FF9D99", "#A0CBE8"],
    "includeValues": true,
    "includeSubtotals": false
  }]
}
```

`backgroundScale` — applies a color gradient across cell values (diverging scale):

```json
{
  "conditionalFormats": [{
    "type": "backgroundScale",
    "columns": ["pcy-margin"],
    "scheme": ["rgb(140,13,37)", "rgb(255,255,255)", "rgb(19,75,133)"],
    "includeValues": true
  }]
}
```

### Table element extras

These fields are accepted on `table` (and master table) elements:

**`visibleAsSource: false`** — Hides the element from being browsable as a standalone table in the
workbook. **Always set this on the master/data table** — it should be a source for charts, not
a table users can navigate to directly:

```json
{
  "kind": "table",
  "name": "Master",
  "visibleAsSource": false,
  "source": { "kind": "data-model", "dataModelId": "<id>", "elementId": "<id>" },
  "columns": [...]
}
```

**`order`** — Explicit column display order. Value is an array of column IDs. Without it, column
order is undefined and may differ from the Tableau source:

```json
{
  "kind": "table",
  "columns": [...],
  "order": ["col-channel", "col-ship", "col-status", "col-revenue", "col-orderid", "col-datekey"]
}
```

**`groupings`** — Row groupings with subtotals (equivalent to Tableau row-level subtotals). Each
entry specifies which columns to group by and which to aggregate:

```json
{
  "groupings": [{
    "id": "grp-dept",
    "groupBy": ["col-department"],
    "calculations": ["col-total-hours", "col-cost"],
    "sort": [{"columnId": "col-total-hours", "direction": "descending", "nulls": "connection-default"}]
  }]
}
```

**`summary`** — Column IDs to show in a summary/footer row at the bottom of the table:

```json
{ "summary": ["col-revenue", "col-orders"] }
```

**`style`** — Table border styling:

```json
{ "style": {"borderRadius": "round", "borderColor": "#E0E0E0", "borderWidth": 1} }
```

### Pie and donut elements

Both use `color` for the dimension (slice category) and `value` for the measure. Donut additionally requires `holeValue` for the center label.

```json
{
  "kind": "pie",
  "columns": [
    {"id": "dim-region", "formula": "[Master/Region]", "name": "Region"},
    {"id": "mea-sales",  "formula": "Sum([Master/Sales])", "name": "Sales"}
  ],
  "color": {"id": "dim-region"},
  "value": {"id": "mea-sales"}
}
```

```json
{
  "kind": "donut",
  "columns": [
    {"id": "dim-seg",    "formula": "[Master/Segment]", "name": "Segment"},
    {"id": "mea-sales",  "formula": "Sum([Master/Sales])", "name": "Sales"},
    {"id": "mea-sales2", "formula": "Sum([Master/Sales])", "name": "Sales Total"}
  ],
  "color":     {"id": "dim-seg"},
  "value":     {"id": "mea-sales"},
  "holeValue": {"id": "mea-sales2"}
}
```

`holeValue` can reference the same aggregate as `value` (just a second column definition) or a different one.

### Histogram

Use a regular `bar-chart` with a manual `If()` bucketing formula as the `xAxis` column and `Count()` as the `yAxis` measure:

```json
{
  "kind": "bar-chart",
  "columns": [
    {"id": "bucket", "formula": "If([Master/Sales] < 100, \"$0-$100\", If([Master/Sales] < 500, \"$100-$500\", \"$500+\"))", "name": "Sales Bucket"},
    {"id": "cnt",    "formula": "Count()", "name": "Orders"}
  ],
  "xAxis": {"id": "bucket"},
  "yAxis": [{"id": "cnt"}]
}
```

## Control elements

Controls are fully supported via the spec API. There are 9 control types.

### Filter targets

Every control that filters data uses a `filters` array. The source in each filter entry can point to either a warehouse table directly or a workbook element:

```json
// Warehouse table (connectionId + path)
"filters": [{"source": {"kind": "warehouse-table", "connectionId": "<id>", "path": ["SCHEMA", "CATALOG", "TABLE"]}, "columnId": "COLUMN_NAME"}]

// Workbook element column (server-assigned element and column IDs)
"filters": [{"source": {"kind": "table", "elementId": "<element-id>"}, "columnId": "<server-col-id>"}]
```

### list — dropdown / multi-select

Manual source (fixed static values):

```json
{
  "kind": "control", "controlId": "filter-order", "name": "Order ID",
  "controlType": "list",
  "mode": "include", "selectionMode": "multiple", "values": [],
  "source": {"kind": "manual", "valueType": "text"},
  "filters": [{"source": {"kind": "warehouse-table", "connectionId": "<id>", "path": [...]}, "columnId": "ORDER_ID"}]
}
```

Dynamic source (values populated from a column):

```json
{
  "kind": "control", "controlId": "filter-region", "name": "Region",
  "controlType": "list",
  "mode": "include", "selectionMode": "multiple", "values": [],
  "source": {"kind": "source", "source": {"kind": "table", "elementId": "<master-id>"}, "columnId": "<col-region-id>"},
  "filters": [{"source": {"kind": "table", "elementId": "<master-id>"}, "columnId": "<col-region-id>"}]
}
```

### date-range

```json
{
  "kind": "control", "controlId": "filter-date", "name": "Order Date",
  "controlType": "date-range", "mode": "between",
  "includeNulls": "when-no-value-is-selected",
  "filters": [{"source": {"kind": "warehouse-table", "connectionId": "<id>", "path": [...]}, "columnId": "ORDER_DATE"}]
}
```

### text — single-line text filter

```json
{
  "kind": "control", "controlId": "filter-schema", "name": "Schema",
  "controlType": "text", "mode": "equals", "case": "insensitive",
  "includeNulls": "when-no-value-is-selected", "showOperators": false,
  "filters": [{"source": {"kind": "table", "elementId": "<element-id>"}, "columnId": "<col-id>"}]
}
```

### text-area — multi-line text input

```json
{
  "kind": "control", "controlId": "filter-text-area",
  "controlType": "text-area",
  "filters": [{"source": {"kind": "warehouse-table", "connectionId": "<id>", "path": [...]}, "columnId": "ORDER_ID"}]
}
```

### segmented — parameter / radio buttons

Manual values (most common for parameters):

```json
{
  "kind": "control", "controlId": "p_date_dimension", "name": "Time Period",
  "controlType": "segmented",
  "source": {"kind": "manual", "valueType": "text", "values": ["Month", "Quarter", "Year"], "labels": [null, null, null]},
  "value": "Quarter"
}
```

Dynamic source (values from a column):

```json
{
  "kind": "control", "controlId": "Ship-Mode", "name": "Ship Mode",
  "controlType": "segmented",
  "source": {"kind": "source", "source": {"kind": "warehouse-table", "connectionId": "<id>", "path": [...]}, "columnId": "SHIP_MODE"},
  "value": null
}
```

Segmented controls have no `filters` — they act as parameters referenced in element formulas via `controlId`:

```
Sum(If([p_date_dimension] = "Month", [Sales], Null))
```

### number — exact number match

```json
{
  "kind": "control", "controlId": "filter-qty", "name": "Quantity",
  "controlType": "number", "mode": "=",
  "includeNulls": "when-no-value-is-selected",
  "filters": [{"source": {"kind": "table", "elementId": "<element-id>"}, "columnId": "<col-id>"}]
}
```

### number-range — from/to number inputs

```json
{
  "kind": "control", "controlId": "filter-sales-range", "name": "Sales Range",
  "controlType": "number-range",
  "includeNulls": "when-no-value-is-selected",
  "filters": [{"source": {"kind": "warehouse-table", "connectionId": "<id>", "path": [...]}, "columnId": "SALES"}]
}
```

### slider — single value with bounds

```json
{
  "kind": "control", "controlId": "slider-discount", "name": "Max Discount",
  "controlType": "slider", "low": 0, "high": 100, "mode": "<=", "value": 0,
  "includeNulls": "when-no-value-is-selected",
  "filters": [{"source": {"kind": "table", "elementId": "<element-id>"}, "columnId": "<col-id>"}]
}
```

### range-slider — range with two handles

```json
{
  "kind": "control", "controlId": "range-slider-sales", "name": "Sales Range",
  "controlType": "range-slider", "low": 0, "high": 100, "max": 100,
  "includeNulls": "when-no-value-is-selected",
  "filters": [{"source": {"kind": "warehouse-table", "connectionId": "<id>", "path": [...]}, "columnId": "SALES"}]
}
```

### top-n — filter to top or bottom N items

```json
{
  "kind": "control", "controlId": "top-n-products", "name": "Top N",
  "controlType": "top-n", "rankingFunction": "rank", "mode": "top-n",
  "includeNulls": "when-no-value-is-selected",
  "filters": [{"source": {"kind": "table", "elementId": "<element-id>"}, "columnId": "<col-id>"}]
}
```

### Element-level top-n filter (on charts)

To hard-code a top-N filter on a chart element (not user-adjustable), add a `filters` array to the element:

```json
{
  "kind": "bar-chart",
  "columns": [...],
  "xAxis": {"id": "PRODUCT_NAME", "sort": {"by": "nZea2N896k", "direction": "descending"}},
  "yAxis": [{"id": "nZea2N896k"}],
  "filters": [{
    "id": "top-10-filter",
    "columnId": "nZea2N896k",
    "kind": "top-n",
    "rankingFunction": "row-number",
    "mode": "top-n",
    "rowCount": 10,
    "includeNulls": "never"
  }]
}
```

## Full spec assembly with layout

```ruby
# Merge layout into a copy of the current spec, then PUT
spec = YAML.safe_load(File.read('/tmp/current-spec.yaml'), permitted_classes: [Date, Time])

# Build per-page XML using server-assigned IDs
pages_by_name = spec['pages'].each_with_object({}) { |p, h| h[p['name']] = p }

overview_xml  = page_xml(pages_by_name['Overview']['id'],  ...)
product_xml   = page_xml(pages_by_name['Product']['id'],   ...)
# ...

# Set ONE top-level layout field — remove any layout from page objects
spec['pages'].each { |p| p.delete('layout') }
spec['layout'] = [
  "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
  overview_xml,
  product_xml
].join("\n")

File.write('/tmp/workbook-with-layout.json', JSON.pretty_generate(spec))
```

Then PUT:
```bash
curl -s -X PUT \
  -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/workbook-with-layout.json \
  "$SIGMA_BASE_URL/v2/workbooks/<workbookId>/spec"
```

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Using `"kind": "kpi"` | `"Invalid kind: 'kpi'"` | The correct kind is `"kpi-chart"` — never `"kpi"` |
| KPI names invisible or truncated inside container | Inner `gridRow` too small — e.g., `1 / 2` inside a 6-row container | Set inner end value = container outer end value: container `1 / 9` → KPIs `1 / 9` |
| KPIs appear as a tiny sliver at top of container | Same root cause as above | Same fix — match inner row span to container outer span |
| Setting `layout` on each page object instead of top-level | PUT returns success but UI shows no layout change | Set `spec['layout']` once at the top level; strip `layout` from all page objects |
| Bare `<Page>` tag without `type`/`id` attributes | Layout ignored silently | Use `<Page type="grid" gridTemplateColumns="repeat(24, 1fr)" gridTemplateRows="auto" id="<pageId>">` |
| Using `measures` instead of `yAxis` on bar/line charts | `"Invalid array: ...yAxis, got undefined"` | Replace `measures` with `yAxis` |
| KPI missing `value` field | `"Invalid object: ...value, got undefined"` | Add `"value": {"id": "<col-id>"}` to every `kpi-chart` element |
| Using `rows`/`columnGroups` on a pivot table | API accepts silently but pivot does not render | Use `rowsBy`/`columnsBy` (object arrays) and `values` (string array) |
| Using IDs from POST body instead of GET response | Layout elements don't appear | Always GET spec after POST to get real IDs |
| `<LayoutElement>` for a container | Empty container visible | Use `<GridContainer>` for elements that have children |
| Hand-writing layout XML | Off-grid sizing, overlapping elements | Use Ruby helpers; let math determine positions |
| Overlapping row ranges | Elements hidden behind each other | Draw row ranges on paper; ensure no two elements share rows on the same column span |
| Fallback `els.values[N]` when page has fewer elements than expected | `elementId=""` in XML — PUT rejected with `invalid_request` | Guard with `(le(id, ...) if id)` and call `.compact` on the children array before passing to `page_xml` |
| Using `dimension` on a `line-chart` | Works but is non-canonical | Use `xAxis` for both `bar-chart` and `line-chart` |
