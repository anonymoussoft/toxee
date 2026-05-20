# Toxee 手机/平板端 Review 汇总

> 生成日期：2026-05-20
> 关联清单：[`2026-05-20-feature-inventory.md`](./2026-05-20-feature-inventory.md)
> 范围：基于功能清单对手机（phone）与平板（tablet）实现做横向 review，按严重度分级。
> 方法：4 个并行子 agent 分别审查响应式骨架、消息域 UI、通话 UI、通知/平台集成，再去重汇总。

---

## 🔴 Critical — 产品级阻塞

### 1. 后台收消息 / 收来电完全失败

- 没有 Android 前台服务、没有 iOS PushKit / VoIP background mode、没有 FCM/APNs 接入。
- Tox 完全依赖 `FfiChatService.startPolling()` 持续运行，但移动 OS 会在数秒到数十秒内冻结 Flutter 引擎。
- 现状：app 一进后台或锁屏 → polling 停 → 消息 + 来电全丢，且 `resumed` 时也没有重新 bootstrap / 重连逻辑。
- 涉及：
  - `android/app/src/main/AndroidManifest.xml`（缺 `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_PHONE_CALL` / `USE_FULL_SCREEN_INTENT`）
  - `ios/Runner/Info.plist`（缺 `UIBackgroundModes: voip, audio`）
  - `lib/main.dart:200-209`
  - `lib/ui/home_page.dart:372-381`
- 这是一个聊天 app 的核心产品缺陷，必须做架构级方案（前台服务 + 推送中继 / PushKit + CallKit）。

### 2. 手机端无法管理会话（删除 / 置顶 / 标已读）

- `lib/ui/home_page.dart:199-238` 只注册了 `onSecondaryTapConversationItem`（右键），触摸设备根本不会触发。
- 手机用户进得了聊天但完全无法操作会话列表。
- 修复：UIKit 同时挂 `onLongPressConversationItem`，必要时改 `third_party/chat-uikit-flutter`。

### 3. 手机端 Drawer 无入口

- `lib/ui/home_page.dart:802` 挂了 `drawer:` 但没有 AppBar，也没人调 `openDrawer()`。
- 修复：底部导航已覆盖全部入口，直接删 Drawer 是最干净的方案。

### 4. 加好友 / 建群 Dialog 不躲键盘

- `lib/ui/add_friend_dialog.dart:294-403`、`lib/ui/add_group_dialog.dart:200-260` 的 `_dialogInset` 只算横向 padding，没用 `MediaQuery.viewInsets.bottom`。
- iPhone SE 等小屏上键盘弹起后 Submit 按钮和字数计数都被遮，且 `SingleChildScrollView` 滚不到。
- 同问题在 `lib/ui/group/group_builder_override.dart:511-543` 改群名 Dialog 上也有。

### 5. 来电铃声不尊重静音 / 振动模式 + 后台不响

- `lib/call/ringtone_player.dart` 用 `audioplayers` 直接放 WAV，走 `STREAM_MUSIC`。
- 没查 `AudioManager.getRingerMode()`、没振动、音量键调到的不是来电音量。
- 修复方向：Android 用 `RingtoneManager` + `STREAM_RING`，iOS 用 `.playback` 单独激活铃声 session。

---

## 🟠 High — 强烈建议短期修

### 响应式 & 布局

- **断点用 `size.width` 而非 `shortestSide`**（`lib/util/responsive_layout.dart:31-51`）：手机横屏被识别为平板，底部导航消失换成侧栏、UIKit 切到双栏，体验错乱。`isMobile / isTablet / isDesktop` 应换 `shortestSide`，`shouldShow*` 保留 `width`。
- **`PopScope(canPop: false)` 拦截了 UIKit 内部 push/pop**（`lib/ui/home_page.dart:783-800`）：聊天详情 → 返回键 → 不是回列表而是跳回 Chats tab，破坏 UIKit 导航栈。
- **`NewEntryButton` 浮在 UIKit AppBar 上方**（`lib/ui/home_page.dart:1244-1264`）：`SafeArea(top: false)` + `top: AppSpacing.lg` 让按钮压在 AppBar 标题上。
- **`_onTapContactItem` 用 `Navigator.canPop()` 推断 UI 意图**（`lib/ui/home_page.dart:711-736`）：在搜索 / 设置页时点联系人会把当前路由 pop 掉直接跳聊天。

### 通话 UI

- **通话全屏视图全部没 `PopScope`**（`lib/call/call_overlay.dart`、`lib/call/incoming_call_view.dart`、`lib/call/in_call_view.dart`）：Android 返回键会 pop 下层路由但通话 UI 还在，状态错乱。
- **权限在接听瞬间才弹**（`lib/call/call_service_manager.dart:686`）：用户面对 "接听 UI + 系统权限弹窗" 双层；如果拒绝权限会立刻 `rejectCall()`，对方看到的是 "接了又挂"。应在首次进入 app / 通话设置时预请求。
- **`CallFloatingWidget` 不是系统 PiP**（`lib/call/call_floating_widget.dart`）：注释写着 PiP 但其实是 Flutter Overlay，切到别的 app 就消失。
- **`CallSceneShell` 的 `SafeArea` 把视频画面也裁了**（`lib/call/call_ui_shell.dart:43`）：视频通话出现黑边，业界标准是视频铺满、控件躲安全区。

