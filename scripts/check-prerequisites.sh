#!/usr/bin/env bash
# Check sigma-skills runtime prerequisites without installing or changing them.

set -u

profile="${1:-all}"
case "$profile" in
  sigma-api|sigma-workbooks|all) ;;
  *)
    echo "Usage: $0 [sigma-api|sigma-workbooks|all]" >&2
    exit 64
    ;;
esac

missing=()

check_required () {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  [ok]      %s\n' "$tool"
  else
    printf '  [missing] %s\n' "$tool"
    missing+=("$tool")
  fi
}

check_optional () {
  local tool="$1"
  local purpose="$2"
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  [ok]      %s (%s)\n' "$tool" "$purpose"
  else
    printf '  [optional] %s (%s)\n' "$tool" "$purpose"
  fi
}

echo "Required tools for $profile:"
for tool in bash curl jq base64; do
  check_required "$tool"
done

if [[ "$profile" == "sigma-workbooks" || "$profile" == "all" ]]; then
  check_required ruby
  if command -v yq >/dev/null 2>&1; then
    printf '  [ok]      yq (YAML parsing)\n'
  elif command -v python3 >/dev/null 2>&1 &&
       python3 -c 'import yaml' >/dev/null 2>&1; then
    printf '  [ok]      python3 + PyYAML (YAML parsing)\n'
  else
    printf '  [missing] yq or python3 + PyYAML (YAML parsing)\n'
    missing+=("yq")
  fi
fi

echo
echo "Optional interactive-browser-login tools:"
check_optional python3 "loopback callback listener"
check_optional openssl "PKCE and secure random generation"
if command -v security >/dev/null 2>&1; then
  printf '  [ok]      security (macOS refresh-token storage)\n'
elif command -v secret-tool >/dev/null 2>&1; then
  printf '  [ok]      secret-tool (Linux refresh-token storage)\n'
else
  printf '  [optional] security or secret-tool (refresh-token storage)\n'
fi

if [[ "${#missing[@]}" -eq 0 ]]; then
  echo
  echo "Ready: all required tools are available."
  exit 0
fi

echo
echo "Missing required tools: ${missing[*]}"
case "$(uname -s)" in
  Darwin)
    echo "Install with Homebrew, for example: brew install jq yq ruby"
    ;;
  Linux)
    echo "Debian/Ubuntu example: sudo apt install jq ruby-full"
    echo "Install Go yq from https://github.com/mikefarah/yq/releases"
    ;;
  *)
    echo "Use your platform package manager; Windows users should use WSL."
    ;;
esac
exit 1
