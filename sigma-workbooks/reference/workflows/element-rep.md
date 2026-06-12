# Element-Level Workbook Rep (`scripts/wb-rep.rb`)

The Sigma spec API is whole-workbook only: GET and PUT move the entire spec. On a
5-page, 40-element workbook that means every small edit drags the full document
through your context, and parallel work on two elements is a merge hazard. The
**rep** fixes this by making the *element* the unit of work: the spec is exploded
into a directory of small YAML files, edited with ordinary file tools, and
reassembled on push.

Load this file when: a workbook has grown past ~1 page / ~10 elements, multiple
elements need editing in one session, you want to parallelize element work across
sub-agents, or the user wants workbook changes reviewable as diffs.

## Layout

```
<rep>/
  workbook.yaml              top-level fields (name, folderId, schemaVersion, description)
  pages/
    010-overview/            numeric prefix = page order (×10 so you can insert between)
      _page.yaml             page id / name / visibility — everything except elements
      _layout.xml            this page's <Page> block of the layout XML (omit = auto-arrange)
      010-revenue-kpi.yaml   one element per file; prefix = element order, rest is a slug
      020-sales-by-region.yaml
  renders/                   PNGs written by `render`
  .sigma/                    plumbing — never hand-edit
    manifest.yaml            workbookId, url, pulledAt/pushedAt
    snapshot.yaml            the full spec as last synced with the server
    layout-preamble.xml      XML prolog preserved for byte-exact reassembly
```

Nothing is a new format: every file is a verbatim slice of the spec, so all the
per-element reference files in this skill (charts.md, kpis.md, tables.md, …)
apply unchanged to a single element file.

## Commands

All commands need `SIGMA_BASE_URL` / `SIGMA_API_TOKEN` (sigma-api skill) except
`status` and `assemble`, which are offline.

```bash
# Tip: with admin credentials, GET /v2/workbooks?skipPermissionCheck=true lists workbooks
# beyond your grants (same flag as /v2/dataModels) — useful for finding a workbook id to pull.
scripts/wb-rep.rb summarize <id|dir>           # zoom level 0: pages, element kinds, sources — no spec in context
scripts/wb-rep.rb pull <workbook-id> <dir>     # GET + explode (refuses to clobber local edits; --force to discard)
scripts/wb-rep.rb status <dir>                 # element-level diff: files vs last-synced snapshot
scripts/wb-rep.rb push <dir>                   # reassemble → remote-drift check → validate-spec.sh → PUT → readback
scripts/wb-rep.rb render <dir>                 # export every page as PNG into <dir>/renders/ — then LOOK at them
scripts/wb-rep.rb render <dir> --page Overview # one page (id, name, or slug); --element <id> for one element
scripts/wb-rep.rb import <spec.yaml> <dir>     # explode a local spec; push will POST a new workbook (create mode)
scripts/wb-rep.rb assemble <dir> -o out.yaml   # reassembled spec without pushing (debugging)
scripts/wb-rep.rb capabilities                 # every authorable kind, distilled live from the OpenAPI
scripts/wb-rep.rb capabilities --kind bar-chart [--field color]   # fields of a kind / schema of one field
```

The read side is a zoom: `summarize` (whole workbook, one screen) → `ls pages/<page>/`
(one page, file listing) → `Read <element>.yaml` (one element, full detail) →
`capabilities --kind <kind> [--field <f>]` (what's authorable there). No step loads the
whole spec into context.

Safety built into `push`:

1. **Drift check** — if the server spec changed since your pull (someone edited in
   the UI), push aborts and shows exactly what you'd overwrite. Re-pull and
   re-apply, or `--force`.
2. **Diff preview** — prints the added/removed/changed elements it is about to push.
3. **Validation** — runs `validate-spec.sh` on the assembled spec; aborts on issues
   (`--no-validate` to override a false positive).
4. **Layout lint** — warns about elements not referenced in their page's `_layout.xml`.
5. **Readback** — refreshes the snapshot from the server and reports any fields the
   server normalized.

`push` is still a full-spec PUT under the hood (the API has no element PATCH), but
you never see that: the rep gives you element-level GET/POST/PATCH semantics at
the file layer.

## The build loop: Plan → Build → See

**Plan.** Decide pages and elements first (use `workflows/composition.md`). Express
the plan as the file tree itself: create page dirs and *stub* element files (id,
kind, name, source — no styling). The tree is the plan document.

**Build — fan out sub-agents, one per element file.** Element files are
independent, so parallel sub-agents cannot conflict: give each agent one file
path, the relevant reference file (e.g. `charts.md` for a bar chart), the source
element/column list it may reference, and the formula rules. No agent ever needs
the whole workbook in context. The orchestrator keeps only the plan and the
shared facts (source names, column lists, palette).

Things that span elements stay with the orchestrator: `_layout.xml`, control
targets, cross-element `[Element Name/Column]` refs, and the id namespace
(hand out unique element/column ids in the plan so agents never collide).

**Push, verify, see.**

```bash
scripts/wb-rep.rb push <dir>
scripts/verify-workbook.sh <workbook-id>    # compile check — formulas resolve?
scripts/wb-rep.rb render <dir>              # then Read the PNGs
```

Look at every render. Compare against the plan (or the user's target image —
see `workflows/from-image.md`): wrong chart type, unreadable axis, dead space,
truncated labels, default-blue-everything. Fix the specific element files and
repeat. Stop when a render passes inspection, not when the API returns 200 —
a clean POST proves the spec parsed, only the pixels prove the dashboard is good.

## Editing rules

- **Order = filename prefix.** Reorder elements/pages by renaming. New element
  between `010-` and `020-` → name it `015-`. Slugs after the prefix are cosmetic.
- **Add an element** = add a file (unique `id` inside) + reference it in
  `_layout.xml`. **Delete** = delete the file + its layout reference.
- **IDs are stable.** The server preserves element/column ids on PUT and CREATE,
  so file identity survives round-trips. Never reuse a deleted element's id.
- Cross-element formula refs use the *element name*: renaming an element breaks
  `[Old Name/Column]` refs in other files — grep the rep before renaming.
- `_layout.xml` holds exactly one `<Page …>…</Page>` block whose `id` matches
  `_page.yaml`. A page with no `_layout.xml` auto-arranges (fine for single-element
  pages only — see `specification/layout.md`).
- `.sigma/` is plumbing. To resync files from the server: `pull <id> <dir> --force`.

## Git

A rep directory is designed to be committed: one element per file means PRs show
"changed: revenue-kpi.yaml" instead of a 2,000-line spec diff. Commit the rep
including `.sigma/snapshot.yaml` (it's the merge base); add `renders/` to
`.gitignore` if PNG churn is unwanted.
