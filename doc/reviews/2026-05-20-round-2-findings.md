# Round-2 Findings — Fix agents 自身引入的新问题 + 用户人工 review 补充

> 日期：2026-05-20（第二轮）
> 来源：6 个 reviewer agent 对 Round-1 fix 的对照检查 + 用户人工 review 补充 4 条
> 用途：作为 Round-2 并发修复的输入

## High（block-merge）

### R2-1 `_failAccept` 在 `accept()` 成功后发 `reject()` — 信令协议违规，呼叫方僵尸状态

- 位置：`third_party/tim2tox/dart/lib/service/call_bridge_service.dart:227-262`
- 现象：`acceptInvitation` 中 `_sdkPlatform.accept()` `code == 0` 后，若 `friendNumber == null`（line 234）或 `answerCall` 失败（line 246）会走 `_failAccept`，里面发 `reject()`。但 `accept()` 成功已触发对端 `onInviteeAccepted`（line 123），对端转 `inCall` 状态。`reject()` 是 pre-accept 动词，post-accept 协议层不保证回收 → 对端可能停留在"已接通/仍在呼叫"半开状态。
- 建议修法：区分 `_sdkPlatform.accept()` 失败（line 228 `code != 0`）与 post-accept 失败（line 233/245）两种路径。后者改用 `_sdkPlatform.cancel(...)` 或 `endCall` 等 post-accept 拆机动词；或本地继续走 `endCall` 完整流程让对端看到"已接通但立即挂断"。emit 的 `endReason` 应该是 `'hangup'` 而非 `'cancel'`。
- 归属：Fix-Y（third_party/tim2tox）

### R2-2 CI 没有 submodule 远端可达性检查的替代步骤 — dangling pointer 能进主分支

- 位置：`tool/verify_submodule_remote.sh:27-30`；`.github/workflows/` 全部
- 现象：脚本在 `CI=true` 时 `exit 0` 跳过，注释说"dedicated workflow step"会做，但实际 `.github/workflows/` 中没有任何 step 调用 `verify_submodule_remote.sh` 或等价检查。`--no-verify`、GitHub UI merge、bot push 均能绕过本地 hook → 主分支可能进入 dangling submodule SHA。
- 建议修法：在 `.github/workflows/analyze.yml`（或新建 `submodule_verify.yml`）加 step 显式执行 `bash tool/verify_submodule_remote.sh` 但**先 unset CI=true 或调用一个不走 CI 短路的入口**。最干净的做法：把脚本拆成"核心逻辑函数"+"hook 包装器"，CI 走核心逻辑（仍带超时），hook 走包装器（带 CI=true 短路）。或者保留现状但在 CI step 中 `env: CI=` 临时清掉，跑完再恢复。
- 归属：Fix-U（CI/工具）

### R2-3 libsodium 1.0.20 tarball SHA-256 需人工核对

- 位置：`tool/ci/build_tim2tox.sh:13`
- 现象：`LIBSODIUM_1_0_20_SHA256="ebb65ef6ca439333c2bb41a0c1990587288da07f6c7fd07cb3a18cc18d30ce19"`。Reviewer 印象 jedisct1 release 的 .tar.gz SHA 前缀是 `6d28f47e`，而该常量是 `ebb65ef6`。若不一致，所有 Android/iOS CI 一律 hard-fail。
- 建议修法：在本地或 CI 上执行 `curl -L https://download.libsodium.org/libsodium/releases/libsodium-1.0.20.tar.gz | shasum -a 256` 核对 → 若不一致则替换常量。注意：jedisct1 同时发布了 .tar.gz 和 -stable.tar.gz、msvc.zip 等多种格式，每个 SHA 不同；要核对的是脚本里 `DOWNLOAD_URL`/`download_file_once` 实际拉的那个文件。
- 归属：Fix-U

### R2-4 下载目录热更新 callback 未挂接 — 功能等于未修

