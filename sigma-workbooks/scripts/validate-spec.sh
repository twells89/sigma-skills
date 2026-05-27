#!/usr/bin/env bash
# validate-spec.sh — scan a workbook spec for likely formula-qualification errors.
#
# Catches the #1 Sigma spec mistake: a bare bracketed reference (e.g. [Question ID])
# inside a formula when the referenced column actually lives on the source element,
# not the current one, and therefore needs a prefix (e.g. [AI Usage Data/Question ID]).
#
# Accepts YAML (recommended) or JSON input. YAML is detected by the
# .yaml/.yml extension and converted to JSON internally before the jq pass.
#
# Usage: ./validate-spec.sh <path-to-spec.yaml|.json>
# Exit codes:
#   0  — no obvious issues
#   1  — issues found
#   2  — setup / input error
#
# Limitations: regex-based, so it does not parse formulas semantically. It can
# produce false positives on bracketed text inside string literals (e.g.
# DateFormat(..., "[MM] %Y") ) — inspect flagged cases before blindly fixing.
# It does NOT verify that qualified refs ([Source/col]) point to real sources;
# the server reports those.

set -euo pipefail

FILE="${1:-}"
if [ -z "$FILE" ]; then
  echo "Usage: $0 <path-to-spec.yaml|.json>" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: brew install jq (macOS) or apt install jq (Debian/Ubuntu)." >&2
  exit 2
fi

if [ ! -f "$FILE" ]; then
  echo "Error: file not found: $FILE" >&2
  exit 2
fi

# Convert YAML → JSON in memory if the file looks like YAML.
#
# Earlier versions trusted yq's exit code as proof of JSON output, which broke
# against Go yq (mikefarah, Homebrew default on macOS): `yq . file.yaml` exits 0
# but emits YAML, not JSON, so the downstream jq call failed with
# "Invalid literal at line 1, column 5". Fix: try Go yq's explicit -o=json first,
# fall back to Python yq's bare `.`, and validate each candidate with `jq empty`
# before accepting it — the success criterion is now "output parses as JSON",
# not "yq exited 0".
to_json() {
  case "$FILE" in
    *.yaml|*.yml)
      if command -v yq >/dev/null 2>&1; then
        # Go yq (mikefarah) — explicit JSON output flag, unambiguous.
        out=$(yq -o=json . "$FILE" 2>/dev/null) \
          && printf '%s' "$out" | jq empty >/dev/null 2>&1 \
          && { printf '%s' "$out"; return 0; }
        # Python yq (kislyuk) — bare `.` already emits JSON.
        out=$(yq . "$FILE" 2>/dev/null) \
          && printf '%s' "$out" | jq empty >/dev/null 2>&1 \
          && { printf '%s' "$out"; return 0; }
      fi
      if command -v python3 >/dev/null 2>&1; then
        python3 - "$FILE" <<'PY' 2>/dev/null && return 0
import sys, json
try:
    import yaml
except ImportError:
    sys.exit(2)
with open(sys.argv[1]) as f:
    print(json.dumps(yaml.safe_load(f)))
PY
      fi
      echo "Error: cannot convert YAML to JSON. Install one of:" >&2
      echo "  - Go yq:        brew install yq                (recommended on macOS)" >&2
      echo "  - Python yq:    pip install yq" >&2
      echo "  - PyYAML:       pip install PyYAML            (python3 + import yaml)" >&2
      exit 2
      ;;
    *)
      cat "$FILE"
      ;;
  esac
}

SPEC_JSON="$(to_json)"

ISSUES=$(printf '%s' "$SPEC_JSON" | jq -r '
  .pages[]? | .elements[]? |
    . as $element |
    (.columns // []) as $cols |
    ($cols | map(.name // "")) as $siblings |
    $cols[]? |
    . as $col |
    ($col.formula // "") as $formula |
    ( [ $formula | scan("\\[[^/\\]]+\\]") | .[1:-1] ] ) as $bare_refs |
    ( $bare_refs | map(select(. as $ref | $siblings | index($ref) | not)) ) as $unresolved |
    select($unresolved | length > 0) |
    "Element: \($element.name // $element.id // "(unnamed)")\n  Column: \($col.name // $col.id // "(unnamed)")\n  Formula: \($formula)\n  Unresolved bare refs: \($unresolved | join(", "))\n"
')

if [ -z "$ISSUES" ]; then
  echo "OK: no obvious formula qualification errors."
  echo ""
  echo "Note: this validator only catches bare bracketed refs ([col] without a '/') that"
  echo "don't match a sibling column in the same element. Qualified refs ([Source/col])"
  echo "are not verified here — the server checks those on publish."
  exit 0
fi

echo "Likely formula qualification errors:"
echo ""
echo "$ISSUES"
echo "Fix: a bare bracketed ref ([col] with no '/') must match a column 'name' defined"
echo "in the SAME element's columns[] array. Otherwise add the source prefix."
echo ""
echo "  Wrong:  Count([Question ID])"
echo "  Right:  Count([AI Usage Data/Question ID])       (source element name as prefix)"
exit 1
