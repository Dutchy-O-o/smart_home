/// Compile-time environment values injected via `--dart-define` at build
/// time. NEVER read from a bundled `.env` file — that file is plaintext
/// inside the APK and can be extracted with `apktool` in seconds.
///
/// Build / run command:
///
///     flutter run \
///       --dart-define=CLAUDE_API_KEY=sk-ant-... \
///       --dart-define=SPOTIFY_CLIENT_ID=... \
///       --dart-define=SPOTIFY_CLIENT_SECRET=... \
///       --dart-define=EMOTION_API_URL=https://ramazan.local:8000/predict
///
/// For VS Code / Android Studio launch configs see `README.md` →
/// "Build configuration".
///
/// `String.fromEnvironment` is evaluated at compile time, so the constants
/// below are baked into the binary. Same blast radius as the old `.env`
/// for *release* builds — but with `.env` no longer present in the APK
/// the secrets only land in builds that explicitly pass them in. Public
/// debug builds for screenshots / demos can ship without keys at all.
class Env {
  Env._();

  static const String claudeApiKey =
      String.fromEnvironment('CLAUDE_API_KEY');

  static const String spotifyClientId =
      String.fromEnvironment('SPOTIFY_CLIENT_ID');

  static const String spotifyClientSecret =
      String.fromEnvironment('SPOTIFY_CLIENT_SECRET');

  static const String emotionApiUrl = String.fromEnvironment(
    'EMOTION_API_URL',
    defaultValue: 'https://ramazan.local:8000/predict',
  );

  /// True when the key was injected at build time. Use to gate feature
  /// surfaces that need the key — e.g. show a "Configure API key" hint
  /// instead of a broken Chat tab.
  static bool get hasClaudeKey => claudeApiKey.isNotEmpty;
  static bool get hasSpotifyId => spotifyClientId.isNotEmpty;
  static bool get hasSpotifySecret => spotifyClientSecret.isNotEmpty;
}
