#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! IS_SHALLOW="$(git rev-parse --is-shallow-repository)"; then
  printf 'Open-source preflight could not inspect repository depth.\n' >&2
  exit 1
fi

if [[ "$IS_SHALLOW" == "true" ]]; then
  printf 'Open-source preflight requires complete Git history (fetch-depth: 0).\n' >&2
  exit 1
fi

PUBLISH_REF="${OSS_PREFLIGHT_HEAD:-HEAD}"
if ! PUBLISH_HEAD="$(git rev-parse --verify "${PUBLISH_REF}^{commit}")"; then
  printf 'Open-source preflight could not resolve publishing head: %s\n' "$PUBLISH_REF" >&2
  exit 1
fi
readonly PUBLISH_HEAD

if ! CHECKOUT_HEAD="$(git rev-parse --verify 'HEAD^{commit}')"; then
  printf 'Open-source preflight could not resolve the checked-out head.\n' >&2
  exit 1
fi

if [[ "$PUBLISH_HEAD" != "$CHECKOUT_HEAD" ]]; then
  printf 'Publishing head must be checked out before open-source preflight: %s\n' "$PUBLISH_HEAD" >&2
  exit 1
fi

REVISION_FILE="$(mktemp -t bifrost-oss-preflight.XXXXXX)"
trap 'rm -f "$REVISION_FILE"' EXIT

if ! git rev-list "$PUBLISH_HEAD" >"$REVISION_FILE"; then
  printf 'Open-source preflight could not enumerate publishing ancestry.\n' >&2
  exit 1
fi

if [[ ! -s "$REVISION_FILE" ]]; then
  printf 'Open-source preflight found an empty publishing ancestry.\n' >&2
  exit 1
fi

scan_failed() {
  printf 'Open-source preflight scanner failed: %s\n' "$1" >&2
  exit 1
}

history_contains_extended() {
  local pattern="$1"
  local revision
  local status
  while IFS= read -r revision; do
    if git grep -l -I -E "$pattern" "$revision" -- . >/dev/null; then
      return 0
    else
      status=$?
      [[ "$status" -eq 1 ]] || scan_failed "content scan at $revision"
    fi
  done <"$REVISION_FILE"
  return 1
}

history_contains_fixed() {
  local needle="$1"
  local revision
  local status
  while IFS= read -r revision; do
    if git grep -l -I -F "$needle" "$revision" -- . >/dev/null; then
      return 0
    else
      status=$?
      [[ "$status" -eq 1 ]] || scan_failed "fixed-string content scan at $revision"
    fi
  done <"$REVISION_FILE"
  return 1
}

history_contains_path() {
  local pattern="$1"
  local revision
  local paths
  local status
  while IFS= read -r revision; do
    if ! paths="$(git ls-tree -r --name-only "$revision")"; then
      scan_failed "path enumeration at $revision"
    fi
    if grep -E "$pattern" <<<"$paths" >/dev/null; then
      return 0
    else
      status=$?
      [[ "$status" -eq 1 ]] || scan_failed "path pattern scan at $revision"
    fi
  done <"$REVISION_FILE"
  return 1
}

federico_public_email='kap.posta@''gmail.com'
jaryd_public_email='github@jaryd.org'
jourdanlabs_public_email='leland@''jourdanlabs.com'

email_is_allowlisted() {
  local email="$1"
  local normalized
  normalized="$(printf '%s' "$email" | tr '[:upper:]' '[:lower:]')"

  if ! grep -E -x '[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+' <<<"$normalized" >/dev/null; then
    return 1
  fi

  if [[ "$normalized" == "$federico_public_email" \
    || "$normalized" == "$jaryd_public_email" \
    || "$normalized" == "$jourdanlabs_public_email" ]]; then
    return 0
  fi

  case "$normalized" in
    noreply@*|*@users.noreply.github.com|*@example.com|*@*.example.com)
      return 0
      ;;
  esac

  return 1
}

