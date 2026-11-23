/// Version de l'app : `sysiphe-course.apk` est compilée avec
/// `--dart-define=COURSE=true` (module Course GPS) ; `sysiphe.apk` sans.
const kCourse = bool.fromEnvironment('COURSE');

/// Nom de l'APK de cette version dans les Releases GitHub.
const kApkName = kCourse ? 'sysiphe-course.apk' : 'sysiphe.apk';

/// Nom de l'APK de l'autre version (pour passer de l'une à l'autre).
const kOtherApkName = kCourse ? 'sysiphe.apk' : 'sysiphe-course.apk';
