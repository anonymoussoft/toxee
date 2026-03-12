# toxee 通话与扩展
> 语言 / Language: [中文](CALLING_AND_EXTENSIONS.md) | [English](CALLING_AND_EXTENSIONS.en.md)


本文档说明 toxee 中已经落地、但不属于基础聊天链路的扩展能力：音视频通话、UIKit 插件、局域网 Bootstrap 与 IRC 集成。

## 1. 通话架构

当前客户端的通话实现依赖三个层次：

- `FakeUIKit.startWithFfi()` 创建 `CallStateNotifier` 和 `CallServiceManager`
- `HomePage.initState()` 在 `Tim2ToxSdkPlatform` 设置完成后调用 `callServiceManager.initialize()`
- `CallServiceManager.initialize()` 依次初始化 `ToxAVService`、`CallBridgeService`、`TUICallKitAdapter`，并通过 `registerToxAVWithTUICore()` 注册到 TUICore

这意味着通话系统依赖 `Tim2ToxSdkPlatform` 已经就绪；否则 signaling listener 无法正确挂载。

## 2. 两条通话路径

### 2.1 Signaling 路径

这是 UIKit 触发的主路径：

1. 用户在 UIKit 中点击音视频通话按钮
2. TUICore 把调用转给 `TUICallKitAdapter`
3. `TUICallKitAdapter` 通过 `Tim2ToxSdkPlatform.invite()` 创建 signaling invite
4. 若能解析出好友 `friendNumber`，则同步调用 `ToxAVService.startCall()`
5. `CallBridgeService` 负责处理接受、拒绝、取消、超时等 signaling 事件
6. `CallStateNotifier` 驱动通话 UI 和悬浮层

### 2.2 Native ToxAV 路径

这是为了兼容 qTox 等外部 ToxAV 呼叫保留的路径：

1. `ToxAVService` 直接收到 native callback
2. `CallServiceManager` 把它映射成 `native_av_<friendNumber>` 形式的 inviteID
3. UI 仍通过 `CallStateNotifier` 进入统一的来电/通话状态机

因此，客户端既支持 UIKit signaling 路径，也支持纯 ToxAV 直连路径。

## 3. 通话记录写入

通话结束时，`CallServiceManager` 会回调 `FakeUIKit.onCallRecordNeeded`。随后 `FakeUIKit` 会：

- 构造自定义消息格式的通话记录
- 写入 `FfiChatService` 历史，确保历史消息查询可见
- 通过 event bus 发出实时事件
- 注入 UIKit `messageData`，保证当前打开会话立即刷新

这保证了“历史可追溯”和“当前会话实时刷新”同时成立。

## 4. UIKit 插件接入

### 4.1 sticker

- 在 `HomePage.initState()` 中优先于 message 组件注册
- 如果 `selfId` 尚未就绪，则在连接成功后补注册
- 这样可以避免 message input 初始化时拿不到 `stickerPluginInstance`

### 4.2 textTranslate / soundToText

- 在 HomePage 中按需懒注册
- 注册状态由 `_textTranslatePluginRegistered` 和 `_soundToTextPluginRegistered` 控制，避免重复接入

## 5. 局域网 Bootstrap

`LanBootstrapServiceManager` 负责桌面端本地 Bootstrap 服务：

- 自动探测本机可用 LAN IP
- 创建独立测试实例作为 Bootstrap 服务节点
- 暴露本机 IP、UDP 端口和 DHT 公钥给 UI
- 允许客户端在局域网内快速互连

这部分不是基础聊天必需能力，但对桌面局域网调试和演示很重要。

## 6. IRC 集成

`IrcAppManager` 负责 IRC 扩展：

- 动态加载 `libirc_client.dylib`
- 为 IRC channel 创建 / 恢复对应的 Tox group
- 维护 `channel -> groupId` 映射
- 调用 `FfiChatService.connectIrcChannel()` / `disconnectIrcChannel()` / `unloadIrcLibrary()`

客户端 UI 只负责安装状态、频道入口和交互，真正的 IRC 网络收发仍在 tim2tox 侧动态库实现。

## 7. 相关文档

- [HYBRID_ARCHITECTURE.md](HYBRID_ARCHITECTURE.md)
- [IMPLEMENTATION_DETAILS.md](IMPLEMENTATION_DETAILS.md)
- [../../tim2tox/doc/TOXAV_AND_SIGNALING.md](../../tim2tox/doc/TOXAV_AND_SIGNALING.md)
