# Toxee 手机/平板实现 Review 状态对照（当前工作区）

> 生成日期：2026-05-20
> 基准文档：[`2026-05-20-impl-review-findings.md`](./2026-05-20-impl-review-findings.md)
> 对照范围：当前未提交改动 + 子项目指针变化（`third_party/tim2tox`）
> 目的：回答两件事
> 1. 原始实现 review 里哪些项已补、哪些仍遗漏
> 2. 当前这批改动里有没有原文档没覆盖到的新风险或未 review 区域

---

## 结论摘要

- 这一轮改动已经覆盖了原始文档里相当多的 UI / 响应式 / 输入体验问题，尤其是：
  - Drawer 无入口
  - Dialog 键盘遮挡
  - Home 页返回键拦截 UIKit push/pop
  - 通话页 `PopScope`
  - 通话视频安全区裁切
  - Tox ID / Group ID 自动纠错
  - 搜索 `shrinkWrap`
  - iCloud 备份排除 `avatars/`
  - Android notification channel 的 sound / vibration
  - Android 通知权限缓存跨账号泄漏
  - 显式 `INTERNET`
  - QR 自适应尺寸
  - 手机端默认 5MB 自动下载限制
  - 下载目录按钮在移动端隐藏
  - `inactive` 不再触发后台保存
  - `useDesktopMode: true` 首屏闪动
  - `NSUserNotificationsUsageDescription`

- 但仍有几类问题没有真正收口：
  - 后台收消息 / 收来电仍只是声明层占位，没有前台服务 / PushKit / CallKit / 恢复重连逻辑
  - 手机端会话长按菜单仍未落地
  - 铃声静音 / 振动模式、系统 PiP、预授权时机等通话体验问题仍未修
  - missed-call / reconnect 这条链路虽然补了一部分，但又引入了新的路由与消息语义问题

- 此外，当前 diff 里还有几处原始文档没有覆盖到的新风险：
  - `ResponsiveLayout.isDesktop()` 被一起改成 `shortestSide`，会误伤桌面窗口
  - missed-call 通知 payload 点开后不会跳转
  - `network_error` 通话记录会被 UIKit 当成“发起通话”而不是“异常结束”

---

## 已修 / 基本已修

### 响应式与 Home 壳层

- **Drawer 无入口**：已处理。`drawer:` 已从 `Scaffold` 移除，底部导航成为手机端唯一入口。见 `lib/ui/home_page.dart`。
- **Home 返回键误拦截 UIKit push/pop**：已处理。`PopScope(canPop: false)` 改成基于 `Navigator.canPop()` 的条件拦截，根导航栈有页面时让正常 `pop` 发生。见 `lib/ui/home_page.dart:801-833`。
- **`NewEntryButton` 压住 UIKit AppBar**：已处理。按钮改为 `top: kToolbarHeight + AppSpacing.sm`，并恢复顶部 `SafeArea`。见 `lib/ui/home_page.dart:1219-1233`。
- **`_onTapContactItem` 用 `Navigator.canPop()` 猜 UI 意图**：已处理。现在显式用 `_inContactProfileContext` 区分“联系人列表点击”和“资料页里的 Send Message”。见 `lib/ui/home_page.dart`。
- **`useDesktopMode: true` 首屏闪动**：已处理。启动时改为根据 `ResponsiveLayout.shouldShowMasterDetail(context)` 决定。见 `lib/ui/home_page_bootstrap.dart`。

### Dialog / 输入 / 列表

- **加好友 Dialog 不躲键盘**：已处理。`SingleChildScrollView` 的底部 padding 加上 `MediaQuery.viewInsets.bottom`。见 `lib/ui/add_friend_dialog.dart:291-303`。
- **建群 Dialog 不躲键盘**：已处理。加入高度上限和底部 keyboard inset。见 `lib/ui/add_group_dialog.dart:214-230`。
- **改群名 Dialog 不躲键盘**：已处理。输入框包进 `SingleChildScrollView`，并设置 `scrollPadding`。见 `lib/ui/group/group_builder_override.dart`。
- **Tox ID / Group ID 输入没禁自动纠错**：已处理。加了 `autocorrect: false`、`enableSuggestions: false`、`textCapitalization: TextCapitalization.none`。见 `lib/ui/add_friend_dialog.dart:342-351` 与 `lib/ui/add_group_dialog.dart:298-306`。
- **搜索结果 `ListView(shrinkWrap: true)`**：已处理。`shrinkWrap` 已移除。见 `lib/ui/search/custom_search.dart`。
- **搜索框缺 `TextInputAction.search`**：已处理。见 `lib/ui/search/custom_search.dart`。
- **Group/Public/Conference 三段按钮窄屏溢出**：已处理。segment label 改为 `FittedBox`。见 `lib/ui/add_group_dialog.dart`。
- **配对页 QR 固定 260pt**：已处理。改成基于 viewport 的 `clamp(180, 260)`。见 `lib/ui/pairing/pairing_host_page.dart`。

