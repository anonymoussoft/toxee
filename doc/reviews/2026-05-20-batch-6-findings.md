# Batch 6 — 工程基础设施（域 Q）findings

> Review 日期：2026-05-20
> 范围：构建、工具链、CI、补丁机制、git hooks、复杂度检查、Release 发布
> 配套：[功能清单](./2026-05-20-feature-inventory.md) · [Prompt 模板](./2026-05-20-review-prompts.md)

## 扫描范围与发现概览

扫描覆盖 `tool/bootstrap_deps.dart`、`tool/vendor_state.json`、`tool/verify_submodule_remote.sh`、`tool/git-hooks/pre-push`、`tool/refresh_sdk_patch.sh`、`tool/check_complexity.dart`、`analysis_options.yaml`、`tool/ci/build_tim2tox.sh`、`tool/ci/package_artifacts.sh`、`tool/ci/publish_release.sh`、`tool/ci/prepare_ios_signing.sh`、`tool/ci/common.sh`，以及 `.github/workflows/` 全部 6 个工作流。

共发现 **12 条** 置信度 ≥ medium 的 finding：2 条 high、8 条 medium、2 条 low。核心风险集中在：vendor_state 的两阶段写入竞态、patch 首次应用时的漏记、pre-push hook 失效绕过路径、ARM64 构建在 release 发布路径上的行为、libsodium 未固定下载 SHA、iOS runner 版本漂移、check_complexity 的静态强制可行性。

## High

### [high] F1: vendor_state.json 两阶段写入竞态 — CI-only / Developer-only

- 位置：`tool/bootstrap_deps.dart:165-168`（首次写）vs `:201-205`（补写 `patches_sha256`）
- 现象：`needVendor` 为真时，步骤 2 vendor SDK 后立即写 `{'version', 'sha256'}`，此时 `patches_applied` 与 `patches_sha256` 未写入。若进程在 :168 之后、:205 之前被杀（OOM、Ctrl-C、CI 超时），下次运行靠多个条件拼凑正确性。
- 风险：写入时序非原子，分支简化（如 `storedPatchesSha256 != null` → `isNotEmpty`）即产生"vendor 了但没 patch"的 SDK 被当 ready 使用，运行时 ABI 不匹配 crash。
- 建议修法：合并为单次写入，补丁 apply 完成后一次性写完整状态；用 `.tmp` 文件 + rename 保证原子性。
- 置信度：high

### [high] F2: apply_sdk_patches 失败时 stateFile 留下脏状态，offline-check 误判通过 — CI-only

- 位置：`tool/bootstrap_deps.dart:165-168`；`.github/workflows/bootstrap_fresh.yml:38-39`
- 现象：`--force` 路径触发 vendor，写入 `{version, sha256}` 无 patches_sha256；若 apply_sdk_patches 失败（`patchCode != 0`），:197-199 `exit(patchCode)` 留下中间状态。`bootstrap_fresh` 的 offline-check 会通过（version/sha256 匹配），但 SDK 实际未打补丁。
- 风险：CI 给出"通过"信号但产出 SDK 是无补丁版本，`flutter analyze` 可能过（补丁若只改实现），运行时行为不同。
- 建议修法：apply_sdk_patches 失败时清除或回滚 stateFile。
- 置信度：high

## Medium

### [medium] F3: pre-push hook 的 ls-remote 超时/SSH 不可用静默跳过 — Developer-only

- 位置：`tool/verify_submodule_remote.sh:112-113, 120-121`
- 现象：两步 git 子命令都重定向 stderr 到 `/dev/null`。`git ls-remote` 默认网络超时在慢网络下超过 60s，hook 挂起 `git push`。`set -euo pipefail` 对 `|| true` 路径无效。
- 风险：SSH 不可用或网络慢时 hook 挂起；可被 `--no-verify` 绕过（文档允许）但阻力远小于预期。
- 建议修法：加 `GIT_TERMINAL_PROMPT=0 git -c http.timeout=15 -c core.sshCommand='ssh -o ConnectTimeout=10'` 约束超时；CI 环境（`CI=true`）跳过 hook 改为独立 CI step。
- 置信度：medium

