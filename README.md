# Sigma Claude Code Skills

Claude Code CLI skills for building and maintaining analytics in Sigma Computing.

The skills split along the surfaces of the Sigma REST API — one for data models, one for workbooks, plus utility skills that orchestrate them. Each skill is a self-contained directory; place this repo (or a symlink to each skill) under `~/.claude/skills/`.

## Skills

| Skill | Purpose |
|-------|---------|
| [`sigma-data-models`](sigma-data-models/) | Author Sigma data models from existing warehouse tables — sources, columns, metrics, relationships, filters, calc columns, CLS. Covers spec shape, discovery, CRUD, validation, and authoring judgment calls. **Out of scope: converting from another BI tool's format** (use the converter MCP / browser tool). |
| [`sigma-workbooks`](sigma-workbooks/) | Build, edit, and iterate on Sigma workbook specs — pages, layout, controls, charts (line/bar/area/combo/donut), KPIs, tables, pivot tables, formulas, sources. Canonical reference for the workbook spec; other skills cross-link here for spec shape. |
| [`custom-sql-to-data-model`](custom-sql-to-data-model/) | Scan Sigma workbooks for custom SQL elements and promote them into proper data models, then repoint the source workbook. |

> **Looking for `tableau-to-sigma` or `tableau-vds-to-snowflake`?** Those skills are still iterating and live in the private [`twells89/sigma-skills-staging`](https://github.com/twells89/sigma-skills-staging) repo. They graduate here once they're stable across multiple real conversions.

## Pick the right skill

| User asks for… | Load |
|---|---|
| "Build me a Sigma data model from the `ORDERS` table in Snowflake" | `sigma-data-models` |
| "Add a metric / relationship / column to my existing data model" | `sigma-data-models` |
| "Convert this dbt / LookML / Tableau / Power BI / Alteryx model to Sigma" | The **converter MCP** or the **browser converter tool** — *not* a skill. The skills cover authoring, not source-format parsing. |
| "Build me a sales dashboard / workbook from this data model" | `sigma-workbooks` |
| "Add a KPI / chart / control to an existing workbook" | `sigma-workbooks` |
| "There's custom SQL in this workbook — promote it to a model" | `custom-sql-to-data-model` |

## Architecture

```
sigma-data-models     ──┐
                        ├── building blocks (load on demand)
sigma-workbooks       ──┘

custom-sql-to-data-model    ─── orchestrator: SQL extraction + DM creation
```

`sigma-data-models` and `sigma-workbooks` are the building blocks meant to be loaded by any Sigma authoring task. `custom-sql-to-data-model` is a higher-level pipeline that depends on them.

## Auth

All skills assume Sigma API credentials are already configured. Set the standard env vars before invoking any skill:

```bash
export SIGMA_BASE_URL="https://api.sigmacomputing.com"
export SIGMA_CLIENT_ID="..."
export SIGMA_CLIENT_SECRET="..."

# Exchange for an access token
SIGMA_API_TOKEN=$(curl -s -X POST "$SIGMA_BASE_URL/v2/auth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$SIGMA_CLIENT_ID&client_secret=$SIGMA_CLIENT_SECRET" \
  | jq -r .access_token)
export SIGMA_API_TOKEN
```

Sigma client credentials are issued from **Administration → Developer Access** in your Sigma org.

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

See individual skill directories for license information.
