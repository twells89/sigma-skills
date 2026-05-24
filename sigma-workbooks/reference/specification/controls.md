# Controls

Recipe book for the control element family and the patterns that wire them up. For the canonical schemas of each variant:

```bash
jq -r '.components.schemas | keys[] | select(test("Control"))' /tmp/sigma-api.json
jq '.components.schemas.ListControl, .components.schemas.DateRangeControl, .components.schemas.TextControl' /tmp/sigma-api.json
```

Controls are interactive filter elements — dropdowns, date pickers, text inputs, sliders, etc. They live in the page's `elements` array alongside tables and charts, **not** nested inside them. The wiring (which column a control filters, which downstream elements respond) is the part of the design that the OpenAPI doesn't really teach — that's what this file is for.

## Common Fields

| Field | Required | Notes |
|---|---|---|
| `kind` | yes | Always `control` |
| `id` | yes | Element ID — must be unique on the page |
| `controlId` | yes | Formula reference name (e.g., `RegionFilter`) — keep distinct from `id`. This is the human-meaningful handle. |
| `controlType` | yes | Determines the widget and filter behavior (see variants below) |
| `name` | yes | Display label |
| `source` | usually | Points at the column whose values populate the control. Shape: `{ kind: source, source: { kind: table, elementId: ... }, columnId: ... }` |
| `filters` | yes | Array of `{ source: { kind: table, elementId: ... }, columnId: ... }` — connects the control to the column(s) it filters |

---

## List (dropdown / multi-select)

```yaml
kind: control
id: ctrl-region
controlId: RegionFilter
name: Store region
controlType: list
mode: include
selectionMode: multiple
values: []
source:
  kind: source
  source:
    kind: table
    elementId: sales-table
  columnId: col-region
filters:
  - source:
      kind: table
      elementId: sales-table
    columnId: col-region
```

- `mode`: `include` | `exclude`
- `selectionMode`: `single` | `multiple`
- `values`: initial selected values. `[]` = none pre-selected.

## Date Range

A date-range control filters one or more date columns. The widget shape is determined by `mode`, and each mode takes different additional fields. Eight modes are supported. No `source` is needed — the column is defined by the `filters` binding.

Common shape:

```yaml
kind: control
id: ctrl-date
controlId: DateFilter
name: Date range
controlType: date-range
mode: <see below>
includeNulls: when-no-value-is-selected
filters:
  - source:
      kind: table
      elementId: sales-table
    columnId: col-date
```

`includeNulls`: `always` | `never` | `when-no-value-is-selected`.

### Modes

| Mode | Extra fields | Use for |
|---|---|---|
| `between` | `startDate?`, `endDate?` (ISO 8601) | Inclusive range. Both fields optional — omitting them shows the picker with no preset. |
| `last` | `value` (number), `unit`, `includeToday` (bool) | "Last N days/weeks/months." |
| `next` | `value`, `unit`, `includeToday` | "Next N days/weeks/months." |
| `current` | `unit` | "This year/quarter/month/week/day." |
| `on` | `date` (ISO 8601) | Exact date match. |
| `before` | `date` | Strictly before a fixed date. |
| `after` | `date` | Strictly after a fixed date. |
| `custom` | `startDate`, `endDate` (each: ISO string OR `{ op, unit, value }` for relative) | Mixed fixed/relative bounds. |

`unit` values: `year`, `quarter`, `month`, `week-starting-sunday`, `week-starting-monday`, `day`, `hour`, `minute`.

For relative `startDate` / `endDate` shapes (used in `custom` mode):

```yaml
op: now-minus
unit: day
value: 30
```

`op`: `now-minus` or `now-plus`.

### Common Examples

**Last 70 days:**

```yaml
mode: last
value: 70
unit: day
includeToday: true
```

**This quarter:**

```yaml
mode: current
unit: quarter
```

**Fixed range:**

```yaml
mode: between
startDate: "2026-01-01"
endDate: "2026-03-31"
```

**Last 90 days through today (custom mode with relative bounds):**

```yaml
mode: custom
startDate:
  op: now-minus
  unit: day
  value: 90
endDate:
  op: now-minus
  unit: day
  value: 0
```

## Text

Single-line text filter.

```yaml
kind: control
id: ctrl-search
controlId: SearchText
name: Search
controlType: text
mode: contains
value: ""
case: insensitive
includeNulls: when-no-value-is-selected
filters:
  - source:
      kind: table
      elementId: sales-table
    columnId: col-product-name
```

`mode` values: `equals`, `does-not-equal`, `contains`, `does-not-contain`, `starts-with`, `ends-with`, `like`, `matches-regexp`, and their negations.

## Number Range

```yaml
kind: control
id: ctrl-amount
controlId: AmountFilter
name: Amount
controlType: number-range
mode: between
values: [0, 1000]
filters:
  - source:
      kind: table
      elementId: sales-table
    columnId: col-amount
```

## Slider

A slider is a **`number-range` control**, not a distinct `slider` kind. There is no separate `controlType: slider` shape (don't use `value`/`min`/`max` at the top level — those get rejected with a misleading `Invalid kind: pages[0].elements[N], got "control"` error; the actual problem is the control's inner shape, not the element kind).

Single-handle slider — use `number-range` with `mode: between` and a two-element `values` array for the current range:

```yaml
kind: control
id: ctrl-top-n
controlId: TopN
name: Top N
controlType: number-range
mode: between
values: [1, 10]
filters: []
```

