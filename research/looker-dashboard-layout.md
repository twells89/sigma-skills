# Looker → Sigma Dashboard Layout Extraction (Spike)

**Beads issue:** `beads-sigma-vgz`
**Status:** Research / desk study (no live Looker access)
**Recommendation:** **Partial — yes for `layout: newspaper` dashboards via the REST API, no for `layout: tile` / `layout: static` / `layout: grid` without a pixel→grid heuristic. Requires new MCP tooling that does not exist today.**

---

## 1. Why this spike exists

The `tableau-to-sigma` skill ships a Phase 3 layout pipeline that mirrors a Tableau workbook onto Sigma's 24-column grid by:

1. POSTing a workbook spec (charts, KPIs, controls) without layout.
2. GETing the spec back to learn server-assigned element IDs.
3. Generating layout XML in Ruby — `<Page>`, `<GridContainer>`, `<LayoutElement>` — with `gridColumn="c0 / c1"` / `gridRow="r0 / r1"` span notation against `repeat(24, 1fr)` columns.
4. PUTing the spec back with one **top-level** `layout` field (per-page `layout` is silently ignored).

We want Phase 3 coverage for Looker dashboards — i.e. given a Looker dashboard, produce equivalent Sigma element specs and a layout XML string that places those tiles where the Looker original placed them.

References in this repo:
- `tableau-to-sigma/SKILL.md` — overall pipeline shape
- `tableau-to-sigma/refs/workbook-layout.md` — Sigma 24-col grid, Ruby `gc()`/`le()`/`page_xml()` helpers, KPI inner-row gotcha
- `tableau-to-sigma/refs/data-model-spec.md` — data-model JSON shape
- `sigma-workbooks/reference/specification/` — canonical workbook spec surface

---

## 2. Looker has two layout surfaces, and they disagree

Unlike Tableau, where every workbook has a single canonical `.twb` representation, Looker exposes **two** layout sources that must be reconciled:

### 2a. REST API (`GET /dashboards/{id}` + `dashboard_layouts`)

Returns runtime objects:

| Type | Key fields |
|---|---|
| `Dashboard` | `id`, `title`, `description`, `folder_id`, `slug`, `lookml_link_id`, `dashboard_filters[]`, `dashboard_elements[]`, `dashboard_layouts[]` |
| `DashboardElement` | `id`, `dashboard_id`, `look_id`, `query` (object), `merge_result_id`, `result_maker`, `type` (vis kind), `title`, `subtitle_text`, `body_text`, `note_text`, `vis_config` (opaque JSON) |
| `DashboardLayout` | `id`, `dashboard_id`, `type` (`newspaper` / `tile` / `static` / `grid`), `active`, `column_width`, `width`, `dashboard_layout_components[]` |
| `DashboardLayoutComponent` | `id`, `dashboard_layout_id`, `dashboard_element_id`, `row` (int), `column` (int), `width` (int), `height` (int), plus `granular_row`/`granular_column`/`granular_width`/`granular_height` for high-DPI overrides, and `element_title`, `vis_type` |
| `DashboardFilter` | `id`, `name`, `title`, `type`, `default_value`, `model`, `explore`, `dimension`, `allow_multiple_values`, `required` |

The layout positions live in `DashboardLayoutComponent`, **not** on the element. One element can appear in multiple layouts (mobile vs desktop) and only the `active: true` layout matters.

### 2b. LookML (`*.dashboard.lookml` files)

YAML-flavoured Looker files where layout fields are inlined on each element. Sample (extracted live from `looker-open-source/block-redshift-admin`):

```yaml
- dashboard: redshift_admin
  preferred_viewer: dashboards-next
  title: Redshift Admin
  layout: newspaper
  query_timezone: query_saved
  elements:
  - title: Table Load Summary
    name: Table Load Summary
    model: block_redshift_admin_v2
    explore: redshift_data_loads
    type: table
    fields: [redshift_data_loads.root_bucket, redshift_data_loads.s3_path_clean, ...]
    sorts: [redshift_data_loads.root_bucket]
    listen: {}
    row: 0
    col: 2
    width: 20
    height: 13
```

LookML and API representations diverge:
- LookML uses `col`; API uses `column`.
- LookML may omit `row`/`col` entirely (for `layout: tile` it auto-flows; for `layout: newspaper` defaults are `row: 0`, `col: 0`, `width: 8`, `height: 6`).
- LookML `fields:` uses `view.field` syntax (e.g. `redshift_data_loads.root_bucket`); the API returns the same syntax inside the `query.fields` array.
- A LookML dashboard linked to a database-backed copy will surface as a `Dashboard` row with `lookml_link_id` set; user edits in the UI become divergence.