- 位置：`lib/ui/settings/settings_page_build.dart:478`
- 现象：`global_settings_section.dart` 定义并调用了 `widget.onDownloadsConfigChanged?.call()`，但 `settings_page_build.dart` 处的 `GlobalSettingsSection(...)` 实例化没有传入该回调，因 `?.call()` 是 null-safe 静默跳过 → 下载目录改动仍需重启才生效。
- 建议修法：在 `settings_page_build.dart` 第 478 行调用补上 `onDownloadsConfigChanged: () => widget.service.reloadDownloadsConfig()`（如 service 没有该方法则 dispatch 到内部 reload 逻辑，或调用 `_ffi.refreshFileTransferDirectory()` 等价方法）。
- 归属：Fix-V（UI）

### R2-5 `AccountSwitcher.switchAccount` 在 boot 前更新 `lastLoginTime` — 同样的 bug 兄弟路径漏修

- 位置：`lib/util/account_switcher.dart:63`
- 现象：Round-1 修了 `LoginUseCase` 与 `LoginPage` 的 boot-后再 touch 时序，但 `AccountSwitcher.switchAccount` 仍调用默认 `addAccount(...)`（`updateLastLogin: true`），且在 `initializeServiceForAccount` 成功后立即调用，没有等待 `AppBootstrapCoordinator.boot()`。
- 建议修法：`AccountSwitcher.switchAccount` 中 `addAccount` 改 `updateLastLogin: false`；在调用方（HomePage._initAfterSessionReady 完成后）触发 `Prefs.touchAccountLoginTime`。或在 `account_switcher.dart` 内对返回的 service 自己调用 `boot()`，然后才 `touchAccountLoginTime`。
- 归属：Fix-W（账户/网络）

### R2-6 `fake_provider.dart` 6 处 `print()` 调用违反 `avoid_print`

- 位置：`lib/sdk_fake/fake_provider.dart` L137、L347、L364、L390、L397、L400
- 现象：Round-1 在该文件新增的代码段使用了裸 `print()`，违反 `analysis_options.yaml` 中的 `avoid_print: true`（lint 级别 warning，CI 当前 `--no-fatal-warnings` 不阻塞但会出现在 advisory analyze 步骤）。
- 建议修法：全部替换为 `AppLogger.debug('[FakeChatDataProvider] ...')`，与文件中其他日志风格一致。
- 归属：Fix-X

### R2-7 `V2TimConversationListener` 新增但 dispose 未 `removeConversationListener` — 又一处跨会话 listener 泄漏

- 位置：`lib/sdk_fake/fake_provider.dart:368-402`（构造函数内 `Future.delayed(500ms, ...)` 注册）
- 现象：`addConversationListener` 向 UIKit SDK 单例注册了 `onConversationChanged` / `onConversationDeleted`，但 `dispose()`（L840-850）没有对应的 `removeConversationListener`。多账户切换后 listener 累积。
- 建议修法：构造函数保存 listener 引用 `_sdkConvListener = V2TimConversationListener(...)`，`dispose()` 中调用 `TencentCloudChat.instance.chatSDKInstance.manager.getConversationManager().removeConversationListener(_sdkConvListener)`。
- 归属：Fix-X

### R2-8 `_doSyncPlatformEffectsForState` 不处理 `reconnecting` → iOS reconnect 期间音频会话被关

- 位置：`lib/call/call_service_manager.dart:604-618`
- 现象：`CallEffectsListener._handleCallStateChanged` 在 ringing/inCall/reconnecting 都会触发 `syncPlatformEffectsForState`，但 `_doSyncPlatformEffectsForState` 仅对 `ringing || inCall` 调 `activateSession`，对 `reconnecting` fallthrough 到 `deactivateSession()`。8s 重连窗口内 iOS 音频会话被关闭，恢复时才重激活 → 通话音频中断。
- 建议修法：line 609 把条件改为 `state == ringing || state == inCall || state == reconnecting`，并沿用上一已知 `preferSpeaker` 值或读 `_callState.mode`。
- 归属：Fix-Z

### R2-9 3 个测试文件 `persistence.dispose()` 未 await — 测试 flaky + lint

- 位置：
  - `test/message_history_backup_cleanup_test.dart:79`
  - `test/tim2tox_history_cache_single_source_test.dart:77`
  - `test/message_history_persistence_perf_test.dart:199, 219`
