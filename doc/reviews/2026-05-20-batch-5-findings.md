# Batch 5 — UI、平台壳、插件、扩展（域 L + M + N + O）findings

> Review 日期：2026-05-20
> 范围：UI 框架、主页、设置、主题/语言、桌面端壳、托盘、插件、IRC 应用
> 配套：[功能清单](./2026-05-20-feature-inventory.md) · [Prompt 模板](./2026-05-20-review-prompts.md)

## 扫描范围与发现概览

覆盖文件：`home_page.dart`（含三个 part）、`home/`、`settings/`、`global_settings_section.dart`、`desktop_shell_bootstrap.dart`、`app_tray.dart`、`responsive_layout.dart`、`theme_controller.dart`、`locale_controller.dart`、`applications_page.dart`、`custom_search.dart` 前段、以及 `third_party/chat-uikit-flutter` 中 `TencentCloudChatBasicData`。共发现 9 个值得报告的问题，集中在：插件不注销（跨会话泄漏）、WindowManager preventClose 不完整、conversationStream 裸订阅无法取消、下载目录设置"仅存 Prefs 不通知 service"、主题切换 UIKit 同步顺序及 AppTheme.set 不等待、IRCApp 流订阅竞态与 `use_build_context_synchronously` 违规、以及 home_page.dart 超出 500 LOC 门槛。

## Critical

### [critical] WindowManager `onWindowClose` 异步处理期间可多次触发 destroy — 无幂等保护

- 位置：`lib/bootstrap/desktop_shell_bootstrap.dart:11-27`
- 现象：`setPreventClose(true)` 是正确的，但 `onWindowClose` 是 `async`，在 `getBounds()`/`setWindowBounds()` await 期间如果用户再次点击关闭或触发快捷键，`windowManager.destroy()` 会被重入调用。`_WindowStateListener` 是普通类实例非单例，无 `_closing` 保护标志。
- 风险：多次 `destroy()` 在部分 window_manager 版本上会 crash 或留下僵尸进程；Prefs 写入可能在 destroy 后被第二次覆盖为无效状态。
- 可见症状：用户快速双击关闭按钮，应用崩溃或进程残留后台。
- 建议修法：添加 `bool _closing = false;` 首行判断并设置；或用 `setPreventClose(false)` 后 `close()` 的标准 pattern。
- 置信度：high

## High

### [high] 插件登出后不注销，UIKit `basic.plugins` 全局列表重复 add

- 位置：`lib/ui/home_page_plugins.dart:47-200`；`third_party/chat-uikit-flutter/tencent_cloud_chat_common/lib/data/basic/tencent_cloud_chat_basic_data.dart:67,84-86`
- 现象：`TencentCloudChatBasicData.plugins` 是裸 `List`，`addPlugin` 只做 `add()`，无去重或 replace。`clear()` 只重置 `_hasLoggedIn`/`_currentUser`，不清空 `plugins`。`_stickerPluginRegistered` 等标志随 `HomePage` 重建而重置，每次登录都会再 `addPlugin`，全局列表持续增长。
- 可见症状：登出再登入，消息工具栏贴纸图标出现两个或更多。
- 风险：多次登录后工具栏重复按钮；text-translate/sound-to-text 回调被调用多次（重复翻译/转写副作用）；旧 plugin 持有已销毁 `context`，潜在 use-after-free。
- 建议修法：`SessionRuntimeCoordinator` re-init 路径或 `UikitDataFacade` session-teardown 调 `plugins.clear()`，或在 `TencentCloudChatBasicData.clear()` 加 `plugins.clear()`（fork 可改）；同时 `addPlugin` 先检查同名是否存在。
- 置信度：high

### [high] `home_page_bootstrap.dart` 中 `conversationStream`/`totalUnreadStream` 裸 listen 无法取消

- 位置：`lib/ui/home_page_bootstrap.dart:561-566`
- 现象：两行 `.listen(...)` 的返回值被直接丢弃。
- 可见症状：切换账户后短暂看到上一个账户的会话列表闪烁。
- 建议修法：保存为成员变量 `_convStreamSub`/`_unreadStreamSub` 并加入 `_bag`。
- 置信度：high

> 注：此条与 Batch 1 同一根因，按"跨 batch 问题按根因归属"原则在 Batch 1 主记，本条作为 UI 侧影响补充。

### [high] `ApplicationsPage` IRC 流回调违反 `use_build_context_synchronously`

- 位置：`lib/ui/applications/applications_page.dart:89-103`
- 现象：`_userJoinPartSub` listen 回调在 `setState` 之后调用 `ScaffoldMessenger.of(context)`。`mounted` 检查在外层（行 77），但 setState 后的同一回调帧内使用 context，在窗口最小化或 ApplicationsPage 被移出树时可能在 deactivated context 上调用。
- 风险：抛 `FlutterError: Looking up a deactivated widget's ancestor`；release build 下静默错误或 snackbar 显示在错误 Scaffold。
- 建议修法：`setState(...)` 后再次检查 `if (!mounted) return;` 再调 `ScaffoldMessenger.of(context)`。
- 置信度：high