### 输入 & 列表

- **Tox ID / Group ID 输入框没禁自动纠错**（`lib/ui/add_friend_dialog.dart:335`、`lib/ui/add_group_dialog.dart:286`）：iOS 自动纠错会把 76 位 hex 当拼写错误改掉。缺 `autocorrect: false` / `enableSuggestions: false` / `textCapitalization: TextCapitalization.none`。
- **搜索结果 `ListView(shrinkWrap: true)`**（`lib/ui/search/custom_search.dart:557`）：放弃懒加载，低端 Android 输入一个字就重 layout 所有结果。

### 平台集成

- **iOS iCloud 备份排除漏了 `avatars/`**（`lib/util/app_bootstrap_coordinator.dart:35-56`）：只标记了 `fileRecv` 和 `profileDir`，头像缓存被白白上传备份。
- **Android Notification Channel 没显式声明 sound / vibration**（`lib/notifications/notification_service.dart:160-175`）：渠道首次创建后不可改，万一厂商 ROM 默认静音就永远救不回来。
- **`_androidPermissionGranted` 缓存在账号切换时不重置**（`lib/notifications/notification_service.dart:71-73`）：A 拒绝过通知，切到 B 也继续静默。
- **`AndroidManifest.xml` 没显式 `INTERNET` 权限**：通常 Flutter 模板有，但属于隐式依赖。
- **缺 missed call 通知 + 重连超时 endReason 错**（`lib/call/call_service_manager.dart:178-188`）：8s 重连失败时记成 `'hangup'` 而非 `'missed'`，且不推系统通知。

---

## 🟡 Medium — 体验细节

- `SegmentedButton` 三段（Public / Private / Conference）在 iPhone SE 窄屏溢出（`lib/ui/add_group_dialog.dart:217-257`）。
- 搜索框缺 `textInputAction: TextInputAction.search`（`lib/ui/search/custom_search.dart:458`）：iOS 键盘显示「换行」而非「搜索」。
- 64 字符 Group ID / 76 字符 Tox ID 在 `ListTile.subtitle` 单行省略，用户复制不到（`lib/ui/search/custom_search.dart:588,605`）。
- 配对页 QR 固定 260pt（`lib/ui/pairing/pairing_host_page.dart:325`）：应改 `clamp(180, 260)`。
- `autoDownloadSizeLimit` 默认 30MB 在蜂窝下太大（`lib/util/prefs.dart:843`），手机端应默认 5MB。
- 横竖屏切换时本地预览卡片位置不重 clamp（`lib/call/in_call_view.dart:384`）。
- `CodecProfile` 只看对端 bitrate 反馈，不感知 Wi-Fi → 4G 切换（`lib/call/call_codec_profile.dart`）。
- IRC `ApplicationsPage` 在 IndexedStack 隐藏时也弹 SnackBar（`lib/ui/applications/applications_page.dart:89-100`）。
- `lib/ui/settings/global_settings_section.dart:118-149` 下载目录按钮在移动端可见可点但点了无反应，应隐藏 / 置灰。
- `didChangeAppLifecycleState` 把 `inactive` 也算后台（`lib/ui/home_page.dart:373-381`）：每弹系统对话框都会触发一次磁盘写。

---

## 🟢 Low / 提醒

- `lib/ui/home_page_bootstrap.dart:314` 无条件设 `useDesktopMode: true`，可能让手机首屏短暂以双栏渲染再切回单栏。
- `lib/util/responsive_layout.dart` 在 600-720 宽度区间 `isTablet` 和 `shouldShowBottomNav` 同时为 true，存在语义重叠。
- `ios/Runner/Info.plist` 建议补 `NSUserNotificationsUsageDescription`（审核相关）。

---

## 修复优先级建议

| 阶段 | 工作内容 | 预计影响 |
|---|---|---|
| **P0 必修** | 后台收消息架构（前台服务 + voip background mode）、长按菜单替代右键、Dialog 键盘 inset、铃声尊重静音模式 | 不修无法当聊天 app 用 |
| **P1 短期** | 断点改 `shortestSide`、`PopScope` 调整、通话全屏 SafeArea、ID 输入框禁纠错、avatars 排 iCloud、missed call 通知 | 体验完整性 |
| **P2 打磨** | Codec 网络类型自适应、PiP 系统化、SegmentedButton 自适应、Drawer 清理 | 长期质量 |

---

## 关联测试 / 文档入口

- 架构上下文：`doc/architecture/HYBRID_ARCHITECTURE.en.md`、`doc/architecture/MAINTAINER_ARCHITECTURE.en.md`
- 通话回归：`test/call_in_call_view_test.dart`、`test/call_bridge_service_test.dart`、`test/call_and_history_regression_test.dart`
- 通知 / 角标：暂无专用测试，建议补 `notification_channel_idempotency_test`、`badge_account_switch_test`
- 响应式：暂无专用测试，建议补 `responsive_breakpoint_orientation_test`
