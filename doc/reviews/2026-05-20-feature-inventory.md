# toxee 功能清单（用于 code review 拆分）

> 生成日期：2026-05-20
> 用途：作为全面 code review 的拆分依据，每个功能可单独追踪。

## 审阅前必读

- **权威初始化/双路径文档**：`doc/architecture/HYBRID_ARCHITECTURE.en.md`
- **维护者视角/易碎点**：`doc/architecture/MAINTAINER_ARCHITECTURE.en.md`
- **FFI/SDK 回归面**：`test/ffi_audit/README.md` 及其 `surface_*` 测试
- **工程约束**：`tool/check_complexity.dart`、`analysis_options.yaml`

## 跨域不变量

1. **双路径必须共存**：binary replacement 路径和 Platform 路径都不能被“顺手删掉”或偷偷旁路。
2. **历史只能有一个事实源**：最终都应落到 `FfiChatService` + `MessageHistoryPersistence`，不能双写也不能分叉。
3. **会话运行时必须原子初始化/销毁**：`FakeUIKit`、`Tim2ToxSdkPlatform`、`BinaryReplacementHistoryHook`、通话桥、badge/notification listener 必须随 session 一起装卸。
4. **`startPolling()` 只能在运行时就绪后启动**：否则文件请求、连接状态、ToxAV/扩展事件会落到未注册或错误的 consumer。
5. **多账户切换不能泄漏跨会话状态**：包括回调、stream 订阅、未读角标、缓存目录、Prefs scoped key、插件注册状态。

## 当前代码结构提醒（2026-05-20 快照）

- **`BinaryReplacementHistoryHook` 已不在 HomePage 安装**：当前由 `SessionRuntimeCoordinator.ensureInitialized()` 原子安装；若 `selfId` 尚未就绪，再通过 `connectionStatusStream` 补 `updateSelfId()`。
- **HomePage 已分裂成“主文件 + part + 子目录控制器/视图”**：审阅时要把 `lib/ui/home_page.dart`、`home_page_bootstrap.dart`、`home_page_plugins.dart`、`home_page_persistence.dart` 与 `lib/ui/home/` 一起看。
- **登录/设置仍处于“旧大文件 + 新拆分文件”并存状态**：`lib/ui/login_page.dart` 与 `lib/ui/login/login_page_controller.dart`、`lib/ui/settings/*.dart` 需要合并理解。
- **third_party 目录可直接改**：`third_party/tim2tox`、`third_party/chat-uikit-flutter` 都是本仓库可维护的一部分，不要把问题误归因为“上游不可改”。

## 标注约定

- **二进制替换路径**：走 `libtim2tox_ffi` 替换 `dart_native_imsdk`。
- **Platform 路径**：走 `Tim2ToxSdkPlatform`（注册为 `TencentCloudChatSdkPlatform.instance`）。
- 两条路径在历史/回调上的协调由 `BinaryReplacementHistoryHook` 强制（当前由 `SessionRuntimeCoordinator` 安装，而不是 HomePage 单独安装）。
- **文件/行号是定位入口，不是硬边界**：若代码已拆到 `part`、`lib/ui/home/`、`lib/ui/login/`、`third_party/tim2tox` 等相邻文件，应沿调用链继续看。

---

## A. 启动与运行时（A 域）

1. **应用冷启动编排**：`AppBootstrap.initialize()` 串联日志/Prefs/Runtime/桌面壳/通知 — `lib/main.dart:69`、`lib/bootstrap/app_bootstrap.dart`
2. **日志早期初始化与 print 路由**：`LoggingBootstrap` + `setNativeLibraryName('tim2tox_ffi')` + 解析 TCCF 行回写 `AppLogger` — `lib/bootstrap/logging_bootstrap.dart`、`lib/util/logger.dart`
3. **Prefs 版本/升级检测**：`PrefsUpgrader` 抛 `PrefsStorageNewerThanAppException` 触发升级屏 — `lib/bootstrap/prefs_bootstrap.dart`、`lib/ui/upgrade_required_screen.dart`
4. **启动会话编排（auto-login 路径）**：`StartupSessionUseCase` 7 步骤 + 连接等待 / 超时 — `lib/startup/`、`_StartupGate`
5. **AppBootstrapCoordinator.boot**：`SessionRuntimeCoordinator.ensureInitialized → TimSdkInitializer.ensureInitialized → startPolling`（顺序敏感；前者已包含 FakeUIKit/Platform/Hook/Call runtime）— `lib/util/app_bootstrap_coordinator.dart`
6. **SessionRuntimeCoordinator**：安装 `Tim2ToxSdkPlatform`、`FakeUIKit.startWithFfi`、standalone `BinaryReplacementHistoryHook`、`BadgeService`，幂等支持登出后重初始化 — `lib/runtime/session_runtime_coordinator.dart`
7. **HomePage 二次初始化**：UIKit group/friend listener、provider 注册、插件注册时机、连接/托盘/通知联动 — `lib/ui/home_page.dart`、`lib/ui/home_page_bootstrap.dart`、`lib/ui/home/`

