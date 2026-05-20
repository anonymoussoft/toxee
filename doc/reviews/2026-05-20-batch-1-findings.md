# Batch 1 — 核心混合架构（域 A + 域 P）findings

> Review 日期：2026-05-20
> 范围：`lib/main.dart`、`lib/bootstrap/`、`lib/runtime/`、`lib/util/app_bootstrap_coordinator.dart`、`lib/startup/`、`lib/auth/login_use_case.dart`、`lib/adapters/`、`lib/sdk_fake/`、`third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart`、HomePage 拆分文件群
> 配套：[功能清单](./2026-05-20-feature-inventory.md) · [Prompt 模板](./2026-05-20-review-prompts.md)

## 扫描范围与发现概览

扫描覆盖：`lib/main.dart`、`lib/bootstrap/`（全部）、`lib/runtime/session_runtime_coordinator.dart` + `tim_sdk_initializer.dart`、`lib/util/app_bootstrap_coordinator.dart`、`lib/startup/startup_session_use_case.dart`、`lib/auth/login_use_case.dart`、`lib/adapters/`（全部 5 个）、`lib/sdk_fake/fake_uikit_core.dart`、`lib/ui/home_page.dart` + `home_page_bootstrap.dart`、`third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart`，以及对应测试。

发现问题 7 条：1 条 high（`conversationStream`/`totalUnreadStream` 订阅跨会话泄漏）、2 条 medium（`TimSdkInitializer.then` 不等待、dedup 扫描对空 `conversationId` 的静默吞噬）、2 条 medium（`BootstrapNodesAdapter` 不实现 `getBootstrapNodeMode`、`BinaryReplacementHistoryHook.saveMessage` catch 块吞噬错误无日志）、另有 2 条 low 及 1 条 handoff note。

## Findings

### [high] `conversationStream` 和 `totalUnreadStream` 的订阅未被取消，跨会话泄漏

- 位置：`lib/ui/home_page_bootstrap.dart:561-565`
- 现象：`_initAfterSessionReady()` 中 `provider.conversationStream.listen(...)` 和 `provider.totalUnreadStream.listen(...)` 的返回值 `StreamSubscription` 被丢弃，没有赋给任何字段，也没有注册到 `_bag`。
- 风险：与跨域不变量 5（"多账户切换不能泄漏跨会话状态"）直接冲突。退出账户 → `FakeChatDataProvider.dispose()` 关闭底层 `StreamController`，已注册的 listen 回调成为悬挂 closure，持有旧 provider、旧服务的引用，下一次进入 HomePage 又新建同名订阅，导致两个 session 的数据事件同时驱动同一个 `UikitDataFacade`。`cancel_subscriptions` lint 规则也明确禁止此模式。
- 建议修法：在 `_HomePageState` 添加 `StreamSubscription<List<V2TimConversation>>? _convProviderSub` 和 `StreamSubscription<int>? _unreadProviderSub`，赋值后通过 `_bag.add` 注册取消。`getInitialConversations().then(...)` 也应改为 `unawaited` 并在错误路径记录日志。
- 置信度：high

### [high] `saveMessage` 的 `catch` 块完全静默，吞噬所有错误

- 位置：`third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart:184`
- 现象：`} catch (e) { // Silently handle errors }` — 磁盘配额满、JSON 解析失败、`MessageHistoryPersistence` 异常等都不产生任何日志输出。
- 风险：`BinaryReplacementHistoryHook` 是历史持久化的唯一覆盖点（binary-replacement 路径）。静默失败意味着消息静默丢失，且运维日志中没有任何信号，难以排查。违背项目"logger 需捕获所有有意义错误"的规范。
- 建议修法：改为 `catch (e, st) { logger?.logWarning('BinaryReplacementHistoryHook.saveMessage failed: $e\n$st'); }` 或至少 `print`。tim2tox fork 可以直接修改。
- 置信度：high

### [medium] `TimSdkInitializer.ensureInitialized().then(...)` 未 await，UIKit group/friend listener 可能在 platform 就绪前注册

- 位置：`lib/ui/home_page_bootstrap.dart:9-21`
- 现象：`TimSdkInitializer.ensureInitialized()` 以 `.then()` 而不是 `await` 调用，其后续代码（`initGroupListener()`、`initFriendListener()`）与下面的 `ChatDataProviderRegistry`、插件注册等并行推进。
- 风险：若 `TimSdkInitializer` 花费超过几帧完成，`initGroupListener` 会在 SDK 未初始化时注册，造成 UIKit group event 的 silent drop；`.catchError` 内的 `return` 并不中止 `_initAfterSessionReady()` 后续流程，即使 TIM init 失败，后续注册仍会继续，带来不一致状态。
- 建议修法：改为 `await TimSdkInitializer.ensureInitialized();`，然后顺序执行 `initGroupListener`/`initFriendListener`，并把错误抛出或至少阻止后续步骤。
- 置信度：high

### [medium] `BinaryReplacementHistoryHook.saveMessage` 在 `selfId` 为空时静默丢弃消息，但没有任何日志或指标

