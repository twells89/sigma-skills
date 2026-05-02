# Column Naming Gotchas

## The slash problem

Sigma uses `/` as the source-prefix separator in formula references: `[TableName/ColumnName]`.
If a column's `name` field itself contains `/`, every formula that references it becomes unresolvable.

**Tableau display names that contain slashes (common):**
- "Country/Region" → rename to `"Country"`
- "State/Province" → rename to `"State"`

**Rule:** Before writing the data model spec, rename any column whose `name` contains `/`.
Do it once in the data model; all downstream workbook formulas inherit the clean name.

## Tableau display names ≠ warehouse column names

Tableau stores a human-readable "display name" that is almost never the actual Snowflake column name.

| Tableau display | Snowflake column |
|---|---|
| Sub-Category | SUB_CATEGORY |
| Country/Region | COUNTRY_REGION |
| Order Date | ORDER_DATE |
| Customer Name | CUSTOMER_NAME |

**Rule:** Always fetch actual column names from the Sigma connection API:
```bash
curl -s -H "Authorization: Bearer $SIGMA_API_TOKEN" \
  "$SIGMA_BASE_URL/v2/connections/tables/<urlId>/columns" \
  | jq '[.entries[] | {name, dataType}]'
```

Never infer warehouse column names from Tableau display names.

## Sub-Category hyphen

"Sub-Category" is a valid column `name` in the data model spec. Hyphens are fine.
The formula reference `[Orders/Sub-Category]` works correctly.

## Cascading failures

If one column formula is invalid, the entire element (table) fails — not just that column.
The error message names the specific bad ref. Fix only that ref and retry; don't rebuild the whole element.

## Column ID format

Column IDs in a data model spec can be any unique string. The server reassigns them on POST, so your
IDs are just for cross-referencing within the JSON file you're writing. Short readable IDs like
`"col-sales"` or `"met-profit-ratio"` are fine.

## Metrics vs columns

Metrics are aggregate formulas that live alongside columns but reference column names without a table prefix:
```json
{"id": "met-sales", "formula": "Sum([Sales])", "name": "Total Sales"}
```
Note: `[Sales]` not `[ORDERS/Sales]` — within the same element, bare refs work.

## Integer date keys (YYYYMMDD format)

Snowflake warehouses commonly store dates as integers in `YYYYMMDD` format (e.g., `20240115`).
Sigma line charts treat these as plain numbers — the axis shows integer values instead of dates
and the trend renders incorrectly.

**Rule:** Cast integer date keys to proper dates at the workbook column level by building an ISO
string and passing it to `Date()`:

```json
{"id": "col-date", "formula": "Date(Left(Text([Master/ORDER_DATE_KEY]), 4) & \"-\" & Mid(Text([Master/ORDER_DATE_KEY]), 5, 2) & \"-\" & Right(Text([Master/ORDER_DATE_KEY]), 2))", "name": "Order Date"}
```

Key points:
- `Text()` is the correct string conversion function — `ToText()` does not exist in Sigma
- `Date()` takes a single ISO date string (`"YYYY-MM-DD"`) — it does not accept 3 separate arguments
- `DateParse()` does not exist in Sigma — do not use it
- `Mid()` is 1-indexed (position 5 gives the month digits of a YYYYMMDD integer)

Do this in the workbook master table column, not in the data model — keep the integer column
as-is in the data model (useful for filtering/sorting) and cast only where you need a date axis.

## Cross-year month rollup (Tableau MONTH part vs Sigma DateTrunc)

A Tableau dimension built from `MONTH([Order Date])` (the date *part*, not a truncation)
produces 12 month-name buckets that aggregate across **all years** in the data — January
2024 and January 2025 collapse into a single "January" point.

Sigma's `DateTrunc("month", [date])` does **not** do this. It preserves the year, so the
same data renders as 24 month-year points (Jan 2024, Jan 2025, …) instead of 12.

When the Tableau view CSV shows month names without years (e.g. `"Month of Order Date Key,Gross Revenue\nJanuary,1224.88\n..."`),
the original chart is using the part-extraction form. To match it in Sigma, synthesize a
single-year date inside the formula so all years share an axis:

```json
{
  "id": "mr-month",
  "formula": "Date(\"2024-\" & Mid(Text([Master/Order Date Key]), 5, 2) & \"-01\")",
  "name": "Month",
  "format": {"kind": "datetime", "formatString": "%B"}
}
```

The year `"2024-"` is arbitrary — any constant works because it's stripped by the `%B`
format. Same trick adapts to `Year`-stripped quarters (use a fixed year and the quarter's
first month) or weeks (fixed year + ISO week).

If the Tableau CSV shows month-year together (`"January 2024,664.94\n..."`), the chart is
using `DateTrunc` and you don't need this workaround — plain `DateTrunc("month", [Master/Order Date])`
matches.

> **Always confirm by inspecting the CSV before picking a formula.** Tableau worksheet titles
> ("Monthly Revenue Trend") don't tell you which form is in use; the CSV does.

## YAML response from spec endpoints

`POST /v2/dataModels/spec` and `POST /v2/workbooks/spec` return **YAML**, not JSON.
Piping to `jq` causes `parse error: Invalid numeric literal`.

Parse with Ruby:
```bash
ruby -r yaml -r json -r date -e \
  "puts JSON.pretty_generate(YAML.safe_load(STDIN.read, permitted_classes:[Date,Time]))"
```
