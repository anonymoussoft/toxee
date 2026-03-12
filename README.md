# toxee

toxee 是一个集成 Tim2Tox 的示例 Flutter 聊天客户端应用。当前实现运行在“二进制替换 + Platform/FfiChatService 并存”的混合架构上，用于承接 Tencent Cloud Chat UIKit 的消息、会话、账号、Bootstrap 与通话能力。

## 文档 / Documentation

- 中文文档索引：[doc/README.md](doc/README.md)
- English documentation index: [doc/README.en.md](doc/README.en.md)
- 当前架构说明：[doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) / [doc/ARCHITECTURE.en.md](doc/ARCHITECTURE.en.md)
- 混合架构与回调路径：[doc/HYBRID_ARCHITECTURE.md](doc/HYBRID_ARCHITECTURE.md) / [doc/HYBRID_ARCHITECTURE.en.md](doc/HYBRID_ARCHITECTURE.en.md)
- 账号与会话生命周期：[doc/ACCOUNT_AND_SESSION.md](doc/ACCOUNT_AND_SESSION.md) / [doc/ACCOUNT_AND_SESSION.en.md](doc/ACCOUNT_AND_SESSION.en.md)
- 相关 Tim2Tox 文档：[../tim2tox/doc/README.md](../tim2tox/doc/README.md) / [../tim2tox/doc/README.en.md](../tim2tox/doc/README.en.md)

## 项目结构

本项目位于与 `tim2tox` 同级的目录：

```
chat-uikit/
├── tim2tox/                    # Tim2Tox 实现
│   ├── source/                 # C++ 核心实现
│   ├── ffi/                    # C/C++ FFI 接口层
│   └── dart/                   # Dart 包（tim2tox_dart）
│       └── lib/
│           ├── ffi/            # FFI 绑定层
│           ├── service/        # 服务层
│           └── sdk/            # SDK Platform 实现
│
└── toxee/        # 本 Flutter 客户端应用
    ├── lib/
    │   ├── sdk_fake/           # 适配层（将 tim2tox 数据转换为 UIKit 格式）
    │   ├── ui/                  # UI 组件
    │   ├── util/                # 工具类（偏好设置、日志等）
    │   └── i18n/                # 国际化
    └── macos/                   # macOS 平台配置
```

## 集成方案

toxee 当前使用**混合架构**集成 Tim2Tox，而不是单独的“纯二进制替换”或“纯 Platform 接口”模式。

### 当前实现：混合架构

**关键点**：
- UIKit 大部分 SDK 调用仍通过 `TIMManager.instance` → `NativeLibraryManager` → Dart* 函数进入 Tim2Tox。
- `HomePage` 启动阶段会设置 `TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(...)`，用于历史查询、特殊回调、会话联动等 Platform 路径。
- `FakeUIKit.startWithFfi(...)` 与 `FfiChatService` 负责账号恢复、Bootstrap 节点加载、poll loop、文件事件、通话桥和扩展插件能力。
- 客户端使用默认实例；多实例主要面向 `tim2tox/auto_tests` 等测试场景。

**主调用路径**：
```
UIKit SDK
  ↓
TIMManager.instance / UIKit Providers
  ↓
NativeLibraryManager 或 Tim2ToxSdkPlatform
  ↓
FfiChatService / Tim2ToxFfi / dart_compat_layer.cpp
  ↓
V2TIM*Manager / ToxManager
```

**详细说明**：
- 客户端整体架构：[doc/ARCHITECTURE.md](doc/ARCHITECTURE.md)
- 混合架构职责分工：[doc/HYBRID_ARCHITECTURE.md](doc/HYBRID_ARCHITECTURE.md)
- Tim2Tox 架构与二进制替换机制：[../tim2tox/doc/ARCHITECTURE.md](../tim2tox/doc/ARCHITECTURE.md) / [../tim2tox/doc/BINARY_REPLACEMENT.md](../tim2tox/doc/BINARY_REPLACEMENT.md)

## 架构概述

### 整体架构（简化示意）

