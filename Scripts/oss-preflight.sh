#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  printf 'Open-source preflight requires complete Git history (fetch-depth: 0).\n' >&2
  exit 1
fi

history_contains_extended() {
  local pattern="$1"
  local revision
  while IFS= read -r revision; do
    if git grep -l -I -E "$pattern" "$revision" -- .; then
      return 0
    fi
  done < <(git rev-list --all)
  return 1
}

history_contains_fixed() {
  local needle="$1"
  local revision
  while IFS= read -r revision; do
    if git grep -l -I -F "$needle" "$revision" -- .; then
      return 0
    fi
  done < <(git rev-list --all)
  return 1
}

history_contains_path() {
  local pattern="$1"
  local revision
  while IFS= read -r revision; do
    if git ls-tree -r --name-only "$revision" | grep -E "$pattern"; then
      return 0
    fi
  done < <(git rev-list --all)
  return 1
}

required_files=(
  LICENSE
  NOTICE.md
  README.md
  CONTRIBUTING.md
  SECURITY.md
  PRIVACY.md
  CODE_OF_CONDUCT.md
)

for path in "${required_files[@]}"; do
  [[ -f "$path" ]] || {
    printf 'Missing open-source release file: %s\n' "$path" >&2
    exit 1
  }
done

git diff --check

git check-ignore -q build/.bifrost-ignore-probe || {
  printf 'build/ must remain ignored.\n' >&2
  exit 1
}

if git ls-files build | grep -q .; then
  printf 'Generated build artifacts are tracked.\n' >&2
  exit 1
fi

if git ls-files | grep -E '(^|/)(\.env|\.netrc)$' >/dev/null; then
  printf 'A local credential/config file is tracked.\n' >&2
  exit 1
fi

credential_pattern='(gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|A(KIA|SIA)[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[A-Za-z0-9_-]{35}|https?://[^/@[:space:]]+:[^/@[:space:]]+@|-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|-----BEGIN PGP PRIVATE KEY ''BLOCK-----)'
if history_contains_extended "$credential_pattern"; then
  printf 'Potential credential material found in reachable Git history.\n' >&2
  exit 1
fi

if history_contains_extended '[A-Za-z0-9._%+-]+@icloud\.com'; then
  printf 'Private iCloud address found in reachable Git history.\n' >&2
  exit 1
fi

machine_path_pattern='/''Users/[^/[:space:]"]+'
if history_contains_extended "$machine_path_pattern"; then
  printf 'Machine-specific private path found in reachable Git history.\n' >&2
  exit 1
fi

private_team_id="VMM5SZ8""V5Y"
if history_contains_fixed "$private_team_id"; then
  printf 'Apple development team identifier found in reachable Git history.\n' >&2
  exit 1
fi

private_signing_name="Leland Jourdan"" II"
if history_contains_fixed "$private_signing_name"; then
  printf 'Private signing identity found in reachable Git history.\n' >&2
  exit 1
fi

if history_contains_path '(^|/)(SOUL\.md|mts/souls/)'; then
  printf 'Sacred soul material found in reachable Git history.\n' >&2
  exit 1
fi

echo 'BIFROST Browser open-source preflight passed.'
