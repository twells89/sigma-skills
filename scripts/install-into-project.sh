#!/usr/bin/env bash
# install-into-project.sh — drop a skill's generated agent files into a target project (or user-global config).
#
# Usage:
#   install-into-project.sh <skill-name> <target> [<dest-dir>]
#
#   <skill-name>   sigma-api | sigma-data-models | sigma-workbooks
#                  | sigma-reports | sigma-plugin-authoring
#                  | custom-sql-to-data-model
#   <target>       codex | cursor | cline | continue | cortex | all
#   <dest-dir>     project directory (default: $PWD)
#                  pass --global to install into user-global config paths instead.
#
# Examples:
#   install-into-project.sh sigma-api cursor ~/work/myproject
#   install-into-project.sh sigma-workbooks all ~/work/myproject
#   install-into-project.sh sigma-reports all ~/work/myproject
#   install-into-project.sh sigma-workbooks codex --global   # → ~/.codex/AGENTS.md (concat)
#
# Cortex Code reads Claude's SKILL.md format natively — for `cortex`, this
# script copies the canonical skill and its runtime into
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

runtime_root () {
  local target_dir="$1"
  if [[ "$target_dir" == "--global" ]]; then
    printf '%s\n' "$HOME/.sigma-skills"
  else
    printf '%s\n' "$target_dir/.sigma-skills"
  fi
}

copy_runtime_skill () {
  local source_dir="$1"
  local name="$2"
  local root="$3"
  local target_dir="$root/$name"
  mkdir -p "$target_dir"
  for entry in SKILL.md scripts reference refs docs examples plugins; do
    if [[ -e "$source_dir/$entry" ]]; then
      cp -R "$source_dir/$entry" "$target_dir/"
    fi
  done
}

install_runtime () {
  local root="$1"
  copy_runtime_skill "$skill_dir" "$skill" "$root"
  if [[ "$skill" != "sigma-api" && -d "$REPO_ROOT/sigma-api" ]]; then
    copy_runtime_skill "$REPO_ROOT/sigma-api" "sigma-api" "$root"
  fi
  cp "$REPO_ROOT/scripts/check-prerequisites.sh" "$root/check-prerequisites.sh"
  echo "wrote runtime companion $root/$skill/"
}

install_codex () {
  local target_dir="$1"
  if [[ "$target_dir" == "--global" ]]; then
    target_dir="$HOME/.codex"
  fi
  mkdir -p "$target_dir"
  local src="$gen/codex/AGENTS.md"
  local dst="$target_dir/AGENTS.md"
  local begin="<!-- BEGIN sigma-skills:$skill -->"
  local end="<!-- END sigma-skills:$skill -->"
  local prior
  prior="$(mktemp)"
  if [[ -f "$dst" ]]; then
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { managed = 1; next }
      $0 == end { managed = 0; next }
      !managed { print }
    ' "$dst" > "$prior"
  fi
  {
    if [[ -s "$prior" ]]; then
      cat "$prior"
      echo
    fi
    echo "$begin"
    cat "$src"
    echo "$end"
  } > "$dst"
  rm -f "$prior"
  echo "wrote managed $skill section to $dst"
}

install_cursor () {
  local target_dir="$1"
  if [[ "$target_dir" == "--global" ]]; then
    target_dir="$HOME"
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
    target_dir="$HOME"
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
  codex)
    install_runtime "$(runtime_root "$dest")"
    install_codex "$dest"
    ;;
  cursor)
    install_runtime "$(runtime_root "$dest")"
    install_cursor "$dest"
    ;;
  cline)
    install_runtime "$(runtime_root "$dest")"
    install_cline "$dest"
    ;;
  continue)
    install_runtime "$(runtime_root "$dest")"
    install_continue "$dest"
    ;;
  cortex)   install_cortex   "$dest" ;;
  all)
    install_runtime "$(runtime_root "$dest")"
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
