/// Central configuration for the Jamendo API.
///
/// SECURITY RULES:
/// - Only the public Client ID is used for read-only music browsing & playback.
/// - The Client Secret is NEVER included, logged, or requested in source code.
class JamendoConfig {
  static const String clientId = 'da19c12c';
  static const String apiBaseUrl = 'https://api.jamendo.com/v3.0';
  static const String defaultFormat = 'json';

  // Private constructor to prevent instantiation
  JamendoConfig._();
}