```
┌─────────────────────────────────────────────────────────┐
│              toxee (客户端)                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │   UI     │  │  Adapter │  │  Utils   │  │   i18n   │ │
│  │  Layer   │  │  Layer   │  │  Layer   │  │          │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────────┘ │
└───────┼──────────────┼─────────────┼────────────────────┘
        │              │             │
        └──────────────┴─────────────┘
                       │
        ┌──────────────▼──────────────┐
        │    Tim2Tox Dart Package      │
        │  ┌────────┐  ┌──────────┐  │
        │  │  SDK   │  │ Service  │  │
        │  │Platform│  │  Layer   │  │
        │  └───┬────┘  └────┬─────┘  │
        │      │             │        │
        │  ┌───▼─────────────▼─────┐ │
        │  │    FFI Bindings        │ │
        │  └───────────┬────────────┘ │
        └──────────────┼──────────────┘
                      │
        ┌─────────────▼─────────────┐
        │        Tim2Tox            │
        │  ┌────────┐  ┌─────────┐  │
        │  │  FFI   │  │  C++    │  │
        │  │  C/C++ │  │  Core   │  │
        │  └───┬────┘  └────┬────┘  │
        └──────┼────────────┼───────┘
               │            │
        ┌──────▼────────────▼──────┐
        │      Tox (c-toxcore)      │
        └───────────────────────────┘
```

### 数据流（当前实现）

**SDK 调用路径**（所有 UIKit SDK 操作）：
```
UIKit SDK Calls 
  → TIMManager.instance (原生 SDK 调用方式)
  → NativeLibraryManager.bindings.DartXXX(...)
  → FFI 动态查找符号 (在 libtim2tox_ffi.dylib 中)
  → dart_compat_layer.cpp (Dart* 函数实现)
  → V2TIM*Manager (C++ API 实现)
  → ToxManager (Tox 核心)
  → toxcore (P2P 通信)
```

**重要说明**：
- 当前实现同时使用 `NativeLibraryManager` 路径与 `Tim2ToxSdkPlatform` 路径
- 动态库名称从 `dart_native_imsdk` 替换为 `tim2tox_ffi`
- 消息ID统一使用 `timestamp_userID` 格式（毫秒级时间戳），确保唯一性和一致性
- 完全兼容原生 SDK 的调用方式和回调格式

**消息发送路径**：
```
UIKit Message Input 
  → ChatMessageProvider (Fake)
  → 离线检测（如果联系人离线，立即标记为失败）
  → TIMManager.instance.getMessageManager().sendMessage()
  → NativeLibraryManager.bindings.DartSendMessage(...)
  → dart_compat_layer.cpp::DartSendMessage()
  → V2TIMMessageManagerImpl::SendMessage(...)
  → ToxManager::SendMessage(...)
  → tox_friend_send_message() (c-toxcore)
  → 超时检测（文本消息5秒，文件消息根据大小动态计算）
  → 如果超时或失败，保存到本地持久化存储
```

**接收路径**（事件/消息）：
```
toxcore (P2P 网络接收)
  → ToxManager::OnFriendMessage()
  → V2TIMMessageManagerImpl::OnRecvNewMessage()
  → DartAdvancedMsgListenerImpl::OnRecvNewMessage()
  → BuildGlobalCallbackJson() (json_parser.cpp)
  → SendCallbackToDart() (callback_bridge.cpp)
  → Dart_PostCObject_DL() (发送到 Dart ReceivePort)
  → NativeLibraryManager._handleNativeMessage()
  → NativeLibraryManager._handleGlobalCallback()
  → UIKit SDK Listeners
  → UI 更新
```

### 核心组件

#### Framework 层（tim2tox_dart 包）

- **Tim2ToxFfi** (`tim2tox_dart/lib/ffi/`): Dart FFI 绑定，直接调用 C 库
- **FfiChatService** (`tim2tox_dart/lib/service/`): 高级服务层，管理消息历史、轮询、状态等
- **Tim2ToxSdkPlatform** (`tim2tox_dart/lib/sdk/`): 实现 `TencentCloudChatSdkPlatform` 接口
- **抽象接口** (`tim2tox_dart/lib/interfaces/`): 定义可注入的依赖接口

