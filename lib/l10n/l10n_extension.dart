import 'package:flutter/widgets.dart';
import 'app_localizations.dart';
import 'app_localizations_en.dart';

export 'app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this) ?? AppLocalizationsEn();
}

AppLocalizations contextL10n(BuildContext context) {
  return AppLocalizations.of(context) ?? AppLocalizationsEn();
}
