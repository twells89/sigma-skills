# Sigma AI Coding-Agent Skills

Skills for building and maintaining analytics in Sigma Computing from any AI coding agent.

The skills split along the surfaces of the Sigma REST API — one for data models, one for workbooks, plus utility skills that orchestrate them. Each skill is a self-contained directory.

**Supported agents** (`generated/` outputs per skill, install via `scripts/install-into-project.sh`):

| Agent | Format | How it loads |
|---|---|---|
| Claude Code | `SKILL.md` (canonical) | Symlink the skill into `~/.claude/skills/` |
| Cortex Code (Snowflake) | `SKILL.md` (same as Claude Code) | Symlink into `~/.snowflake/cortex/skills/` or rely on its `~/.claude/skills/` fallback |
| Codex (OpenAI CLI) | `AGENTS.md` | Drop `generated/codex/AGENTS.md` into project root or `~/.codex/AGENTS.md` |
| Cursor | `.cursor/rules/<name>.mdc` | Drop `generated/cursor/rules/<skill>.mdc` into `<project>/.cursor/rules/` |
| Cline / Roo | `.clinerules/<name>.md` | Drop `generated/cline/<skill>.md` into `<project>/.clinerules/` |
| Continue.dev | `.continue/rules/<name>.md` | Drop `generated/continue/<skill>.md` into `<project>/.continue/rules/` |

See [Installation](#installation) below for the install helper.

## Skills

| Skill | Purpose |
|-------|---------|
| [`sigma-api`](sigma-api/) | Configure Sigma API credentials and mint short-lived bearer tokens with client credentials or interactive browser OAuth. Prerequisite for skills that call the REST API. |
| [`sigma-data-models`](sigma-data-models/) | Author Sigma data models from existing warehouse tables — sources, columns, metrics, relationships, filters, calc columns, CLS. Covers spec shape, discovery, CRUD, validation, and authoring judgment calls. **Out of scope: converting from another BI tool's format** (use the converter MCP / browser tool). |
| [`sigma-workbooks`](sigma-workbooks/) | Build, edit, and iterate on Sigma workbook specs — pages, layout, controls, charts (line/bar/area/combo/donut), KPIs, tables, pivot tables, formulas, sources. Canonical reference for the workbook spec; other skills cross-link here for spec shape. |
| [`sigma-plugin-authoring`](sigma-plugin-authoring/) | Recreate a source viz that has no native Sigma equivalent — a radial gauge, custom heatmap, sankey — as a bespoke `@sigmacomputing/plugin`: build, register, host, embed, bind, verify. Includes a worked gauge example. |
| [`custom-sql-to-data-model`](custom-sql-to-data-model/) | Scan Sigma workbooks for custom SQL elements, dedupe across workbooks, build or reuse data models, then repoint via the v3alpha `:swapSources` endpoint. Handles many workbooks pointing at one shared model. |

> **Looking for `tableau-to-sigma` or `tableau-vds-to-snowflake`?** Those skills are still iterating and live in the private [`twells89/sigma-skills-staging`](https://github.com/twells89/sigma-skills-staging) repo. They graduate here once they're stable across multiple real conversions.

## Pick the right skill

| User asks for… | Load |
|---|---|
| "Authenticate to Sigma / get or refresh an API token" | `sigma-api` |
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

Use the `sigma-api` skill to configure credentials and mint a token. For the
client-credentials flow:

```bash
export SIGMA_BASE_URL="https://api.sigmacomputing.com"
export SIGMA_CLIENT_ID="..."
export SIGMA_CLIENT_SECRET="..."

# Exchange for an access token using HTTP Basic authentication.
eval "$(bash ~/sigma-skills/sigma-api/scripts/get-token.sh)"
```

Sigma client credentials are issued from **Administration → Developer Access** in your Sigma org.

## Installation

### Claude Code & Cortex Code (use SKILL.md directly)

```bash
git clone https://github.com/twells89/sigma-skills.git ~/sigma-skills
mkdir -p ~/.claude/skills
for d in ~/sigma-skills/*/; do
  name=$(basename "$d")
  ln -sf "$d" ~/.claude/skills/"$name"
done
```

Cortex Code reads `~/.claude/skills/` as a fallback, so the same setup works for both. Or symlink into `~/.snowflake/cortex/skills/` explicitly.

### Codex / Cursor / Cline / Continue (use generated files)

Each skill ships pre-built outputs in `generated/`. Use the install helper to drop them into a project (or your user-global config):

```bash
# Project-local install
~/sigma-skills/scripts/install-into-project.sh tableau-to-sigma codex ~/work/myproject
~/sigma-skills/scripts/install-into-project.sh sigma-workbooks   cursor ~/work/myproject
~/sigma-skills/scripts/install-into-project.sh sigma-workbooks   all    ~/work/myproject

# User-global install
~/sigma-skills/scripts/install-into-project.sh sigma-workbooks   codex  --global   # → ~/.codex/AGENTS.md
~/sigma-skills/scripts/install-into-project.sh sigma-workbooks   cursor --global   # → ~/.cursor/rules/
```

The Codex installer appends to an existing `AGENTS.md` rather than overwriting, so you can layer multiple skills.

### Regenerating outputs after a SKILL.md edit

```bash
ruby ~/sigma-skills/scripts/sync-targets.rb ~/sigma-skills/<skill>
```

The rewriter strips Claude-only marker blocks, reveals non-Claude marker blocks, and injects each target's expected frontmatter. Markers in `SKILL.md`:

```markdown
<!-- agents:claude-only -->
This text appears only in the canonical SKILL.md (Claude Code, Cortex Code).
<!-- /agents:claude-only -->

<!-- agents:non-claude
This text appears only in the non-Claude generated outputs (Codex, Cursor, …).
The whole block is one HTML comment, so Claude/Cortex see nothing.
agents:end -->
```

## Updating

These skills are maintained against current Sigma API behavior. When the API evolves and a skill returns a "schema mismatch" error (`unknown field`, `unexpected property`, `invalid argument` on shape), pull the latest:

```bash
cd ~/sigma-skills && git pull
```

Each skill's `SKILL.md` includes a Troubleshooting section that points at the live OpenAPI spec for spot-fixes when the skill is mid-update.

## License

See individual skill directories for license information.
