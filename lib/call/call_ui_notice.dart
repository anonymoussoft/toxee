import '../i18n/app_localizations.dart';

typedef CallUiMessageResolver = String Function(AppLocalizations l10n);

class CallUiNotice {
  final int id;
  final CallUiMessageResolver resolveMessage;
  final bool isError;
  final bool offerSettings;

  const CallUiNotice({
    required this.id,
    required this.resolveMessage,
    this.isError = false,
    this.offerSettings = false,
  });
}
