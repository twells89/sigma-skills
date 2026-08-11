# Report Element Support Matrix

The report request schema references `CommonElement`, but schema publication is
not the same as safe report support. Use this conservative matrix.

## States

| State | Meaning | Authoring policy |
|---|---|---|
| Live-proven | Passed verify, create, readback, update, and PDF export in a report-enabled org | Safe baseline; still validate each new shape |
| Documented | Covered by report examples or report documentation and present in OpenAPI | Validate and verify before write |
| Schema-only | Present in `CommonElement`, but report behavior or PDF behavior is not established here | Warn; require targeted live verify/readback/PDF evidence |
| Unsupported | Report documentation identifies the feature as unsupported | Reject for authoring |
| Workbook-only | Present only in `WorkbookElement` | Reject; redesign or use a workbook |

## Live-proven baseline

The following kinds passed verify, persistent create, GET readback,
full-document PUT, and populated landscape PDF export on 2026-08-11:

- `bar-chart`, including horizontal orientation, single color, sorting, and
  hidden legend
- `combo-chart`, with bar and line series over a `DateTrunc("quarter", ...)`
  axis
- `kpi-chart`, with `Sum`, `CountDistinct`, ratio formulas, number formats,
  value color/font size, and layout anchor/title orientation
- `table`, including warehouse-table and table-element sources, grouping,
  aggregate calculations, presentation style, banding, horizontal grid lines,
  and `dataBars` conditional formatting
- `text`, including Markdown and inline font/color styling

The same report proved a hidden dependency page, absolute pixel layout,
header/footer panel assignment and rendering, complete panel readback, and a
new document version after PUT. This is a baseline, not blanket proof of every
optional field on these kinds.

## Documented common kinds

- `area-chart`
- `control`, except `controlType: synced`
- `divider`
- `geography-map`
- `image`
- `line-chart`
- `pivot-table`
- `point-map`
- `region-map`
- `scatter-chart`

Use the current OpenAPI for each complete element shape. When installed, the
matching `sigma-workbooks/reference/specification/` element, source, formula,
and formatting guides provide useful common-shape recipes. Ignore all workbook
layout and workbook-only behavior in those guides.

## Schema-only kinds

- `button`
- `embed`
- `input-table`
- `plugin`

These may verify in some configurations, but interactive or write-back
behavior and PDF output require explicit evidence. The local validator emits a
warning rather than accepting them silently.

The inherited top-level `document.settings` field is also schema-published but
not report-proven by this skill. Preserve it unchanged when it appears in a
readback, warn before PUT, and do not author new theme/navigation settings
without targeted verify, readback, and PDF evidence.

## Unsupported kinds and subtypes

- `waterfall-chart`
- `progress` (gauge/progress presentation)
- `control` with `controlType: synced`

These appear in the shared OpenAPI union but are called unsupported by report
documentation. The local validator rejects them.

## Workbook-only kinds

- `chat`
- `container`
- `form`
- `navigation`
- `page-break`
- `repeated-container`
- `tabbed-container`

Do not emulate these by copying workbook layout XML. Convert the design to
fixed report pages or keep it as a workbook.

## Unknown future kinds

The API can add common kinds before this skill is updated. The validator warns
on an unknown kind instead of claiming it is invalid. Inspect the current
OpenAPI and report documentation, run `/v2/reports/spec/verify`, and update the
matrix only after evidence establishes the correct state.

## Lossy readback warning

`GET /v2/reports/{reportId}/spec` can omit features unsupported by report code
representation. Before PUT, compare the code representation with the report's
element, page, and control inventory APIs. If inventory objects are missing
from `document`, stop. Replacing the document can permanently remove omitted
features from the next report version.
