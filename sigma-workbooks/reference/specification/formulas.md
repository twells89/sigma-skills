# Sigma Formula Reference

## ⚠️ READ FIRST: The #1 Formula Mistake

When an element sources another element (e.g., a KPI or chart sourcing a table), **every column reference inside aggregations must include the source element's name as a prefix.** Forgetting the prefix is the single most common Sigma spec error.

**Wrong:**
```json
{ "kind": "kpi-chart", "source": { "kind": "table", "elementId": "usage-table" },
  "columns": [{ "name": "Total", "formula": "Count([Question ID])" }] }
```

**Right:**
```json
{ "kind": "kpi-chart", "source": { "kind": "table", "elementId": "usage-table" },
  "columns": [{ "name": "Total", "formula": "Count([AI Usage Data/Question ID])" }] }
```

**Why:** a bare `[column_name]` means *defined in THIS element's own `columns[]` array* — not *visible through the source*. SQL intuition leaks here: `Count([col])` feels local because the source "is" the table, but Sigma's formula language requires you to name the source explicitly.

**Rule of thumb:** if your element's `source` points at another element (or a warehouse table, or a join), 90%+ of your formulas will start with `[<SourceName>/...]`. Bare refs are only for columns you literally defined a line or two above in the same `columns[]` array.

Before publishing, run `./scripts/validate-spec.sh <spec.json>` — it catches exactly this mistake.

---

## ⚠️ READ SECOND: Special Characters in Column Names

Raw warehouse column names often contain characters that Sigma normalizes when producing the "friendly name" used in formulas. Writing a formula against the raw warehouse name will silently fail to resolve — a real hang-up when you can't figure out why an "Invalid column" error keeps firing on a name that obviously exists in the warehouse.

**The worst offenders:**

- **`/`** — **cannot appear in a column reference.** The slash is the source-prefix separator in bracket syntax (`[Source/col]`), so Sigma strips it from column names. A warehouse column named `Net/Gross` becomes something like `Net Gross` in the friendly name.
- **`-`** — typically replaced or stripped.
- **`.`**, **`[`**, **`]`**, **leading/trailing whitespace** — stripped.

**Rule:** ask the user for the exact column name Sigma uses (the friendly name shown in the workbook UI), and copy it verbatim. Do not transform the raw warehouse name yourself, and do not guess at the normalization — the exact rules vary across character classes.

Wrong: `[ORDERS/Net/Gross Revenue]` (slash inside a column name; unparseable)
Wrong: `[ORDERS/Order-ID]` (raw warehouse name with a dash)
Right: `[ORDERS/Net Gross Revenue]` (friendly name)
Right: `[ORDERS/Order ID]` (friendly name)

If publish fails with "Invalid column" on a column you know exists in the warehouse, re-confirm the friendly name with the user and copy it character-for-character. Do not hand-edit warehouse names.

---

## Column Reference Rules

Every column formula references either a column **outside** the element or a column **inside** the same element.

### Outside the element — use `[SourceName/column_name]`

The prefix depends on the source type:

- **Warehouse table**: `SourceName` = last segment of the `path` array.
  - Path `["DB", "SCHEMA", "ORDERS"]` → `[ORDERS/revenue]`
  - Path `["ANALYTICS", "PUBLIC", "USERS"]` → `[USERS/email]`

- **Another workbook element**: `SourceName` = that element's `name` field.
  - Element named "Sales Table" → `[Sales Table/Revenue]`

- **Join source**: `SourceName` = the `name` field on a specific join leg, or the top-level `name` on the join object (for the `primarySource` leg).
  - Join with `primarySource` implicitly tied to top-level `name: "Sales Star"` → `[Sales Star/Order Number]` for primary columns.
  - Join leg with `name: "Sales"` → `[Sales/Cust Key]` for that joined table's columns.
  - Warehouse path segments do **not** become the prefix inside a join — use the join leg's `name` instead.

- Column names must match exactly what the describe endpoint returns. **Never invent column names.**

### Inside the same element — use `[column_name]` (no prefix)

References a column already defined in this element by its `name` field.

```
// Given columns: "Revenue" (formula: [ORDERS/revenue]), "Cost" (formula: [ORDERS/cost])
// A third column can reference them:
[Revenue] - [Cost]       // valid — references sibling columns by name
Sum([Revenue])           // valid — aggregation over a sibling column
```

**A column cannot reference itself** — that is a circular reference error. This trips up copy-paste: if a column's `name` field matches any bracketed reference inside its own `formula`, the server treats it as circular even when you meant to reference a different column. Rename one side to break the cycle.

### Common mistakes