### [medium] F4: refresh_sdk_patch.sh 拒绝多补丁但不给明确建议 — Developer-only

- 位置：`tool/refresh_sdk_patch.sh:61-64`
- 现象：`SERIES_ENTRIES[@]` 长度 > 1 时 `exit 1`，建议手动 `git format-patch`。但 `apply_sdk_patches.dart` 已支持多补丁顺序 apply，`vendor_state.json` 的 patches_sha256 是多文件串联哈希。
- 风险：开发者拆分补丁时找不到工具支持，倾向于把所有修改塞入单个 `.patch`，导致补丁越来越大。
- 建议修法：扩展支持多补丁（`git format-patch baseline..HEAD -o $PATCHES_DIR`），或 `exit 1` 信息里提供完整命令。
- 置信度：medium

### [medium] F5: offline-check 在 patches_sha256 字段缺失时静默通过 — Developer-only / CI-only

- 位置：`tool/bootstrap_deps.dart:109-113`；offline-check 路径 :291-307
- 现象：`patchesChanged` 条件要求 `storedPatchesSha256 != null && isNotEmpty`。旧 `vendor_state.json` 无此字段时 `patchesChanged = false`；offline-check 在 patches_sha256 缺失时直接通过，无法检测"补丁文件被本地修改但 lock 未更新"。
- 建议修法：offline-check 若 series 文件存在但 `patches_sha256` 缺失，应报警而非静默跳过。
- 置信度：medium

### [medium] F6: libsodium 下载无 sha256 校验 — CI-only

- 位置：`tool/ci/build_tim2tox.sh:219`（Android）、:347（iOS）
- 现象：`download_file_once` 只检查文件是否已存在，下载后直接解压，无完整性验证。GitHub release CDN 返回被污染内容或本地缓存损坏，后续所有 Android/iOS libsodium 静态库都会错误。
- 风险：libsodium 是加密底层依赖，静默引入错误版本会导致加密不正确，编译期无法发现。
- 建议修法：下载后 `sha256sum` / `shasum -a256` 验证已知哈希（与 `lock.json` 维护），失败 `ci_die`。
- 置信度：medium

### [medium] F7: ARM64 构建不稳定，单 job 失败阻塞整个 release — CI-only

- 位置：`.github/workflows/build-packages.yml:573-581`（`publish` job `needs: [linux, windows, macos, android, ios]`）；round 7 commit `e6a782b`、round 8 commit `0123680`
- 现象：`fail-fast: false` 保证各 job 独立运行，但 `publish` 的 `needs` 在 strategy group 级别判断 — Linux 矩阵中任意 job 失败整组失败，`publish` 不发布。round 7/8 显示 Linux ARM64 / Windows ARM64 在 Flutter fusion repo `update_engine_version.sh` 上持续不稳定，LUCI_CONTEXT 是非公开 workaround。
- 风险：runner 镜像或 Flutter stable 更新可能让 LUCI_CONTEXT 失效，整个 release 被阻塞。
- 建议修法：ARM64 job 标记为 optional（独立 job + `continue-on-error: true`），或 release 条件只依赖 x86_64 主架构。追踪 Flutter 上游对 `update_engine_version` 的修复尽快去掉 LUCI_CONTEXT。
- 置信度：medium

### [medium] F8: iOS 用 macos-14，桌面用 macos-15，Xcode 版本不一致 — CI-only

