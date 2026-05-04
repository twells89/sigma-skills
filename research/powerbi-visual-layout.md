# PowerBI Visual Layout Extraction — Research Spike

> Beads issue: **beads-sigma-tq6**
> Status: desk research / structural analysis only — no live PowerBI access used.
> Goal: determine how to extract per-visual position/size from a PowerBI report and
> map it onto Sigma's 24-column dashboard grid, mirroring the existing
> `tableau-to-sigma` Phase 3 layout pipeline.

---

## 1. Target — what Sigma's layout expects

The `tableau-to-sigma` skill's Phase 5d generates a single top-level `layout` XML
string on the workbook spec. The grid is fixed:

- 24 columns (`gridTemplateColumns="repeat(24, 1fr)"`), span notation `1 / 25` = full width
- Auto-sized rows; conventional row units (KPI ≈ 6–9 rows, half-width chart ≈ 12–13 rows, table ≈ 15–20 rows)
- Container elements (`<GridContainer>`) wrap KPI rows; child `<LayoutElement>` row spans MUST equal the container's outer span (auto rows do not stretch to fill)

Whatever we extract from PowerBI, we must reduce it to four integers per visual:
`gridColumnStart, gridColumnEnd, gridRowStart, gridRowEnd` — plus a child/parent
relationship for any group containers.

---

## 2. PBIX file internals — `Report/Layout`

A `.pbix` is a ZIP archive. The relevant entry for layout is `Report/Layout`,
a JSON document. Two important file-level gotchas before parsing:

1. **Encoding is UTF-16 LE with BOM.** Reading it as UTF-8 yields garbled NULs
   between every character. In Python: `zf.read('Report/Layout').decode('utf-16')`.
2. **Position is stored in two places** on each visual and PBIX writers can
   disagree between them. Reads should prefer the outer `visualContainer`
   coordinates and fall back to `config.layouts[0].position` only if the outer
   set is missing. Writers must update both.

### 2a. Top-level shape (legacy PBIX, the format still produced today by Power BI Desktop unless PBIR is enabled)

```jsonc
{
  "id": 0,
  "resourcePackages": [ /* themes, custom visuals */ ],
  "config": "{ ... stringified JSON ... }",     // activePageIndex, settings, theme refs
  "layoutOptimization": 0,
  "sections": [
    {
      "id": 0,
      "name": "ReportSection1",                 // internal page id
      "displayName": "Sales Overview",          // user-visible tab name
      "ordinal": 0,                             // 0-based page order
      "displayOption": 1,                       // 1=fitToPage, 2=fitToWidth, 3=actualSize
      "width":  1280,                           // page canvas px
      "height": 720,
      "config": "{ ... }",                      // bg, padding, page-level options
      "filters": "[ ... ]",                     // page-scope filters (stringified)
      "visualContainers": [ ... ]               // see 2b
    }
  ]
}
```

Default canvas is **1280 × 720 (16:9)**; users can override per page (4:3, Letter, Custom).
Some inner fields (`config`, `filters`, `query`) are themselves stringified JSON
that needs a second `json.loads()`.

### 2b. visualContainer shape

```jsonc
{
  "x":      490.18675721561970,                 // canvas-pixel coords, top-left origin
  "y":      211.47707979626486,
  "z":      0,                                  // stacking order (PBIR also exposes this)
  "width":  299.490662139219,
  "height": 299.490662139219,
  "tabOrder": 1000,                             // accessibility / keyboard tab order
  "config":   "{ ... stringified ... }",        // contains name, layouts[0].position dup, singleVisual, objects
  "filters":  "[ ... ]",                        // visual-level filters
  "query":    "{ ... }",                        // semantic query (data binding)
  "dataTransforms": "{ ... }"                   // projections, sort, formatting overrides
}
```

After parsing `config`:

