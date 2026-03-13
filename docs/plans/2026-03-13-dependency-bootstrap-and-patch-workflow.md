# Submodule And Vendor Dependency Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make a fresh clone of `toxee` able to initialize `tim2tox` and `chat-uikit-flutter` as pinned submodules, download and patch `tencent_cloud_chat_sdk`, generate local dependency overrides, and complete a build without requiring manually prepared sibling repositories.

**Architecture:** Treat `toxee` as the only entry repository. Keep `tim2tox` and `chat-uikit-flutter` in `third_party/` as git submodules, with `chat-uikit-flutter` pinned to your fork `git@github.com:anonymoussoft/chat-uikit-flutter.git`. Keep `tencent_cloud_chat_sdk` as a generated vendor dependency under `third_party/tencent_cloud_chat_sdk`, downloaded from a locked versioned source archive and patched from the `tim2tox` submodule. A bootstrap command initializes submodules, vendors the SDK, applies the SDK patch series, and writes a generated `pubspec_overrides.yaml` so `flutter pub get` and all build scripts resolve only in-repo paths.

**Tech Stack:** Flutter, Dart CLI scripts, `git submodule`, HTTP archive download, unified-diff patch series, shell build wrappers, GitHub Actions

---

### Task 1: Introduce a stable `third_party/` layout and submodule declarations

**Files:**
- Create: `.gitmodules`
- Modify: `.gitignore`
- Modify: `README.md`
- Create: `doc/DEPENDENCY_LAYOUT.md`

**Step 1: Write the failing structure checklist**

- Document the current assumptions that break a fresh `toxee` clone:
  - `tim2tox_dart` is only resolvable through `../tim2tox/dart`.
  - UIKit packages are only resolvable through `../chat-uikit-flutter/...`.
  - `tencent_cloud_chat_sdk` is only resolvable through `../tencent_cloud_chat_sdk-8.7.7201`.

**Step 2: Confirm the current failure mode**

Run: `cd /Users/bin.gao/chat-uikit/toxee && rg -n "../tim2tox|../chat-uikit-flutter|../tencent_cloud_chat_sdk" pubspec.yaml`

Expected: the current app manifest still depends on sibling directories outside the repo.

**Step 3: Implement the repository layout**

- Add `third_party/tim2tox` as a submodule pointing to `git@github.com:anonymoussoft/tim2tox.git`.
- Add `third_party/chat-uikit-flutter` as a submodule pointing to `git@github.com:anonymoussoft/chat-uikit-flutter.git`.
- Pin the `chat-uikit-flutter` submodule to the desired fork commit on your maintained branch.
- Reserve `third_party/tencent_cloud_chat_sdk` as a generated directory, ignored by git.
- Document the target layout:

```text
toxee/
├── third_party/
│   ├── tim2tox/                 # submodule
│   ├── chat-uikit-flutter/      # submodule to anonymoussoft fork
│   └── tencent_cloud_chat_sdk/  # generated vendor tree
├── patches/                     # optional root-level bootstrap metadata
├── tool/
│   └── bootstrap_deps.dart
└── pubspec_overrides.yaml       # generated
```

**Step 4: Verify submodule declarations**

Run: `cd /Users/bin.gao/chat-uikit/toxee && git config --file .gitmodules --get-regexp 'submodule\\..*\\.(path|url)'`

Expected: `third_party/tim2tox` and `third_party/chat-uikit-flutter` are declared with the intended URLs.

### Task 2: Remove hardcoded sibling-path assumptions from package resolution

**Files:**
- Modify: `pubspec.yaml`
- Modify: `third_party/tim2tox/dart/pubspec.yaml`
- Modify: `README.md`
- Create: `pubspec_overrides.yaml` (generated, gitignored)
- Modify: `.gitignore`

**Step 1: Write the failing resolution checklist**

- `toxee/pubspec.yaml` should no longer reference `../tim2tox`, `../chat-uikit-flutter`, or `../tencent_cloud_chat_sdk-*`.
- `third_party/tim2tox/dart/pubspec.yaml` should no longer reference `../../chat-uikit-flutter`.
- Checked-in manifests should remain portable even before bootstrap writes overrides.

**Step 2: Confirm the current failure mode**

Run: `cd /Users/bin.gao/chat-uikit/toxee && flutter pub get`

Expected: dependency resolution only works when sibling repos already exist outside the `toxee` repo.

**Step 3: Implement the minimal dependency declaration cleanup**

- Change `tim2tox_dart` in `pubspec.yaml` from a fixed sibling path to a neutral dependency satisfied by generated overrides.
- Remove checked-in local `dependency_overrides` from `pubspec.yaml`.
- Change `tencent_cloud_chat_common` in `third_party/tim2tox/dart/pubspec.yaml` from a fixed relative path to a versioned dependency that can be redirected by the root override file.
- Add `pubspec_overrides.yaml` and `third_party/tencent_cloud_chat_sdk/` to `.gitignore`.
- Update `README.md` so the documented entry flow becomes `git clone -> bootstrap -> flutter pub get -> build`.

