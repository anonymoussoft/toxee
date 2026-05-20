# Batch 2 — 消息域（域 D + E + F + G + H + I）findings

> Review 日期：2026-05-20
> 范围：消息收发、历史持久化、会话、媒体/文件、好友、群组
> 配套：[功能清单](./2026-05-20-feature-inventory.md) · [Prompt 模板](./2026-05-20-review-prompts.md)

## 扫描范围与发现概览

扫描覆盖 Batch 2 全部一级文件：`message_history_persistence.dart`、`binary_replacement_history_hook.dart`、`fake_msg_provider*.dart`（含三个 part 文件）、`fake_managers.dart`、`fake_im.dart`、`fake_provider.dart`、`add_friend_dialog.dart`、`add_group_dialog.dart`、`group_builder_override.dart`、`prefs.dart` 相关段落，并沿调用链跟踪到 `tim2tox_sdk_platform.dart`、`ffi_chat_service.dart` 中的 `clearGroupHistory/clearC2CHistory`、`FriendAssetCleanup`。共发现 **critical 1 条、high 4 条、medium 5 条**，集中在：退群历史未清理、`clearGroupHistoryMessage` 双路不协调、防抖窗口丢消息、未读计数时间漂移、失败消息缓存跨会话污染、流订阅泄漏。

## Critical

### [critical] 退群/解散群后本地历史永久残留 — quitGroup 路径遗漏清理

- 位置：`lib/ui/group/group_builder_override.dart:681-694`（`_handleQuitGroup`）；对照路径 `lib/sdk_fake/fake_managers.dart:410-460`（`deleteConversation`）
- 现象：`_handleQuitGroup` 只调用 UIKit 的 `groupSDK.quitGroup` / `dismissGroup`，成功后仅做路由弹出。它不调用 `addQuitGroup(gid)`，也不调用 `clearGroupHistory`。`deleteConversation` 才会同时清理历史并写 quitGroups，但两个 UI 入口（群设置页"退出群"和"解散群"）都走 `_handleQuitGroup` 而不是 `deleteConversation`。
- 风险：
  1. 用户退群后，`Prefs.getQuitGroups()` 不包含该 gid，导致 `loadAllHistories` 不过滤、`getConversationList` 继续展示该群、未读计数继续累加——典型"幽灵群"现象。
  2. C++ 侧 `groupQuitNotification` 回调确实会经 `Tim2ToxSdkPlatform` 调用 `addQuitGroup`（`tim2tox_sdk_platform.dart:3958`），但这依赖 Platform 路径已就绪且回调被正确分发——在离线重启或 Platform 未设置时此回调可能错过。
  3. 违反跨域不变量 5（多账户切换/会话清理）。
- 建议修法：在 `_handleQuitGroup` 成功分支主动调用 `Prefs.addQuitGroup(gid)` 并通过 `FakeConversationManager.deleteConversation('group_$gid')` 清理。修改范围：**toxee only**。
- 置信度：high

## High

### [high] `clearGroupHistoryMessage` 双路不协调：UI 清历史仅走 UIKit SDK 路径，持久化层可能未清

- 位置：`lib/ui/group/group_builder_override.dart:652-658`（`_onClearChatHistory`）
- 现象：`_onClearChatHistory` 调用 `TencentCloudChat.instance.chatSDKInstance.groupSDK.clearGroupHistoryMessage(...)` 并在 `code == 0` 时调 UIKit dataInstance 清视图缓存。这是二进制替换路径（走 C++）。但 `MessageHistoryPersistence` 中的 JSON 文件只能通过 Platform 路径的 `clearHistoryMessage` 回调才能清除。若回调分发失败（如时序、Platform 未安装），群历史 JSON 文件将永留，下次冷启动历史复活。
- 建议修法：在 `code == 0` 分支额外调用 `FakeConversationManager.deleteConversation('group_$groupID')` 或直接 `ffi.clearGroupHistory(gid)`。修改范围：**toxee only**。
- 置信度：high

