/// Build-time configuration.
///
/// The workspace origin can be overridden for local testing with
/// `--dart-define=CRM_ORIGIN=http://localhost:43872`; release builds use the
/// production workspace. Plain HTTP is accepted only for loopback addresses.
class AppConfig {
  static const String origin = String.fromEnvironment(
    'CRM_ORIGIN',
    defaultValue: 'https://crm.acquiretechsoftwaresolution.in',
  );

  static const String appName = 'Acquiretech CRM';
  static const String version = '2.0.0';

  static Uri get originUri => Uri.parse(origin);

  static String get host => originUri.host;

  static bool get isSecureOrigin {
    final uri = originUri;
    return uri.scheme == 'https' || uri.host == 'localhost' || uri.host == '127.0.0.1';
  }
}