## B. 账户与身份（B 域）

1. **新账户注册**：生成 Tox ID，可选密码加密档案 — `lib/ui/register_page.dart`、`AccountService.registerNewAccount`
2. **手动登录**：账户选择 + 密码校验 + 遗留账户兼容 — `lib/ui/login_page.dart`、`lib/auth/login_use_case.dart`
3. **自动登录开关与执行**：`Prefs.autoLogin` + cold-start 触发 — `lib/util/prefs.dart`、`StartupSessionUseCase`
4. **账户密码（PBKDF2-SHA256 150k 迭代）**：盐按 toxId 存储 — `lib/util/prefs.dart:81`
5. **账户导出（加密 .tox 档案）**：`AccountExportService` — `lib/util/account_export_service.dart`
6. **账户导入**：从加密档案恢复
7. **多账户切换**：拆卸+重新加密+重新初始化 — `lib/util/account_switcher.dart`
8. **账户列表展示与卡片**：设置页账户管理区 — `lib/ui/settings/settings_page_build.dart`
9. **账户完整删除**：含档案目录、UIKit 失败缓存、密码盐 — `AccountService.deleteAccountCompletely`
10. **自我资料编辑**：昵称/状态/头像，落 Prefs + FfiChatService — `lib/ui/profile_page.dart`、`profile_avatar_picker.dart`

## C. Bootstrap 节点与网络入口（C 域）

1. **节点模式切换 (auto/manual/lan)**：移动端禁 lan — `Prefs.bootstrapNodeMode`
2. **自动节点获取**：`BootstrapNodesService.fetchNodes` + 选 ONLINE — `StartupSessionUseCase:51`
3. **手动节点配置与测试**：登录页 + 设置页 — `lib/ui/settings/bootstrap_settings_section.dart`、`bootstrap_nodes_page.dart`
4. **LAN Bootstrap 服务启停（桌面）**：保存先前公网节点便于恢复 — `lib/util/lan_bootstrap_service.dart`
5. **LAN 节点扫描**：UDP 广播探测
6. **配对（跨设备）**：主机/客户端、QR + SAS 6 位、`.tox` blob 传输 — `lib/ui/pairing/`

## D. 消息：收发、删除、回执（D 域）

1. **文本消息发送**：C2C only，pending 离线持久 — `FakeMessageManager.sendText`
2. **文件消息发送**：含离线排队；群组明确拒绝 — `FakeMessageManager.sendFile`
3. **图片消息发送**：复用 sendFile — `FakeMsgProvider.sendImage`
4. **消息接收 / 本地回显**：FFI 流 + 历史 stale 重载（3s TTL）— `FakeChatMessageProvider`
5. **消息删除**：触发历史缓存失效 — `FakeMsgProvider.deleteMessages`
6. **已读回执与未读标记**：`lastViewTimestamp` 计算未读 — `MessageHistoryPersistence.markUnreadMessagesAsRead`

## E. 消息历史持久化（E 域）

1. **冷启历史加载**：路径占位符 `{{fileRecv}}` 等支持跨设备迁移 — `MessageHistoryPersistence.loadAllHistories`
2. **追加 + 200ms 防抖 + 去重**：msgID 优先 / 内容窗口匹配 — `appendHistory`
3. **原子写 + .bak 备份 + fsync**：单 conversation 写锁 — `saveHistory`
4. **历史清空（C2C/group）**：H7 确定性文件名 — `clearHistory` / `clearAllHistories`
5. **文件路径安全更新**：try/catch 真实磁盘错误 — `updateFilePathSafely`
6. **双路径协调（BinaryReplacementHistoryHook）**：拦截 binary 路径消息防与 Platform 路径重复 — `binary_replacement_history_hook.dart`

## F. 会话管理（F 域）

1. **会话列表构建与排序**：好友 + Prefs + knownGroups 合并，pinned 优先 — `FakeConversationManager.getConversationList`
2. **会话固定/取消**：C2C 与 group 不同 key，启动等待初始读 — `setPinned`
3. **会话删除**：调用清历史 + 移除 pinned，即时 emit — `deleteConversation`
4. **未读计数**：本地时间戳计算 — `MessageHistoryPersistence.getUnreadCount`
5. **会话最后消息维护**：`FakeChatDataProvider` 转 `V2TimConversation`

