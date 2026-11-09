import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/services/update_service.dart';

void main() {
  // Forme réelle de la Release v2.2.0 (API GitHub, champs utiles).
  final release = {
    'tag_name': 'v2.2.0',
    'body': 'Build 2.2.0+10 — commit 76bd388\n\n## What\'s Changed\n…',
    'assets': [
      {
        'name': 'sysiphe.apk',
        'size': 54611064,
        'browser_download_url':
            'https://github.com/Mephisto116631/sysiphe/releases/download/v2.2.0/sysiphe.apk',
      }
    ],
  };

  test('lecture de la Release GitHub', () {
    final u = parseRelease(release)!;
    expect(u.version, '2.2.0');
    expect(u.build, 10);
    expect(u.label, '2.2.0+10');
    expect(u.size, 54611064);
    expect(u.apkUrl, endsWith('/v2.2.0/sysiphe.apk'));
  });

  test('Release sans APK ou sans numéro de build : ignorée', () {
    expect(parseRelease({...release, 'assets': []}), isNull);
    expect(parseRelease({...release, 'body': 'Notes'}), isNull);
  });

  test('comparaison sur le numéro de build', () {
    final u = parseRelease(release)!; // +10
    expect(isNewer(u, '2.1.0+9'), isTrue);
    expect(isNewer(u, '2.2.0+10'), isFalse);
    expect(isNewer(u, '2.3.0+12'), isFalse);
    expect(isNewer(u, 'dev'), isFalse); // build local : jamais
  });
}