### [high] 200ms 防抖丢失最后一批消息（应用意外终止时）

- 位置：`third_party/tim2tox/dart/lib/utils/message_history_persistence.dart:869-888`（`_scheduleDebouncedSave`）；相关 `flushPendingSaves`（:893）；`dispose`（:916）
- 现象：`appendHistory` 对每次写操作设置 200ms 防抖。`dispose()` 只取消定时器而不刷盘，`flushPendingSaves()` 需调用方主动调用。若应用进程被 OS 强杀（crash、OOM、强退）或在最后一批消息写入后 200ms 内 `dispose()` 没有配对 `flushPendingSaves()`，这批消息永久丢失。
- 风险：Tox P2P 无服务端补发，历史丢失不可恢复。高频聊天最容易命中窗口。
- 建议修法：teardown/logout 与 `runZonedGuarded` onError fallback 中调用 `flushPendingSaves()` 并 `await` 完成；检查 `dispose()` 调用方先 `await flushPendingSaves()`。修改范围：**Tim2Tox 上游** + **toxee** teardown 序列。
- 置信度：high

### [high] `FakeChatMessageProvider` 的多个流订阅在 `dispose()` 后仍活跃（泄漏）

- 位置：`lib/sdk_fake/fake_msg_provider.dart:86-140`（构造函数内 `ffi.progressUpdates.listen`×2、`ffi.fileRequests.listen`、`ffi.avatarUpdated.listen`）
- 现象：构造函数中对四个流的 `listen` 调用未将 `StreamSubscription` 存储到实例字段。`dispose()`（:515）只取消了 `_sub`，四个流的订阅句柄均被丢弃。
- 风险：logout → re-login 后旧实例的回调仍然活跃，写入 `_buffers`、`_sendProgressCtrl`、`_cachedFriendAvatars` — 上一会话数据。违反不变量 5。
- 建议修法：将四个 `listen` 返回值保存为 `StreamSubscription?` 实例字段，`dispose()` 统一取消。修改范围：**toxee only**。
- 置信度：high

### [high] `_failedMsgIDsCache` 跨会话污染：logout 时缓存未清零

- 位置：`lib/sdk_fake/fake_msg_provider.dart:71-75`；`fake_msg_provider_routing.dart:624-640`
- 现象：`_failedMsgIDsCache` 是实例级字段，`dispose()` 未清零。`_mapMsgWithFailedCheck` 刷新缓存时读取 `Prefs.getCurrentAccountToxId()` 是异步的；若 `currentToxId` 在切换中途读到旧账户的 toxId，缓存被旧数据填充，在新账户下误判消息为 SEND_FAIL。
- 建议修法：`dispose()` 中显式清零 `_failedMsgIDsCache = null; _failedCacheDirty = true;`。`_mapMsgWithFailedCheck` 应与当前 FfiChatService 实例绑定而非依赖全局 Prefs。修改范围：**toxee only**。
- 置信度：high

## Medium

### [medium] 未读计数基于 `lastViewTimestamp` 存在系统时间回拨和跨设备时间漂移风险

- 位置：`third_party/tim2tox/dart/lib/utils/message_history_persistence.dart:1371-1393` 和 :1401
- 现象：比较 `msg.timestamp.millisecondsSinceEpoch > lastViewTimestamp`。`lastViewTimestamp` 写入用 `DateTime.now()` 本地时钟，消息 `timestamp` 来自对端 Tox 节点时钟。时钟偏差可能导致已读消息重新被计未读（角标虚高不归零），或新消息早于 lastViewTimestamp 永远不被计数。
- 建议修法：持久化 `lastViewTimestamp` 时使用消息列表最高时间戳而非当前设备时钟；或同时持久化已读 msgID 集合作为备用机制。修改范围：**Tim2Tox 上游**。
- 置信度：medium

### [medium] `FakeChatDataProvider` 构造函数中匿名 fire-and-forget async IIFE 订阅未被 `dispose()` 取消

