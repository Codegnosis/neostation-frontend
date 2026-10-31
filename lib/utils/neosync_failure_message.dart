import 'package:neostation/l10n/app_locale.dart';

/// What to tell the user about a failed NeoSync request, given the service's
/// [result] map: [text] looks up an [AppLocale] key (callers pass
/// `(key) => key.getString(context)`). Free of widget imports so the choice is
/// testable on its own.
///
/// A request that never got an answer (`isNetworkError`) says the server
/// couldn't be reached, in the app language; the service's own "Network
/// error: …" text is English and meant for the log. What the server itself
/// said is passed on as it was, or [fallback] when it said nothing.
String? neoSyncFailureMessage(
  Map<String, dynamic> result,
  String Function(String key) text, {
  String? fallback,
}) {
  if (result['isNetworkError'] == true) {
    return text(AppLocale.neoSyncUnreachable);
  }
  return result['message'] as String? ?? fallback;
}
