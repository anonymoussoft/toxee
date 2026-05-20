# Batch 4 — 账户与网络入口（域 B + C）findings

> Review 日期：2026-05-20
> 范围：账户生命周期、密码加密、Bootstrap 节点策略、LAN bootstrap、配对
> 配套：[功能清单](./2026-05-20-feature-inventory.md) · [Prompt 模板](./2026-05-20-review-prompts.md)

## 扫描范围与发现概览

扫描覆盖域 B/C 共约 20 个文件：`account_service.dart`、`account_switcher.dart`、`prefs.dart`（全 1912 行）、`account_export/` 子目录全部、`lan_bootstrap_service.dart`、`bootstrap_nodes.dart`、`bootstrap_settings_section.dart`、`login_use_case.dart`、`add_friend_dialog.dart`、`tox_utils.dart`、`pairing/` 全部（含 `pairing_crypto.dart`、`pairing_host.dart`）。

总体质量较高：PBKDF2 参数合理、配对加密协议完整（X25519 ECDH + HKDF + ChaCha20-Poly1305 + SAS 双端确认）、原子写保护 profile 文件。主要风险集中在：PBKDF2 比较非恒定时间、`deleteAccountWithoutService` 遗漏 `currentAccountToxId` 清除、LAN bootstrap 绑定 `0.0.0.0`、远程节点服务无签名校验、`_kPreLanBootstrapNode` 应用崩溃后可能永久残留、账户导出未版本化、`compareToxIds` 前缀匹配过宽。

## High

### [high] PBKDF2 密码验证使用非恒定时间字符串比较 — 威胁模型：本地攻击者

- 位置：`lib/util/prefs.dart:1810-1811`
- 现象：`verifyAccountPassword` 最终执行 `actual == expected`，两者皆为 `base64Encode(hashBytes)` 生成的 Dart `String`，`==` 走平台原生字符串比较，按字节短路。
- 风险：本地攻击者（rooted Android / macOS 沙箱逃逸后进程注入）可通过时序侧信道枚举 base64 字节逐位还原正确 hash。PBKDF2 本身的 150k 迭代未被绕过，但验证端的时序泄漏缩短了在线暴力搜索空间。
- 建议修法：替换为 length-invariant XOR 累计比较：
  ```dart
  bool _constantEq(String a, String b) {
    if (a.length != b.length) return false;
    var x = 0;
    for (var i = 0; i < a.length; i++) x |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    return x == 0;
  }
  ```
- 置信度：high

### [high] `deleteAccountWithoutService` 遗漏清除 `currentAccountToxId`

- 位置：`lib/util/account_service.dart:570-623`
- 现象：登录页删除账户（无 running service）调用 `deleteAccountWithoutService`，完成了 `clearAccountData(toxId)`、`removeAccount(toxId)`、profile 目录删除、UIKit failed-message 清理，但没有调用 `Prefs.setCurrentAccountToxId(null)`。对比 `deleteAccountCompletely`（行 563）显式调用。
- 风险：若被删账户刚好是当前登录账户，`Prefs._cachedCurrentAccountToxId` 仍保留已删除账户 toxId，下次冷启动 `_StartupGate` 读到 stale ID，尝试加载不存在的 profile，启动崩溃或无法登录。违反不变量 5。
- 建议修法：末尾补充：
  ```dart
  final current = await Prefs.getCurrentAccountToxId();
  if (current == toxId) await Prefs.setCurrentAccountToxId(null);
  ```
- 置信度：high

## Medium

### [medium] `_kPreLanBootstrapNode` 在应用崩溃时永久残留 — 威胁模型：本地状态

- 位置：`lib/ui/settings/bootstrap_settings_section.dart:395-430`；`lib/util/prefs.dart:617-639`
- 现象：`_startLanBootstrapService` 先保存当前节点到 `_kPreLanBootstrap*`，再启动 LAN 实例。若进程在启动成功之后、`_stopLanBootstrapService` 之前崩溃，重启后 `_kPreLanBootstrap*` 仍保存旧节点；`getLanBootstrapServiceRunning()` 返回 `true`（已写入），但 `LanBootstrapServiceManager._bootstrapInstanceHandle` 为 null（内存未恢复），用户看到"服务运行中"但当前 bootstrap 节点仍是 LAN 地址（无效）且无法自动恢复到公网节点。
- 建议修法：启动时检查：若 `getLanBootstrapServiceRunning()` 为 true 但内存中 service 未运行，自动执行 stop 清理逻辑（恢复 pre-LAN 节点、清旗标、清 prefs）。
- 置信度：medium

### [medium] 远程节点服务（`nodes.tox.chat/json`）无签名/完整性校验 — 威胁模型：网络中间人

- 位置：`lib/util/bootstrap_nodes.dart:96-129`
- 现象：通过普通 HTTPS GET 获取节点列表，无 pinned certificate、无 JSON 签名、无 public-key fingerprint 校验。攻击者如能劫持 DNS 或插入恶意 CA，可返回任意节点 IP 和公钥。
- 风险：注入恶意节点最坏情况是 DoS（已有硬编码 fallback 节点）。主要风险是攻击者能让用户向自己控制的 DHT 节点发起首次 bootstrap，获取用户 IP/时间戳相关性。
- 建议修法：短期添加 hostname pinning（证书指纹）；中期评估上游签名机制；至少添加返回 publicKey 的基本格式校验（`_isValidPubkey` 已存在于 settings 侧但 service 侧没有）。
- 置信度：medium

### [medium] LAN bootstrap 服务绑定 `0.0.0.0`，所有接口可达 — 威胁模型：局域网/VPN 攻击者