- 位置：`lib/sdk_fake/fake_provider.dart:170-329`
- 现象：构造函数内三处 `FakeUIKit.instance.eventBusInstance.on<...>(...).listen(...)` 调用（`FakeIM.topicMessage`、`FakeFriendDeleted`、`FakeGroupDeleted`）的 `StreamSubscription` 没有存储，`dispose()`（:835-843）无法取消。
- 风险：账户切换后旧 `FakeChatDataProvider` 三个监听器继续响应 bus 事件，向已 close 的 controller 写入触发 `StateError`，或写入 `_convMap`（旧账户状态泄漏）。
- 建议修法：三个 `listen()` 存为字段并在 `dispose()` 取消。另检查 `_scheduleConvListEmit` 是否对 `_convCtrl.isClosed` 做保护。修改范围：**toxee only**。
- 置信度：high（仅在 logout/re-login 触发，降 medium）

### [medium] `deleteConversation` 删除会话后 `FakeChatMessageProvider._buffers` 未同步清除

- 位置：`lib/sdk_fake/fake_managers.dart:410-459`；`lib/sdk_fake/fake_msg_provider.dart:501-513`（`clearMessageBuffer`）
- 现象：`deleteConversation` 清持久化、去 pinned、调 `im.refreshConversations()`，但未通知 `FakeChatMessageProvider` 清 `_buffers[conversationID]` 和 `_historyReloadGuards[conv]`。`clearMessageBuffer` 方法存在但未被调用。
- 风险：用户删除会话后再次打开（如通过通知），仍展示已删除的历史消息约 3 秒直到 TTL 过期。
- 建议修法：`deleteConversation` 成功后调 `FakeUIKit.instance.chatMsgProvider?.clearMessageBuffer(conversationID)`。修改范围：**toxee only**。
- 置信度：medium

### [medium] `FakeIM._seedHistory` 重复 emit 导致 msgID 不一致造成视觉重复

- 位置：`lib/sdk_fake/fake_im.dart:701-738`
- 现象：`_seedHistory` 用 `'${h.timestamp.millisecondsSinceEpoch}_${h.fromUserId}'` 作为 msgID（非 `h.msgID`），而真实 msgID 可能不同。`FakeChatMessageProvider._onTopicMessage` 用 msgID 去重时无法命中 `existingIndex`，把历史当新消息追加。文件消息尤其明显。
- 建议修法：优先使用 `h.msgID ?? '${h.timestamp...}_${h.fromUserId}'`，与 `FakeMessageManager.getHistory`（:551）保持一致。修改范围：**toxee only**。
- 置信度：medium

### [medium] `add_group_dialog.dart` join group 入口缺少群 ID 格式前置校验

- 位置：`lib/ui/add_group_dialog.dart:305-311`
- 现象：join 表单 validator 仅检查非空，不验证群 ID 格式。对比 `AddFriendDialog` 对 Tox ID 有 64/76 字符 + 十六进制校验。public group chat_id 是 64 字符 hex，conference 不同前缀。
- 风险：粘贴格式错误的群 ID 直接发到 `joinGroup`，错误信息暴露 C++ 原始字符串；误输入好友 Tox ID 也无警告。
- 建议修法：validator 增加基本格式检查 — 非空、合法十六进制、public group 最小 64 字符，输出本地化错误信息。修改范围：**toxee only**。
- 置信度：medium

## 全局观察

消息域的核心不变量（历史单一事实源 + 双路不重复）在稳态下基本成立，但"退出/清除"路径存在系统性漏洞：退群走的是二进制替换路径（UIKit SDK），清历史依赖 C++ 回调；而真正可靠的清理逻辑只在 Platform 路径（`deleteConversation`）中。建议统一"退出=清理"的入口到 `FakeConversationManager.deleteConversation` 或等价的协调点，而不是让 C++ 回调承担唯一兜底职责。流订阅泄漏问题集中在 `FakeChatMessageProvider` 和 `FakeChatDataProvider` 的构造函数，建议增加对应的 `cancel_subscriptions` lint 覆盖这两个文件。