**Step 4: Verify dependency declarations are now bootstrap-friendly**

Run: `cd /Users/bin.gao/chat-uikit/toxee && rg -n "../tim2tox|../chat-uikit-flutter|../tencent_cloud_chat_sdk|../../chat-uikit-flutter" pubspec.yaml third_party/tim2tox/dart/pubspec.yaml`

Expected: no remaining sibling-path assumptions in checked-in package manifests.

### Task 3: Add a bootstrap pipeline that initializes submodules and vendors the SDK

**Files:**
- Create: `tool/bootstrap_deps.dart`
- Create: `tool/tencent_cloud_chat_sdk.lock.json`
- Create: `tool/vendor_state.json` (generated)
- Create: `tool/test_bootstrap_smoke.sh`
- Modify: `README.md`

**Step 1: Write the failing bootstrap smoke test**

- Create `tool/test_bootstrap_smoke.sh` that:
  - removes `third_party/tencent_cloud_chat_sdk/` and `pubspec_overrides.yaml`
  - deinitializes the two submodules if needed
  - runs `dart run tool/bootstrap_deps.dart --offline-check-only`
  - asserts the command fails because the bootstrap tool does not exist yet

**Step 2: Run the smoke test to confirm it fails**

Run: `cd /Users/bin.gao/chat-uikit/toxee && bash tool/test_bootstrap_smoke.sh`

Expected: failure because `tool/bootstrap_deps.dart` is missing.

**Step 3: Implement the bootstrap tool**

- Add `tool/tencent_cloud_chat_sdk.lock.json` with:
  - package version `8.7.7201`
  - source archive URL
  - expected SHA-256 checksum
- Implement `tool/bootstrap_deps.dart` so it:
  - runs `git submodule sync --recursive`
  - runs `git submodule update --init --recursive third_party/tim2tox third_party/chat-uikit-flutter`
  - verifies both submodules are at the commits pinned by the superproject
  - downloads and unpacks the SDK archive into `third_party/tencent_cloud_chat_sdk`
  - writes `tool/vendor_state.json` with the resolved SDK version and checksum
  - is idempotent and safe to re-run

**Step 4: Verify bootstrap fetches the expected sources**

Run: `cd /Users/bin.gao/chat-uikit/toxee && dart run tool/bootstrap_deps.dart`

Expected:
- `third_party/tim2tox` exists and is initialized as a submodule
- `third_party/chat-uikit-flutter` exists and is initialized as a submodule
- `third_party/tencent_cloud_chat_sdk` exists and matches the locked SDK checksum

### Task 4: Apply and maintain only the SDK patch series

**Files:**
- Create: `third_party/tim2tox/patches/tencent_cloud_chat_sdk/8.7.7201/series`
- Create: `third_party/tim2tox/patches/tencent_cloud_chat_sdk/8.7.7201/0001-*.patch`
- Modify: `tool/bootstrap_deps.dart`
- Create: `tool/refresh_sdk_patch.sh`
- Modify: `doc/PATCH_MAINTENANCE.md`

**Step 1: Write the failing patch-application check**

- Extend `tool/test_bootstrap_smoke.sh` so it verifies:
  - bootstrap fails cleanly when an SDK patch file declared in `series` is missing
  - bootstrap fails cleanly when an SDK patch no longer applies
  - bootstrap does not try to patch `chat-uikit-flutter`, because UIKit changes now live in the forked submodule history

**Step 2: Run the smoke test to confirm it fails**

Run: `cd /Users/bin.gao/chat-uikit/toxee && bash tool/test_bootstrap_smoke.sh`

Expected: failure until SDK patch discovery and application are implemented.

**Step 3: Implement the SDK patch workflow**

- Store all `tencent_cloud_chat_sdk` changes inside the `tim2tox` repo as ordered patch files plus a `series` file.
- Teach `tool/bootstrap_deps.dart` to:
  - discover the active SDK version from `tool/tencent_cloud_chat_sdk.lock.json`
  - load the SDK patch series from `third_party/tim2tox/patches/tencent_cloud_chat_sdk/<version>/`
  - apply patches to `third_party/tencent_cloud_chat_sdk` with `git apply --check` first, then `git apply`
  - skip reapplication safely when the vendor tree already matches the patched state
- Add `tool/refresh_sdk_patch.sh` to regenerate SDK patches from local edits in `third_party/tencent_cloud_chat_sdk` back into `third_party/tim2tox/patches/...`.
- Document that `chat-uikit-flutter` changes must be committed in `anonymoussoft/chat-uikit-flutter`, then consumed by updating the submodule pointer in `toxee`.

**Step 4: Verify patch application and refresh workflow**

Run: `cd /Users/bin.gao/chat-uikit/toxee && dart run tool/bootstrap_deps.dart --force`

