# toxee – 主题与配色全面复查报告

在已按计划完成「高 / 中 / 低」优先级改动后，对全工程做了二次检查，确认是否还有遗漏。

---

## 1. 已按计划修复并确认无误

- **search_chat_history_window.dart**：关键词高亮已改为 `theme.colorScheme.primary`（通过 `highlightColor` 传入）。
- **startup_loading_screen.dart**：进度条背景与步骤指示器已改为 `theme.colorScheme.onSurface.withValues(...)`，并移除未使用的 `isDark`。
- **home_page.dart**：已读人数角标图标与文字已改为 `Theme.of(context).colorScheme.onPrimary`。
- **profile_page.dart**：头像相机按钮描边与图标已改为使用参数 `onPrimary`。
- **upgrade_required_screen.dart**：`UpgradeRequiredApp` 已使用 `Prefs.getThemeMode()` + 与 main 一致的 `_lightTheme` / `_darkTheme`。
- **app_theme_config.dart**：`createYouthfulThemeModel()` 已为 Light/Dark 补充 `onPrimary`、`onSecondary`、`secondButtonColor`（微信风格）。

---

## 2. 本次复查结论：无新增遗漏

对以下位置做了逐项检查，**未发现**需要再纳入主题的遗漏控件/窗口/背景。

| 范围 | 检查结果 |
|------|----------|
| **applications_page / irc_channel_dialog** | 全程使用 `TencentCloudChatThemeWidget` 与 `colorTheme.*`，无硬编码颜色。 |
| **bootstrap_nodes_page / lan_bootstrap_scan_page** | 使用 `TencentCloudChatThemeWidget` + `Theme.of(context).colorScheme`（含 error/primary），无硬编码。 |
| **SnackBar** | 所有带 `backgroundColor` 的 SnackBar 均使用 `Theme.of(context).colorScheme.error` 或 `.primary`；未设置的使用主题默认。 |
| **AlertDialog / showDialog** | 如 login、settings、home（含 _showMessageReceiversDialog）、sidebar（_showProfileDialog）、home_utils（promptText）等，均未写死颜色，依赖 Theme。 |
| **responsive_scaffold.dart** | 仅接收可选 `backgroundColor` 参数，无内置硬编码颜色。 |
| **home_utils.dart** | `promptText` 的 AlertDialog 使用主题与 `AppThemeConfig.inputBorderRadius`，无硬编码色。 |

---

## 3. 刻意保留或设计取舍（非遗漏）

| 位置 | 说明 |
|------|------|
| **app_theme_config.dart** | 所有 `Color(0x...)`、`Colors.white` 等为**主题定义本身**（含 createYouthfulThemeModel 内 light/dark 色值），不视为“未纳入主题”。 |
| **Colors.transparent** | 出现在 profile_page（头像占位、Scaffold 背景）、sidebar（未选中 tab 背景）、add_friend_dialog、add_group_dialog，表示“无填充”，为语义用法，符合主题体系。 |
| **qr_card_generator.dart** | 卡片画布使用 `Colors.white` / `Colors.black12` / `Colors.black87` 等，用于**导出图片**的 QR 可读性与对比度；`primaryColor` / `textColor` 已由调用方从 `colorTheme` 传入，主题已参与。若未来需要“深色模式二维码卡片”可再单独扩展背景/前景。 |
| **app_tray.dart** | 系统托盘图标使用固定 `ui.Color`，与计划一致：**设计取舍**（托盘 API 一般不随应用主题切换）；若需可再做 light/dark 两套资源。 |

---

## 4. 小结

- **是否存在未纳入主题的控件/窗口/背景**：在计划已实施的前提下，**未发现新的遗漏**；上述“刻意保留”项均已在计划或本报告中说明。
- **微信参考 / 深色与浅色 / 主题正确传给 Tencent UIKit**：维持原计划结论不变；本次复查未改变这三点结论。

若后续新增页面或对话框，建议继续统一使用 `TencentCloudChatThemeWidget` + `colorTheme` 或 `Theme.of(context).colorScheme`，避免直接使用 `Colors.xxx` 或裸 `Color(0x...)`（除在 `AppThemeConfig` 或类似集中主题定义中）。
