# Building from a target image

Use this workflow when the user has provided a screenshot, mockup, or PDF of a dashboard they want reproduced in Sigma — including migrations from Tableau, Looker, PowerBI, or any other BI tool.

The general spec workflow ([the rest of SKILL.md](../../SKILL.md)) still applies. This document covers **only the additional steps** that come *before* and *alongside* normal data discovery and spec drafting.

## Why this workflow exists

When the user supplies an image, the agent's first job isn't to call the API — it's to *interpret*. A workbook spec is a precise object; an image is not. Going straight from "I see a picture" to "POST this YAML" almost always produces a workbook that has the right vibe but wrong shape, wrong axes, or wrong groupings — because the agent never committed to an interpretation explicit enough to debug.

The workflow below makes the interpretation step explicit and auditable.

## Workflow

### Step 0a — Read the target image first

Before any API calls, before any data discovery, **read the image with the Read tool**. Don't read it as a confirmation step at the end; read it as the first thing you do.

If the user provided a target image, treat the workbook-creation task as a two-input problem: the prose request *and* the image. The image usually carries more information than the prose, but ambiguities in the image are why the prose is also there.

### Step 0b — Describe what you see, in Sigma terms

After reading the image, **write out an inventory** of what you saw. Do this as part of your reply / planning, before drafting any spec. The inventory has three sections:

1. **Element count and kinds.** For each visible element, name the Sigma `kind` it most closely maps to (`kpi-chart`, `bar-chart`, `line-chart`, `donut-chart`, `table`, `text`, `image`, `geography-map`, etc.). If you're not sure, describe the visual marks (bars of equal width? a line? a sector?) and state your best guess.
2. **Per-element details.** For each element: what's on the x-axis, y-axis, color/series channel? Is it grouped or stacked? Are there filters or controls visible?
3. **Layout.** Grid density (how many elements per row, how many rows), any container groupings (logos / headers / sections), any visible whitespace.

The goal is to produce an explicit, debuggable interpretation. If you build a workbook and the visual judge says "this looks different," you can point at the inventory and see exactly where you went wrong.

### Step 0c — Validate the interpretation

Before drafting, read your own inventory and check it against the image again. Two questions:

- **Are there elements you didn't list?** Look at the corners and edges; small KPIs and titles get missed.
- **Is anything ambiguous?** "I see a bar chart with bars of different colors — that could be `color.by: category` on a single grouping, or it could be a stacked bar with one stack." When in doubt, prefer the simpler interpretation and note that you're guessing — don't quietly commit.

### Step 0d — Now proceed with normal discovery

Once you have a validated inventory, run the normal data-discovery flow (see Step 3 of the main workflow). For each element in the inventory, decide which available column maps to the axis or grouping field. If the source data doesn't have a column that matches the image's exactly, **substitute the closest equivalent and note the substitution** — structural fidelity matters more than data fidelity for image-driven cases.

Example: image shows "Gross Margin by Customer Value Tier (Bronze / Silver / Gold / Platinum)" but the available data has no customer tiers. Substitute by a comparable categorical dimension that does exist (e.g., a `customer_segment` column with whatever buckets it has, or a derived bucket from order count). Document this in your final summary.

### Step 0d.1 — Verify each dimension picked is the *right shape*

A common failure: the agent sees "Ship Speed Category" in the target image (four bars labeled Economy / Express / Slow / Standard), grabs the first categorical-looking column in the available data (e.g. `product_brand` with hundreds of values), and ends up with a bar chart that has 200 unreadable rotated labels.

Before drafting, for each dimension you picked, sanity-check two things:

1. **Cardinality.** Count distinct values in the column. If the target image shows 4 bars and your column has 200 distinct values, that's the wrong column — keep looking, or derive a coarser bucketing.
2. **Semantics.** The column's contents should make sense for what the target's label implies. "Ship speed" should be values like Express/Standard/Slow, not product names or SKUs.

A two-line probe in your data-discovery step:

```sql
-- check cardinality
SELECT COUNT(DISTINCT <candidate_column>) FROM <table>;
-- check semantics (sample values)
SELECT DISTINCT <candidate_column> FROM <table> LIMIT 10;
```

If the candidate fails either check, document the gap in your final summary and either (a) substitute a different column that fits better, (b) derive a coarser bucketing via a formula like `If([order_count] >= 10, "Frequent", [order_count] >= 3, "Regular", "Occasional")`, or (c) drop that element from your reproduction if no good substitute exists.

### Step 0d.2 — Verify each metric is the *right calculation*

The other common failure: agent sees "Return Rate by Ship Speed" in the target and builds a bar chart showing 0-100% values for every category because they used `Sum([is_return])` instead of a rate calculation.

Before drafting, for each measure (the y-axis aggregate) you picked:

- **If the target label says "rate" or "%":** the measure is a *ratio*, not a sum. Use `Sum([numerator])/Count(*)` or `Sum([numerator])/Sum([denominator])` — not a raw sum.
- **If the target label says "average":** use `Avg(...)`, not `Sum(...)`.
- **If the target label is a money amount:** confirm the column is the right kind (revenue / margin / cost / price), and format the column with a currency format string.

After creation, the produced chart's y-axis range should look approximately like the target's. A "0-100%" axis when the target shows "0-4%" is a calculation error, not a formatting one.

### Step 0e — Draft and verify

From here, follow the standard workflow (Steps 5–8). One additional verification step before declaring done:

- **Export the workbook to PDF** via `POST /v2/workbooks/{id}/export` with `{"format": {"type": "pdf", "layout": "landscape"}}`, download via `GET /v2/query/{queryId}/download`, then compare the result side-by-side with the target image.
- Diff at the inventory level: do the chart kinds match? Are the axes assigned correctly? Does the layout density match? If not, iterate via PUT before declaring done.

## Things to watch out for

- **The toolbar text in BI tool screenshots is misleading.** A Tableau "marks card" labeled "automatic" or a Looker "visualization type: bar" can ship as anything visually — read the actual visual, not the metadata text.
- **Don't carry source-tool concepts directly.** Tableau "sheets," Looker "looks," PowerBI "visuals" all map onto Sigma's flat `elements[]` list, but they don't translate 1:1. A Tableau dashboard tab is a Sigma `page`; a Tableau sheet is one or more Sigma elements.
- **Title text isn't the data.** A chart titled "Gross Revenue by Ship Speed" tells you what the user wants the chart *labeled*; the data fields are inferred from the visual marks, axes, and the user's other instructions — not from the title.
- **When the data is empty.** If your produced workbook renders "No data" for a panel, the structural interpretation may be right but the data substitution wrong. Re-check: did you pick a column that actually has rows in the selected time range? Did the default filter exclude everything? Fix and re-verify rather than calling it done.

## What this workflow does NOT cover

This page is about *interpreting* an image into spec intent. It does not redefine:

- How to discover data (see `reference/workflows/discover.md`)
- How to write formulas, layouts, or spec shapes (see `reference/specification/*.md`)
- How to validate a spec before submitting (see `reference/workflows/validate.md`)
- How to verify after creating (see `scripts/verify-workbook.sh`)

You still need those — this workflow just sits in front of them.