#### 客户端适配层（本项目中）

**接口适配器** (`lib/adapters/`):
- `SharedPreferencesAdapter`: 实现 `ExtendedPreferencesService`，使用 `SharedPreferences`
- `AppLoggerAdapter`: 实现 `LoggerService`，使用 `AppLogger`
- `BootstrapNodesAdapter`: 实现 `BootstrapService`，使用 `BootstrapNodes`
- `EventBusAdapter`: 实现 `EventBusProvider`，使用 `FakeEventBus`
- `ConversationManagerAdapter`: 实现 `ConversationManagerProvider`，使用 `FakeConversationManager`

**数据适配层** (`lib/sdk_fake/`):
- `fake_im.dart`: 事件总线，订阅 FfiChatService 并发出 FakeConversation/FakeMessage 等
- `fake_managers.dart`: Conversation/Message/Contact 管理器
- `fake_provider.dart` & `fake_msg_provider.dart`: 桥接到 UIKit 的可插拔数据提供者接口
- `fake_uikit_core.dart`: UIKit 核心适配
- `fake_event_bus.dart`: 事件总线实现
- `fake_models.dart`: 客户端特定的数据模型（与 framework 模型兼容）

**工具层** (`lib/util/`):
- `prefs.dart`: 偏好设置管理（SharedPreferences）
- `logger.dart`: 日志系统
- `bootstrap_nodes.dart`: Bootstrap 节点配置
- `tox_utils.dart`: Tox ID 工具函数
- `theme_controller.dart`: 主题管理
- `locale_controller.dart`: 语言管理

**UI 层** (`lib/ui/`):
- 主要使用 Tencent Cloud Chat UIKit 组件
- 少量自定义 UI（登录页、设置页等）

## 依赖关系

### Framework 依赖

```yaml
dependencies:
  tim2tox_dart:
    path: ../tim2tox/dart
```

### UIKit 依赖

```yaml
dependencies:
  tencent_cloud_chat_common: ^4.1.0+1
  tencent_cloud_chat_message: ^4.1.0+3
  tencent_cloud_chat_conversation: ^4.1.0
  tencent_cloud_chat_contact: ^4.1.0
  # ... 其他 UIKit 包
```

所有 UIKit 包通过 `dependency_overrides` 指向本地路径。

## 构建和运行

### 快速开始（推荐）

#### 跨平台构建脚本

使用跨平台构建脚本构建所有支持的平台：

```bash
./build_all.sh
```

构建特定平台：

```bash
./build_all.sh --platform macos --platform linux --platform windows
```

构建选项：

```bash
./build_all.sh --help  # 查看所有选项
```

#### macOS 快速启动脚本

使用一键脚本（仅 macOS）：

```bash
cd /Users/bin.gao/chat-uikit/toxee
bash run_toxee.sh
```

这个脚本会：
1. 构建 tim2tox framework（包括 FFI 库，使用 DEBUG 模式以便调试）
2. 构建 IRC 客户端库（如果需要）
3. 构建 Flutter macOS 应用（DEBUG 模式）
4. 将 `libtim2tox_ffi.dylib` 和 `libsodium` 打包到应用 bundle
5. 修复动态库路径（使用 `@loader_path`）
6. 启动应用并显示日志（实时 tail 日志文件）

**日志文件**:
- `build/native_build.log` - C++ 构建日志
- `build/flutter_build.log` - Flutter 构建日志
- `build/flutter_client.log` - 应用运行时日志（符号链接到沙盒目录的实际日志文件）

**日志位置**:
- 实际日志文件位于: `~/Library/Containers/com.example.toxee/Data/Library/Application Support/com.example.toxee/flutter_client.log`
- 项目目录中的 `build/flutter_client.log` 是指向实际日志文件的符号链接

**注意事项**:
- 脚本会自动检测更改，如果没有更改会跳过构建
- 如果遇到构建错误，查看日志文件获取详细信息
- 首次构建可能需要较长时间（下载依赖、编译等）
- 脚本使用 DEBUG 模式构建，包含完整的调试符号，便于调试崩溃问题
- 应用会在后台运行，脚本会持续 tail 日志直到应用退出

