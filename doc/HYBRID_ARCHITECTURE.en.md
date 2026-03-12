# toxee Hybrid Architecture
> Language: [Chinese](HYBRID_ARCHITECTURE.md) | [English](HYBRID_ARCHITECTURE.en.md)


This document describes the hybrid architecture currently used by toxee: the underlying calls are still based on the binary replacement path, and historical messages, calls, some custom callbacks and expansion capabilities are supplemented by `Tim2ToxSdkPlatform`.

## 1. Architecture Overview

toxee is not a pure binary replacement, but a **mixed mode**:

- **Binary replacement**: The dynamic library is replaced from `dart_native_imsdk` to `libtim2tox_ffi`, and most C++ callbacks are dispatched through NativeLibraryManager
- **Hybrid Platform**: In **HomePage.initState()**, set `TencentCloudChatSdkPlatform.instance = Tim2ToxSdkPlatform` when `TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform`, used for historical queries, some SDK calls and C++ special callbacks

**Important**: Tim2ToxSdkPlatform must be set, otherwise C++ callbacks such as clearHistoryMessage, groupQuitNotification, groupChatIdStored, etc. cannot be executed correctly.

## 2. Recommended initialization sequence

**Conceptual order** (logical dependencies):

```
1. FfiChatService.init() #Initialize Tox and local persistence
2. FfiChatService.login() #Restore selfId and connection status
3. FfiChatService.updateSelfProfile() # Synchronize nickname/signature
4. FakeUIKit.startWithFfi(service) # Establish the adaptation layer and call manager
5. TIMManager.instance.initSDK() # Set UIKit side _isInitSDK
6. FfiChatService.startPolling() # Poll native events, files and ToxAV
7. HomePage settings Tim2ToxSdkPlatform # enable the Platform path and custom callbacks
8. Initialize BinaryReplacementHistoryHook, call bridge and plug-in
```

**Actual execution sequence** (consistent with the code):

1. **main()**: `setNativeLibraryName('tim2tox_ffi')`, without setting Platform.
2. **_StartupGate._decide()** (automatic login path): First complete `init()`, `login()`, `updateSelfProfile()` through `AccountService.initializeServiceForAccount(..., startPolling: false)`; then execute `FakeUIKit.startWithFfi(service)` → `_initTIMManagerSDK()` → `service.startPolling()` → Wait for connection/timeout → Load friend information → Navigate to `HomePage(service)`.
3. **LoginPage._login()** (manual login path): When you have an account, go to `AccountService.initializeServiceForAccount(...)`; the old account compatibility path is still manual `init()` → `login()` → `_initTIMManagerSDK()` → `updateSelfProfile()` → `startPolling()`; then navigate to `HomePage(service)`.
4. **HomePage.initState()**: If FakeUIKit is not started, `FakeUIKit.startWithFfi(widget.service)`; if `TencentCloudChatSdkPlatform.instance is! Tim2ToxSdkPlatform`, set `Tim2ToxSdkPlatform` and mount `onGroupMessageReceivedForUnread`; then initialize `CallServiceManager`, `BinaryReplacementHistoryHook`, UIKit's group/friend listener, and sticker / textTranslate / soundToText plug-in.

**Description**: **Platform is set** in HomePage. `BinaryReplacementHistoryHook` is initialized after `HomePage._initTIMManagerSDK()` is completed; `CallServiceManager` relies on the already set `Tim2ToxSdkPlatform` to register the signaling listener.

**Division of Responsibilities**:

- **FfiChatService.init**: Responsible for Tox core initialization
- **TIMManager.initSDK**: Set the SDK layer `_isInitSDK` flag and call C++ DartInitSDK (shares the same underlying instance with FfiChatService)
- **Platform settings**: must be done in HomePage or earlier, for use by getHistoryMessageList, clearHistoryMessage, etc.

## 3. Functional process

### 3.1 Message sending

| Path | Description |
|------|------|
| **Main Path** | FakeChatMessageProvider → FakeMessageManager.sendText/sendFile → FfiChatService |
| **Alternate path** | If the code goes to V2TimMessageManager.sendMessage and Platform has been set → Tim2ToxSdkPlatform → FfiChatService |

Currently UIKit message input goes through the ChatMessageProvider, so all is actually sent via the FfiChatService.

### 3.2 Message history

| Path | Description |
|------|------|
| **Provider layer** | FakeChatMessageProvider._loadHistoryForConversation → FakeMessageManager.getHistory → FfiChatService.getHistory |
| **SDK layer** | tencent_cloud_chat_common and so on call getHistoryMessageListV2 → if Platform=Tim2ToxSdkPlatform → FfiChatService.getHistory |

Both paths end up at FfiChatService/MessageHistoryPersistence.

### 3.3 Conversations and Friends

All pass through the FakeUIKit adaptation layer and use FfiChatService (getFriendList, getFriendApplications, knownGroups) directly without going through Platform or NativeLibraryManager.

### 3.4 File transfer