- 位置：`.github/workflows/build-packages.yml:372-375` vs :502
- 现象：iOS job 固定 `macos-14`（Xcode 15.x），macOS 桌面用 `macos-15`（Xcode 16.x）。两环境共享 `build_tim2tox.sh` iOS 构建路径，但 SDK 路径、bitcode、Swift ABI、链接器标志有差异。`macos-14` 是 deprecated runner。
- 风险：iOS 包在不同 Xcode 版本下行为静默不一致；`macos-14` 停用后 iOS CI 中断。
- 建议修法：iOS job 升级到 `macos-15` 并同步测试 Podfile.lock 兼容性。
- 置信度：medium

### [medium] F9: macOS PKG 无代码签名，Gatekeeper 拒装 — User-facing

- 位置：`tool/ci/package_artifacts.sh:283-289`
- 现象：`pkgbuild` 产出未签名 PKG，无 `productsign --sign`，无 `spctl --assess`。macOS 13+ 对互联网未签名 PKG 默认拒装。iOS/Android 都有签名路径，macOS 是唯一无签名的桌面平台。
- 风险：普通用户下载后 Gatekeeper 阻拦，错误提示对用户不友好。
- 建议修法：CI secrets 加 `MACOS_DEVELOPER_ID_INSTALLER_CERT` + `MACOS_NOTARIZATION_*`，`package_macos` 增加 `productsign` + `notarytool submit`（参照 iOS 路径），secrets 不存在时 warn 而非失败。
- 置信度：medium

### [medium] F10: prepare_ios_signing.sh 未清理临时 keychain — CI-only

- 位置：`tool/ci/prepare_ios_signing.sh:27-33`
- 现象：创建 `$RUNNER_TEMP/toxee-ci-signing.keychain-db` 并设为 default，无 `trap` 在退出时 `security delete-keychain`，无 post-job 清理。`IOS_KEYCHAIN_PASSWORD` 默认值 `toxee-ci-keychain` 是固定弱密码。
- 风险：GitHub Actions ephemeral runner 上不是安全问题，但本地或自托管 runner 上会以弱密码持久残留；本地调试会污染开发者 keychain。
- 建议修法：脚本末尾或 workflow post 步骤 `security delete-keychain`；默认密码改为随机生成。
- 置信度：medium

## Low

### [low] F11: check_complexity.dart enforcement 切换路径不明确 — Developer-only

- 位置：`tool/check_complexity.dart:23-25`
- 现象：`exit(1)` 被注释，CI `Complexity guard` 仅打印警告。当前 `home_page.dart`、`applications_page.dart` 等超 500 行，切换 enforcement 立即 CI 失败。
- 建议修法：白名单机制（`// ignore-complexity`），对已有超标文件豁免，新文件强制；或 PR CI 仅对新增超标文件 delta 检测。
- 置信度：medium（归 low：已知技术债非新缺陷）

### [low] F12: analysis_options.yaml 与 CI `--no-fatal-warnings` 组合导致本地比 CI 严格 — Developer-only

- 位置：`analysis_options.yaml:29`；`.github/workflows/analyze.yml:27`
- 现象：`prefer_final_locals` 在 flutter_lints 中是 lint，`flutter analyze` 以 WARNING 级别报告。`--no-fatal-warnings` 使 CI 对所有 lints 静默通过；本地 IDE 报警告但 CI 始终绿色，方向与 CLAUDE.md 描述的"hard gate"相反。
- 建议修法：CI 中也运行不加 `--no-fatal-warnings` 的 analyze；通过 `analyzer.errors` 配置仅降级已知大量违反的规则，而非全局关闭 fatal warnings。
- 置信度：medium（归 low：不产生直接功能损坏）

## 全局观察

工程基础设施整体设计思路清晰：patch sha256 校验、offline-check 闭环、pre-push 防悬垂指针、multi-arch matrix 均属少见的工程严谨度。主要风险集中在两阶段写入的原子性（F1/F2）和 ARM64 构建稳定性对 release 路径的单点影响（F7）。libsodium 交叉编译路径的完整性验证缺失（F6）是一个有现实攻击面的遗漏，建议与 F1/F2 一起优先处理。