### 手动构建

#### 1. 构建 tim2tox framework

```bash
cd ../tim2tox
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_FFI=ON
make tim2tox_ffi
```

#### 2. 构建 IRC 客户端（可选）

```bash
cd ../example
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make irc_client
```

#### 3. 构建 Flutter 应用

```bash
cd ../../toxee
flutter pub get
flutter build macos --debug
```

#### 4. 复制动态库到应用 bundle

```bash
# 复制 FFI 库
cp ../tim2tox/build/ffi/libtim2tox_ffi.dylib \
   build/macos/Build/Products/Debug/toxee.app/Contents/MacOS/

# 复制 IRC 库（如果需要）
cp ../tim2tox/example/build/libirc_client.dylib \
   build/macos/Build/Products/Debug/toxee.app/Contents/MacOS/

# 复制 libsodium（如果需要）
# 使用 install_name_tool 修复路径
```

## 文档

### 主要文档

- [构建和部署指南](doc/BUILD_AND_DEPLOY.md) - 详细构建步骤、各平台构建说明、依赖安装、常见错误解决
- [集成指南](doc/INTEGRATION_GUIDE.md) - 如何集成 tim2tox framework、接口适配器实现、初始化流程、最佳实践
- [故障排除](doc/TROUBLESHOOTING.md) - 常见问题解答、日志分析、调试技巧、性能优化

### 其他文档

- [架构文档](doc/ARCHITECTURE.md) - 整体架构设计
- [实现细节](doc/IMPLEMENTATION_DETAILS.md) - 实现细节说明
- [混合架构文档](doc/HYBRID_ARCHITECTURE.md) - 当前混合架构职责、回调路径与数据流
- [账号与会话](doc/ACCOUNT_AND_SESSION.md) - 账号初始化、切换、退出与删除生命周期
- [通话与扩展能力](doc/CALLING_AND_EXTENSIONS.md) - 通话、插件、局域网 Bootstrap 与 IRC 扩展能力
- [平台支持](doc/PLATFORM_SUPPORT.md) - 平台支持说明

## 使用 Tim2Tox

### 初始化

在 `lib/ui/home_page.dart` 的 `initState()` 中：

```dart
import 'package:tim2tox_dart/tim2tox_dart.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'adapters/shared_prefs_adapter.dart';
import 'adapters/logger_adapter.dart';
import 'adapters/bootstrap_adapter.dart';
import 'adapters/event_bus_adapter.dart';
import 'adapters/conversation_manager_adapter.dart';
import 'sdk_fake/fake_uikit_core.dart';

// 1. 初始化 FakeUIKit（这会初始化 conversationManager）
FakeUIKit.instance.startWithFfi(widget.service);

// 2. 创建接口适配器
final prefsAdapter = SharedPreferencesAdapter(await SharedPreferences.getInstance());
final loggerAdapter = AppLoggerAdapter();
final bootstrapAdapter = BootstrapNodesAdapter(await SharedPreferences.getInstance());
final eventBusAdapter = EventBusAdapter(FakeUIKit.instance.eventBusInstance);
final conversationManagerAdapter = ConversationManagerAdapter(
  FakeUIKit.instance.conversationManager!,
);

// 3. 创建服务
final ffiService = FfiChatService(
  preferencesService: prefsAdapter,
  loggerService: loggerAdapter,
  bootstrapService: bootstrapAdapter,
);

// 4. 设置 SDK Platform
TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform(
  ffiService: ffiService,
  eventBusProvider: eventBusAdapter,
  conversationManagerProvider: conversationManagerAdapter,
);
```

### 接口适配器

客户端需要实现以下接口适配器（已在 `lib/adapters/` 中提供）：

**必需接口**：
- `ExtendedPreferencesService`: `SharedPreferencesAdapter` - 使用 `SharedPreferences`
- `LoggerService`: `AppLoggerAdapter` - 使用 `AppLogger`
- `BootstrapService`: `BootstrapNodesAdapter` - 使用 `BootstrapNodes`