- 位置：`lib/util/lan_bootstrap_service.dart:202-282`
- 现象：本地 bootstrap 实例绑定端口由 Tox 核心决定（通常 `0.0.0.0`），`_bootstrapServiceIP` 存第一个物理网卡 IP。`_isVirtualInterface` 过滤 docker/vmnet 等，但 tailscale/wireguard 等 VPN 接口未过滤，外部攻击者可直接探测。
- 建议修法：`_isVirtualInterface` 追加 VPN 前缀（`tun`/`tap`/`utun`/`wg`）；考虑"仅绑定选定接口"的高级选项。
- 置信度：medium

### [medium] 账户导出文件无版本号字段

- 位置：`lib/util/account_export/tox_file_io.dart` 全文；`full_backup.dart:163-174`
- 现象：`.tox` 依赖 tox_pass_encrypt 协议（有 magic header 但无 toxee 格式版本）；`.zip` 全备份的 `metadata.json` 含 `exportDate` 但无 `formatVersion`。`importFullBackup` 直接解析 `scopedPrefs`，无版本迁移逻辑。
- 风险：未来修改 scoped prefs 键名或 schema 时，旧备份导入会静默丢失或错误恢复。维护性风险。
- 建议修法：`metadata.json` 写入 `'formatVersion': 1`；`importFullBackup` 检查版本。
- 置信度：medium

### [medium] `compareToxIds` 前缀匹配过宽，可能允许同前缀不同账户匹配

- 位置：`lib/util/tox_utils.dart:58-69`
- 现象：在 `n1.length >= 16 && n2.length >= 16` 时执行 `longer.startsWith(shorter)`，意味着 16 字符前缀可匹配任意 64 字符公钥。`Prefs.getAccountByToxId` step 4 使用此函数，若账户列表存在短前缀条目（legacy 16-char），可能错误匹配到不同账户。
- 建议修法：限制前缀匹配仅在 `shorter.length == 16` 且 `longer.length >= 64` 时生效；或将前缀匹配从通用 `compareToxIds` 移出，只在 `getAccountByToxId` step 4 内联做受控匹配。
- 置信度：medium

### [medium] `deleteAccountCompletely` 中 `clearAllAccountData()` 在 dispose 之后调用必然失败

- 位置：`lib/util/account_service.dart:496-563`
- 现象：行 501 `teardownCurrentSession(reEncryptProfile: false)` → `disposeRuntime()`，行 506 `service.clearAllAccountData()` 被包裹空 catch（行 507-509，注释"Service already disposed, ignore"）。teardown 已 dispose，此调用每次静默失败，留下 `FfiChatService` 可能存有的 account-level 清理（SQLite、文件锁）被跳过。
- 建议修法：将 `clearAllAccountData()` 移到 `teardownCurrentSession` 之前调用。
- 置信度：medium

### [medium] 账户切换中 profile 解密后崩溃，明文残留磁盘 — 威胁模型：本地攻击者

- 位置：`lib/util/account_switcher.dart:39-62`
- 现象：先 `verifyAccountPassword` → `teardownCurrentSession`（re-encrypt 旧账户）→ `initializeServiceForAccount`（`decryptProfileFile` 解密目标账户写回磁盘）。若 `decryptProfileFile` 成功但 `service.init()` 抛异常，catch 块会尝试 `encryptProfileFile` 回滚；但若进程崩溃（SIGKILL）则 profile 以明文留在磁盘。
- 风险：明文窗口数秒到数十秒。iOS/Android 沙箱缓解，macOS/Linux/Windows 风险较高。
- 建议修法：try-finally 保证 profile 总会被 re-encrypt；用 `.new` staging 文件缩短明文窗口。
- 置信度：medium

### [medium] 配对 `.tox` blob 导出到 temp 文件后删除失败时明文留存 — 威胁模型：本地攻击者

- 位置：`lib/ui/pairing/pairing_host_page.dart:93-107`
- 现象：导出到 `getTemporaryDirectory()` 后读取字节再删除。`await File(tmp).delete()` 在 catch 中只打日志不重试，删除失败则明文 profile 留在系统 temp 目录。无密码账户的 `.tox` 是未加密 profile blob，任何可读 temp 目录的进程可读取完整 Tox identity。
- 建议修法：改为内存路径（`exportAccountData` 直接返回字节）；或 finally 块保证删除，失败则 zero-fill 覆写后再删除。
- 置信度：medium

### [medium] `addAccount` 在登录尚未完整成功时更新 `lastLoginTime`

- 位置：`lib/util/prefs.dart:1533`
- 现象：`addAccount` 对已有账户无条件 `lastLoginTime = DateTime.now()`。`LoginUseCase.execute`（行 84-89）在 `initializeServiceForAccount` 成功后调用 `addAccount`，但若 `AppBootstrapCoordinator.boot()` 后续失败（`TimSdkInitializer` 抛），`lastLoginTime` 已更新，UI 上看起来像"最近登录"。
- 建议修法：`lastLoginTime` 应在完整 boot 流程成功后才更新；调整 `LoginPage` 调用时机。
- 置信度：medium

## 全局观察

域 B/C 的最大优势是密码存储侧已有扎实的 PBKDF2+secure-storage 迁移机制，配对协议加密层次清晰。主要改进方向：PBKDF2 验证结尾需改为常量时间比较（直接安全风险）；`deleteAccountWithoutService` 遗漏 currentAccountId 清除（账户状态泄漏）；LAN bootstrap 的崩溃恢复和接口绑定范围需要收紧。远程节点获取无签名校验是长期技术债，纯 HTTPS 连接下现阶段可接受但应记录在安全 roadmap。
