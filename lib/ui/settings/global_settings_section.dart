import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../util/app_theme_config.dart';
import '../../util/locale_controller.dart';
import '../../util/theme_controller.dart';
import '../../util/prefs.dart';
import '../../i18n/app_localizations.dart';
import '../widgets/section_header.dart';

/// Global app settings (appearance, language, notification sound, downloads, auto-download).
/// Shown on both login settings and main settings. When [toxId] is null (login page),
/// notification sound is hidden.
class GlobalSettingsSection extends StatefulWidget {
  const GlobalSettingsSection({
    super.key,
    required this.colorTheme,
    this.toxId,
  });

  final dynamic colorTheme;
  /// When non-null, show notification sound setting (per-account).
  final String? toxId;

  @override
  State<GlobalSettingsSection> createState() => _GlobalSettingsSectionState();
}

class _GlobalSettingsSectionState extends State<GlobalSettingsSection> {
  bool _languageExpanded = false;
  bool _notificationSoundEnabled = true;
  final TextEditingController _downloadsDirectoryController = TextEditingController();
  final TextEditingController _sizeLimitController = TextEditingController();

  dynamic get _colorTheme => widget.colorTheme;

  bool _isLocaleEqual(Locale a, Locale b) {
    if (a.languageCode != b.languageCode) return false;
    if (a.scriptCode != null && b.scriptCode != null) return a.scriptCode == b.scriptCode;
    if (a.scriptCode != null || b.scriptCode != null) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadNotificationSoundSetting();
    _loadDownloadsDirectory();
    _loadAutoDownloadSizeLimit();
  }

