# Sigma Claude Code Skills

Claude Code CLI skills for building, migrating, and maintaining analytics in Sigma Computing.

The skills split along the surfaces of the Sigma REST API — one for data models, one for workbooks, plus migration / utility skills that orchestrate them. Each skill is a self-contained directory; place this repo (or a symlink to each skill) under `~/.claude/skills/`.

## Skills

| Skill | Purpose |
|-------|---------|
| [`sigma-data-models`](sigma-data-models/) | Author Sigma data models from existing warehouse tables — sources, columns, metrics, relationships, filters, calc columns, CLS. Covers spec shape, discovery, CRUD, validation, and authoring judgment calls. **Out of scope: converting from another BI tool's format** (use the converter MCP / browser tool). |
| [`sigma-workbooks`](sigma-workbooks/) | Build, edit, and iterate on Sigma workbook specs — pages, layout, controls, charts (line/bar/area/combo/donut), KPIs, tables, pivot tables, formulas, sources. Canonical reference for the workbook spec; other skills cross-link here for spec shape. |
| [`tableau-to-sigma`](tableau-to-sigma/) | Convert a Tableau datasource or workbook into a Sigma data model + matching dashboard. Orchestrates column discovery, data model creation via REST API, Ruby-generated layout XML, and Phase-5 workbook repointing. Defers to `sigma-workbooks` for canonical workbook spec shape. |
| [`custom-sql-to-data-model`](custom-sql-to-data-model/) | Scan Sigma workbooks for custom SQL elements and promote them into proper data models, then repoint the source workbook. |
| [`tableau-vds-to-snowflake`](tableau-vds-to-snowflake/) | Convert a Tableau `.tds` / VDS source into a Snowflake-compatible data model definition. |

## Pick the right skill

| User asks for… | Load |
|---|---|
| "Build me a Sigma data model from the `ORDERS` table in Snowflake" | `sigma-data-models` |
| "Add a metric / relationship / column to my existing data model" | `sigma-data-models` |
| "Convert this dbt / LookML / Tableau / Power BI / Alteryx model to Sigma" | The **converter MCP** or the **browser converter tool** — *not* a skill. The skills cover authoring, not source-format parsing. |
| "Build me a sales dashboard / workbook from this data model" | `sigma-workbooks` |
| "Add a KPI / chart / control to an existing workbook" | `sigma-workbooks` |
| "I have a Tableau workbook (`.twb` / `.twbx`) — recreate it in Sigma" | `tableau-to-sigma` (which loads `sigma-data-models` and `sigma-workbooks` as needed) |
| "There's custom SQL in this workbook — promote it to a model" | `custom-sql-to-data-model` |

## Architecture

```
sigma-data-models     ──┐
                        ├── building blocks (load on demand)
sigma-workbooks       ──┘

tableau-to-sigma            ─── orchestrator: full Tableau pipeline
custom-sql-to-data-model    ─── orchestrator: SQL extraction + DM creation
tableau-vds-to-snowflake    ─── narrow utility
```

The two "building block" skills (`sigma-data-models` and `sigma-workbooks`) are meant to be loaded by any Sigma authoring task. The orchestrators are higher-level pipelines that depend on them.

## Auth

All skills assume Sigma API credentials are already configured. The standard pattern (used by `tableau-to-sigma`):

```bash
source ~/.sigma-env
eval "$(<repo>/tableau-to-sigma/scripts/get-token.sh)"
# Now $SIGMA_API_TOKEN and $SIGMA_BASE_URL are set for any subsequent curl call.
```

Required env vars: `SIGMA_BASE_URL`, `SIGMA_CLIENT_ID`, `SIGMA_CLIENT_SECRET`. Run `tableau-to-sigma/scripts/setup.rb` to populate them interactively the first time.

## Installation

These are Claude Code skills. Two ways to use them:

### Option A — Symlink each skill

```bash
git clone https://github.com/twells89/sigma-skills.git ~/sigma-skills
mkdir -p ~/.claude/skills
for d in ~/sigma-skills/*/; do
  name=$(basename "$d")
  ln -sf "$d" ~/.claude/skills/"$name"
done
```

### Option B — Drop the whole repo as a plugin

Place this repo under `.claude/plugins/` or reference it via the `sigma-computing` plugin marketplace.

## Updating

These skills are maintained against current Sigma API behavior. When the API evolves and a skill returns a "schema mismatch" error (`unknown field`, `unexpected property`, `invalid argument` on shape), pull the latest:

```bash
cd ~/sigma-skills && git pull
```

Each skill's `SKILL.md` includes a Troubleshooting section that points at the live OpenAPI spec for spot-fixes when the skill is mid-update.

## License

See individual skill directories for license information. The `tableau-to-sigma` skill is dual-purposed for both internal Sigma demos and external customer migrations — review its `SKILL.md` before redistributing.