### 2c. The four `layout:` modes

| Mode | Unit | Positioning | Notes |
|---|---|---|---|
| `newspaper` (default in modern Looker) | **24-column grid**, height in **6-row tile units** | `row` (0-based, top), `col` (0-based, left), `width` (columns 1–24), `height` (rows) | **Direct map to Sigma's 24-column grid.** Default tile height 6 ≈ default Looker dashboard "row of tiles". |
| `tile` | `tile_size` pixels (default 160 px) | `row` / `col` in tile units, but tiles flow auto-arranged | Pre-newspaper "card grid". Most legacy LookML dashboards. |
| `static` | `tile_size` pixels | `top` / `left` (pixels), `width` / `height` (pixels) | Free-form pixel positioning — no grid. |
| `grid` | Newspaper-like, but 12 columns | Same fields as newspaper | Legacy — most upgrades convert it to newspaper. Looker docs flag this as a subset of newspaper. |

---

## 3. Mapping Looker newspaper → Sigma 24-column grid

This is the path of least resistance and the recommended scope of Phase 3 v1.

| Looker (newspaper) | Sigma (`refs/workbook-layout.md`) |
|---|---|
| 24 columns, `col` 0-based | 24 columns, `gridColumn` 1-based span |
| `row` 0-based row (≈12 px units, but used relatively) | `gridRow` 1-based span; Sigma rows are "auto" relative units |
| `width` in columns | `gridColumn` end - start = `width` |
| `height` in rows | `gridRow` end - start = `height` |

Conversion formulas (Looker → Sigma):

```
gridColumn = "${col + 1} / ${col + 1 + width}"
gridRow    = "${row + 1} / ${row + 1 + height}"
```

So a Looker tile at `row: 0, col: 2, width: 20, height: 13` becomes:

```xml
<LayoutElement elementId="<sigma-id>" gridColumn="3 / 23" gridRow="1 / 14"/>
```

That's a single arithmetic transform — no spatial heuristic required for newspaper. The Ruby helpers in `tableau-to-sigma/refs/workbook-layout.md` (`gc()`, `le()`, `page_xml()`) work as-is once Looker components are loaded into the same `(elementId, c0, c1, r0, r1)` shape.

### Container / sub-grouping
Looker has no native container element analogous to Sigma's `container`. Tile groups in Looker are visual only (no parent ID), so the converter should:
- emit each Looker element as a top-level `<LayoutElement>`,
- **not** synthesize Sigma `container` elements automatically.

KPI rows in Looker (`type: single_value`, `single_value` height typically 2–3 rows in newspaper) can optionally be wrapped in a Sigma `<GridContainer>` if the converter detects 3+ adjacent single-value tiles in the same row band — but this is a nice-to-have, not required.

### Row-height calibration
Looker rows ≠ Sigma rows. Looker newspaper rows are ~50 px each and elements typically span 6 rows for a chart. Sigma rows are "auto" — driven by content. Empirical heuristic from `refs/workbook-layout.md` row-sizing guide:

| Looker `height` | Sigma typical span |
|---|---|
| 2–3 (single_value KPI) | 6–8 inner units (match container outer span if grouped) |
| 6 (default chart) | 12–13 |
| 13 (large table) | 18–20 |

Rather than re-deriving, the converter can pass Looker `height` straight through as Sigma row units — because Sigma rows auto-size, the proportions hold even if the absolute pixel size differs. Visual verification post-publish is still required.

### Static / tile / grid layouts
For `layout: static` (pixel positions), a heuristic is needed: divide the canvas into a 24-column grid and snap each tile's `left`/`top`/`width`/`height` (in pixels) to the nearest column/row. This is lossy. Recommended fallback: emit a warning, place tiles in document order at `gridColumn="1 / 25"` stacked, leave manual layout to the user.

For `layout: tile`, Looker auto-flows tiles in a 12-column grid; converter should expand to 24 by doubling each `col` and `width` value. No row positioning data exists, so emit tiles in document order.

For `layout: grid` (12-column legacy), double each `col` and `width`.

---

## 4. Sigma-MCP tool validation — **blocked**

The task asked for `parse_lookml` and `convert_lookml_to_sigma` MCP tools. **Neither exists in the currently exposed Sigma-MCP surface.**

