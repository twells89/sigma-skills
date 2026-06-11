# Composition: making the design choice

A workbook spec that compiles cleanly and has correct data can still be unusable. Layout, element choice, label clarity, whether to add a comparison vs current state — these are design decisions, not API ones. **This skill has no opinions about what makes a good dashboard.** It asks you to ask.

## Calibrate scope to the request

Build the simplest workbook that fully answers the request. Let the ask set the complexity — not a template, and not a sense of what a dashboard "should" have. Both directions fail: a bare table dumped on a page when the user wanted a dashboard, and an unrequested multi-page layout with joins and a KPI row when the user asked for one number.

A rough sizing ladder (starting points, not rules):

- **A single thing** — "show total revenue", "a table of orders", "one KPI" → one element. Skip explicit layout XML; auto-arrange is fine for a single element or a uniform stack of tables.
- **A focused view** — "revenue over time with a region filter" → a few elements plus a control; light layout.
- **A dashboard** — "a sales dashboard", "an exec overview" → the fuller pattern is appropriate: a KPI row up top, one or two charts, a supporting table, controls, explicit layout XML, and the base/source table on a hidden page (see Defaults below). This is the tier where polish is the point.

For concrete shapes at any tier, don't assemble from memory. Fetch a real workbook's spec (`GET /v2/workbooks/{id}/spec`, Steps 1–2) and read the relevant feature docs — a live spec shows current, valid, org-idiomatic structure, including the layout XML the OpenAPI doesn't model. Size up only when the request asks for it.

## When to stop and ask the user

Defer to the user any time the prompt admits more than one reasonable interpretation. Signals:

- **Open-ended request.** "Build me a sales dashboard" leaves dozens of decisions unmade — audience, time scope, level of detail, what decision the dashboard should support.
- **The data could be sliced multiple ways.** If revenue can be broken out by region OR product OR month OR channel and the prompt doesn't specify, pick the most-obvious one *and* surface that choice (see below) — but for a real ambiguity, just ask.
- **Page-shape ambiguity.** Single page or multi-page? Executive summary vs. operator detail? Don't guess if the answer changes the entire workbook.
- **You're about to make a structural decision the user can't easily revert.** Reordering elements is easy; deciding "this needs three pages" and threading sources across them is harder to undo.

When you do ask, keep it specific. "What would you like the dashboard to look like?" is useless. Better:

- *"Is this for an executive briefing or operator detail? Affects whether I use KPIs at top or a ranked detail table."*
- *"Should this support a weekly meeting (current-state snapshot) or an investigation (drillable detail)?"*
- *"What decision should the viewer be able to make after looking at this?"*

## Surface your decisions in the final summary

Agents quietly choose: how many KPIs, which chart kinds, multi-page vs single, what to group on, what to sort by. The user can't see those choices from the rendered workbook alone. Always include a one-paragraph summary at the end of the run listing the structural choices you made and inviting redirection.

Example: *"Built a single-page dashboard with 4 KPIs across the top, a revenue-by-region bar chart, and a ranked store table sorted descending by revenue. Used Sales Amount over Net Orders for the headline metric. Tell me if you want any of these changed — different KPI mix, multi-page split, a different sort, etc."*

## Defaults to fall back on when not asking

These are *defaults, not rules.* The skill doesn't claim they're right for every dashboard; they're starting points when the user's preference isn't known and stopping to ask isn't appropriate.

- **Source/base tables go on a hidden page.** When a workbook needs a base table (warehouse-table or join source) to feed charts, KPIs, and grouped views, that base table doesn't belong in the dashboard view. Put it on a separate page with `visibility: hidden` (see `reference/specification/schema.md`) and source dashboard elements from it via `elementId`. The base table stays available to the workbook without dropping a million-row dump on the viewer.
- **Sort ranked tables by the metric the user is ranking on.** "Bottom 10 stores by revenue" implies ascending by revenue; "top products" implies descending. Sorting alphabetically by name is rarely what a meeting attendee wants.
- **Don't expose intermediate joins as visible elements.** Same rationale as the base-table rule — they're plumbing, not deliverables.

## Image-driven cases have their own composition guide

When the user provides a target screenshot or mockup, the design space is much narrower — the goal is structural fidelity to the image. See `reference/workflows/from-image.md` for the observation-first workflow that applies in that case.
