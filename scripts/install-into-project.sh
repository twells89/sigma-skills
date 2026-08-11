#!/usr/bin/env bash
# install-into-project.sh — drop a skill's generated agent files into a target project (or user-global config).
#
# Usage:
#   install-into-project.sh <skill-name> <target> [<dest-dir>]
#
#   <skill-name>   sigma-workbooks | sigma-reports | sigma-data-models
#                  | custom-sql-to-data-model
#                  | tableau-to-sigma | tableau-vds-to-snowflake
#   <target>       codex | cursor | cline | continue | cortex | all
#   <dest-dir>     project directory (default: $PWD)
#                  pass --global to install into user-global config paths instead.
#
# Examples:
#   install-into-project.sh tableau-to-sigma codex ~/work/myproject
#   install-into-project.sh sigma-workbooks all ~/work/myproject
#   install-into-project.sh sigma-reports all ~/work/myproject
#   install-into-project.sh sigma-workbooks codex --global   # → ~/.codex/AGENTS.md (concat)
#
# Cortex Code reads Claude's SKILL.md format natively — for `cortex`, this
# script symlinks the canonical SKILL.md (and its refs/) into
# ~/.snowflake/cortex/skills/<skill-name>/ when --global is used.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGING_ROOT="$HOME/sigma-skills-staging"

skill="${1:-}"
target="${2:-}"
dest="${3:-$PWD}"

if [[ -z "$skill" || -z "$target" ]]; then
  sed -n '2,/^$/p' "$0" >&2
  exit 64
fi

# Resolve skill dir (graduated repo first, then staging).
if [[ -d "$REPO_ROOT/$skill" ]]; then
  skill_dir="$REPO_ROOT/$skill"
elif [[ -d "$STAGING_ROOT/$skill" ]]; then
  skill_dir="$STAGING_ROOT/$skill"
else
  echo "skill '$skill' not found in $REPO_ROOT or $STAGING_ROOT" >&2
  exit 65
fi

gen="$skill_dir/generated"

install_codex () {
  local target_dir="$1"
  if [[ "$target_dir" == "--global" ]]; then
    target_dir="$HOME/.codex"
    mkdir -p "$target_dir"
  fi
  local src="$gen/codex/AGENTS.md"
  local dst="$target_dir/AGENTS.md"
  if [[ -f "$dst" ]]; then
    echo "appending $skill section to $dst"
    {
      echo
      echo "<!-- ===== $skill (from sigma-skills) ===== -->"
      cat "$src"
    } >> "$dst"
  else
    cp "$src" "$dst"
    echo "wrote $dst"
  fi
}

install_cursor () {
  local target_dir="$1"
  if [[ "$target_dir" == "--global" ]]; then
    target_dir="$HOME/.cursor"
  fi
  mkdir -p "$target_dir/.cursor/rules"
  local src="$gen/cursor/rules/$skill.mdc"
  local dst="$target_dir/.cursor/rules/$skill.mdc"
  cp "$src" "$dst"
  echo "wrote $dst"
}

install_cline () {
  local target_dir="$1"
  if [[ "$target_dir" == "--global" ]]; then
    echo "cline has no documented user-global location; install per-project" >&2
    exit 66
  fi
  mkdir -p "$target_dir/.clinerules"
  local src="$gen/cline/$skill.md"
  local dst="$target_dir/.clinerules/$skill.md"
  cp "$src" "$dst"
  echo "wrote $dst"
}

install_continue () {
  local target_dir="$1"
  if [[ "$target_dir" == "--global" ]]; then
    target_dir="$HOME/.continue"
  fi
  mkdir -p "$target_dir/.continue/rules"
  local src="$gen/continue/$skill.md"
  local dst="$target_dir/.continue/rules/$skill.md"
  cp "$src" "$dst"
  echo "wrote $dst"
}

install_cortex () {
  local target_dir="$1"
  if [[ "$target_dir" == "--global" ]]; then
    target_dir="$HOME/.snowflake/cortex/skills/$skill"
  else
    target_dir="$target_dir/.cortex/skills/$skill"
  fi
  mkdir -p "$target_dir"
  # Cortex reads the canonical Claude SKILL.md format unchanged.
  cp "$skill_dir/SKILL.md" "$target_dir/SKILL.md"
  if [[ -d "$skill_dir/refs" ]];      then cp -R "$skill_dir/refs"      "$target_dir/"; fi
  if [[ -d "$skill_dir/reference" ]]; then cp -R "$skill_dir/reference" "$target_dir/"; fi
  if [[ -d "$skill_dir/scripts" ]];   then cp -R "$skill_dir/scripts"   "$target_dir/"; fi
  echo "wrote $target_dir/ (canonical SKILL.md + refs/scripts)"
}

case "$target" in
  codex)    install_codex    "$dest" ;;
  cursor)   install_cursor   "$dest" ;;
  cline)    install_cline    "$dest" ;;
  continue) install_continue "$dest" ;;
  cortex)   install_cortex   "$dest" ;;
  all)
    install_codex    "$dest"
    install_cursor   "$dest"
    install_cline    "$dest"
    install_continue "$dest"
    install_cortex   "$dest"
    ;;
  *)
    echo "unknown target '$target'" >&2
    exit 64
    ;;
esac