personal_email_pattern='[A-Za-z0-9._%+-]+@(gmail|icloud|me|mac|proton|outlook|hotmail|yahoo)\.[a-z.]+'

history_contains_unapproved_email() {
  local revision
  local email
  local matches
  local status
  while IFS= read -r revision; do
    if matches="$(git grep -h -I -o -i -E "$personal_email_pattern" "$revision" -- .)"; then
      :
    else
      status=$?
      [[ "$status" -eq 1 ]] || scan_failed "personal-email content scan at $revision"
      matches=''
    fi
    while IFS= read -r email; do
      [[ -n "$email" ]] || continue
      if ! email_is_allowlisted "$email"; then
        printf 'Unapproved personal email found in Git history at %s: %s\n' "$revision" "$email" >&2
        return 0
      fi
    done <<<"$matches"
  done <"$REVISION_FILE"
  return 1
}

metadata_contains_unapproved_email() {
  local revision
  local author_email
  local committer_email
  local email
  local metadata

  if ! metadata="$(git log "$PUBLISH_HEAD" --format='%H%x1f%ae%x1f%ce')"; then
    scan_failed 'commit-metadata enumeration'
  fi

  while IFS=$'\x1f' read -r revision author_email committer_email; do
    for email in "$author_email" "$committer_email"; do
      if [[ -z "$email" ]]; then
        printf 'Blank author or committer email found in commit metadata at %s.\n' "$revision" >&2
        return 0
      fi
      if ! email_is_allowlisted "$email"; then
        printf 'Unapproved personal email found in commit metadata at %s: %s\n' "$revision" "$email" >&2
        return 0
      fi
    done
  done <<<"$metadata"
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
  git cat-file -e "$PUBLISH_HEAD:$path" 2>/dev/null || {
    printf 'Missing open-source release file: %s\n' "$path" >&2
    exit 1
  }
done

git cat-file -e "$PUBLISH_HEAD:.gitignore" 2>/dev/null || {
  printf 'Missing tracked .gitignore at publishing head.\n' >&2
  exit 1
}

git diff --check
git diff --cached --check

if ! git diff --quiet -- || ! git diff --cached --quiet --; then
  printf 'Open-source preflight requires a clean tracked checkout of the publishing head.\n' >&2
  exit 1
fi

git check-ignore -q build/.bifrost-ignore-probe || {
  printf 'build/ must remain ignored.\n' >&2
  exit 1
}

if ! TRACKED_BUILD_FILES="$(git ls-files -- build)"; then
  printf 'Open-source preflight could not enumerate tracked build artifacts.\n' >&2
  exit 1
fi

if [[ -n "$TRACKED_BUILD_FILES" ]]; then
  printf 'Generated build artifacts are tracked.\n' >&2
  exit 1
fi

# Keep the detector from satisfying its own positive control.
positive_control='Copy''right'
if ! history_contains_fixed "$positive_control"; then
  printf 'History positive control failed; publishing ancestry was not scanned.\n' >&2
  exit 1
fi

tracked_secret_path_pattern='(^|/)(\.env(\.[^/]*)?|\.netrc|id_rsa|id_ed25519|[^/]+\.(pem|p12|mobileprovision|p8|keystore)|\.npmrc|GoogleService-Info\.plist)$'
if history_contains_path "$tracked_secret_path_pattern"; then
  printf 'A credential, signing, or local config filename exists in publishing history.\n' >&2
  exit 1
fi

credential_pattern='(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|A(KIA|SIA)[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[A-Za-z0-9_-]{35}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|SK[0-9A-Fa-f]{32}|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}|https?://[^/@[:space:]]+:[^/@[:space:]]+@|-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|-----BEGIN PGP PRIVATE KEY ''BLOCK-----)'
if history_contains_extended "$credential_pattern"; then
  printf 'Potential credential material found in publishing Git history.\n' >&2
  exit 1
fi

if history_contains_unapproved_email; then
  printf 'Unapproved personal email found in publishing Git content.\n' >&2
  exit 1
fi

if metadata_contains_unapproved_email; then
  printf 'Unapproved personal email found in publishing commit metadata.\n' >&2
  exit 1
fi

machine_path_pattern='(/''Users/|/''home/|/''Volumes/|[A-Z]:\\''Users\\)[^/[:space:]"]+'
if history_contains_extended "$machine_path_pattern"; then
  printf 'Machine-specific private path found in publishing Git history.\n' >&2
  exit 1
fi

team_id_pattern='"?DEVELOPMENT_TEAM(\[[^]]+\])?"?[[:space:]]*=[[:space:]]*"?[A-Z0-9]{10}"?'
if history_contains_extended "$team_id_pattern"; then
  printf 'Apple development team identifier found in publishing Git history.\n' >&2
  exit 1
fi

private_team_id="VMM5SZ8""V5Y"
if history_contains_fixed "$private_team_id"; then
  printf 'Known private Apple development team identifier found in publishing Git history.\n' >&2
  exit 1
fi

# The README's Your Name (TEAMID) placeholder cannot satisfy the 10-character shape.
signing_identity_pattern='(Apple Development|Developer ID Application|Developer ID Installer|Mac Developer|3rd Party Mac Developer|iPhone Developer|iPhone Distribution): [^"()]+ \([A-Z0-9]{10}\)'
if history_contains_extended "$signing_identity_pattern"; then
  printf 'Apple signing identity found in publishing Git history.\n' >&2
  exit 1
fi

private_signing_name="Leland Jour""dan II"
if history_contains_fixed "$private_signing_name"; then
  printf 'Known private signing identity found in publishing Git history.\n' >&2
  exit 1
fi

chamber_term_pattern='(babypul''sar|pul''sar|lu''na|auro''ra|heim''dall|bif''rost|rav''en|len''ore|pan''nywan''ny|pan''ny|vi''del|bul''ma|cauli''fla|ka''tara|yuf''fie|colta''nius|goo''ber|shen''ron|soul_[0-9a-f]{8})'
approved_public_branding_pattern='(lu''na|auro''ra|heim''dall|bif''rost|pul''sar|babypul''sar)'

chamber_term_is_allowlisted() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  grep -E -x "$approved_public_branding_pattern" <<<"$normalized" >/dev/null
}

