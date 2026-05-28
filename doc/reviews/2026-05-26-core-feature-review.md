# 2026-05-26 核心功能 Review 记录

本轮 review 覆盖媒体/文件传输、联系人与好友申请、账号导入导出、本地离线存储、bootstrap/登录设置、profile/群组/profile 相关回归、响应式 UI，以及当前本地改动的二次 code review。

## 修复项

- **C2C 媒体离线发送**：HomePage 自定义图片/视频入口不再预先用 `getFriendList()` 判定离线，而是直接委托 `FfiChatService.sendFile(...)`。离线好友的文件发送由服务层写入 `offline_message_queue.json` 并显示 pending 气泡，好友上线后再 drain。
- **群组媒体/文件传输**：Tox group/conference 当前无文件通道，`FakeChatMessageProvider.sendImage/sendFile` 维持快速失败语义，避免产生永远不会完成的发送气泡。
- **好友申请 dismissed 状态**：接受好友申请时必须先等 FFI 成功；成功后清理同一 `userId` 下所有 `<userId>|<wording>` dismissed 指纹，避免旧忽略状态挡住后续申请。
- **完整账号备份头像元数据**：导出 `.zip` 时会从账号 `avatars/` 目录补齐 `friend_<id>_avatar_<timestamp>.<ext>` 等头像文件的 `friend_avatar_path_<friendId>` 元数据，并转成 `@account_data/...` 可移植路径。
- **完整账号备份导入安全**：导入 `.zip` 前预检 `chat_history/` 与 `avatars/` 条目，拒绝 `../`、绝对路径、Windows drive 前缀和反斜杠路径；预检通过后才写入 profile、历史、头像、离线队列和 scoped prefs。
- **SDK 回调 API 兼容**：tim2tox Dart 侧使用当前 bootstrap SDK 提供的 `addTimCallback2Map` / `addTimValueCallback2Map`，避免旧 `timCallback2Future` / `timValueCallback2Future` 名称导致 8.8/8.9 API 不匹配。

## 验证

- `flutter test`：全量通过，仍保留仓库原有 skip。
- 定向覆盖：账号导入导出、好友申请、媒体离线队列、群组会话刷新、profile/call actions、登录/账号运行时、bootstrap 设置、响应式布局、本地 prefs/历史存储均已跑过相关测试。
- `flutter build macos --debug`：通过。
- `dart analyze lib test`：无 error；仍有既有 warning/info。

## 限制

- 当前执行环境为 macOS，只能实际构建 macOS。Android/iOS 相关通过已有 source/static 测试覆盖；Linux/Windows 需在对应宿主或 CI runner 上构建验证。
- `flutter analyze` 会扫描未完全按当前仓库工作区配置的 `third_party/` 嵌套包，仍会输出大量第三方/嵌套工程噪声；本轮以 `dart analyze lib test` 和全量 `flutter test` 作为应用层验证依据。
