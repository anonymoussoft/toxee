# Batch 3 — 通话与通知（域 J + K）findings

> Review 日期：2026-05-20
> 范围：`lib/call/` 全部、`lib/notifications/` 全部、`third_party/tim2tox/dart/lib/service/{call_bridge_service,tuicallkit_adapter,call_av_backend}.dart`、相关测试
> 配套：[功能清单](./2026-05-20-feature-inventory.md) · [Prompt 模板](./2026-05-20-review-prompts.md)

## 扫描范围与发现概览

扫描了 `lib/call/` 全部 23 个文件、`lib/notifications/` 3 个文件、`third_party/tim2tox/dart/lib/service/call_bridge_service.dart`、`call_av_backend.dart`，以及测试文件 `test/call_*.dart`（14 个）。主要关注点：信令/ToxAV 状态机（含 8s reconnecting）、AudioHandler/VideoHandler capture 配对、CallEffectsListener 副作用释放、铃声 start/stop 全路径、未接来电历史 endReason 区分、`toggleSpeaker` 是否真的影响底层、CodecProfile 滞回、通知 inbox/deep-link、BadgeService 切账户清零。

发现 10 条有效 finding。最严重的是 `toggleSpeaker` 完全不影响底层音频路由，以及信令侧 `ended` 回调 `endReason` 全部折叠为 `cancel` 导致未接来电历史区分失效。

## High

### [high] F-1：`toggleSpeaker` 只改 UI 状态，底层音频路由从不切换 — UI 侧 / 副作用侧

- 位置：`lib/call/call_state_notifier.dart:149-152` 与 `lib/call/call_service_manager.dart:762-780`
- 现象：`CallStateNotifier.toggleSpeaker()` 仅翻转 `_isSpeakerOn` 并通知 UI。`CallServiceManager` 中 `toggleMute()` / `toggleVideo()` 都会下调 FFI（`_avService?.muteAudio` / `_avService?.muteVideo`），但没有任何代码在 `isSpeakerOn` 变化时调用 `_callAudioPlatform.selectRoute(...)` 或 `activateSession(preferSpeaker: ...)`。`InCallManager` 接口中也没有 `toggleSpeaker` 方法。
- 风险：用户点击扬声器按钮后图标变化但耳机/扬声器不切换，通话音频始终走默认路由（iOS 耳机模式），功能完全不可用。
- 建议修法：在 `InCallManager` 补充 `Future<void> toggleSpeaker()`；`CallServiceManager` 实现中读 `_callState.isSpeakerOn` 新值，调用 `_callAudioPlatform.activateSession(preferSpeaker: newValue)` 或 `selectRoute` 切到扬声器路由。
- 置信度：high

### [high] F-2：`endReason` 全部折叠为 `'cancel'` — 信令侧

- 位置：`lib/call/call_service_manager.dart:311-320`
- 现象：`CallBridgeService` 把 `onInvitationCancelled`、`onInviteeRejected`、`onInvitationTimeout` 都映射为同一个 `CallState.ended` 回调，无终止原因字段。`CallServiceManager` 无法区分——"对方拒接"、"超时"、"对方取消"都写成 `'cancel'`，只有"挂断中途"写 `'hangup'`。spec 要求是 `'reject|hangup|timeout|cancel'` 四档。
- 风险：未接来电历史 `endReason` 永远是 `'cancel'`，用户无法区分"主叫取消"和"被叫拒接"或"超时"。
- 建议修法：`CallBridgeService` 三个回调分别触发不同枚举值或扩展 `onCallStateChanged` 签名增加可选 `reason`。
- 置信度：high

### [high] F-3：`onInvitationCancelled`/`onInvitationTimeout` 无条件调用 `endCall`，即便 ToxAV 从未 answer — 信令侧 / ToxAV 侧

- 位置：`third_party/tim2tox/dart/lib/service/call_bridge_service.dart:91-100` 和 :145-157
- 现象：来电被取消或超时时，两个回调都在 `callInfo.friendNumber != null` 时直接调用 `_avService.endCall(friendNumber)`。但 callee 没有 `answerCall`（ToxAV 从未接入），此时 `toxav_call_control(CANCEL)` 行为由底层实现决定，可能静默失败或触发错误日志；`endCall` 返回 `false` 桥层没检查，`_activeCalls` 被 `remove` 后看似已结束，但 ToxAV 资源是否真清理取决于实现。
- 建议修法：仅当 `callInfo.state == ringing || inCall` 时才调用 `endCall`；或在 `ToxAVService.endCall` 内部做 idempotent guard。
- 置信度：high

### [high] F-4：`reconnecting` 状态下 `_qualityEstimator` 继续更新，可能在恢复后发出"虚假降级"信号 — ToxAV 侧

- 位置：`lib/call/call_service_manager.dart:425-432`（`_onAudioBitrateChanged` / `_onVideoBitrateChanged`），搭配 `call_quality_estimator.dart`
- 现象：`markReconnecting()` 后 `_qualityEstimator` 没有被 `reset()` 也没有暂停。ToxAV bitrate 回调仍调用 `_onAudioBitrateChanged` / `_onVideoBitrateChanged`，把连接中断时的极低 bitrate 写入 estimator；更严重的是 `_applyPeerSuggestedProfile` 在 reconnecting 期间被触发，可能将 `_activeProfile` 和 `setAudioBitRate/setVideoBitRate` 降到最低档，恢复后不会自动回升。
- 建议修法：`markReconnecting()` 暂停 estimator（新增 `suspend()`/`resume()`），或调用 `reset()`；reconnecting 状态下跳过 `_applyPeerSuggestedProfile`。
- 置信度：high