### 通知 / 平台集成

- **iCloud 备份排除漏了 `avatars/`**：已处理。见 `lib/util/app_bootstrap_coordinator.dart`。
- **Android Notification Channel 没显式 sound / vibration**：已处理。见 `lib/notifications/notification_service.dart`。
- **通知权限缓存跨账号泄漏**：已处理，而且已接到 runtime teardown。`resetSessionState()` 会清 `_androidPermissionGranted`，`SessionRuntimeCoordinator` 也已调用它。见 `lib/notifications/notification_service.dart:497-506` 与 `lib/runtime/session_runtime_coordinator.dart:158-161`。
- **`AndroidManifest.xml` 没显式 `INTERNET`**：已处理。见 `android/app/src/main/AndroidManifest.xml:20-23`。
- **`NSUserNotificationsUsageDescription` 缺失**：已处理。见 `ios/Runner/Info.plist:84-85`。

### 其他体验修正

- **手机端默认自动下载 30MB 太大**：已处理。移动端默认值改为 5MB。见 `lib/util/prefs.dart:842-853`。
- **横竖屏切换时通话浮窗位置不重 clamp**：已处理。现在会重新 clamp 并持久化位置。见 `lib/call/call_floating_widget.dart:150-163`。
- **下载目录按钮在移动端可见但不可用**：已处理。移动端隐藏 picker 按钮，仅保留展示字段。见 `lib/ui/settings/global_settings_section.dart`。
- **`inactive` 也算后台，频繁写盘**：已处理。只在 `paused` / `detached` 保存。见 `lib/ui/home_page.dart:381-397`。

---

## 部分响应，但还没真正完成

### 1. 后台收消息 / 收来电

- **只补了声明，没有补实现。**
- Android 现在声明了 `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_PHONE_CALL` / `USE_FULL_SCREEN_INTENT`，iOS 也补了 `UIBackgroundModes: voip, audio`，但两边注释都明确写着“本轮不实现，只占位”。见 `android/app/src/main/AndroidManifest.xml:24-36` 与 `ios/Runner/Info.plist:86-96`。
- `resumed` 时的恢复重连仍是空实现。见 `lib/ui/home_page.dart:391-397`。
- 所以原始文档里的 Critical 1 不能标记为“已修”，只能算“把需求声明出来了”。

### 2. missed-call / reconnect 链路

- **只修了一半。**
- 正向部分：
  - 增加了 missed-call 专用通知 channel
  - 来电未接 / reconnect 超时会发 missed-call 通知
  - reconnect 超时不再写死 `'hangup'`，而是写 `'network_error'`
- 但这条链路没有闭环，后面还有新的问题，见下文“新发现”。

### 3. 长 ID 显示问题

- 原始文档提到搜索结果里的 64/76 字符 ID 被单行省略，不利于识别与复制。
- 当前改动把 subtitle 改成了前 8 后 8 的压缩显示，改善了“完全看不出尾部”的问题，但它不是严格意义上的“可复制方案”。见 `lib/ui/search/custom_search.dart`。
- 这一项更接近“部分改善”，不是彻底解决。

---

## 仍未修复

### Critical / High 级遗留

- **手机端无法管理会话（删除 / 置顶 / 标已读）**：仍未修。代码里还是只挂 `onSecondaryTapConversationItem`，并且直接留了 TODO 说明触摸设备没有长按菜单。见 `lib/ui/home_page.dart:200-206`。
- **来电铃声不尊重静音 / 振动模式 + 后台不响**：未见相关改动，本轮没有触碰 `lib/call/ringtone_player.dart`。
- **权限在接听瞬间才弹**：仍未修。当前仍在进入通话流程后调用 `_ensurePermissionsForCurrentMode()`。见 `lib/call/call_service_manager.dart:307-314`。
- **`CallFloatingWidget` 不是系统 PiP**：仍未修。当前只修了位置 clamp，没有引入 Android/iOS 系统级 PiP。
- **`CodecProfile` 不感知网络类型切换**：未修，本轮未触碰 `lib/call/call_codec_profile.dart`。
- **IRC `ApplicationsPage` 在隐藏页也弹 SnackBar**：未修，本轮未触碰 `lib/ui/applications/applications_page.dart`。