## Medium

### [medium] 主题切换 `AppTheme.set(chosen)` 未 await，违反 `unawaited_futures`

- 位置：`lib/ui/settings/global_settings_section.dart:225-235`
- 现象：`AppTheme.set(chosen)` 返回 `Future<void>`（内部 await Prefs），但调用处没有 `await` 也没有 `unawaited()`。`setBrightnessMode` 在同一 `onSelectionChanged` 回调中同步调用。
- 风险：`Prefs.setThemeMode` 抛错被静默丢弃；`ThemeMode.system` 分支用 `MediaQuery.platformBrightnessOf(context)` 解析，context 已过时可能读到错误值。
- 可见症状：System 主题下切回"System"后 UIKit 颜色方案有时与系统实际亮度不一致。
- 建议修法：改为 `unawaited(AppTheme.set(chosen))`；system 分支考虑监听 `platformBrightnessOf` 变化。
- 置信度：medium

### [medium] `DesktopShellBootstrap` 窗口位置不检查屏幕边界，多屏断开后越界

- 位置：`lib/bootstrap/desktop_shell_bootstrap.dart:48-70`
- 现象：`validBounds` 只检查宽高（960-4096），不检查 x/y 是否在可用显示器范围。用户拔副屏后重启，窗口可能出现在屏幕外不可见区域。
- 可见症状：拔掉外接显示器后启动，托盘图标正常但点击无响应（窗口在不可见区域）。
- 建议修法：用 `screen_retriever` 检查可用屏幕区域，越界 fallback 到 `center: true`。
- 置信度：medium

### [medium] 下载目录更改仅写 Prefs，运行中 FfiChatService 不知情

- 位置：`lib/ui/settings/global_settings_section.dart:109-140`（`_selectDownloadsDirectory`）
- 现象：写 `Prefs.setDownloadsDirectory(...)` 后仅更新 UI 文本控制器，未通知 service。
- 可见症状：修改后接收的文件仍保存在旧目录，需重启才生效。
- 建议修法：写 Prefs 后通过回调或 `widget.service` 同步 C++ 层接收目录；`Prefs.autoDownloadSizeLimit` 同样问题。
- 置信度：medium

### [medium] `global_settings_section.dart` 调用 `getApplicationDocumentsDirectory()` 但未导入 `path_provider`

- 位置：`lib/ui/settings/global_settings_section.dart:89`
- 现象：文件顶部 import 列表中没有 `path_provider`，但行 89 直接调用 `getApplicationDocumentsDirectory()`。代码路径仅在 `Platform.isAndroid || Platform.isIOS` 时执行。
- 可见症状：Android/iOS 进入设置选择下载目录时崩溃。
- 建议修法：顶部添加 `import 'package:path_provider/path_provider.dart';`，验证 `pubspec.yaml` 有该依赖。
- 置信度：medium

### [medium] `CustomSearch._searchLocalMessageContent` 无 per-conversation 历史页数限制，大量历史用户搜索时高内存

- 位置：`lib/ui/search/custom_search.dart:73-131`
- 现象：每会话最多加载 2000 条（200/页 × 10 页），全部驻留 `allMessages` 直到函数返回。50 会话 × 2000 条 ≈ 100k 条 V2TimMessage 对象，峰值约 50MB+。串行 await，每帧间任务受阻。
- 可见症状：用户搜索普通词如"hello"，应用明显卡顿 1-2 秒。
- 建议修法：全局搜索时降低 per-conversation 页数（5 页/1000 条）；发现匹配后提前 break；或移到 isolate。
- 置信度：medium

## Low

### [low] `home_page.dart` 主文件 2319 行，`applications_page.dart` 1120 行，远超 500 LOC

- 位置：`lib/ui/home_page.dart`（2319 行）；`lib/ui/applications/applications_page.dart`（1120 行）
- 现象：单文件超过 `tool/check_complexity.dart` 500 行警告阈值，含实质性业务逻辑（`_loadPersistedGroupsIntoUIKit`、`_handleGroupChanged`、`_sendMedia` 等 100+ 行方法）。
- 建议修法：`_HomePageState` 的 group 操作移至 `lib/ui/home/home_group_controller.dart`；`applications_page.dart` 的 installed-details panel 拆为单独 widget。
- 置信度：high（事实计数）；low 严重度因当前 warn-only。

## 全局观察

本批次最高风险是**插件全局列表不随 session 清除**（多账户登录双重注册）和**两条流订阅裸 listen 无法取消**（跨会话数据污染）。平台壳层的 WindowManager 多屏越界和 preventClose 重入有用户可感知的硬崩风险。IRC ApplicationsPage 的 `use_build_context_synchronously` 违规在 IRC 功能启用后会被 flutter analyze 捕获。下载目录和自动下载阈值的设置无热生效路径是持续性 UX 摩擦点。`custom_search.dart` 的全量历史加载无上限对历史较多的用户是实质性性能风险。