> **Round-trip gap:** as of 2026-04, `values` on a `number-range` control does not reliably round-trip. A `PUT` with `values: [1, 10]` reads back as `values: null` on the next `GET`. The UI still respects the initial value when the workbook renders, but the source-of-truth view via the API shows `null`. Don't rely on a subsequent `GET` to confirm the value stuck — open the workbook or trust the last-known `PUT`.

## Text Area

Multi-line text input. Same shape as `text`, different widget:

```yaml
kind: control
id: ctrl-notes
controlId: NotesFilter
name: Notes contains
controlType: text-area
mode: contains
value: ""
case: insensitive
includeNulls: when-no-value-is-selected
filters:
  - source:
      kind: table
      elementId: tickets-table
    columnId: col-body
```

## Segmented (parameter / radio buttons)

> **Verified 2026-05-24 against sigma-skill-recon test #6.** `controlType: segmented` is the correct shape for Tableau-style parameters (a small fixed set of choices rendered as radio buttons / button group).

Manual values (most common — parameter):

```yaml
kind: control
id: ctrl-time-period
controlId: TimePeriod
name: Time period
controlType: segmented
source:
  kind: manual
  valueType: text
  values: ["Month", "Quarter", "Year"]
  labels: [null, null, null]
value: Quarter
```

Dynamic values (sourced from a column):

```yaml
kind: control
id: ctrl-ship-mode
controlId: ShipMode
name: Ship mode
controlType: segmented
source:
  kind: source
  source: { kind: table, elementId: sales-table }
  columnId: col-ship-mode
value: null
```

Segmented controls have **no `filters`** — they act as parameters referenced in element formulas via `controlId`:

```
Sum(If([TimePeriod] = "Month", [Sales], Null))
```

## Control types that do NOT exist

> **Verified 2026-05-24 against sigma-skill-recon tests #3-5.** The following `controlType` values are all rejected with HTTP 400 `Invalid kind: "control"`. They are not valid spec shapes — use the correct alternative.
>
> | Rejected `controlType` | Use instead |
> |---|---|
> | `slider` | `number-range` with `mode: between` and a two-element `values` array (see Slider section above) |
> | `range-slider` | `number-range` |
> | `toggle` | `list` with `selectionMode: single` and a fixed two-value source (or rebuild as a parameter via `segmented`) |
> | `checkbox` | Same — `list` or `segmented` |
> | `dropdown` | `list` with `selectionMode: single` |
> | `radio` | `segmented` (for parameters) or `list` with `selectionMode: single` |

---

## One Control, Multiple Elements

A control's `filters` array can hold **multiple bindings** — one per element/column the control should filter. This is the right tool for a page-level filter that applies to several tables or charts at once. Don't make a separate control per element.

```yaml
kind: control
id: ctrl-region
controlId: RegionFilter
name: Store region
controlType: list
mode: include
selectionMode: multiple
values: []
source:
  kind: source
  source:
    kind: table
    elementId: sales-table
  columnId: col-region
filters:
  - source: { kind: table, elementId: sales-table }
    columnId: col-region
  - source: { kind: table, elementId: returns-table }
    columnId: col-region
  - source: { kind: table, elementId: sales-by-region }
    columnId: col-region
```

Each binding names the target element by `elementId` and the column on that element to filter by `columnId`. The column IDs do **not** need to match across elements; they just need to exist on each target element.

## One Element, Multiple Controls

The dual pattern, and a common Sigma layout: a parent table that several controls filter, with downstream elements (KPIs, charts, secondary tables) sourcing from the parent. Filter once at the parent — every element that sources it inherits the filter automatically.

```yaml
# Parent: "sales-table". Downstream KPIs/charts source from it.
# Three controls each filter the parent on a different column.

- kind: control
  id: ctrl-region
  controlId: RegionFilter
  controlType: list
  mode: include
  selectionMode: multiple
  values: []
  source:
    kind: source
    source: { kind: table, elementId: sales-table }
    columnId: col-region
  filters:
    - source: { kind: table, elementId: sales-table }
      columnId: col-region

- kind: control
  id: ctrl-date
  controlId: DateFilter
  controlType: date-range
  mode: between
  filters:
    - source: { kind: table, elementId: sales-table }
      columnId: col-date

- kind: control
  id: ctrl-amount
  controlId: AmountFilter
  controlType: number-range
  mode: between
  values: [0, 10000]
  filters:
    - source: { kind: table, elementId: sales-table }
      columnId: col-amount
```

Multiple controls on the same target compose with **AND** — selecting region "West" + date "Q1" narrows to the intersection. Prefer this over binding each control to every downstream element; it's less repetitive and keeps the filter chain in one place.

## Where Control Bindings Apply

Controls parametrize **filter values** on their target elements — nothing else. They cannot bind to structural fields like `rowCount`, `rankingFunction`, aggregation choice, or chart mappings. A spec like `rowCount: "[TopN]"` will be rejected; the field takes a number literal only. To vary a top-N cap interactively you currently need to duplicate the element per cap or wait for a future field that accepts a control reference.

## Tip: `controlId` vs `id`

They are not the same and both are required:
- `id` is the element ID used internally and in `layout.md`.
- `controlId` is a human-facing handle used when referring to this control's value from formulas or downstream logic. Pick it to be meaningful (e.g., `RegionFilter`, `DateRange`).
