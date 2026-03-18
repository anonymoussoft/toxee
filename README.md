# toxee

> 基于 Tim2Tox 的 Flutter 聊天客户端 / 示例应用

---

## 5 分钟内理解本项目

- **toxee 是什么**：一个可运行的 Flutter 聊天 App，用 Tencent Cloud Chat UIKit 做界面，用 **tox** 做后端，走 Tox P2P 网络。
- **Tim2Tox 是什么**：连接 UIKit 与 tox 的兼容层/框架（在 `third_party/tim2tox`，上游仓库：[https://github.com/anonymoussoft/tim2tox](https://github.com/anonymoussoft/tim2tox)）；不是聊天应用本身。
- **架构一句话总结**：toxee 通过「二进制替换 + Platform」混合架构接入 Tim2Tox，大部分 SDK 调用走 NativeLibraryManager → Dart*，历史/轮询/通话等由 Tim2ToxSdkPlatform → FfiChatService 补足。
- **最短跑起来**：克隆 → `dart run tool/bootstrap_deps.dart` → `flutter pub get` → `./build_all.sh --platform macos --mode debug` 或 `./run_toxee.sh`。

深层实现与阅读路径见 [doc/README](doc/README.md)。

---

## 项目简介

**toxee** 是**基于 tox 的 Flutter 聊天客户端 / 示例应用**。它展示如何将 tox 与 Tencent Cloud Chat UIKit 集成，实现去中心化 P2P 聊天：账号、会话、消息、好友、群组、Bootstrap、可选通话与扩展能力均在当前仓库内实现或对接。

**明确定义**：

- **它是**：一个可运行的 Flutter 应用，面向“想跑起来”的开发者和“想理解客户端与 Tim2Tox 关系”的维护者；同时作为集成 Tim2Tox 的参考实现。
- **它不是**：底层协议库（协议与 V2TIM 映射在 Tim2Tox 中实现）。
- **它不是**：通用 SDK（UI、账号体系、Bootstrap 配置、通话桥等是 toxee 自身实现，其他客户端需自行适配）。

---

## 这个项目解决什么问题

- **对使用者**：提供一个“开箱可跑”的 Tox 聊天客户端，使用现成 UIKit 界面与交互，无需从零写 UI。
- **对集成者**：展示如何做依赖引导（submodule、SDK 拉取与打补丁、pubspec_overrides）、如何实现 Tim2Tox 的接口注入（Preferences、Logger、Bootstrap 等）、如何安排 init → login → startPolling → Platform 的启动顺序。
- **对维护者**：说明为何采用混合架构、二进制替换与 Platform 各自承担哪些能力、调用链与日志从哪里看，便于排错与扩展。

---

## 它与 Tim2Tox 的关系


| 维度       | Tim2Tox                                                            | toxee                                                                    |
| -------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| **角色**   | 兼容层/框架：提供 C++ 核心、C FFI、Dart 封装与 SDK Platform 实现，供任意 Flutter 客户端接入。 | 客户端/示例应用：消费 Tim2Tox，实现账号、UI、Bootstrap、历史、通话桥等。                           |
| **位置**   | `third_party/tim2tox`（submodule，上游 [anonymoussoft/tim2tox](https://github.com/anonymoussoft/tim2tox)）。                            | 本仓库根目录。                                                                  |
| **依赖方向** | Tim2Tox 不依赖 toxee；通过接口注入依赖“偏好/日志/Bootstrap”等能力。                    | toxee 依赖 `tim2tox_dart`，并实现 Tim2Tox 所需的接口、构造 FfiChatService、设置 Platform。 |


**调用关系（简化）**：

```
toxee (UI / 账号 / Bootstrap / 适配层)
    │
    ├── setNativeLibraryName('tim2tox_ffi')   →  SDK 加载 libtim2tox_ffi
    ├── FfiChatService( prefs, logger, bootstrap, ... )  →  Tim2Tox 服务层
    ├── Tim2ToxSdkPlatform( ffiService )     →  Platform 路径入口
    └── FakeUIKit / FakeMessageManager 等     →  将 Tim2Tox 数据适配为 UIKit 格式
                    │
                    ▼
            Tim2Tox (dart / ffi / C++)
                    │
                    ▼
            c-toxcore (Tox P2P)
```

---

## 当前架构概览

当前采用**混合架构**：既做**二进制替换**（SDK 仍通过 NativeLibraryManager → Dart* 调用 Tim2Tox），又设置 **Tim2ToxSdkPlatform**（历史、部分回调、通话等走 FfiChatService）。

**为什么是混合架构而不是纯二进制替换或纯 Platform？**

- **纯二进制替换**：最少改业务代码，但历史消息、clearHistoryMessage、groupQuitNotification、Bootstrap 配置、轮询与通话等需要 Dart 侧状态与持久化，仅靠 C++ 回调无法完整实现；UIKit 的 getHistoryMessageList 等会失败或行为不完整。
- **纯 Platform**：所有 SDK 调用都走 Platform，需要实现的方法多、与 SDK 版本强绑定，迁移与维护成本高；且当前 SDK 的 isCustomPlatform 路由下，部分能力仍依赖原生库加载，纯 Platform 难以完全替代。
- **混合架构**：大部分调用沿用“换库不换接口”的二进制替换，保持与现有 SDK 调用习惯一致；仅把“必须由 Dart 实现”的能力（历史、轮询、Bootstrap、通话桥、部分回调）交给 Platform + FfiChatService，兼顾兼容性与功能完整性。详见 [doc/architecture/HYBRID_ARCHITECTURE.md](doc/architecture/HYBRID_ARCHITECTURE.md)。

**调用链（ASCII）**：

```
                    UIKit / 业务
                          │
        ┌─────────────────┴─────────────────┐
        │                                    │
   TIMManager.instance              getHistoryMessageList 等
        │                                    │
   NativeLibraryManager              Tim2ToxSdkPlatform
   bindings.DartXXX()                     │
        │                                    │
        └──────────────┬─────────────────────┘
                       │
              libtim2tox_ffi (dart_compat_* / tim2tox_ffi_*)
                       │
              FfiChatService（轮询、历史、登录状态）
                       │
              V2TIM*Manager / ToxManager → c-toxcore
```

---

## 仓库结构


| 路径               | 职责与边界                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------ |
| `lib/`           | 应用 Dart 代码：UI、启动、适配层、工具。                                                                         |
| `lib/bootstrap/` | 启动阶段：日志与路径（`LoggingBootstrap`）、`setNativeLibraryName('tim2tox_ffi')`、C++ 日志文件设置；在 `main()` 最早执行。 |
| `lib/adapters/`  | Tim2Tox 接口实现：Preferences、Logger、Bootstrap、EventBus、ConversationManager 等，注入给 FfiChatService。     |
| `lib/sdk_fake/`  | 适配层：将 FfiChatService / Tim2Tox 数据转换为 UIKit 所需的 Fake 模型与 Provider，桥接消息、会话、好友、群组。                  |
| `lib/ui/`        | 页面与组件：登录、首页、会话、设置、Bootstrap 等；主要使用 UIKit 组件，少量自定义页。                                              |
| `lib/util/`      | 工具：`AppLogger`、偏好、Bootstrap 节点列表、主题/语言等。                                                         |
| `lib/startup/`   | 启动流程：账号恢复、Bootstrap 决策、init → login → startPolling、超时与错误处理。                                      |
| `lib/call/`      | 通话 UI 与效果（TUICallKit 适配、来电 overlay 等）。                                                           |
| `tool/`          | 依赖引导：`bootstrap_deps.dart`（submodule、SDK 拉取与打补丁、pubspec_overrides）。                              |
| `third_party/`   | 依赖：tim2tox、tencent_cloud_chat_sdk、chat-uikit-flutter（submodule 或脚本拉取）。                           |
| `doc/`           | 架构、混合架构、账号会话、构建、排错、扩展等文档。                                                                        |


---

## 快速开始

**从零开始的最短启动路径**（在仓库根目录执行）：

```bash
# 1. 克隆（若尚未克隆）
git clone <repo-url> toxee && cd toxee

# 2. 依赖引导：submodule、SDK 拉取与打补丁、生成 pubspec_overrides
dart run tool/bootstrap_deps.dart

# 3. 拉取 Dart/Flutter 依赖
flutter pub get

# 4. 构建并运行（会先构建 tim2tox FFI 库）
./build_all.sh --platform macos --mode debug
# 或使用 run 脚本（构建 + 启动 + 可选日志 tail）
./run_toxee.sh
```

若出现 `package_config.json` 解析错误，可先执行 `dart tool/bootstrap_deps.dart`（不用 `run`）再执行 `flutter pub get`。完整步骤与常见问题见 [doc/getting-started.md](doc/getting-started.md)、[doc/operations/DEPENDENCY_BOOTSTRAP.md](doc/operations/DEPENDENCY_BOOTSTRAP.md)。

---

## 构建与运行

- **统一构建**：`./build_all.sh --platform <macos|ios|android|...> --mode <debug|release>`；**仅运行**：`./run_toxee.sh`（其他平台见 `run_toxee_ios.sh`、`run_toxee_android.sh` 等）。
- 详细步骤、各平台说明、依赖布局见 [doc/operations/BUILD_AND_DEPLOY.md](doc/operations/BUILD_AND_DEPLOY.md)、[doc/operations/DEPENDENCY_BOOTSTRAP.md](doc/operations/DEPENDENCY_BOOTSTRAP.md)、[doc/operations/DEPENDENCY_LAYOUT.md](doc/operations/DEPENDENCY_LAYOUT.md)。遇到问题见 [doc/TROUBLESHOOTING.md](doc/TROUBLESHOOTING.md)。

---

## 文档入口

完整文档索引与按角色阅读路径（新用户 / 接入方 / 维护者）见 **[doc/README](doc/README.md)**。常用入口：[依赖引导](doc/operations/DEPENDENCY_BOOTSTRAP.md)、[排障](doc/TROUBLESHOOTING.md)、[混合架构](doc/architecture/HYBRID_ARCHITECTURE.md)、[接入指南](doc/integration/INTEGRATION_GUIDE.md)、[维护者视角](doc/architecture/MAINTAINER_ARCHITECTURE.md)。

---

## 适用场景与非适用场景

**适用**：

- 想快速跑通一个基于 Tox 的 Flutter 聊天应用。
- 需要参考“如何把 Tim2Tox 集成进客户端”（依赖、接口、启动顺序、混合架构）。
- 在现有 toxee 基础上做功能扩展或二次开发（UI、Bootstrap、通话、插件等）。

**非适用**：

- 仅需“Tox 协议库”或“通用 IM SDK”：应使用 Tim2Tox 或 c-toxcore，而非 toxee。
- 需要与腾讯云 IM 服务端互通：toxee 后端为 Tox P2P，不连接腾讯云。

---

## 已知限制

- **平台**：构建与日常开发以 macOS 为主；iOS/Android 需按各平台配置与脚本验证。
- **历史与回调**：历史消息在 Dart 侧（FfiChatService / MessageHistoryPersistence）；混合架构下需避免二进制替换路径与 Platform 路径重复写历史或重复回调（由 BinaryReplacementHistoryHook 与 Platform 分工约定）。
- **多实例**：toxee 使用 Tim2Tox 默认单例；多实例主要用于 tim2tox 的 auto_tests，不在本客户端默认流程。
- **依赖**：依赖 submodule 与脚本拉取的 SDK/UIKit；首次或变更依赖后必须执行 `dart run tool/bootstrap_deps.dart` 再 `flutter pub get`。

---

## 新贡献者 onboarding

- 先按「快速开始」在本地跑通一次，确认能登录、发消息、看会话列表。
- 阅读本 README「5 分钟内理解」「它与 Tim2Tox 的关系」「当前架构概览」；再按 [doc/README](doc/README.md) 中与你目标一致的**推荐阅读路径（按角色）**走一遍。
- 改启动/日志/依赖：`lib/main.dart`、`lib/bootstrap/logging_bootstrap.dart`、`tool/bootstrap_deps.dart`；改消息/会话/历史：`lib/sdk_fake/`、[doc/architecture/HYBRID_ARCHITECTURE.md](doc/architecture/HYBRID_ARCHITECTURE.md)。修改 Tim2Tox 本身在 `third_party/tim2tox`（上游 [anonymoussoft/tim2tox](https://github.com/anonymoussoft/tim2tox)），见 [third_party/tim2tox/doc/README.md](third_party/tim2tox/doc/README.md)。

---

## 许可证

见 [LICENSE](LICENSE) 文件。