### 4a. Verbatim tool discovery

Available `mcp__Sigma-MCP__*` tools, captured from the deferred-tool catalog:

```
mcp__Sigma-MCP__begin_session
mcp__Sigma-MCP__create_workbook
mcp__Sigma-MCP__describe
mcp__Sigma-MCP__list_documents
mcp__Sigma-MCP__query
mcp__Sigma-MCP__search
```

Searching the catalog explicitly returns no matches:

```
ToolSearch query="+lookml"   max_results=10 → No matching deferred tools found
ToolSearch query="+convert"  max_results=10 → No matching deferred tools found
```

The Sigma-Docs API endpoint catalog also has no matches:

```
mcp__Sigma-Docs__search-endpoints pattern="lookml"  → No matches found for "lookml"
mcp__Sigma-Docs__search-endpoints pattern="convert" → No matches found for "convert"
```

`mcp__Sigma-MCP__begin_session` returns instructions covering only Tables / Data Models / Workbooks — no LookML import path is mentioned.

`mcp__Sigma-Docs__search query="LookML Looker conversion import migration"` returned a single hit, `migrate-a-dataset-to-a-data-model`, which is about migrating Sigma datasets to Sigma data models — unrelated to Looker.

### 4b. What this means for the spike

We could not run a real LookML dashboard sample through `parse_lookml` / `convert_lookml_to_sigma` because neither tool is wired up in the MCP. The downstream comparison ("what the converter produces today vs. what's needed") cannot be made. The closest existing Sigma converter for LookML is the **browser-based "Convert from LookML"** tool referenced in `README.md`'s picker table — it's a UI flow, not exposed via MCP.

We did successfully retrieve a real public LookML dashboard sample (`looker-open-source/block-redshift-admin/dashboards/redshift_admin.dashboard.lookml`) and confirmed the field shape matches Looker's documentation. The sample is reproduced in §2b above for downstream test cases.

---

## 5. Gotchas catalog

These are translation hazards — issues a Looker→Sigma converter must detect or document, ranked by how often they bite real dashboards.

### 5a. Liquid templating in fields and SQL