- 现象：Round-1 把 `MessageHistoryPersistence.dispose()` 改为 async，但三个测试文件仍以 sync 形式调用（也违反 `unawaited_futures` lint）。`flushPendingSaves` 在测试 tempDir 清理时仍 in-flight，可能"file not found"或目录写入失败。
- 建议修法：三处都改 `await persistence.dispose();`。
- 归属：Fix-Y（测试在主仓 test/，不在 third_party，但与 tim2tox dispose 接口变更耦合，由 Fix-Y 一并修）

## Medium（应同 PR 修）

### R2-10 `SessionRuntimeCoordinator._state == starting` 入口未守 — 并发窗口未完全消除

- 位置：`lib/runtime/session_runtime_coordinator.dart:46-65`
- 现象：`ensureInitialized` 仅 `_state == started` 短路 + `_initializing != null` 等待。`_state = starting` 与 `_initializing = completer.future` 之间仍有微任务调度窗口，并发调用者可能都通过两个检查，建立第二个 `Tim2ToxSdkPlatform` 实例并覆盖 `_initializing`，第一个调用者的 `finally` 清掉 future 后第二个调用者永远不被唤醒。
- 建议修法：在 `_state == started` 检查之后立即补：
  ```dart
  if (_state == SessionRuntimeState.starting) {
    if (_initializing != null) {
      await _initializing!;
    }
    return;
  }
  ```
  把 `_state = starting` 设置时机移到原子的合适位置。
- 归属：Fix-Z

### R2-11 `_qualityEstimator.observe*` 在 reconnecting 跳过 `return` 之前调用 — estimator 被脏数据污染

- 位置：`lib/call/call_service_manager.dart:438, 449`
- 现象：`_onAudioBitrateChanged` / `_onVideoBitrateChanged` 先调 `_qualityEstimator.observeAudioBitrate` / `observeVideoBitrate`，再判 reconnecting 才 `return`。reconnecting 期间的零/低 bitrate 被写入 estimator，`reset()` 后又被脏值替换，`clearReconnecting()` 恢复 `inCall` 后 UI 质量指示器短暂显示错误值。
- 建议修法：在 observe* 调用之前判断 `_callState.state == CallUIState.reconnecting`，是则 return；observe* 仅在非 reconnecting 时执行。
- 归属：Fix-Z

### R2-12 lastLoginTime key 不一致 + auto-login 路径 0 更新

- 位置：`lib/ui/login_page.dart:372`；`lib/startup/startup_session_use_case.dart:107`
- 现象：
  1. LoginUseCase 用 `toxIdForLogin` 作为 account 列表 key（comment 明示"service.selfId may differ in format"），但 `login_page.dart:372` 直接传 `service.selfId` 给 `touchAccountLoginTime` → 格式不一致时找不到正确条目。
  2. `StartupSessionUseCase`（auto-login 路径）在 `boot` 完成后没有调用 `touchAccountLoginTime` → auto-login 用户的"最近登录"永远停更。
- 建议修法：
  - 方案 A：让 `LoginUseCase` 把 `toxIdForLogin` 一并返回给调用方（在 `LoginSuccess` 类型上加字段），`login_page.dart` 用返回值而不是 `service.selfId`。
  - 方案 B：让 `Prefs.touchAccountLoginTime(...)` 内部用与 `getAccountByToxId` 一致的 fuzzy 匹配（按 normalize/前缀），不要求严格相等。
  - 在 `StartupSessionUseCase` line 107 之后（auto-login 成功的 `StartupOpenHome` 返回前），补 `await Prefs.touchAccountLoginTime(currentService.selfId)`（用方案 B 后这一行就够了）。
- 归属：Fix-W

### R2-13 `Prefs.addAccount` 新账户分支无条件 set `lastLoginTime` — 与 `updateLastLogin: false` 契约矛盾