---

## 原始文档没覆盖到，但当前必须补记的新问题

### N1. `ResponsiveLayout.isDesktop()` 一起改成 `shortestSide`，会误伤桌面窗口

- 位置：`lib/util/responsive_layout.dart:52-56`
- 原始文档聚焦手机 / 平板，把“设备分类判断改成 `shortestSide`”列为建议是对的；但当前实现把 `isDesktop()` 也一起改掉了。
- 这会让常见桌面窗口（例如 `1440x900`、`1280x800`）因为 `shortestSide < 1024` 而被判成 tablet，随后所有依赖 `responsiveValue(...)` 的桌面样式都会退成平板值。
- 这是当前改动引入的共享层回归，原始手机/平板 review 没覆盖到这条桌面路径。

### N2. missed-call 通知点开后不会跳转

- 位置：
  - 发通知：`lib/notifications/notification_service.dart:561-571`
  - 路由：`lib/ui/home_page_bootstrap.dart:809-820`
- 现状：通知 payload 现在是 `missed_call:<peerId>`，但通知点击路由仍然只认识 `c2c_` / `group_`，会直接走 unknown prefix 返回。
- 结果：missed-call 通知能弹，但用户点开后没有任何跳转。

### N3. `network_error` 通话记录会被 UIKit 当成“发起通话”

- 位置：
  - 发记录：`lib/call/call_service_manager.dart:203-214`
  - 序列化：`lib/sdk_fake/fake_uikit_core.dart`
- 现状：`CallServiceManager` 新增了 `_emitCallRecord('network_error')`，但 `fake_uikit_core` 只识别 `hangup/cancel/reject/timeout`。
- 未知值会落到默认分支，生成 `actionType = 1` 且 `cmd = audioCall/videoCall`，UIKit 会把它解析成“发起通话”而不是“异常结束”。
- 这不是原始文档里的旧问题，而是这轮实现带来的新语义错误。

---

## 子项目与未 review 区域

### `third_party/tim2tox`

- 当前主仓 diff 包含 `third_party/tim2tox` 子模块指针变更。
- 子模块工作区本身是干净的，本地没有额外未提交代码；变化来自指针从旧提交移动到新提交。
- 这意味着：
  - **主仓级 review** 已经把“子模块被 bump”这一事实纳入范围
  - **但具体子模块 commit 的逻辑变化** 仍应按该子模块自己的 diff 单独 review

### `third_party/tencent_cloud_chat_sdk/macos/Frameworks/dart_native_imsdk.framework`

- 这个目录当前是未跟踪的二进制 framework。
- 它不在主仓 staged/modified diff 里，但它确实存在于工作区。
- 由于是二进制产物，当前 review 只能把它标记为“未做源码级审查”；若它计划被纳入版本控制，需要单独确认来源、版本、用途和是否应忽略。

---

## 建议的后续动作

### 先补功能闭环

1. 先修 `missed_call:` payload 路由，让通知点击至少能落到对应 `c2c_` 会话。
2. 修 `network_error` 的 call-record 编码，让它在 UIKit 里显示为“异常结束”而不是“发起通话”。
3. 把 `isDesktop()` 恢复成基于 width 的桌面能力判断，或把“设备类别”和“布局容量”两个概念彻底拆开。

### 再继续补原始高优先级遗留

1. 会话长按菜单替代右键
2. 来电铃声走系统来电通道
3. 通话权限预授权
4. 后台前台服务 / PushKit / 恢复重连

### 建议补测试

- `responsive_breakpoint_orientation_test`
  - 覆盖 phone landscape、tablet portrait、desktop window 三类场景
- `notification_payload_routing_test`
  - 覆盖 `c2c_`、`group_`、`friend_req:`、`missed_call:`
- `call_record_end_reason_mapping_test`
  - 覆盖 `hangup/cancel/reject/timeout/network_error`