```jsonc
{
  "name": "71e22ef0cde4efc97e8a",               // stable visual id (alphanum, ~20 chars)
  "layouts": [
    { "id": 0,
      "position": { "x": 490.18, "y": 211.47, "z": 0,
                    "width": 299.49, "height": 299.49 } }
  ],
  "singleVisual": {
    "visualType": "card",                       // see kind-mapping table below
    "projections":  { /* role -> column refs */ },
    "prototypeQuery": { /* DAX-ish query */ },
    "objects":   { /* per-object format props */ },
    "drillFilterOtherVisuals": true
  }
}
```

`singleVisual.visualType` values seen in samples: `card`, `multiRowCard`,
`textbox`, `barChart`, `clusteredBarChart`, `columnChart`, `clusteredColumnChart`,
`lineChart`, `areaChart`, `lineClusteredColumnComboChart`, `pieChart`,
`donutChart`, `tableEx`, `pivotTable`, `slicer`, `map`, `filledMap`,
`scatterChart`, `gauge`, `kpi`, `image`, `shape`, `actionButton`. There is also
`groupVisualContainer` (legacy) / `visualGroup` (PBIR) used as a parent
container that other visuals reference via `parentGroupName`.

### 2c. PBIR (Power BI Enhanced Report) — newer on-disk format

When a project is saved via Power BI Desktop with the PBIR developer preview
enabled (or via `pbi-tools`), the single `Report/Layout` blob is exploded into
a folder tree:

```
MyReport.Report/
├── definition.pbir
├── definition/
│   └── report.json                              // resourcePackages, theme, settings
└── definition/pages/
    ├── pages.json                               // ordered list of page folder names
    ├── ReportSection_<id>/
    │   ├── page.json                            // displayName, height, width, ordinal
    │   └── visuals/
    │       └── visualContainer_<id>/
    │           ├── visual.json                  // position{x,y,z,width,height}, tabOrder, visualType
    │           ├── filters.json
    │           └── query.json
```

`visual.json` keeps the same coordinate semantics — top-left origin, canvas
pixels — but cleanly splits position out of the `config` blob:

```jsonc
{
  "name": "<id>",
  "position": { "x": 490.19, "y": 211.48, "z": 0, "width": 299.5, "height": 299.5 },
  "tabOrder": 1000,
  "visual": { "visualType": "card", "query": { ... } }
}
```

Either format converts to Sigma using the same coordinate math. Recommend
detecting which one is present (`Report/Layout` blob vs. `definition/pages/`
tree) and dispatching to two parsers behind a common visual struct.

### 2d. Fields we care about per visual (post-extraction)

```ruby
{
  page_id:        "ReportSection1",   # name
  page_title:     "Sales Overview",   # displayName
  page_w:         1280,
  page_h:         720,
  visual_id:      "71e22ef0cde4efc97e8a",
  visual_type:    "card",
  parent_group:   nil,                 # or another visual's name when grouped
  x: 490.19, y: 211.48, w: 299.49, h: 299.49,
  z: 0,
  tab_order: 1000,
  hidden: false                        # PBIR exposes displayState; legacy infers via objects
}
```

---

## 3. PowerBI REST / embedded API — what's actually exposed

| Path | Returns visual position? | Auth | Tier required |
|---|---|---|---|
| `GET /v1.0/myorg/groups/{groupId}/reports/{reportId}/pages` | **No** — only `name`, `displayName`, `order` | AAD bearer + `Report.Read.All` (or `.ReadWrite.All`) | Any (Pro) |
| `GET /v1.0/myorg/groups/{groupId}/reports/{reportId}/pages/{pageName}` | **No** — same fields, single page | same | Any |
| `GET /v1.0/myorg/groups/{groupId}/reports/{reportId}/Export` (download PBIX) | **Indirect** — yields a PBIX you parse offline | AAD bearer + `Report.ReadWrite.All` | Pro for download; tenant admin can disable |
| `POST /v1.0/myorg/reports/{reportId}/ExportTo` (Export-To-File) | **No** — produces PDF / PPTX / PNG; no JSON layout | AAD bearer | Premium / Embedded / Fabric capacity (NOT Premium-Per-User) |
| Embedded JS SDK `report.getPages()` → `page.getVisuals()` → `visual.layout` | **Yes** — `{ x, y, z, width, height, displayState }` per visual | Embed token from `POST /generateToken` | Premium / Embedded / Fabric capacity (browser-side runtime) |