Expected:
- bootstrap reports the SDK patch series in order
- re-running bootstrap is idempotent
- `tool/refresh_sdk_patch.sh` writes back only SDK patches, not UIKit patches

### Task 5: Generate overrides and route every build entrypoint through bootstrap

**Files:**
- Modify: `tool/bootstrap_deps.dart`
- Modify: `build_all.sh`
- Modify: `run_toxee.sh`
- Modify: `run_toxee_android.sh`
- Modify: `run_toxee_ios_device.sh`
- Modify: `.github/workflows/analyze.yml`
- Modify: `README.md`
- Modify: `doc/BUILD_AND_DEPLOY.md`

**Step 1: Write the failing integration checklist**

- `build_all.sh` must bootstrap before `flutter pub get`
- all platform helper scripts must bootstrap before build-specific work
- CI must bootstrap before `flutter pub get`
- generated `pubspec_overrides.yaml` must point only inside `third_party/`

**Step 2: Confirm the current scripts miss the bootstrap step**

Run: `cd /Users/bin.gao/chat-uikit/toxee && rg -n "bootstrap_deps|pubspec_overrides|third_party/" build_all.sh run_toxee.sh run_toxee_android.sh run_toxee_ios_device.sh .github/workflows/analyze.yml`

Expected: no bootstrap integration yet.

**Step 3: Implement build-entry integration**

- Extend `tool/bootstrap_deps.dart` to generate `pubspec_overrides.yaml` with overrides for:
  - `tim2tox_dart -> third_party/tim2tox/dart`
  - `tencent_cloud_chat_sdk -> third_party/tencent_cloud_chat_sdk`
  - all UIKit packages used by `toxee -> third_party/chat-uikit-flutter/...`
- Update every build script to call `dart run tool/bootstrap_deps.dart` before `flutter pub get`.
- Update the GitHub Actions workflow to run bootstrap before dependency installation and analysis.
- Keep SDK bootstrap separate from the actual native `tim2tox` build so dependency setup and native compilation remain debuggable independently.

**Step 4: Verify the generated override file and build integration**

Run: `cd /Users/bin.gao/chat-uikit/toxee && dart run tool/bootstrap_deps.dart && sed -n '1,220p' pubspec_overrides.yaml`

Expected: every local override points into `third_party/`, with no path escaping outside the repo.

### Task 6: Document the steady-state workflow for fresh clones and upgrades

**Files:**
- Modify: `README.md`
- Create: `doc/DEPENDENCY_BOOTSTRAP.md`
- Create: `doc/PATCH_MAINTENANCE.md`
- Modify: `doc/BUILD_AND_DEPLOY.md`

**Step 1: Write the failing end-to-end checklist**

- A fresh clone of `toxee` can run one bootstrap command and one build command.
- Maintainers know which changes belong in a fork commit versus an SDK patch.
- Upgrading a submodule revision or SDK version has a documented, low-risk workflow.

**Step 2: Run the end-to-end verification on a clean workspace**

Run:
- `git clone <toxee> /tmp/toxee-clean`
- `cd /tmp/toxee-clean`
- `dart run tool/bootstrap_deps.dart`
- `flutter pub get`
- `./build_all.sh --platform macos --mode debug`

Expected:
- submodules are initialized automatically even from a non-recursive clone
- the SDK is downloaded and patched automatically
- `flutter pub get` resolves against generated in-repo paths
- the build reaches the normal native/app compilation stages

**Step 3: Document the ownership rules and upgrade checklist**

- In `doc/DEPENDENCY_BOOTSTRAP.md`, describe the exact bootstrap order:
  1. initialize submodules
  2. vendor the SDK
  3. apply SDK patches
  4. generate `pubspec_overrides.yaml`
  5. run `flutter pub get`
- In `doc/PATCH_MAINTENANCE.md`, define ownership:
  - `toxee` owns submodule pointers and bootstrap orchestration
  - `tim2tox` owns `tencent_cloud_chat_sdk` patches
  - `chat-uikit-flutter` customizations live as normal commits in `anonymoussoft/chat-uikit-flutter`
- Add an upgrade checklist with explicit order:
  1. update the desired fork commit in `third_party/chat-uikit-flutter`
  2. update the desired `tim2tox` commit in `third_party/tim2tox`
  3. bump SDK version and checksum in `tool/tencent_cloud_chat_sdk.lock.json`
  4. refresh SDK patches in `third_party/tim2tox/patches/...`
  5. rerun bootstrap from scratch
  6. rerun focused build verification

**Step 4: Run the final verification set**

Run:
- `cd /Users/bin.gao/chat-uikit/toxee && dart run tool/bootstrap_deps.dart --force`
- `cd /Users/bin.gao/chat-uikit/toxee && flutter pub get`
- `cd /Users/bin.gao/chat-uikit/toxee && dart run tool/check_complexity.dart`

Expected: bootstrap succeeds, dependency resolution succeeds from generated local sources, and the existing repo checks still run.