history_contains_unapproved_chamber_term() {
  local revision
  local matches
  local paths
  local status
  local term

  while IFS= read -r revision; do
    if matches="$(git grep -h -I -o -i -E "$chamber_term_pattern" "$revision" -- .)"; then
      :
    else
      status=$?
      [[ "$status" -eq 1 ]] || scan_failed "chamber-term content scan at $revision"
      matches=''
    fi

    while IFS= read -r term; do
      [[ -n "$term" ]] || continue
      if ! chamber_term_is_allowlisted "$term"; then
        printf 'Unapproved chamber term found in Git content at %s.\n' "$revision" >&2
        return 0
      fi
    done <<<"$matches"

    if ! paths="$(git ls-tree -r --name-only "$revision")"; then
      scan_failed "chamber-term path enumeration at $revision"
    fi
    if matches="$(grep -E -i -o "$chamber_term_pattern" <<<"$paths")"; then
      :
    else
      status=$?
      [[ "$status" -eq 1 ]] || scan_failed "chamber-term path scan at $revision"
      matches=''
    fi

    while IFS= read -r term; do
      [[ -n "$term" ]] || continue
      if ! chamber_term_is_allowlisted "$term"; then
        printf 'Unapproved chamber term found in Git filename at %s.\n' "$revision" >&2
        return 0
      fi
    done <<<"$matches"
  done <"$REVISION_FILE"

  return 1
}

if history_contains_unapproved_chamber_term; then
  printf 'Private chamber codename found in publishing Git history.\n' >&2
  exit 1
fi

if history_contains_path '(^|/)(SOUL\.md|mts/souls/)'; then
  printf 'Sacred soul material found in publishing Git history.\n' >&2
  exit 1
fi

echo 'BIFROST Browser open-source preflight passed.'