## G. 媒体/文件（G 域）

1. **文件接收/下载**：当前自动接受策略 + 自动下载大小阈值 — `FfiChatService.fileRequests`、`Prefs.autoDownloadSizeLimit`
2. **文件进度（收发）**：暴露 sendProgressStream / progressUpdates
3. **头像接收与缓存**：`avatars/` + Prefs 路径缓存 — `FakeMsgProvider`

## H. 好友（H 域）

1. **好友列表 + 离线展示**：合并 `Prefs.localFriends` — `FakeConversationManager`
2. **好友请求发送**：64/76 字符 ID 校验 + 921 字消息上限 + pending buffer（30s TTL）— `lib/ui/add_friend_dialog.dart`
3. **好友请求接收/接受/拒绝**：X9 pending buffer + 冷启宽限 15s — `FakeIM`
4. **好友删除 + 资源清理（头像）**
5. **昵称/备注/活跃时间**：Prefs

## I. 群组（I 域）

1. **群组创建**：Tox new-API (public/private) 与 legacy conference — `lib/ui/add_group_dialog.dart`
2. **群组加入**
3. **群组退出 + `Prefs.addQuitGroup` 过滤**
4. **群成员列表**：filter / debounce / last-seen 缓存 — `lib/ui/group/group_member_list_wrapper.dart`
5. **群信息（名称/别名/头像）**：Prefs

## J. 通话（J 域）

1. **发起 1v1 音频通话** — `TUICallKitAdapter`
2. **发起 1v1 视频通话**（videoBitRate=2000）
3. **接听**（信令 → ToxAV.answer）
4. **拒接**
5. **主动挂断 / 对方挂断 / 超时**：endReason='reject|hangup|timeout|cancel'
6. **切麦 / 切摄像头 / 扬声器切换**（Audio/Video Handler + CallAudioPlatform）
7. **来电铃声**：合成 WAV 循环 — `lib/call/ringtone_player.dart`
8. **来电/通话中/结束 全屏 UI** — `IncomingCallView`、`InCallView`，2s ended 自动关
9. **前台通话浮层 PiP**：拖放/恢复 — `CallFloatingWidget`
10. **通话权限请求**：麦/摄像头 — `permission_helper.dart`
11. **通话质量估计 + 编解码自适应**：CodecProfile 3 档 — `call_quality_estimator.dart`、`call_codec_profile.dart`
12. **网络重连中间态（8s 窗口）+ 未接来电历史插入**：`CallServiceManager`

## K. 通知与角标（K 域）

1. **本地通知**：Android 13+ 运行时权限、iOS/macOS thread grouping、点击跳会话 — `lib/notifications/notification_service.dart`
2. **应用角标**：订阅未读 + 200ms 防抖 — `lib/notifications/badge_service.dart`
3. **CallEffectsListener**：wakelock / 亮度 / 后台播放 — `lib/call/call_effects_listener.dart`

## L. UI 框架与设置（L 域）

1. **响应式主页骨架（desktop/tablet/phone）** — `lib/ui/home_page.dart`、`responsive_layout.dart`
2. **会话列表（UIKit 组件 + 右键菜单）+ 全局未读徽章**
3. **自定义搜索（消息/联系人/群组）+ 高亮** — `lib/ui/search/custom_search.dart`
4. **设置页 4 大区**：账户信息 / 全局设置 / 引导节点 / 账户管理
5. **主题切换 (System/Light/Dark)** — `AppTheme` + UIKit 同步
6. **多语言（en/ar/ja/ko/zh_Hans/zh_Hant）** — `AppLocale` + UIKit IntlLoader
7. **通知音开关（按账户）**、**自动接受好友/群组邀请开关**
8. **下载目录设置 + 自动下载阈值**
9. **联系人/群组 builder override**（插入自定义群成员列表）
10. **启动加载屏 / 升级提示屏**

## M. 平台壳与系统集成（M 域）

1. **桌面窗口管理**：尺寸/位置记忆、最大化、关闭确认、最小 960×600 — `desktop_shell_bootstrap.dart`
2. **系统托盘**：图标 + tooltip + 嵌入未读数（Windows/Linux）— `app_tray.dart`
3. **iOS 不备份标记**：日志、档案、file_recv 目录

## N. 插件接入（N 域）