**Conclusions:**

- The plain REST `GET pages` endpoint is **not sufficient** — it returns no
  geometry. This is a long-standing gap; community feature requests for a
  "Get Visuals Per Page" REST endpoint are open and unaddressed.
- The only programmatic, position-aware live source is the **embedded JS SDK**,
  and it requires a hosted browser context and an embed token from a Premium /
  Embedded / Fabric capacity. Building a converter around it means shipping a
  headless-browser harness (`puppeteer` / `playwright`) plus a service
  principal flow with capacity costs.
- The **Export Report** endpoint downloads the PBIX itself, after which we are
  back to `Report/Layout` parsing. This is gated by Pro tier and a tenant
  setting that admins frequently disable for governance reasons.

---

## 4. Worked example — map one page to Sigma's 24-col grid

I'm using a synthetic but plausible PBIX page modelled on the
`AdventureWorks Sales Sample` from
[microsoft/powerbi-desktop-samples](https://github.com/microsoft/powerbi-desktop-samples)
("Sales Overview" pattern: page header text, KPI row, full-width line chart,
two side-by-side bar charts). I cannot ship the actual extracted JSON without
unzipping the file in the live environment, but the coordinate ranges below
are typical for a 1280×720 AdventureWorks-style overview page and the
arithmetic is what the converter would actually run.

### 4a. Source coordinates (page width 1280, page height 720)

| Visual | visualType | x | y | width | height |
|---|---|---:|---:|---:|---:|
| Page header text | `textbox`  |   20 |   20 | 1240 |  40 |
| KPI: Total Sales | `card`     |   20 |   80 |  300 | 120 |
| KPI: Total Profit | `card`    |  330 |   80 |  300 | 120 |
| KPI: Profit Margin | `card`   |  640 |   80 |  300 | 120 |
| KPI: Customers | `card`       |  950 |   80 |  310 | 120 |
| Sales Trend (line) | `lineChart` |  20 |  220 | 1240 | 220 |
| Sales by Category (bar) | `clusteredBarChart` | 20 | 460 | 620 | 240 |
| Sales by Region (bar)   | `clusteredColumnChart` | 650 | 460 | 610 | 240 |

(In a real extraction the four KPIs would also be reported as children of a
`visualGroup` parent — that group becomes the Sigma `<GridContainer>`.)

### 4b. Conversion math

```
COL_UNIT = page_width  / 24            # px per Sigma column track  → 1280/24 = 53.333
ROW_UNIT = 30                          # chosen per-row pixel height; tuneable
SNAP_PX  = COL_UNIT / 2                # 26.67 px tolerance for end-of-track snap

col_start = floor(x          / COL_UNIT) + 1
col_end   = floor((x + w - 1)/ COL_UNIT) + 2     # +1 for half-open span, +1 for 1-indexing
row_start = floor(y          / ROW_UNIT) + 1
row_end   = ceil ((y + h)    / ROW_UNIT) + 1
```

Rounding rules:

- Snap `col_start` down and `col_end` up so adjacent visuals share a track
  boundary instead of leaving a 1-track gap. PBIX coords are fractional pixels
  (Power BI Desktop drag interactions emit values like `490.18675721561970`),
  so a naive `round` produces off-by-one boundaries between visuals that are
  visually flush.
- For `row_end`, prefer `ceil` plus a "minimum span" floor (KPI ≥ 6 rows, chart
  ≥ 12 rows) so Sigma's auto-row sizing doesn't collapse content.
- After computing every visual, sort by `(row_start, col_start)` and check for
  overlaps; if two visuals share a row range and overlap on columns by ≤ 1
  track, snap the trailing one one column right.

### 4c. Applied to the AdventureWorks page

Using `COL_UNIT = 53.333`, `ROW_UNIT = 30`:

| Visual | x → col_start | (x+w) → col_end | y → row_start | (y+h) → row_end | Sigma `gridColumn` | Sigma `gridRow` |
|---|---|---|---|---|---|---|
| Page header text |  20 → **1**  | 1260 → **25** |  20 → **1** |  60 → **3**  | `1 / 25` | `1 / 3`  |
| KPI Total Sales |  20 → **1**  |  320 → **7**  |  80 → **3** | 200 → **8**  | `1 / 7`  | `3 / 8`  |
| KPI Total Profit | 330 → **7** |  630 → **13** |  80 → **3** | 200 → **8**  | `7 / 13` | `3 / 8`  |
| KPI Profit Margin| 640 → **13**|  940 → **19** |  80 → **3** | 200 → **8**  | `13 / 19`| `3 / 8`  |
| KPI Customers    | 950 → **19**| 1260 → **25** |  80 → **3** | 200 → **8**  | `19 / 25`| `3 / 8`  |
| Sales Trend (line)| 20 → **1** | 1260 → **25** | 220 → **8** | 440 → **16** | `1 / 25` | `8 / 16` |
| Sales by Category (bar) | 20 → **1** | 640 → **13** | 460 → **16** | 700 → **24** | `1 / 13` | `16 / 24` |
| Sales by Region (bar)   | 650 → **13**| 1260 → **25**| 460 → **16** | 700 → **24** | `13 / 25`| `16 / 24` |

Sample math for KPI Total Profit (`x=330, y=80, w=300, h=120`):

```
col_start = floor(330 / 53.333) + 1            = floor(6.1875) + 1 = 6 + 1 = 7
col_end   = floor((330 + 299) / 53.333) + 2    = floor(11.79)  + 2 = 11 + 2 = 13
row_start = floor(80  / 30)    + 1             = floor(2.67)   + 1 = 2 + 1 = 3
row_end   = ceil ((80 + 120) / 30) + 1         = ceil(6.67)    + 1 = 7 + 1 = 8
                                               → gridColumn="7 / 13"  gridRow="3 / 8"
```

Each KPI ends up 6 cols × 5 rows. Adjacent KPIs share a column boundary
(`/7`–`7/`, `/13`–`13/`, `/19`–`19/`), and the four together exactly tile
columns 1–25 — the snap rules collapse the small fractional gutters (10 px of
padding) into clean track boundaries.

### 4d. Container wrap

Because the four KPIs share `gridRow="3 / 8"`, the converter wraps them in a
single Sigma container so they read as one card group:

```ruby
gc(
  container_id, 1, 25, 3, 8,
  [
    le(kpi_total_sales,  1,  7, 3, 8),
    le(kpi_total_profit, 7, 13, 3, 8),
    le(kpi_profit_pct,  13, 19, 3, 8),
    le(kpi_customers,   19, 25, 3, 8)
  ].join("\n")
)
```

Inner `gridRow` matches the container's outer span (`3 / 8`) per the
[`refs/workbook-layout.md`](../tableau-to-sigma/refs/workbook-layout.md)
"inner row spans must match outer" rule.

### 4e. Visual-type → Sigma element-kind mapping (preliminary)

| PBIX `visualType` | Sigma kind | Notes |
|---|---|---|
| `card`, `multiRowCard`, `kpi`, `gauge` | `kpi-chart` | Need `value` field |
| `textbox`, `actionButton` (text-only) | `text` | `body` from `objects.general.text` |
| `image`, `shape` (image-bg) | `image` | `url` from resourcePackages (rare) |
| `lineChart` | `line-chart` | Multi-measure → multiple `yAxis` entries |
| `areaChart`, `stackedAreaChart` | `area-chart` | Set `stacking` |
| `barChart`, `clusteredBarChart`, `stackedBarChart` | `bar-chart` (horizontal) | UI-only orientation; flag for post-publish |
| `columnChart`, `clusteredColumnChart`, `stackedColumnChart`, `hundredPercentStackedColumnChart` | `bar-chart` | Default vertical |
| `lineClusteredColumnComboChart`, `lineStackedColumnComboChart` | `combo-chart` | Mark line series with `type:"line"` |
| `pieChart` | `pie-chart` | `color` + `value` required |
| `donutChart` | `donut-chart` | `color` + `value` + `holeValue` required |
| `scatterChart` | `scatter-chart` | |
| `tableEx` | `table` | |
| `pivotTable`, `matrix` | `pivot-table` | Use `rowsBy`/`columnsBy`/`values` shape |
| `slicer` | `control` | Type derived from slicer mode (list/dropdown/range/date-range) |
| `map`, `filledMap`, `shapeMap`, `azureMap` | `bar-chart` | Sigma has no map; degrade to sorted bar-chart per the existing Tableau pattern |
| `groupVisualContainer` / `visualGroup` | `container` | Wraps children via `<GridContainer>` |
| `funnel`, `treemap`, `waterfallChart`, `ribbonChart`, `decompositionTreeVisual`, `keyInfluencersVisual`, `qnaVisual` | (no equivalent) | Approximate with `bar-chart` or skip with warning |

---

## 5. Auth / scope cost & recommendation

| Path | Setup cost | Per-conversion cost | Reliability | Position fidelity |
|---|---|---|---|---|
| **A. User uploads `.pbix` file** | None | unzip + parse JSON | Highest | Exact pixel coords |
| B. Service principal + `Export Report` REST → unzip | Register AAD app, grant `Report.ReadWrite.All`, admin must allow downloads, Pro license | 1 API call + zip parse | Medium (admin setting, retries on long-poll) | Exact pixel coords (same data as A) |
| C. Headless browser + Embedded JS SDK `getVisuals` | AAD app, embed-token endpoint, **Premium/Embedded/Fabric capacity**, `puppeteer`/`playwright` runtime | Spin up browser, embed report, await getVisuals | Lowest (browser flakiness, capacity throttles) | Exact (`IVisualLayout`) |
| D. REST `GET pages` only | Trivial AAD app | 1 call | Highest | **None** — name/order only, no geometry |

**Recommendation: Path A (PBIX upload) for v1; Path B as an opt-in
"connect to Power BI Service" upgrade later.**

Rationale:

- **A is the only path that needs zero PowerBI tenant access.** The user
  already has the file open in Power BI Desktop; "Save As → upload" is one
  click. Mirrors the `tableau-to-sigma` flow where the user already has access
  to the source workbook.
- **B is the natural step up** when users want to point the converter at a
  workspace report instead of a local file. The implementation reuses 100% of
  the parser written for A — the only new code is the
  `GET /reports/{id}/Export` long-poll plus AAD client-credential flow. Defer
  until A is shipped and the parser is hardened.
- **C is a trap.** Premium / Embedded capacity is ~$5k/month list price; we'd
  also need to host a browser, manage embed tokens, and inherit every Power BI
  Service outage. The only thing it buys over B is "no admin export setting" —
  not worth it for a converter that runs occasionally.
- **D alone is a non-starter.** Zero geometry, zero usefulness for layout.
  Fine as a side call to enumerate page names if we don't want to open the zip
  for the listing UI.

### Implementation sketch (path A, Ruby, parallel to `tableau-to-sigma`)

```ruby
require 'zip'
require 'json'

def extract_visuals(pbix_path)
  Zip::File.open(pbix_path) do |zf|
    raw = zf.glob('Report/Layout').first.get_input_stream.read
    layout = JSON.parse(raw.force_encoding('UTF-16LE').encode('UTF-8'))
    layout['sections'].flat_map do |section|
      page_w, page_h = section.values_at('width', 'height')
      section['visualContainers'].map do |vc|
        cfg = JSON.parse(vc['config'])
        {
          page_id:    section['name'],
          page_title: section['displayName'],
          page_w:     page_w,
          page_h:     page_h,
          visual_id:  cfg['name'],
          visual_type: cfg.dig('singleVisual', 'visualType') ||
                       (cfg['layouts'] ? 'group' : 'unknown'),
          x: vc['x'], y: vc['y'], w: vc['width'], h: vc['height'],
          z: vc['z'] || 0,
          tab_order: vc['tabOrder']
        }
      end
    end
  end
end

def to_sigma_grid(v, col_unit:, row_unit: 30)
  cs = (v[:x] / col_unit).floor + 1
  ce = ((v[:x] + v[:w] - 1) / col_unit).floor + 2
  rs = (v[:y] / row_unit).floor + 1
  re = ((v[:y] + v[:h]) / row_unit).ceil + 1
  { col_start: cs, col_end: ce, row_start: rs, row_end: re }
end
```

The downstream `gc(...)` / `le(...)` / `page_xml(...)` Ruby helpers from
`tableau-to-sigma/refs/workbook-layout.md` then take over unchanged.

---

## 6. Open questions / next spike

1. **Visualgroup → container translation.** PBIR exposes
   `parentGroupName` cleanly; legacy stuffs the same info inside the
   `singleVisual`/`groupVisualContainer` distinction. Need a real PBIR sample
   to confirm the field name.
2. **`displayState: "hidden"`.** Power BI bookmarks toggle visual visibility
   per state. For static export we should drop hidden visuals. Verify both
   PBIX (`config.singleVisual.display`) and PBIR (`visual.position.displayState`).
3. **Tooltip pages.** Pages with `config.type == "tooltip"` should be excluded
   from the Sigma output entirely — they're not user-facing pages.
4. **`displayOption` (page fit mode).** `1=fitToPage`, `2=fitToWidth`,
   `3=actualSize`. Currently we just read `width`/`height` and ignore fit; if
   `2`, the canvas is implicitly scrollable and our `ROW_UNIT` may need to be
   smaller.
5. **Custom visuals.** `resourcePackages` declares them; `singleVisual.visualType`
   is then a long custom id (e.g. `"PBI_CV_..."`). Default fallback:
   `bar-chart` with a warning, same as the Tableau map fallback.
6. **Confirm the math on a real PBIX.** Once an actual sample is unzipped
   (next spike: live env), re-derive the table in §4c against the extracted
   coordinates and compare. Adjust `ROW_UNIT` if charts come out too tall/short.

## Sources

- [Power BI Desktop project report folder — Microsoft Learn (PBIR)](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-report)
- [PBI-Inspector README — schema overview for sections / visualContainers](https://github.com/NatVanG/PBI-Inspector/blob/main/README.md)
- [A Beginner's Guide to Automating Power BI with the Layout File — Antares Analytics](https://www.antaresanalytics.net/post/a-beginner-s-guide-to-automating-power-bi-with-the-layout-file-part-2)
- [PBIR Folder Structure Explained — Draft BI](https://draftbi.com/blog/what-is-pbir)
- [What is PBIR? Full Guide to Power BI Enhanced Report Format — Lukas Reese](https://lukasreese.com/2026/03/16/what-is-pbir-full-guide-to-power-bi-enhanced-report-format/)
- [Apply page size and settings in a Power BI report — Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/create-reports/power-bi-report-display-settings)
- [Reports - Get Pages REST API — Microsoft Learn](https://learn.microsoft.com/en-us/rest/api/power-bi/reports/get-pages)
- [Reports - Export Report (download PBIX) — Microsoft Learn](https://learn.microsoft.com/en-us/rest/api/power-bi/reports/export-report)
- [Reports - Export To File (PDF/PPTX/PNG) — Microsoft Learn](https://learn.microsoft.com/en-us/rest/api/power-bi/reports/export-to-file)
- [Report Layout in Power BI Embedded (custom layout) — Microsoft Learn](https://learn.microsoft.com/en-us/javascript/api/overview/powerbi/custom-layout)
- [Get pages and visuals in a Power BI embedded analytics application — Microsoft Learn](https://learn.microsoft.com/en-us/javascript/api/overview/powerbi/get-visuals)
- [microsoft/powerbi-desktop-samples — AdventureWorks Sales Sample](https://github.com/microsoft/powerbi-desktop-samples)