**可选接口**（用于高级功能）：
- `EventBusProvider`: `EventBusAdapter` - 使用 `FakeEventBus`
- `ConversationManagerProvider`: `ConversationManagerAdapter` - 使用 `FakeConversationManager`

这些适配器将 framework 的抽象接口映射到客户端的具体实现。

## 功能特性

- ✅ 点对点聊天（C2C）
- ✅ 群组聊天
- ✅ 好友管理（添加、删除、接受请求）
- ✅ 文件传输
- ✅ 消息反应（Reactions）
- ✅ 已读回执
- ✅ 输入状态（Typing）
- ✅ **用户状态（在线/离线）** - 已修复，现在可以正确显示在线状态
- ✅ IRC 通道桥接（可选）
- ✅ 完整的 UIKit 集成
- ✅ **回调系统优化** - 所有回调数据正确传递，JSON 格式统一
- ✅ **失败消息处理**：
  - 消息发送超时机制（文本消息5秒，文件消息根据大小动态计算）
  - 离线联系人立即失败检测
  - 失败消息本地持久化（使用 SharedPreferences）
  - 客户端重启后自动恢复失败消息状态
- ✅ **消息ID管理**：
  - 统一使用 `timestamp_userID` 格式（毫秒级时间戳）
  - 确保消息ID的唯一性和一致性
- ✅ **模块化架构**：
  - Tim2Tox FFI 层已完全模块化，代码更易维护
  - 13个功能模块，每个模块专注于特定功能
  - 主文件仅29行，所有实现都在模块文件中

## 编程原则

### 优先使用 UIKit 组件

在编写自定义组件之前，先查找现有的 chat-uikit-flutter 组件。只编写胶水代码/适配器。

示例：
- 会话列表：`TencentCloudChatConversation`
- 消息页面：`TencentCloudChatMessage`
- 联系人：`TencentCloudChatContact`
- 好友请求：`TencentCloudChatContactApplicationList`

### 保持传输细节远离 UI

- 不在 Flutter 或高级 C++ 示例应用中使用 tox 头文件/类型
- 所有 tox 特定代码保留在 tim2tox 内部，通过 V2TIM 类 API 和 C FFI 暴露

### 原生→Dart 的稳定性优先

- 不要从原生后台线程直接 FFI 回调
- 使用字符串编码的事件，从 Dart 端轮询，然后通过事件总线/流分发

### 持久化和身份

- tox savedata 持久化到 `~/Library/Application Support/tim2tox/tox_profile.tox`（macOS）
- 用户配置文件（昵称、状态）和仅本地数据（群组、本地好友、草稿、主题、语言）通过 SharedPreferences 存储

### 国际化和主题

- 应用字符串：`lib/i18n/app_localizations.dart`
- UIKit i18n：`TencentCloudChatLocalizations`
- 主题：使用 `TencentCloudChatThemeWidget` 和 Material Theme

## 故障排除

### 快速诊断

1. **查看日志文件**:
   - `build/native_build.log` - C++ 构建错误
   - `build/flutter_build.log` - Flutter 构建错误
   - `build/flutter_client.log` - 运行时错误

2. **常见问题**:
   - 动态库加载失败 → 检查库路径和依赖
   - 连接失败 → 检查网络和 Bootstrap 节点
   - 消息发送失败 → 检查联系人在线和超时设置
   - 回调不触发 → 检查 SendPort 注册和 Dart API 初始化

3. **详细故障排除**:
   请参考 [故障排除指南](doc/TROUBLESHOOTING.md) 获取详细的问题解决方案。

### 常见问题速查

#### UI 显示 "Invalid friend application"
- 确保接受好友由 `ContactActionProvider`（fake provider）处理，并为 UIKit 返回 resultCode 0

#### Flutter 在原生事件期间崩溃
- 确保所有事件在 C++ 中作为字符串排队，并在 Dart 端轮询
- 避免从原生线程调用 Dart 回调

#### 消息顺序错误
- 消息列表在渲染前按时间戳升序排序，并在消息列表容器中自动滚动到底部

#### Tox 无法连接
- 检查 `build/flutter_client.log` 中的 "bootstrap nodes queued"
- 验证网络权限和 libsodium 打包
- 检查 savedata 位置和 Login bootstrap