- 位置：`third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart:113`
- 现象：`if (capturedPersistence == null || capturedSelfId == null) return;` — `selfId` 为空字符串时也传递到 `MessageConverter.v2TimMessageToChatMessage(v2Msg, capturedSelfId)`，此时 `isSelf` 永远为 false。这与 M6 "deferred selfId" 窗口期相关：hook 安装时 selfId 为空，连接成功前收到的消息的 `isSelf` 会永久错误。
- 风险：在快速连接场景中（例如 LAN bootstrap），`connectionStatusStream` 触发 `updateSelfId` 的 one-shot listener 和首条消息到达之间存在竞争，可能造成自己发的消息显示为他人消息，反之亦然。
- 建议修法：在 `selfId.isEmpty` 情况下记录 warn 日志，并考虑暂存消息到队列待 `updateSelfId` 后重试，或至少在注释中明确边界。
- 置信度：medium

### [medium] `BootstrapNodesAdapter` 与 legacy 登录路径耦合错误，手动节点设置在无 toxId 路径被忽略

- 位置：`lib/adapters/bootstrap_adapter.dart`；对比 `third_party/tim2tox/dart/lib/interfaces/extended_preferences_service.dart:42`
- 现象：`BootstrapNodesAdapter` 实现 `BootstrapService`（三方法 `getBootstrapHost/Port/PublicKey`），但 `FfiChatService._loadAndApplySavedBootstrapNode()` 调用的是 `_prefs?.getBootstrapNodeMode()`（属于 `ExtendedPreferencesService`）。`startup_session_use_case.dart:96-101` 和 `login_use_case.dart:96-99` 的 legacy 路径使用 `BootstrapNodesAdapter(prefs)`，导致 mode 配置失效，行为退化为"总是 auto"。
- 风险：仅影响"没有 toxId"的旧账号登录路径（代码中仍存在并明确注释为 legacy）。用户在 manual 模式保存的节点会被静默忽略。
- 建议修法：legacy path 的 `FfiChatService` 构造也传入 `SharedPreferencesAdapter(prefs)`（带 accountPrefix），或完全移除 `BootstrapNodesAdapter` 合并到 `SharedPreferencesAdapter`。
- 置信度：medium

### [medium] `SessionRuntimeCoordinator.ensureInitialized` 并发竞争窗口

- 位置：`lib/runtime/session_runtime_coordinator.dart:45-58`
- 现象：`_state` 和 `_initializing` 是静态字段。并发锁基于 `_initializing != null`，但状态机检查是 `if (_state == started) return`，然后才检查 `_initializing`。`disposeRuntime()` 后两个调用者同时调用 `ensureInitialized()`，存在极短窗口可能都通过 started 检查并同时进入 `_initializing = completer.future`。
- 风险：账户切换时并发调用（`AppBootstrapCoordinator.boot` + `HomePage._initAfterSessionReady` 可能交叉）触发后会导致两个 `Tim2ToxSdkPlatform` 实例被创建，回调可能只注册在被覆盖的实例上。
- 建议修法：将 `_state = SessionRuntimeState.starting` 在进入互斥临界区前立即设置（在 `_initializing` 赋值之前），消除窗口。
- 置信度：medium

### [low] `home_page_bootstrap.dart` 中 `provider.getInitialConversations().then(...)` 的 unawaited Future 错误静默

- 位置：`lib/ui/home_page_bootstrap.dart:558-560`
- 现象：`.then` 内部抛出异常时会产生 unawaited future 错误，仅由 `PlatformDispatcher.onError` 捕获但无栈定位。`unawaited_futures` lint 会警告。
- 建议修法：`unawaited(provider.getInitialConversations().then(...).catchError((e, st) { AppLogger.logError(...); }));`
- 置信度：medium

### [low] `SharedPreferencesAdapter.clear()` 无 accountPrefix 时静默返回

- 位置：`lib/adapters/shared_prefs_adapter.dart:153-163`
- 现象：当 `_accountPrefix == null` 时直接 `return`（设计保护），但 `ExtendedPreferencesService.clear()` 接口无返回值，调用方无法感知操作被静默跳过。
- 风险：Tim2Tox 在无 accountPrefix 场景调用 `clear()`（例如 logout）会造成数据残留。
- 建议修法：至少加 `AppLogger.warn` 记录"refused clear() — no accountPrefix"，并评估是否应在 `initializeServiceForAccount` 始终传入 accountPrefix。
- 置信度：medium

## Handoff notes（跨 batch）

- `home_page_bootstrap.dart` 中的 `_friendsSub`（订阅 `FakeIM.topicContacts`）和 `_appsSub`（订阅 `FakeIM.topicFriendApps`）的 listener 内部进行了多个 `await`，但这些 async listener 整体是 `void` 回调，任何异常都不会被 `_bag` 取消机制捕获 — 请 **Batch 2** 关注。

## 全局观察

混合架构的最高风险不在于设计本身（已相当完备），而在于"事后注册的订阅没有反向注册到 `_bag`"这类具体实现遗漏（conversationStream/totalUnreadStream）。BinaryReplacementHistoryHook 的 catch 吞噬模式和 TimSdkInitializer 的 `.then` 并行模式是另外两个需要立即修复的点。静态字段（`_state`、`_hookInstalled`）在并发场景下的竞争窗口虽然概率低，但后果不对称（平台实例替换），值得加固。
