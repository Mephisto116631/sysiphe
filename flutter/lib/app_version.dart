/// Version injectée par la CI : `--dart-define=APP_VERSION=2.3.0+12`
/// (nom de version + numéro du run, qui sert aussi de versionCode Android).
/// « dev » pour un build local sans cette option.
const kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