## 日志文件

构建和运行脚本会生成以下日志：

- `build/native_build.log` - C++ 构建日志
- `build/flutter_build.log` - Flutter 构建日志
- `build/flutter_client.log` - 应用运行时日志

## 环境要求

### 支持的操作系统

- **macOS**: 10.14 或更高版本
- **Linux**: 支持主流发行版（Ubuntu, Debian, Fedora 等）
- **Windows**: Windows 10 或更高版本
- **Android**: Android 5.0 (API 21) 或更高版本
- **iOS**: iOS 12.0 或更高版本

### 工具链要求

- **Flutter**: >= 3.22, Dart >= 3.5
- **CMake**: >= 3.4.1（用于 C++ 原生构建）
- **平台特定工具**:
  - **macOS**: Xcode（用于构建 macOS/iOS bundle）
  - **Linux**: GTK3 开发库（`libgtk-3-dev`）
  - **Windows**: Visual Studio 2019 或更高版本（用于构建 Windows 应用）
  - **Android**: Android SDK 和 NDK
  - **iOS**: Xcode（仅限 macOS）

### 原生库依赖

- **libsodium**: 加密库（所有平台都需要）
  - macOS: 通过 Homebrew 安装 (`brew install libsodium`)
  - Linux: 通过包管理器安装 (`apt-get install libsodium-dev` 或 `yum install libsodium-devel`)
  - Windows: 通过 vcpkg 安装 (`vcpkg install libsodium`)
  - Android/iOS: 通过构建脚本自动处理

### 权限要求

**macOS**:
- `com.apple.security.network.client = true`
- `com.apple.security.files.user-selected.read-only / read-write = true`

**Linux/Windows**: 无特殊权限要求

**Android**: 需要网络权限（在 AndroidManifest.xml 中配置）

**iOS**: 需要网络权限（在 Info.plist 中配置）

## 扩展指南

### 添加新消息类型

1. 在 tim2tox 和 FFI 包装器中添加原生发送
2. 在 Dart 中：在 FfiChatService 中解析事件并发出类型化消息
3. 映射到 UIKit：使用内置构建器或通过 chat-uikit 插件点注册自定义构建器

### 群组功能

1. 扩展 V2TIMManagerImpl 以完全管理 Tox 会议（加入/离开/成员/角色）
2. 更新 FakeIM 以发出群组事件，更新 FakeMessageManager 以处理群组历史和发送

### 状态/已读回执/输入增强

1. 将相关的 tox 事件映射到 tim2tox → FFI → FfiChatService，并通过 FakeIM 广播
2. 连接到 ChatMessageProvider/Conversation 流，以便 UIKit 更新徽章和指示器

## 与 Tim2Tox 的关系

本客户端应用是 Tim2Tox 的使用示例。核心实现位于 `../tim2tox/`，包括：

- C++ 核心实现
- FFI 接口层
- Dart 包（tim2tox_dart）

客户端只包含：
- UI 组件
- 适配层（将 framework 数据转换为 UIKit 格式）
- 客户端特定的工具类

这种分离使得 Framework 可以被其他 Flutter 客户端复用。

## 许可证

本项目采用 GPL-3.0 许可证。详见 [LICENSE](LICENSE) 文件。

### 许可证说明

本项目使用 GPL-3.0 许可证，因为：

1. **依赖关系**：本项目直接依赖 `tim2tox_dart` 包（GPL-3.0）
2. **代码合并**：`tim2tox_dart` 的代码会被编译到本项目的最终二进制文件中
3. **Copyleft 条款**：根据 GPL-3.0 的 copyleft 条款，使用 GPL-3.0 库的项目也必须使用 GPL-3.0

### 商业使用

GPL-3.0 允许商业使用，但要求：
- 如果分发软件，必须提供源代码
- 衍生作品也必须使用 GPL-3.0

更多信息请参考 [GPL-3.0 许可证全文](LICENSE) 和 [Tim2Tox 二进制替换机制说明](../tim2tox/doc/BINARY_REPLACEMENT.md)。