| Wrong | Correct | Why |
|-------|---------|-----|
| `[revenue]` | `[ORDERS/revenue]` | Missing table prefix for warehouse column |
| `[ORDERS/Total Revenue]` | `[Total Revenue]` | "Total Revenue" is a sibling column, not a warehouse column |
| `[Revenue]` in the "Revenue" column | Rename one side | A column cannot reference itself |
| `Count([Question ID])` on a sourced element | `Count([AI Usage Data/Question ID])` | Aggregation argument needs the source prefix |

## Operators

### Arithmetic
`+`, `-`, `*`, `/`, `%` (modulo), `^` (power)

**Do not use** `Power()` or `Mod()` — use `^` and `%` instead.

### Boolean
`and`, `or`, `not` are **prefix/infix operators, not function calls** — always put a space before the operand.

```
Wrong: Not(Contains([Deployment], "staging"))       // parses, but every row is null
Right: Not (Contains([Deployment], "staging"))      // space after Not

Wrong: And([Active], [Paid])                         // not a function
Right: [Active] And [Paid]                           // infix

Wrong: Or([Trial], [Free])                           // not a function
Right: [Trial] Or [Free]                             // infix

Right: Not [Active]
Right: [A] And Not [B]
Right: ([Status] = "Active") And ([Plan] = "Pro")
```

The trap: `Not(...)` parses successfully (the parens become grouping), so the failure is silent — null rows, no error. Easy to get wrong by analogy with `Sum([X])` / `If(...)`.

### String concatenation
`&` (not `+`)

**Do not use** `Concat()` — use `&` instead.

## Aggregation Functions

| Function | Description |
|----------|-------------|
| `Sum([col])` | Sum of values |
| `Avg([col])` | Average of values |
| `Count([col])` | Count of non-null values |
| `CountDistinct([col])` | Count of distinct values |
| `Min([col])` | Minimum value |
| `Max([col])` | Maximum value |
| `Median([col])` | Median value |

## Date Functions

| Function | Example |
|----------|---------|
| `DateTrunc(<part>, <date>)` | `DateTrunc("month", [Date])` |
| `DateDiff(<part>, <start>, <end>)` | `DateDiff("day", [Start], [End])` |
| `DateAdd(<part>, <units>, <date>)` | `DateAdd("month", 3, [Date])` |
| `DateFormat(<date>, <fmt>)` | `DateFormat([Date], "%Y-%m-%d")` |

Date parts (must be quoted strings): `"year"`, `"quarter"`, `"month"`, `"week"`, `"day"`, `"hour"`, `"minute"`, `"second"`

## Conditional

```
If(<condition>, <then>, <else>)
```

Supports multiple conditions (chained):
```
If([Status] = "Active", "Active", [Status] = "Pending", "Pending", "Other")
```

**Do not use** `Case` — use `If` instead.

## Text Functions

| Function | Description |
|----------|-------------|
| `Contains(<text>, <search>)` | True if text contains search |
| `Left(<text>, <n>)` | First n characters |
| `Right(<text>, <n>)` | Last n characters |
| `Upper(<text>)` | Uppercase |
| `Lower(<text>)` | Lowercase |
| `Trim(<text>)` | Remove leading/trailing whitespace |
| `Length(<text>)` | Character count |
| `Replace(<text>, <old>, <new>)` | Replace occurrences |

## JSON / Struct Field Access

Columns containing JSON or struct data (common for event payload / metadata columns) support **field access via dot notation** on the bracketed column reference. The extracted value is untyped — wrap it in the appropriate type constructor (`Text`, `Number`, `Date`) to coerce before passing it to downstream functions.

```
Text([Langfuse Metadata].agentId)           // extracts agentId as text
Text([Event Payload].user.id)               // nested access
Number([Event Payload].latency_ms)          // numeric cast
Text([Organizations].users[0])              // array index — first element
Text([Organizations].users[0].email)        // index + nested field
```

Without the wrapping cast, comparisons (`=`, `<`), aggregations (`Count`, `CountDistinct`), and text ops (`Contains`, concatenation with `&`) will often behave unexpectedly or fail silently — the extracted value keeps its variant/untyped flavor. If a JSON-derived formula appears to return `null` or mismatched values for every row, check that it's wrapped in `Text()` / `Number()` first.

Dot notation goes directly on the `]` — no space: `[Col].field`, not `[Col] .field`.

## Other Functions

| Function | Description |
|----------|-------------|
| `Coalesce(<a>, <b>, ...)` | First non-null value |
| `In([col], "a", "b", "c")` | True if value is in the list |
| `IsNull([col])` | True if null |
| `Null` | Null literal |

## Window Functions

| Function | Description |
|----------|-------------|
| `Rank()` | Rank within partition |
| `RowNumber()` | Row number within partition |
| `Lead(<col>)` | Next row's value |
| `Lag(<col>)` | Previous row's value |
| `RunningSum(<col>)` | Cumulative sum |
| `RunningAvg(<col>)` | Cumulative average |
