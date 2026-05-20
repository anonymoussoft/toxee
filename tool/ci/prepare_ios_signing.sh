#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/ci/common.sh
source "$SCRIPT_DIR/common.sh"

ci_require_cmd security
ci_require_cmd base64
ci_require_cmd plutil

[[ -n "${IOS_CERTIFICATE_P12_BASE64:-}" ]] || ci_die "IOS_CERTIFICATE_P12_BASE64 is required"
[[ -n "${IOS_CERTIFICATE_PASSWORD:-}" ]] || ci_die "IOS_CERTIFICATE_PASSWORD is required"
[[ -n "${IOS_PROVISIONING_PROFILE_BASE64:-}" ]] || ci_die "IOS_PROVISIONING_PROFILE_BASE64 is required"

RUNNER_TEMP_DIR="${RUNNER_TEMP:-$(mktemp -d)}"
# Default to a fresh random password each run so a residual local keychain
# isn't sitting around behind a static, well-known password (F10).
if [[ -n "${IOS_KEYCHAIN_PASSWORD:-}" ]]; then
  KEYCHAIN_PASSWORD="$IOS_KEYCHAIN_PASSWORD"
elif command -v openssl >/dev/null 2>&1; then
  KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
else
  KEYCHAIN_PASSWORD="$(date +%s%N 2>/dev/null || date +%s)-$$-$RANDOM"
fi
KEYCHAIN_PATH="$RUNNER_TEMP_DIR/toxee-ci-signing.keychain-db"
P12_PATH="$RUNNER_TEMP_DIR/toxee-signing-cert.p12"
PROFILE_PATH="$RUNNER_TEMP_DIR/toxee.mobileprovision"
PROFILE_INSTALL_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"

# On failure, tear the keychain back down so a half-prepared script doesn't
# leave the runner's default keychain pointing at a partially populated one.
# GitHub-hosted runners are ephemeral, but self-hosted runners and local debug
# invocations otherwise persist this state.
cleanup_partial_keychain() {
  local code=$?
  if [[ $code -ne 0 && -f "$KEYCHAIN_PATH" ]]; then
    security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  fi
  rm -f "$P12_PATH" "$PROFILE_PATH" 2>/dev/null || true
  exit $code
}
trap cleanup_partial_keychain EXIT

echo "$IOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$P12_PATH"
echo "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$P12_PATH" -P "$IOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db
security default-keychain -d user -s "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

mkdir -p "$PROFILE_INSTALL_DIR"
PROFILE_UUID="$(security cms -D -i "$PROFILE_PATH" | plutil -extract UUID raw -o - -)"
cp "$PROFILE_PATH" "$PROFILE_INSTALL_DIR/$PROFILE_UUID.mobileprovision"

SIGNING_IDENTITY="${IOS_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | sed -n 's/.*"\(.*\)"/\1/p' | head -n 1)"
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    printf 'IOS_SIGNING_READY=true\n'
    printf 'IOS_SIGNING_IDENTITY=%s\n' "$SIGNING_IDENTITY"
    printf 'IOS_SIGNING_KEYCHAIN=%s\n' "$KEYCHAIN_PATH"
    printf 'IOS_PROVISIONING_PROFILE_UUID=%s\n' "$PROFILE_UUID"
  } >> "$GITHUB_ENV"
fi

ci_log "Prepared iOS signing keychain and provisioning profile ($PROFILE_UUID)"