  @override
  void dispose() {
    _downloadsDirectoryController.dispose();
    _sizeLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadNotificationSoundSetting() async {
    final toxId = widget.toxId;
    if (toxId == null || toxId.isEmpty) return;
    final enabled = await Prefs.getNotificationSoundEnabled(toxId);
    if (mounted) setState(() => _notificationSoundEnabled = enabled);
  }

  Future<void> _setNotificationSoundEnabled(bool value) async {
    final toxId = widget.toxId;
    if (toxId == null || toxId.isEmpty) return;
    await Prefs.setNotificationSoundEnabled(value, toxId);
    if (mounted) setState(() => _notificationSoundEnabled = value);
  }

  Future<String?> _getDefaultDownloadsDirectory() async {
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home != null) return p.join(home, 'Downloads');
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) return p.join(userProfile, 'Downloads');
      } else if (Platform.isAndroid || Platform.isIOS) {
        final appDir = await getApplicationDocumentsDirectory();
        return p.join(appDir.path, 'Downloads');
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadDownloadsDirectory() async {
    final dir = await Prefs.getDownloadsDirectory();
    final defaultDir = await _getDefaultDownloadsDirectory();
    if (mounted) {
      setState(() {
        _downloadsDirectoryController.text = dir ?? defaultDir ?? '';
      });
    }
  }

  Future<void> _selectDownloadsDirectory() async {
    if (!mounted) return;
    final currentContext = context;
    try {
      String? selectedDirectory;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        selectedDirectory = await FilePicker.platform.getDirectoryPath();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(currentContext)!.directorySelectionNotSupported),
            ),
          );
        }
        return;
      }
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        await Prefs.setDownloadsDirectory(selectedDirectory);
        if (mounted) setState(() => _downloadsDirectoryController.text = selectedDirectory!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.failedToSelectDirectory}: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _loadAutoDownloadSizeLimit() async {
    final limit = await Prefs.getAutoDownloadSizeLimit();
    if (mounted) {
      setState(() => _sizeLimitController.text = limit.toString());
    }
  }

  Future<void> _saveAutoDownloadSizeLimit() async {
    final text = _sizeLimitController.text.trim();
    final limit = int.tryParse(text);
    if (limit != null && limit > 0 && limit <= 10000) {
      await Prefs.setAutoDownloadSizeLimit(limit);
      if (mounted) setState(() {});
    }
  }

  Color _primaryTextColor(BuildContext context) {
    if (_colorTheme != null && _colorTheme.primaryTextColor != null) {
      return _colorTheme.primaryTextColor as Color;
    }
    return Theme.of(context).colorScheme.onSurface;
  }

  Color _secondaryTextColor(BuildContext context) {
    if (_colorTheme != null && _colorTheme.secondaryTextColor != null) {
      return _colorTheme.secondaryTextColor as Color;
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final tL10n = TencentCloudChatLocalizations.of(context);
    if (tL10n == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Appearance
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: tL10n.appearance),
                const SizedBox(height: 8),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: AppTheme.mode,
                  builder: (context, mode, _) {
                    final isDark = mode == ThemeMode.dark;
                    return Row(
                      children: [
                        Expanded(
                          child: RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            value: false,
                            groupValue: isDark,
                            title: Text(tL10n.lightTheme),
                            onChanged: (v) {
                              AppTheme.set(ThemeMode.light);
                              TencentCloudChat.controller.setBrightnessMode(Brightness.light);
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<bool>(
                            contentPadding: EdgeInsets.zero,
                            value: true,
                            groupValue: isDark,
                            title: Text(tL10n.darkTheme),
                            onChanged: (v) {
                              AppTheme.set(ThemeMode.dark);
                              TencentCloudChat.controller.setBrightnessMode(Brightness.dark);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Language
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: tL10n.language),
                const SizedBox(height: 8),
                ValueListenableBuilder<Locale>(
                  valueListenable: AppLocale.locale,
                  builder: (context, loc, _) {
                    final appL10n = AppLocalizations.of(context)!;
                    final languages = [
                      (locale: const Locale('en'), label: appL10n.english),
                      (locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'), label: appL10n.simplifiedChinese),
                      (locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), label: appL10n.traditionalChinese),
                      (locale: const Locale('ja'), label: appL10n.japanese),
                      (locale: const Locale('ko'), label: appL10n.korean),
                      (locale: const Locale('ar'), label: appL10n.arabic),
                    ];
                    Locale? selectedLocale;
                    for (final lang in languages) {
                      if (_isLocaleEqual(loc, lang.locale)) {
                        selectedLocale = lang.locale;
                        break;
                      }
                    }
                    if (selectedLocale == null) {
                      for (final lang in languages) {
                        if (loc.languageCode == lang.locale.languageCode) {
                          if (loc.languageCode == 'zh' && loc.scriptCode == null) {
                            if (lang.locale.scriptCode == 'Hans') {
                              selectedLocale = lang.locale;
                              break;
                            }
                          } else {
                            selectedLocale = lang.locale;
                            break;
                          }
                        }
                      }
                    }
                    selectedLocale ??= languages.first.locale;
                    final selectedLabel = languages.firstWhere(
                      (l) => _isLocaleEqual(l.locale, selectedLocale!),
                      orElse: () => languages.first,
                    ).label;
                    void selectLocale(Locale newLocale) {
                      AppLocale.set(newLocale);
                      TencentCloudChatIntl().setLocale(newLocale);
                      setState(() => _languageExpanded = false);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _languageExpanded = !_languageExpanded),
                            borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Theme.of(context).dividerColor),
                                borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      selectedLabel,
                                      style: Theme.of(context).textTheme.bodyLarge,
                                    ),
                                  ),
                                  Icon(
                                    _languageExpanded ? Icons.expand_less : Icons.expand_more,
                                    color: Theme.of(context).iconTheme.color,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_languageExpanded) ...[
                          const SizedBox(height: 8),
                          ...languages.map((lang) {
                            final isSelected = _isLocaleEqual(selectedLocale!, lang.locale);
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => selectLocale(lang.locale),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                        size: 20,
                                        color: isSelected
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).iconTheme.color,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        lang.label,
                                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          fontWeight: isSelected ? FontWeight.w600 : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (widget.toxId != null && widget.toxId!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
            ),
            child: SwitchListTile(
              title: Text(AppLocalizations.of(context)!.notificationSound),
              subtitle: Text(AppLocalizations.of(context)!.notificationSoundDesc),
              value: _notificationSoundEnabled,
              onChanged: _setNotificationSoundEnabled,
            ),
          ),
        ],
        const SizedBox(height: 12),
        // Downloads Directory
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: AppLocalizations.of(context)!.downloadsDirectory),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _downloadsDirectoryController,
                        readOnly: true,
                        textAlignVertical: TextAlignVertical.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontFamily: 'monospace',
                          color: _primaryTextColor(context),
                        ),
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!.downloadsDirectoryDesc,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: Text(AppLocalizations.of(context)!.selectDownloadsDirectory),
                      onPressed: _selectDownloadsDirectory,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)!.downloadsDirectoryDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _secondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Auto Download Size Limit
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: AppLocalizations.of(context)!.autoDownloadSizeLimit),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _sizeLimitController,
                        keyboardType: TextInputType.number,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.sizeLimitInMB,
                          hintText: '30',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                          ),
                          suffixText: 'MB',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onSubmitted: (_) => _saveAutoDownloadSizeLimit(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save, size: 18),
                      label: Text(AppLocalizations.of(context)!.save),
                      onPressed: _saveAutoDownloadSizeLimit,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)!.autoDownloadSizeLimitDesc,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _secondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