- **Send**: FakeMessageManager.sendFile → FfiChatService.sendFile
- **Receive**: C++ OnFileRecv → file_request enqueue → FfiChatService.startPolling consumption → acceptFile
- **Progress**: FfiChatService.progressUpdates stream → FakeChatMessageProvider

`startPolling()` must be explicitly called by the startup process after service login, otherwise `file_request`, connection status and ToxAV events cannot be consumed.

### 3.5 Call and expansion capabilities

- **Call**: `FakeUIKit.startWithFfi()` creates `CallServiceManager`; `HomePage.initState()` calls its `initialize()` after the Platform is set up, and then strings together `ToxAVService`, `CallBridgeService` and `TUICallKitAdapter`
- **Sticker plug-in**: `HomePage.initState()` attempts to register synchronously before the message component is registered; if `selfId` is not ready yet, it will be registered after the connection is successful.
- **Text Translation/Speech to Text**: Lazy registration on demand in HomePage
- **LAN Bootstrap / IRC**: The entrance is on the client side, managed by `LanBootstrapServiceManager` and `IrcAppManager` respectively. For specific implementation, see the extended document

## 4. Callback process and division of labor

### 4.1 C++ callback path

```
C++ (dart_compat_layer / callback_bridge)
  → Dart_PostCObject
  → NativeLibraryManager._handleGlobalCallback
  → Route by instance_id:
     - instance_id != 0 → Platform.dispatchInstanceGlobalCallback (multiple instances)
     - instance_id == 0 → _sdkListener、_advancedMsgListener、_friendshipListener、_groupListener
```

### 4.2 Division of labor between C++ callbacks and FfiChatService streams

| Source | Purpose | Description |
|------|------|------|
| **C++ ReceiveNewMessage** | _advancedMsgListener dispatched to TIMMessageManager via NativeLibraryManager | The main entry for new messages under binary replacement; BinaryReplacementHistoryHook wraps the listener for persistence |
| **FfiChatService.messages** | stream generated by _onNativeEvent inside FfiChatService | Old-style events (type 0/1/10/11, etc.) from FfiChatService, which may overlap with the C++ layer |
| **FfiChatService.connectionStatusStream** | Connection status | Independent of C++ callbacks |

**Note**: In binary replacement mode, new messages are mainly dispatched by the C++ ReceiveNewMessage callback through NativeLibraryManager. FfiChatService._onNativeEvent mainly handles the old event protocol maintained by itself. The division of labor between the two is different to avoid duplication of processing.

### 4.3 Dependence of special callbacks on Platform

The following callbacks in NativeLibraryManager rely on Platform to be Tim2ToxSdkPlatform, otherwise ffiService cannot be accessed:

- `clearHistoryMessage`: Clear history
- `groupQuitNotification`: Group exit notification
- `groupChatIdStored`: group chat_id persistence

These callbacks are handled by **NativeLibraryManager._handleGlobalCallback** dispatched to **Tim2ToxSdkPlatform._handleCustomCallback** via **dispatchInstanceGlobalCallback** when **platform != null && platform.isCustomPlatform** is detected. If Platform is not set or the type does not match, these callbacks will fail silently.

## 5. Data flow overview

```
┌─────────────────────────────────────────────────────────────────┐
│ Message sending │
│  Message Input → FakeChatMessageProvider → FfiChatService        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ History loading │
│  FakeMessageManager.getHistory ──────┐                          │
│  V2TimMessageManager.getHistoryMessageListV2 ──→ Platform ──┐   │
│ (When the SDK layer isCustomPlatform==true, go to Platform) ↓ │
│                                         FfiChatService.getHistory│
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Callback │
│  C++ → NativeLibraryManager → TIMMessageManager listeners       │
│                            → BinaryReplacementHistoryHook        │
│ C++ special callback → Platform.ffiService (requires Platform=Tim2ToxSdkPlatform) │
└─────────────────────────────────────────────────────────────────┘
```

## 6. Differences from pure binary replacement

| Project | Pure Binary Replacement (Documentation Description) | Current Mixing Scheme |
|------|--------------------------|--------------|
| Platform settings | Do not set | **Required** Tim2ToxSdkPlatform |
| History query | C++ DartGetC2CHistoryMessageList | Platform → FfiChatService.getHistory |
| Special callback | Unable to execute | Depends on Platform.ffiService |
| Main path for sending messages | NativeLibraryManager.DartSendMessage | FakeChatMessageProvider → FfiChatService |

## 7. Related documents

- [ARCHITECTURE.md](ARCHITECTURE.en.md): Overall architecture
- [IMPLEMENTATION_DETAILS.md](IMPLEMENTATION_DETAILS.en.md): Implementation details
- [CALLING_AND_EXTENSIONS.md](CALLING_AND_EXTENSIONS.en.md): Calling, plugins, LAN Bootstrap and IRC extensions
- [../../tim2tox/doc/BINARY_REPLACEMENT.md](../../tim2tox/doc/BINARY_REPLACEMENT.en.md): Binary replacement mechanism