Looker SQL and field expressions support [Liquid](https://cloud.google.com/looker/docs/liquid-variable-reference) — `{% if %}`, `{{ field._value }}`, `{% parameter %}`, `{% condition %}`. Sigma has no Liquid equivalent; the closest analog is a **parameter control** + an `If()`/`Coalesce()` formula or a **dynamic SQL** workaround.

Examples and translation strategy:

| Liquid pattern | Sigma equivalent |
|---|---|
| `{% if user_attribute['region'] == 'EU' %}eur_table{% else %}us_table{% endif %}` (table swap) | Two tables joined as separate sources; a `segmented` control selects which to show. Lossy for row-level swapping. |
| `{% if value > 10000 %}High{% else %}Low{% endif %}` (display formatting) | A calculated column: `If([Master/value] > 10000, "High", "Low")`. Direct translation. |
| `{% condition my_filter %} order_date {% endcondition %}` (templated filter) | Pass-through to a Sigma date-range control wired to `order_date`. Direct translation. |
| `{{ field._value }}` (linking, drill URLs) | Sigma `Hyperlink()` formula or workbook drill-through. Often dropped. |
| `{% parameter p_period %}` (LookML parameter) | Sigma `segmented`/`list` control. Direct translation when the parameter is a finite enum. |

**Detection heuristic:** any field SQL containing `{%` or `{{` triggers a converter warning and stops auto-translation for that field.

### 5b. `merged_results` queries

Looker `merge_result_id` lets one tile join data from two completely different explores. The merge happens client-side using shared field values. Sigma has no client-side merge — the equivalent is either:

- a **data model element** that joins the two underlying tables with a relationship; or
- a **table element** in the workbook with a manual SQL CTE (Sigma allows custom SQL elements, but the team has a separate skill — `custom-sql-to-data-model` — for handling those).

**Translation:** the converter must follow `merge_result_id` to fetch the source query specs, identify the join keys, and emit a single Sigma data-model element with the join. If the Looker merge has more than two sources or non-equi joins, fall back to manual conversion and warn.

### 5c. Table calculations vs. measures

Looker has two distinct things that look similar:
- **Measures** — defined in LookML view files (`measure: sales { type: sum sql: ${TABLE}.sales ;; }`), pushed down to the warehouse, aggregated by the SQL engine.
- **Table calculations** — defined per-tile in the dashboard (`pct_of_total`, `running_total`, `offset()`, etc.), evaluated **client-side** on the result set after SQL returns.

Sigma's data model has **metrics** (analogous to measures, warehouse-evaluated). Sigma's workbook formulas (`Sum()`, `RunningTotal()`, etc.) cover most table-calculation use cases, but they evaluate on-grid against the element data, not on a separately-materialized result set. Mapping rules:

| Looker | Sigma |
|---|---|
| LookML `measure` | Data model element column `formula: "Sum([TABLE/sales])"` (or a metric attached to the element). |
| Table calc `pct_of_total(${revenue})` | Workbook column `[revenue] / Sum([revenue]) Over (All)` |
| Table calc `running_total(${revenue})` | `RunningSum([revenue])` (preserved order) |
| Table calc `offset(${revenue}, -1)` | `Lag([revenue], 1)` |
| Table calc with `${field._is_filtered}` or `${field._in_query}` introspection | **No equivalent.** Drop and warn. |

### 5d. View-vs-explore field-prefix resolution

LookML field references look like `view_name.field_name` — but the **view name** is shadowed by the **explore name** when the explore renames a join (e.g. `join: customers { from: users sql_on: ... }` makes `customers.email` resolve to the `users` view). The converter must walk the explore's `join` clauses to resolve the actual view per prefix before generating Sigma column references.

Sigma's column refs are flat: `[ElementName/Column Name]`. The Tableau pipeline already documents this — the data-model element's `name` becomes the prefix. For Looker, the converter should:

1. For each tile, parse `query.fields[]` like `customers.email`.
2. Resolve `customers` → underlying view via the explore's join graph.
3. Find the warehouse table for that view (`view: users { sql_table_name: prod.public.users ;; }`).
4. Emit a Sigma data-model element named after the **resolved view** (or the explore root for the base view), and reference the column with `[users/EMAIL]`.

This is the single biggest source of bugs in any LookML→anything converter. **Mandatory test cases:** explore with `view_name` aliased; explore with self-join; explore with a `join` whose `relationship: many_to_one` differs from the warehouse FK direction.

### 5e. Tile types Sigma cannot represent 1:1

| Looker tile `type:` | Sigma analog | Notes |
|---|---|---|
| `looker_column`, `looker_bar` | `bar-chart` | Direct. Looker's `stacking` (`normal` / `percent`) maps to Sigma `"none"`/`"stacked"`/`"100"`. |
| `looker_line` | `line-chart` | Direct. |
| `looker_area` | `area-chart` | Direct. |
| `looker_scatter` | `scatter-chart` | Direct (single x, multiple y). Bubble-size encoding is UI-only in Sigma. |
| `looker_pie` | `pie-chart` | Direct. Beware `pie` vs `pie-chart` kind name — Sigma rejects `pie`. |
| `looker_donut_multiples` | `donut-chart` (single ring) | Looker shows N donuts (one per dimension value); Sigma has one — emit a single donut and warn. |
| `looker_grid`, `table` | `table` | Direct. |
| `single_value` | `kpi-chart` | Direct. Use `value` field. |
| `text` | `text` | Direct. Markdown body. Looker `subtitle_text` / `body_text` concatenate. |
| `looker_map`, `looker_geo_coordinates`, `looker_geo_choropleth` | **None** — approximate as `bar-chart` of "Sales by State" sorted descending (Tableau pipeline does the same). |
| `looker_funnel` | **None** — approximate as horizontal `bar-chart`. |
| `looker_waterfall` | **None** — approximate as `combo-chart` with running-total line. |
| `looker_boxplot` | **None** — drop and warn. |
| `looker_wordcloud` | **None** — drop and warn. |
| `looker_timeline` (Gantt) | **None** — drop and warn (same as Tableau pipeline). |
| `looker_sankey` | **None** — drop and warn. |
| Custom visualizations (third-party JS) | **None** — drop and warn. |
| `button` | Sigma `text` with `Hyperlink()` body or workbook action — partial. |

### 5f. Filters: Looker dashboard filters → Sigma controls

Looker `dashboard_filters[]` map cleanly:

| Looker filter `type` | Sigma `controlType` |
|---|---|
| `field_filter` (string list) | `list` |
| `field_filter` (date) | `date-range` |
| `field_filter` (number range) | `number-range` |
| `parameter` | `segmented` (when enum), `text` (when free-form), `number` (when numeric) |

Caveat: Looker filters use *templated filter* syntax (`{% condition %}`) inside SQL to apply themselves. Sigma controls bind directly to a column via `filters: [{source, columnId}]`. The converter must:

1. Find every tile that listens to the filter (`listen:` block in LookML, `listens_to_filters[]` in API).
2. For each, find the column in the Sigma element that corresponds to the bound LookML field.
3. Emit a Sigma `control` whose `filters[]` array references all of those (element, column) pairs.

A Looker filter listened-to by 0 tiles produces a dead Sigma control — drop it.

### 5g. "Cross-filtering" (a tile filtering siblings)

Looker dashboards-next supports cross-filtering — clicking a bar filters every other tile. Sigma supports the same via "Set as filter" actions on chart elements, but **this is not in the spec API today** — it is UI-only. Ship the dashboard without cross-filters and document the post-publish step.

### 5h. `lookml_link_id` divergence

A dashboard with `lookml_link_id` is connected to a `*.dashboard.lookml` file but may have user edits applied via the UI. The API returns the **edited** state; the LookML file represents the **source-of-truth** state. Pick one canonical input — I'd recommend the API, because:

- The UI edits are what the user actually sees.
- The API gives layout components separately (one source of truth for positioning).
- It's the same path Tableau-to-Sigma uses (live API, not file).

### 5i. Element title vs tile title vs note text

Looker has three text fields on a tile:
- `title` — the visualization caption (e.g. "Revenue by Month").
- `subtitle_text` — small text below the title.
- `note_text` / `note_display: hover|below|above` — descriptive note rendered in a tooltip or a fixed slot.

Sigma element specs only persist `id`, `kind`, and a few content fields — chart titles are stored on the element but `subtitle_text`/`note_text` have no spec analog. Translation: concatenate into the chart's title or emit a separate adjacent `text` element.

### 5j. Refresh interval / autorun

Looker tiles can set `refresh: 5 minutes`. Sigma workbooks have a workbook-level scheduled refresh, not per-element. Drop and warn.

---

## 6. Feasibility verdict

**Partial yes.** The mapping from Looker's newspaper layout to Sigma's 24-column grid is a single arithmetic transformation — `gridColumn = (col+1) / (col+1+width)`, `gridRow = (row+1) / (row+1+height)` — and the Ruby layout helpers in `tableau-to-sigma/refs/workbook-layout.md` work as-is once the Looker components are loaded.

What's blocking a turnkey Phase 3:
1. **No `parse_lookml` / `convert_lookml_to_sigma` MCP tool.** Source-format parsing is the precondition for layout extraction. The browser-based converter is UI-only.
2. **Static / tile / grid layouts** require a heuristic snap-to-grid step that has no analog in the Tableau pipeline — non-trivial work.
3. **Liquid, merged_results, table calculations, custom viz** are open-ended; full coverage is impossible. v1 should warn-and-drop.

---

## 7. Recommended additional MCP tooling

To bring Looker-to-Sigma to feature parity with `tableau-to-sigma`, the Sigma MCP needs three new tools, sized roughly:

### 7a. `parse_lookml` (small)
Input: a `*.dashboard.lookml` file body, or a LookML project URL with auth. Output: structured JSON of dashboard + elements + filters with all positioning fields normalized to newspaper-grid units (snap heuristic for tile/static/grid). Returns warnings array for unsupported tile types, Liquid usage, table-calc usage, merged_results, custom viz.

### 7b. `fetch_looker_dashboard` (medium)
Input: Looker host + auth (API key or OAuth) + dashboard ID or slug. Output: same structured JSON as `parse_lookml` but pulled from the live `Dashboard` + `dashboard_layouts/{id}` endpoints with the **active** layout component set.

The Tableau pipeline assumes live API access for the same reasons (authoritative state, layout, filter linkage). Looker's parallel is `dashboard_layouts` + `dashboard_dashboard_elements`.

### 7c. `convert_lookml_to_sigma` (medium-large)
Takes the structured output of (a) or (b) and emits:
- a Sigma data-model spec (one element per resolved view, joined per the explore graph), ready for `POST /v2/dataModels/spec`;
- a Sigma workbook spec (one element per Looker tile, controls per filter, references via `[ElementName/Column]`), ready for `POST /v2/workbooks/spec`;
- a layout XML string usable directly in the Phase 3 PUT.

This is the analogue of the manual `tableau-to-sigma` Phase 3–5 work, but driven entirely from the Looker JSON. Without it, every conversion is bespoke.

### 7d. Optional: `validate_lookml_conversion` (small)
After publishing, pull a chart's data from Sigma (already supported via `query`/`describe`) and compare to the Looker tile's `run_inline_query` result. Mirrors `tableau-to-sigma` Phase 6.

---

## 8. Suggested Phase 3 implementation outline (when tooling lands)

1. **Discovery** — `fetch_looker_dashboard` (or `parse_lookml`) returns dashboard JSON.
2. **Field resolution** — walk explore joins, resolve `view.field` prefixes, emit a Sigma data-model spec with one element per resolved view; POST it; GET the spec back to capture server-assigned IDs.
3. **Workbook spec** — for each Looker `dashboard_element`, emit a Sigma element of the matching `kind`. Use the converter's tile-type table (§5e). Source from the master data-model element; column formulas use `[ElementName/Column]`. POST without layout; GET back to capture element IDs.
4. **Layout XML** — generate via Ruby helpers in `tableau-to-sigma/refs/workbook-layout.md`, using `(col+1, col+1+width)` / `(row+1, row+1+height)` from the Looker components. Single top-level `layout`, no per-page `layout`.
5. **PUT** the spec with layout. Strip read-only fields per `tableau-to-sigma/SKILL.md` Phase 5e.
6. **Verify** — query each Sigma chart and compare to Looker tile data.

The Tableau pipeline's invariants — element-name = formula prefix, `<GridContainer>` for containers, KPI inner-row span = container outer span, `kpi-chart` not `kpi`, `pie-chart` not `pie`, etc. — apply unchanged.

---

## 9. Sources

- [Looker LookML dashboard parameters (Google Cloud)](https://docs.cloud.google.com/looker/docs/reference/param-lookml-dashboard) — `layout` modes (newspaper / tile / static / grid), `row` / `col` / `width` / `height`, `tile_size`.
- [Looker Get DashboardLayout method](https://cloud.google.com/looker/docs/reference/looker-api/latest/methods/Dashboard/dashboard_layout) — `dashboard_layout_components` schema.
- [DashboardLayout type (Looker API 3.1 archive)](https://cloud.google.com/looker/docs/reference/looker-api/3.1/23.12/types/DashboardLayout) — `column_width`, `width`, `active`, `dashboard_layout_components[]`.
- [Looker DashboardElement type (latest)](https://docs.cloud.google.com/looker/docs/reference/looker-api/latest/types/DashboardElement) — `body_text`, `note_text`, `query`, `look_id`, `merge_result_id`, `result_maker`.
- [Looker DashboardApi — keboola/looker-api docs](https://github.com/keboola/looker-api/blob/master/docs/Api/DashboardApi.md) — schema reference for Dashboard / DashboardElement / DashboardLayout / DashboardLayoutComponent / DashboardFilter.
- [Looker DashboardApi — hirosassa/looker-rs docs](https://github.com/hirosassa/looker-rs/blob/master/docs/DashboardApi.md) — corroborating field list including `vis_config`, `lookml_link_id`.
- [Building LookML dashboards (Google Cloud)](https://docs.cloud.google.com/looker/docs/building-lookml-dashboards) — concept docs for `*.dashboard.lookml`.
- [Liquid variable reference (Looker)](https://cloud.google.com/looker/docs/liquid-variable-reference) — `{% if %}`, `{{ field._value }}`, `{% condition %}`, `{% parameter %}`.
- [Templated filters and Liquid parameters (Looker)](https://docs.cloud.google.com/looker/docs/templated-filters) — runtime-only template substitution semantics; persistence not supported on derived tables that use these.
- [Troubleshooting unsupported dashboard layout (Looker)](https://docs.cloud.google.com/looker/docs/best-practices/troubleshooting-unsupported-dashboard-layout) — confirms `static`/`tile`/`grid` are legacy and can render incorrectly.
- [block-redshift-admin sample dashboard.lookml](https://github.com/looker-open-source/block-redshift-admin/blob/master/dashboards/redshift_admin.dashboard.lookml) — concrete LookML dashboard used in §2b.

In-repo references:
- `tableau-to-sigma/SKILL.md`
- `tableau-to-sigma/refs/workbook-layout.md`
- `tableau-to-sigma/refs/data-model-spec.md`
- `tableau-to-sigma/refs/column-gotchas.md`
- `README.md` (for the existing converter-MCP-vs-skill split)
