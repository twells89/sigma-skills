# Generate an operational Sigma app

Use this workflow when the user asks to generate, build, or scaffold a Sigma
**app** — a planning model, approval queue, allocation grid, exception command
center, or an unspecified “app” — and they did **not** supply a target image.

The general spec workflow ([the rest of SKILL.md](../../SKILL.md)) still
applies. This document covers **only the intake steps** that come *before*
discovery and spec drafting: classify the app type, ask the structural
questions the matching recipe requires, record a local intake manifest, and
clone a best-practice fixture.

If the user supplied a screenshot, mockup, PDF, or design artifact, stop and
load `from-image.md` instead. Image-driven reproduction is a different path.

## Why this workflow exists

The four operational recipes (`planning-apps.md`, `allocation-apps.md`,
`approval-apps.md`, `exception-apps.md`) already define grain, writeback
architecture, and runtime gates. Without a single entry point, agents infer
the type from keywords, skip grain questions, and draft from memory. The
common bad first pass is a dashboard with an empty input table that is not
linked to a governed source, or a “planning app” whose scenarios share one
editable grid.

This workflow makes classification, grain, and the starting spec explicit.

Do **not** invent a fifth operational type. Apps are still workbooks
(`POST /v2/workbooks/spec`). Architecture details live in the matching recipe,
not here.

## Workflow

### Step A — Classify (one question, forced choice)

Ask what users should **do** in the workbook. Offer the four documented
types plus two redirects. Do not ask an open-ended “what kind of app?”

| User intent | Route |
|---|---|
| Edit forecasts, scenarios, budgets, assumptions | `planning-apps.md` + `fixtures/planning-app.yaml` |
| Redistribute budget / quota / headcount / capacity across a dimension | `allocation-apps.md` + `fixtures/allocation-app.yaml` |
| Approve, reject, or counter existing records | `approval-apps.md` + `fixtures/approval-app.yaml` |
| Triage exceptions, apply overrides, log resolution | `exception-apps.md` + `fixtures/exception-app.yaml` |
| Read-only dashboard / KPI overview | stop; use `composition.md` |
| Pixel-perfect invoice / statement / PDF | stop; use the `sigma-reports` skill |

A classifier helper can suggest a type from the user's prose; still confirm
it before continuing:

```bash
ruby -r ./scripts/lib/app_intake.rb -e 'p AppIntake.classify(ARGV[0])' \
  "approve or reject pending deals"
```

If the ask is mixed (for example, “planning *and* approvals”), follow the
`from-image.md` boundary rule: **one workbook per app surface**. Confirm the
split, then run this intake twice.

### Step B — Type-specific questions

Keep these few and structural. Do not expand into an open-ended UX interview.
Load the matching recipe after classification so the answers map onto its
grain and gates.

**Every operational type** — the five input-table facts from
`../specification/input-tables.md`:

1. desired row grain and expected row count;
2. whether rows already exist in a governed source;
3. whether users edit whole rows or sparse override columns;
4. one-time file load versus ongoing interactive entry;
5. whether UI loading or warehouse loading is acceptable.

Then the type-specific set:

**Planning** (`planning-apps.md`)

- Which mode: one working plan / scenario planning / variance-only / parity?
- Confirm grain: `Scenario × Period × Planning Line` (or the named columns).
- Filter propagation: Option A (complete grid, formula-scoped analytics) or
  Option B (filtered grid, independent all-scenario read path)?

**Allocation** (`allocation-apps.md`)

- Period column and allocation dimension (Department, Team, Region, …)?
- Extra grain (Role, Product, Channel) only if uniqueness is proven?

**Approval** (`approval-apps.md`)

- Stable entity key column (Deal ID, Request ID, …)?
- Allowed decisions (Approve / Reject / Counter, …)?
- Counter-value column, or status-only?

**Exception** (`exception-apps.md`)

- Stable operational key (SKU, Account ID, Job ID, …)?
- One exception per entity, or a composite key (Exception Type / Observation Date)?
- User override, or recommendation-only?

Do **not** proceed to spec draft until classification, grain keys, and a
write-enabled connection are answered — or the user explicitly says to use
the fixture defaults.

### Step C — Record a local intake manifest

Write the answers outside the skill tree before drafting. Conventional path
is `/tmp/app-intake.json`.

```bash
ruby scripts/lib/app_intake.rb init /tmp/app-intake.json planning
# fill answers, sources, grain.expectedRows from Step B
ruby scripts/lib/app_intake.rb validate /tmp/app-intake.json
```

`init` refuses to overwrite. Allowed `appType` values are `planning`,
`allocation`, `approval`, and `exception`. The helper checks that `recipe`
and `fixture` match the type, that `grain.keys` includes the required keys
for that type, and that the fixture file exists on disk.

Use `--strict` only when sources are bound (write connection, source
connection, table path, expected row count):

```bash
ruby scripts/lib/app_intake.rb validate --strict /tmp/app-intake.json
```

The manifest is local run state. Do not commit customer table paths,
connection IDs, folder IDs, or workbook IDs into this skill.

### Step D — Clone the fixture, then the normal build loop

1. Copy the fixture named in the manifest (under
   `reference/workflows/fixtures/`) to a working spec, e.g.
   `/tmp/workbook-spec.yaml`.
2. Load `discover.md`. Replace placeholders (`<FOLDER_ID>`,
   `<WRITE_CONNECTION_ID>`, `<SOURCE_CONNECTION_ID>`,
   `[Source/…]` column names) with values the API actually returned.
   **Never invent column names.**
3. Load the matching recipe and `../specification/input-tables.md`. Adjust
   grain columns and formulas to the answers; do not skip the recipe's
   non-negotiable layers. Keep the fixture's `tableElementId` on
   `insert-rows` / `update-rows` / `delete-rows` (live OpenAPI). A stale
   `table:` key fails every element oneOf and Sigma reports the masked
   `Invalid kind: "button"`.
4. Continue from SKILL.md Step 5: validate (`./scripts/validate-spec.sh`),
   POST, `./scripts/verify-workbook.sh`, then the recipe's runtime gates in
   `runtime-verification.md`.

Published data entry cannot be set from the spec. Before handoff, for every
input table: element kebab → Set data entry permission → Only in published
version. The setting is absent from `GET /spec`.

## Fixtures

The four files in `fixtures/` are architecture templates, not live org dumps.
Each encodes the layers its recipe requires. Shared rules are in
`fixtures/README.md`. Copy shapes from the matching fixture; do not assemble
an operational app from `example-full.yaml` (that file is an analytical
dashboard).

| Type | Fixture | Required layers |
|---|---|---|
| planning | `fixtures/planning-app.yaml` | governed baseline, empty scenario directory, cross-join matrix, linked plan grid, append-only decision log, submit button |
| allocation | `fixtures/allocation-app.yaml` | period × dimension baseline, linked allocation grid, working allocation + variance, request log |
| approval | `fixtures/approval-app.yaml` | governed entity directory, linked review queue, computed impact, append-only audit log, `whichRows` on the stable entity key |
| exception | `fixtures/exception-app.yaml` | exception directory, linked action queue, deterministic recommendation (not labeled “AI”), override coalesced into final action, resolution log |

## Out of scope here

- Recipe grain, override math, financial sign, and runtime-gate tables —
  those stay in the four `*-apps.md` files.
- Image-driven reproduction — `from-image.md`.
- Read-only dashboards — `composition.md`.
- Printable documents — `sigma-reports`.
