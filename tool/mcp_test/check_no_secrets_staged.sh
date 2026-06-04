#!/usr/bin/env bash
#
# check_no_secrets_staged.sh
# ==========================
# Fails (exit 1) if the git index (staged changes) contains any file that must
# NEVER land in version control.
#
# WHY THIS EXISTS
# ---------------
# The MCP / L3 test harness under tool/mcp_test/ seeds real Tox accounts to
# drive two-instance and echo-peer scenarios. Those seeded fixtures embed the
# account's *Tox secret key* inside `*.tox` profile blobs
# (e.g. tool/mcp_test/fixtures/paired_for_e2e_{A,B}/.../tox_profile.tox and
# tool/mcp_test/echo_peer_state/tox_profile.tox). A leaked Tox secret key lets
# anyone impersonate that identity on the Tox P2P network — it is a credential,
# not test data. It must never be committed.
#
# This guard is the safety net for the FIRST tool/mcp_test/ commit, when the
# whole harness is still untracked: a single `git add tool/mcp_test` would
# otherwise stage secret-key blobs, runtime state, and stray root junk all at
# once. .gitignore rules cover the steady state, but a forced add
# (`git add -f`) or a not-yet-ignored path can slip through — this script
# inspects what is actually staged and refuses the commit.
#
# It is intentionally standalone and rerunnable (no side effects, read-only on
# the index) so it can later be wired into the in-tree pre-push hook
# (tool/install_git_hooks.sh) alongside the existing submodule-SHA guard.
#
# USAGE
# -----
#   bash tool/mcp_test/check_no_secrets_staged.sh
# Exit 0: nothing forbidden is staged.
# Exit 1: prints each offending staged path, grouped by reason.

set -euo pipefail

# Collect staged (cached) paths. Paths are repo-root-relative, forward-slashed,
# regardless of the caller's CWD, so the matching below is CWD-independent.
staged="$(git diff --cached --name-only)"

if [ -z "${staged}" ]; then
  echo "check_no_secrets_staged: no staged files; nothing to check."
  exit 0
fi

offenders=""

# Classify one path; if forbidden, append "<path>\t<reason>" to offenders.
classify() {
  local path="$1"
  local base
  base="$(basename "${path}")"

  case "${path}" in
    # Any Tox profile blob anywhere — these carry the secret key.
    *.tox)
      offenders="${offenders}${path}	Tox secret-key blob (*.tox)
"
      return ;;
    # Seeded two-instance fixtures (deep paths under these dirs).
    tool/mcp_test/fixtures/paired_for_e2e_A/*|tool/mcp_test/fixtures/paired_for_e2e_B/*)
      offenders="${offenders}${path}	seeded e2e fixture (contains secret keys)
"
      return ;;
    # Echo-peer seeded state (holds a tox_profile.tox).
    tool/mcp_test/echo_peer_state/*)
      offenders="${offenders}${path}	echo-peer seeded state (contains secret key)
"
      return ;;
    # Per-run multi-instance runtime (app copies + runtime state).
    tool/mcp_test/.multi_instance_runtime/*)
      offenders="${offenders}${path}	multi-instance runtime state
"
      return ;;
    # Compiled echo-peer build output.
    tool/mcp_test/echo_peer_src/build/*)
      offenders="${offenders}${path}	echo-peer build output
"
      return ;;
    # Driver screenshot/output artifacts (codex final review P2: keep the
    # guard's coverage identical to the .gitignore "never commit" set).
    tool/mcp_test/artifacts/*)
      offenders="${offenders}${path}	driver output artifact (tool/mcp_test/artifacts/)
"
      return ;;
    # Echo-peer runtime logs (echo_peer.stdout.log etc.).
    tool/mcp_test/echo_peer*.log)
      offenders="${offenders}${path}	echo-peer runtime log
"
      return ;;
    # Root SQLite DB written by a stray plugin.
    community_data.db)
      offenders="${offenders}${path}	root community_data.db (runtime artifact)
"
      return ;;
  esac

  # Stray screenshots at the repo root: sc_*.png with no directory component.
  case "${path}" in
    */*) : ;;  # has a directory component -> not a root file, skip this rule
    *)
      case "${base}" in
        sc_*.png)
          offenders="${offenders}${path}	root screenshot (sc_*.png)
"
          return ;;
      esac ;;
  esac
}

while IFS= read -r path; do
  [ -n "${path}" ] || continue
  classify "${path}"
done <<EOF
${staged}
EOF

if [ -n "${offenders}" ]; then
  echo "check_no_secrets_staged: FORBIDDEN files are staged for commit:" >&2
  echo "" >&2
  # offenders is "<path>\t<reason>" lines; print as a tidy list.
  printf '%b' "${offenders}" | while IFS=$'\t' read -r p reason; do
    [ -n "${p}" ] || continue
    printf '  %-70s  %s\n' "${p}" "${reason}" >&2
  done
  echo "" >&2
  echo "Unstage them before committing (git restore --staged <path>) and make" >&2
  echo "sure they are covered by .gitignore. Tox *.tox blobs are secret keys." >&2
  exit 1
fi

echo "check_no_secrets_staged: OK — no forbidden files staged."
exit 0
