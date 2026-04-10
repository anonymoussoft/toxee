#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/ci/common.sh
source "$SCRIPT_DIR/common.sh"

RELEASE_TAG="${RELEASE_TAG:-}"
PRERELEASE="${PRERELEASE:-false}"
ARTIFACTS_DIR="${RELEASE_ARTIFACTS_DIR:-}"
RELEASE_DRY_RUN="${RELEASE_DRY_RUN:-false}"

is_truthy() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

file_matches_regex() {
  local pattern="$1"
  local file="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$file"
    return
  fi

  grep -Eq "$pattern" "$file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      RELEASE_TAG="${2:-}"
      shift 2
      ;;
    --artifacts-dir)
      ARTIFACTS_DIR="${2:-}"
      shift 2
      ;;
    --prerelease)
      PRERELEASE="true"
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: publish_release.sh --tag <tag> --artifacts-dir <dir> [--prerelease]
EOF
      exit 0
      ;;
    *)
      ci_die "Unknown option: $1"
      ;;
  esac
done

[[ -n "$RELEASE_TAG" ]] || ci_die "Release tag is required"
[[ -n "$ARTIFACTS_DIR" ]] || ci_die "Artifacts directory is required"
[[ -d "$ARTIFACTS_DIR" ]] || ci_die "Artifacts directory does not exist: $ARTIFACTS_DIR"

if ! is_truthy "$RELEASE_DRY_RUN"; then
  ci_require_cmd gh
fi

REPO_ROOT="$(ci_repo_root)"
STAGE_DIR="$REPO_ROOT/dist/github-release"
CHECKSUM_FILE="$STAGE_DIR/SHA256SUMS.txt"

ci_reset_dir "$STAGE_DIR"
: > "$CHECKSUM_FILE"

copy_release_asset() {
  local source_file="$1"
  local relative_path="$2"
  local basename
  local destination_name

  basename="$(basename "$source_file")"
  destination_name="$basename"

  if [[ -f "$STAGE_DIR/$destination_name" ]]; then
    destination_name="${relative_path//\//-}"
  fi

  cp "$source_file" "$STAGE_DIR/$destination_name"
  printf '%s  %s\n' "$(ci_sha256_file "$STAGE_DIR/$destination_name")" "$destination_name" >> "$CHECKSUM_FILE"
}

collect_assets() {
  local file relative_path
  while IFS= read -r -d '' file; do
    relative_path="${file#$ARTIFACTS_DIR/}"
    if [[ "$(basename "$file")" == "NOTES.txt" ]]; then
      continue
    fi

    case "$file" in
      *.zip|*.tar.gz|*.apk|*.aab|*.dmg|*.pkg|*.msi|*.msix|*.exe|*.ipa|*.AppImage) ;;
      *) continue ;;
    esac

    if ! should_publish_asset "$relative_path" "$file"; then
      continue
    fi

    copy_release_asset "$file" "$relative_path"
  done < <(find "$ARTIFACTS_DIR" -type f -print0 | sort -z)
}

should_publish_asset() {
  local relative_path="$1"
  local file="$2"
  local group
  local notes_file
  local basename

  group="$(dirname "$relative_path")"
  notes_file="$ARTIFACTS_DIR/$group/NOTES.txt"
  basename="$(basename "$file")"

  if [[ "$group" == "toxee-ios-release" && "$basename" == *.ipa && -f "$notes_file" ]]; then
    if file_matches_regex 'Packaged unsigned iOS app as IPA\.|Unsigned iOS IPA' "$notes_file"; then
      ci_log "Skipping unsigned iOS IPA from GitHub Release: $basename"
      return 1
    fi
  fi

  if [[ "$group" == "toxee-android-release" && ( "$basename" == *.apk || "$basename" == *.aab ) && -f "$notes_file" ]]; then
    if file_matches_regex 'No Android Tim2Tox JNI libraries were staged\.' "$notes_file"; then
      ci_log "Skipping Android asset without staged JNI libs from GitHub Release: $basename"
      return 1
    fi
  fi

  case "$group" in
    toxee-linux-release)
      [[ "$basename" == *.AppImage ]] || return 1
      ;;
    toxee-macos-release)
      [[ "$basename" == *.dmg || "$basename" == *.pkg ]] || return 1
      ;;
    toxee-windows-release)
      [[ "$basename" == *.msi || "$basename" == *.msix || "$basename" == *.exe ]] || return 1
      ;;
    toxee-android-release)
      [[ "$basename" == *.apk ]] || return 1
      ;;
    toxee-ios-release)
      [[ "$basename" == *.ipa ]] || return 1
      ;;
  esac

  return 0
}

prune_existing_release_assets() {
  local asset_name

  while IFS= read -r asset_name; do
    [[ -n "$asset_name" ]] || continue
    if [[ ! -f "$STAGE_DIR/$asset_name" ]]; then
      ci_log "Deleting stale release asset: $asset_name"
      gh release delete-asset "$RELEASE_TAG" "$asset_name" --yes
    fi
  done < <(gh release view "$RELEASE_TAG" --json assets --jq '.assets[].name')
}

create_or_update_release() {
  local extra_create_flags=()

  if [[ "$PRERELEASE" == "true" ]]; then
    extra_create_flags+=(--prerelease)
  fi

  if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    ci_log "Release $RELEASE_TAG already exists; uploading assets with --clobber"
    prune_existing_release_assets
    gh release upload "$RELEASE_TAG" "$STAGE_DIR"/* --clobber
    return
  fi

  if [[ "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" == "$RELEASE_TAG" ]]; then
    ci_log "Creating release from existing tag $RELEASE_TAG"
    local create_cmd=(gh release create "$RELEASE_TAG" "$STAGE_DIR"/* --title "$RELEASE_TAG" --generate-notes --verify-tag)
    if [[ "$PRERELEASE" == "true" ]]; then
      create_cmd+=(--prerelease)
    fi
    "${create_cmd[@]}"
    return
  fi

  ci_log "Creating release $RELEASE_TAG targeting ${GITHUB_SHA:-current HEAD}"
  local create_cmd=(gh release create "$RELEASE_TAG" "$STAGE_DIR"/* --title "$RELEASE_TAG" --generate-notes --target "${GITHUB_SHA:-HEAD}")
  if [[ "$PRERELEASE" == "true" ]]; then
    create_cmd+=(--prerelease)
  fi
  "${create_cmd[@]}"
}

collect_assets

if [[ ! -s "$CHECKSUM_FILE" ]]; then
  ci_die "No release assets were collected from $ARTIFACTS_DIR"
fi

if is_truthy "$RELEASE_DRY_RUN"; then
  ci_log "Dry run enabled; skipping gh release publish"
  exit 0
fi

create_or_update_release
ci_log "Published GitHub Release: $RELEASE_TAG"