## Medium

### [medium] F-5：`_onOutgoingCallInitiated` 在线检查与权限检查之间的竞态 — 信令侧 / UI 侧

- 位置：`lib/call/call_service_manager.dart:244-279`
- 现象：`startRinging` → `await _isFriendOnline` → `if offline: hangUp()` → 再 `if (state==ringing && inviteID==inviteID): _ensurePermissionsForCurrentMode()`。如果 `hangUp()` 在 `_isFriendOnline` 的 await 期间已调用，状态变成 `ended`，2s 后 `_endedResetTimer` 把 `_inviteID` 清为 `null`；但第二个 `if` 的 guard 仅检查 `_callState.inviteID == inviteID`（在 2s 窗口内未清零），权限请求仍发起；完成后 `rejectCall()` 向非 ringing 状态发出 reject 记录。
- 建议修法：补充 `_callState.state == CallUIState.ringing` 条件；或将在线检查与权限检查合并为单步骤。
- 置信度：high（路径可达）

### [medium] F-6：`CallWakePolicy.shouldKeepScreenAwake` 不包含 `reconnecting` — 副作用侧

- 位置：`lib/call/call_effects_listener.dart:73-87`；`CallWakePolicy:15-17`
- 现象：仅覆盖 `ringing` 和 `inCall`，不包含 `reconnecting`。8s grace 窗口内连接正在恢复时屏幕会关闭，而通话 UI 仍显示 "Reconnecting…"。
- 风险：用户误以为通话已结束。
- 建议修法：扩展为 `state == ringing || inCall || reconnecting`，同步更新 `call_effects_policy_test.dart`。
- 置信度：high

### [medium] F-7：`RingtonePlayer.stop()` 异常路径下 `_playing` 不重置，铃声卡死 — 副作用侧

- 位置：`lib/call/ringtone_player.dart:19`
- 现象：`stop()` 只在 `!_playing` 时 early-return；如果 `_player.stop()` 抛异常，`_playing` 不会被设为 `false`（`catch` 里只 warn 但没重置 flag）。再次来电时 `start()` 因 `_playing==true` 直接跳过，铃声永远不响。
- 建议修法：`stop()` 的 catch 块也设置 `_playing = false`：`catch (e) { _playing = false; AppLogger.warn(...); }`。
- 置信度：high

### [medium] F-8：`NotificationService` 切账户时 inbox state 不清零，旧账户消息串台 — 副作用侧

- 位置：`lib/notifications/notification_service.dart:79-85`；`disposeRuntime()` 在 `lib/runtime/session_runtime_coordinator.dart:122-152`
- 现象：`disposeRuntime()` 调用了 `BadgeService.instance.dispose()` 和 `NotificationMessageListener.disposeAndReset()`，但没调用 `NotificationService.instance.cancelAll()`，也没清理 `_grouped`、`_conversationIdHashCache`。切账户后旧账户 inbox state 留存，新消息被 append 到旧 inbox 行；`_conversationIdHashCache` 的 ID 映射不清零导致通知 ID 冲突。
- 建议修法：`disposeRuntime()` 加 `await NotificationService.instance.cancelAll()`；`NotificationService` 新增 `resetSessionState()` 清零 `_grouped`、`_conversationIdHashCache`，在 logout/switch 调用。
- 置信度：high

### [medium] F-9：`acceptInvitation` 在 `friendNumber == null` 时 `_activeCalls` 永久泄漏 — 信令侧

- 位置：`third_party/tim2tox/dart/lib/service/call_bridge_service.dart:192-213`
- 现象：`friendNumber` 无法解析（返回 `0xFFFFFFFF` 后被设为 null）时，signaling accept 已发出但 ToxAV 没有接通，`_activeCalls[inviteID]` 永久留在 map 中。后续 cancel/timeout 信令可能再次尝试 `endCall`；`getActiveCalls()` 返回僵尸 entry。
- 建议修法：在 `friendNumber == null`（和 `result.code != 0`）分支调用 `_sdkPlatform.reject(inviteID: inviteID)` 并从 `_activeCalls` 移除，触发 `onCallStateChanged?.call(inviteID, CallState.ended)`。
- 置信度：high

### [medium] F-10：测试覆盖缺口 — 信令终止路径无回归保护 — 信令侧

- 位置：`test/call_bridge_service_test.dart`（全文）
- 现象：现有 5 个测试均通过 `bridge.registerOutgoingCall` + 命令式方法调用驱动，没有一个测试通过 `sdk.listener?.onInvitationCancelled(...)` / `onInviteeRejected(...)` / `onInvitationTimeout(...)` 触发，也不测试 `friendNumber=null` 或 `0xFFFFFFFF` 分支。这正是 F-2、F-3、F-9 的代码路径，也是生产中最常走的终止路径。
- 建议修法：补充测试覆盖三种 terminated 路径 + `friendNumber==null` 分支。
- 置信度：high

## 全局观察

通话层的设计在「成对 acquire/release」上整体细致（`_captureGeneration` 防竞态、`_endCallCleanup` 统一 bump、VideoHandler `_startFuture/_stopFuture` 序列化），但信令侧（`CallBridgeService`）明显滞后——`endReason` 语义缺失、失败路径不清理 `_activeCalls`、三条 terminated 路径缺乏测试，构成一个有一定风险的薄弱点。`toggleSpeaker` 功能性缺失（F-1）是目前可见度最高的用户感知缺陷，应优先修复。
