# Controls

Recipe book for the control element family and the patterns that wire them up. The OpenAPI is the source of truth for every field; this file adds the wiring patterns it doesn't teach.

Controls are interactive filter elements — lists, date pickers, text inputs, sliders, etc. They live in the page's `elements` array alongside tables and charts, **not** nested inside them. The wiring (which column a control filters, which downstream elements respond) is the part the OpenAPI doesn't teach — that's what this file is for.

**Every `controlType` wires up the same way** (`controlId` + `filters`, below); they differ only in the widget and its value object. So treat the per-type sections below as illustrations of the *wiring*, **not a catalog of what's supported** — a `controlType` you don't see here works the same way. The set also grows over time, so get the current list from the spec rather than hardcoding it:

```bash
jq -r '[.. | objects | select(.properties?.controlType?.enum) | .properties.controlType.enum[0]] | unique[]' /tmp/sigma-api.json
```

## Control Element Fields

A `control` element has exactly these fields:

| Field | Required | Notes |
|---|---|---|
| `kind` | yes | Always `control` |
| `id` | yes | Element ID — must be unique on the page |
| `controlId` | yes | Formula reference name (e.g., `RegionFilter`) — keep distinct from `id`. This is the human-meaningful handle used when referring to the control's value from formulas. |
| `controlType` | yes | Any value the recipe above returns. Determines the widget and filter behavior. |
| `filters` | — | Array of `{ source, columnId }` — connects the control to the column(s) it filters. `source` is `{ kind: table, elementId: ... }`. |
| `parameters` | — | Array, for binding the control to a data-model control (parameter). |
| `name` | — | Display label. |
| `style` | — | Presentation options for the widget. |

There are **no** value/widget fields at the control top level. Things like the selected mode, current value, or range bounds live inside the value object that the control carries, not as flat sibling fields of `controlType`. The recipes below show the value-object shape per type; treat those nested shapes as the value detail, not as additional control-element properties.

`filters[]` items are `{ source: { kind: table, elementId: ... }, columnId: ... }`. The `columnId` is the column on the target element to filter.

---

## List

A single- or multi-select list control over a column's values.

```yaml
kind: control
id: ctrl-region
controlId: RegionFilter
name: Store region
controlType: list
filters:
  - source:
      kind: table
      elementId: sales-table
    columnId: col-region
```

The value object carries the selection (`mode`: `include` | `exclude`; selection cardinality; selected values). `segmented` and `hierarchy` are the other list-style widget types — same wiring, different presentation. Inspect the spec's control value schema for the exact value-object field names rather than guessing.

## Date Range

A date-range control filters one or more date columns. The widget shape is determined by `mode`, and each mode takes different additional fields **inside the value object**. No `source` is needed — the column is defined by the `filters` binding.

```yaml
kind: control
id: ctrl-date
controlId: DateFilter
name: Date range
controlType: date-range
filters:
  - source:
      kind: table
      elementId: sales-table
    columnId: col-date
```

The value object selects a mode and its parameters. `includeNulls`: `always` | `never` | `when-no-value-is-selected`.

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

### Value-object Examples

These show the date-range **value shape**, not flat control fields.

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

Single-line text filter. (`text-area` is the multi-line variant — same wiring, different widget.)

```yaml
kind: control
id: ctrl-search
controlId: SearchText
name: Search
controlType: text
filters:
  - source:
      kind: table
      elementId: sales-table
    columnId: col-product-name
```

The text value object carries the match `mode` and the search string. `mode` values include `equals`, `does-not-equal`, `contains`, `does-not-contain`, `starts-with`, `ends-with`, `like`, `matches-regexp`, and their negations.

## Number Range

```yaml
kind: control
id: ctrl-amount
controlId: AmountFilter
name: Amount
controlType: number-range
filters:
  - source:
      kind: table
      elementId: sales-table
    columnId: col-amount
```

The number-range value object expresses the bounds with `low`, `high`, and an optional `step` — **not** a positional `values: [min, max]` array.

## Sliders

`slider` and `range-slider` are both first-class `controlType` values — distinct from `number` and `number-range`. A `slider` is a single-handle widget; `range-slider` has two handles for a low/high band. Pick the `controlType` for the widget you want and supply the bounds in the value object (`low`/`high`/`step`).

## Single-value types

`number`, `date`, `checkbox`, and `switch` are single-value controls. `checkbox` and `switch` are the boolean widgets — same value (a boolean), different presentation:

```yaml
kind: control
id: ctrl-active-only
controlId: ActiveOnly
name: Active only
controlType: switch
filters:
  - source:
      kind: table
      elementId: users-table
    columnId: col-is-active
```

## Top-N

`top-n` is a dedicated control type for "show the top N" interactions. Wire it like any other control via `filters`; the cap lives in its value object.

---

## One Control, Multiple Elements

A control's `filters` array can hold **multiple bindings** — one per element/column the control should filter. This is the right tool for a page-level filter that applies to several tables or charts at once. Don't make a separate control per element.

```yaml
kind: control
id: ctrl-region
controlId: RegionFilter
name: Store region
controlType: list
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
  filters:
    - source: { kind: table, elementId: sales-table }
      columnId: col-region

- kind: control
  id: ctrl-date
  controlId: DateFilter
  controlType: date-range
  filters:
    - source: { kind: table, elementId: sales-table }
      columnId: col-date

- kind: control
  id: ctrl-amount
  controlId: AmountFilter
  controlType: number-range
  filters:
    - source: { kind: table, elementId: sales-table }
      columnId: col-amount
```

Multiple controls on the same target compose with **AND** — selecting region "West" + date "Q1" narrows to the intersection. Prefer this over binding each control to every downstream element; it's less repetitive and keeps the filter chain in one place.

## Tip: `controlId` vs `id`

They are not the same and both are required:
- `id` is the element ID used internally and in `layout.md`.
- `controlId` is a human-facing handle used when referring to this control's value from formulas or downstream logic. Pick it to be meaningful (e.g., `RegionFilter`, `DateRange`).
</content>
</invoke>