- 位置：`lib/util/prefs.dart:1573-1579`
- 现象：`updateLastLogin: false` 仅守 update 分支（已有账户）。新账户插入分支无条件 `lastLoginTime = DateTime.now().toIso8601String()`。`LoginUseCase` legacy path 用 `updateLastLogin: false` 期望"don't bump"，但对刚新建的 legacy 账户仍会立即 stamp。
- 建议修法：新账户分支也读 `updateLastLogin` 参数：若 false 则 `lastLoginTime: null` 或省略字段，由后续 `touchAccountLoginTime` 在 boot 成功后填。
- 归属：Fix-W

### R2-14 `add_group_dialog` validator 放宽到 32 字符 — invalid ID 仍被传到 C++

- 位置：`lib/ui/add_group_dialog.dart:305-329`
- 现象：注释说"conference IDs 比 64 短"，但 Tox 协议中 `CONFERENCE_ID_SIZE = 32 bytes = 64 hex chars`，与 public group chat_id 同长。`< 32` 的下限会接受 32-63 字符的半截 hex ID。
- 建议修法：把 `< 32` 改为 `!= 64`；或拆 conference / public 两分支（如果未来真有不同长度），目前两者都是 64 hex，统一一条更简洁。
- 归属：Fix-V

### R2-15 `_onClearChatHistory` 用 `deleteConversation` — 顺手清掉 pinned 状态

- 位置：`lib/ui/group/group_builder_override.dart:665-673`
- 现象：用户意图是"清群聊历史"，但 `FakeConversationManager.deleteConversation('group_$gid')` 在 line 432-434 显式 `_pinned.remove(pinnedKey)` 并写回 Prefs → 置顶状态丢失。
- 建议修法：改用直接对内层 API 的调用：`FfiChatService.clearGroupHistory(gid)` + `FakeUIKit.instance.messageProvider?.clearMessageBuffer('group_$gid')` + `FakeUIKit.instance.im?.refreshConversations()`，不调 deleteConversation。或者在 FakeConversationManager 加 `clearHistoryWithoutDelete(conversationID)` 公开方法把"清历史不删会话不解 pinned"的语义独立出来。
- 归属：Fix-V

### R2-16 `TimSdkInitializer` 失败时 `return` 让 HomePage 卡死无降级

- 位置：`lib/ui/home_page_bootstrap.dart:9-14`
- 现象：Round-1 把 `.then` 改 `await`+`try/catch`，catch 后 `return`。但 `_initAfterSessionReady` 后续的 provider/registry/插件/listener/UI 状态全部跳过 → HomePage 黑屏，用户唯一出路是强杀。
- 建议修法：catch 块不要直接 `return`；调用 `UikitDataFacade.updateInitializedStatus(true)` + 一个错误状态标志，或导航到 `UpgradeRequiredScreen` 等价的错误页提示用户重启或导出账户。
- 归属：Fix-X

---

## 文件归属（用于 Round-2 并发修复）

| Agent | 负责 R2 编号 | 文件 |
|---|---|---|
| Fix-X round 2 | R2-6, R2-7, R2-16 | `lib/sdk_fake/fake_provider.dart`、`lib/ui/home_page_bootstrap.dart` |
| Fix-Y round 2 | R2-1, R2-9 | `third_party/tim2tox/dart/lib/service/call_bridge_service.dart`、`test/message_history_backup_cleanup_test.dart`、`test/tim2tox_history_cache_single_source_test.dart`、`test/message_history_persistence_perf_test.dart` |
| Fix-Z round 2 | R2-8, R2-10, R2-11 | `lib/call/call_service_manager.dart`、`lib/runtime/session_runtime_coordinator.dart` |
| Fix-W round 2 | R2-5, R2-12, R2-13 | `lib/util/account_switcher.dart`、`lib/util/prefs.dart`、`lib/ui/login_page.dart`、`lib/startup/startup_session_use_case.dart`、`lib/auth/login_use_case.dart` |
| Fix-V round 2 | R2-4, R2-14, R2-15 | `lib/ui/settings/settings_page_build.dart`、`lib/ui/add_group_dialog.dart`、`lib/ui/group/group_builder_override.dart` |
| Fix-U round 2 | R2-2, R2-3 | `.github/workflows/analyze.yml`（或新建）、`tool/verify_submodule_remote.sh`、`tool/ci/build_tim2tox.sh` |