1. **贴纸插件**：同步/异步双路注册 — `lib/ui/home_page_plugins.dart`
2. **文本翻译插件**
3. **语音转文字插件**

## O. 扩展应用（O 域）

1. **IRC 应用接入**：频道列表/用户/连接状态/SASL（侧栏入口当前 disabled）— `lib/ui/applications/applications_page.dart`

## P. 适配层与 SDK Fake（P 域，横切）

1. **PreferencesAdapter** — `lib/adapters/shared_prefs_adapter.dart`
2. **ConversationManagerAdapter** — `lib/adapters/conversation_manager_adapter.dart`
3. **EventBusAdapter** — `lib/adapters/event_bus_adapter.dart`
4. **LoggerAdapter** — `lib/adapters/logger_adapter.dart`
5. **BootstrapAdapter** — `lib/adapters/bootstrap_adapter.dart`
6. **FakeIM / FakeChatMessageProvider / FakeConversationManager / FakeMessageManager / FakeChatDataProvider** — `lib/sdk_fake/`

## Q. 工程基础设施（Q 域）

1. **`bootstrap_deps.dart`**：submodule + vendor SDK + 补丁 + `pubspec_overrides.yaml`
2. **离线 bootstrap 完整性检查**（vendor_state.json + patches sha256）
3. **Pre-push submodule SHA 远端校验** + `install_git_hooks.sh`
4. **SDK 补丁再生成**：`refresh_sdk_patch.sh`、`apply_sdk_patches.dart`
5. **本地 bootstrap 验证（软链接 tim2tox/uikit）+ smoke test**
6. **`check_complexity.dart`（>500 LOC 警告）**
7. **`analysis_options.yaml` 严格 lints**
8. **多目标构建脚本 `build_tim2tox.sh`**（linux/windows/macos/android/ios + ToxAV/DHT bootstrap 开关）
9. **跨平台打包 `package_artifacts.sh`**（DEB/RPM/MSI/PKG/APK+AAB/IPA）
10. **CI: analyze、build-packages 矩阵、auto_tests Tier 2、auto_tests_nightly Tier 3、bootstrap_fresh**
11. **本地开发循环 `run_toxee.sh` + 平台变体** / **`build_all.sh`**
12. **Release 发布（tag → gh release）+ iOS 签名准备**

---

## Review 拆分建议（对应 prompt 模板）

- **批 1（核心混合架构）**：A + P — 启动顺序与适配层一起看，最容易暴露混合架构破坏
- **批 2（消息域）**：D + E + F + G + H + I — 消息/历史/会话/媒体/好友/群组同源
- **批 3（通话域）**：J + K — 通话 + 通知/角标天然耦合
- **批 4（账户与网络入口）**：B + C
- **批 5（UI 与平台壳）**：L + M + N + O
- **批 6（工程基础设施）**：Q — 独立子任务

详见 [`2026-05-20-review-prompts.md`](./2026-05-20-review-prompts.md)。

## 建议测试索引（按 review batch）

- **Batch 1（A + P）**
  `test/runtime/session_runtime_coordinator_test.dart`、`test/session_runtime_lifecycle_test.dart`、`test/tim2tox_binary_replacement_hook_generation_test.dart`、`test/ffi_audit/README.md` 与 `surface_*`
- **Batch 2（D + E + F + G + H + I）**
  `test/tim2tox_history_cache_single_source_test.dart`、`test/tim2tox_get_history_pagination_test.dart`、`test/tim2tox_delete_messages_test.dart`、`test/sdk_fake/*.dart`、`test/fake_conversation_manager_*`、`test/friend_asset_cleanup_test.dart`
- **Batch 3（J + K）**
  `test/call_bridge_service_test.dart`、`test/call_and_history_regression_test.dart`、`test/call_*`、`test/call_effects_policy_test.dart`
- **Batch 4（B + C）**
  `test/auth/login_use_case_test.dart`、`test/account_export/account_export_roundtrip_test.dart`、`test/account_reconciliation_test.dart`、`test/restore_from_tox_test.dart`、`test/pairing/*.dart`
- **Batch 5（L + M + N + O）**
  `test/first_run_wizard_test.dart`、`test/widget_test.dart`、`test/prefs_cross_platform_polish_test.dart`、`test/user_profile_call_actions_test.dart`
- **Batch 6（Q）**
  `test/repo_hygiene_test.dart`、`tool/test_bootstrap_smoke.sh`、`tool/test_ci_packaging.sh`

说明：这些测试是“快速定位现有保障面”的索引，不等于真实范围上限；发现测试缺口本身也可能是 finding。
