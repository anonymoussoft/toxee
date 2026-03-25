#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/ci/common.sh
source "$SCRIPT_DIR/common.sh"

RELEASE_TAG="${RELEASE_TAG:-}"
PRERELEASE="${PRERELEASE:-false}"
ARTIFACTS_DIR="${RELEASE_ARTIFACTS_DIR:-}"

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

ci_require_cmd gh

REPO_ROOT="$(ci_repo_root)"
STAGE_DIR="$REPO_ROOT/dist/github-release"
BUILD_NOTES_FILE="$STAGE_DIR/BUILD-NOTES.txt"
CHECKSUM_FILE="$STAGE_DIR/SHA256SUMS.txt"

ci_reset_dir "$STAGE_DIR"
: > "$BUILD_NOTES_FILE"
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
      {
        printf '=== %s ===\n' "$(dirname "$relative_path")"
        cat "$file"
        printf '\n'
      } >> "$BUILD_NOTES_FILE"
      continue
    fi

    case "$file" in
      *.zip|*.tar.gz|*.apk|*.aab|*.dmg|*.pkg|*.msi|*.msix|*.exe|*.ipa) ;;
      *) continue ;;
    esac

    copy_release_asset "$file" "$relative_path"
  done < <(find "$ARTIFACTS_DIR" -type f -print0 | sort -z)
}

create_or_update_release() {
  local extra_create_flags=()

  if [[ "$PRERELEASE" == "true" ]]; then
    extra_create_flags+=(--prerelease)
  fi

  if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    ci_log "Release $RELEASE_TAG already exists; uploading assets with --clobber"
    gh release upload "$RELEASE_TAG" "$STAGE_DIR"/* --clobber
    return
  fi

  if [[ "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" == "$RELEASE_TAG" ]]; then
    ci_log "Creating release from existing tag $RELEASE_TAG"
    gh release create "$RELEASE_TAG" "$STAGE_DIR"/* \
      --title "$RELEASE_TAG" \
      --generate-notes \
      --verify-tag \
      "${extra_create_flags[@]}"
    return
  fi

  ci_log "Creating release $RELEASE_TAG targeting ${GITHUB_SHA:-current HEAD}"
  gh release create "$RELEASE_TAG" "$STAGE_DIR"/* \
    --title "$RELEASE_TAG" \
    --generate-notes \
    --target "${GITHUB_SHA:-HEAD}" \
    "${extra_create_flags[@]}"
}

collect_assets

if [[ ! -s "$CHECKSUM_FILE" ]]; then
  ci_die "No release assets were collected from $ARTIFACTS_DIR"
fi

if [[ ! -s "$BUILD_NOTES_FILE" ]]; then
  rm -f "$BUILD_NOTES_FILE"
fi

create_or_update_release
ci_log "Published GitHub Release: $RELEASE_TAG"
