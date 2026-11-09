import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../app_version.dart';

/// Version complète « 2.3.0+12 » → (nom, numéro de build).
(String, int)? parseVersion(String v) {
  final m = RegExp(r'(\d+\.\d+\.\d+)\+(\d+)').firstMatch(v);
  return m == null ? null : (m.group(1)!, int.parse(m.group(2)!));
}

class UpdateInfo {
  final String version; // « 2.3.1 »
  final int build; // numéro du run CI = versionCode Android
  final String apkUrl;
  final int size; // octets
  const UpdateInfo(this.version, this.build, this.apkUrl, this.size);

  String get label => '$version+$build';
}

/// Lit la réponse de l'API GitHub « dernière Release ». Le numéro de build
/// est dans le texte de la Release (« Build 2.3.0+12 — commit … »), écrit
/// par build-flutter.yml. null si la Release n'a pas d'APK ou pas de build.
UpdateInfo? parseRelease(Map<String, dynamic> json) {
  final v = parseVersion((json['body'] as String?) ?? '');
  final assets = (json['assets'] as List?) ?? const [];
  final apk = assets.cast<Map<String, dynamic>>().where(
      (a) => (a['name'] as String?)?.endsWith('.apk') ?? false);
  if (v == null || apk.isEmpty) return null;
  return UpdateInfo(v.$1, v.$2, apk.first['browser_download_url'] as String,
      (apk.first['size'] as num?)?.toInt() ?? 0);
}

/// Plus récente que la version installée ? Comparaison sur le numéro de
/// build (il augmente à chaque build). Build local « dev » : jamais.
bool isNewer(UpdateInfo latest, String current) {
  final cur = parseVersion(current);
  return cur != null && latest.build > cur.$2;
}

/// Mise à jour intégrée depuis les Releases GitHub (dépôt public).
class UpdateService {
  static const _latestUrl =
      'https://api.github.com/repos/Mephisto116631/sysiphe/releases/latest';
  static const _channel = MethodChannel('sysiphe/update');

  /// Dernière Release si elle est plus récente que l'app, sinon null.
  static Future<UpdateInfo?> checkForUpdate() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_latestUrl));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'sysiphe-app');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('GitHub a répondu ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final info = parseRelease(jsonDecode(body) as Map<String, dynamic>);
      return info != null && isNewer(info, kAppVersion) ? info : null;
    } finally {
      client.close();
    }
  }

  /// Télécharge l'APK dans le cache ; [onProgress] reçoit 0..1.
  static Future<File> download(UpdateInfo info,
      {void Function(double)? onProgress}) async {
    final dir = await _channel.invokeMethod<String>('updatesDir');
    final file = File('$dir/sysiphe-${info.label}.apk');
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(Uri.parse(info.apkUrl))).close();
      if (res.statusCode != 200) {
        throw HttpException('Téléchargement : HTTP ${res.statusCode}');
      }
      final total = res.contentLength > 0 ? res.contentLength : info.size;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  /// Ouvre l'installeur Android. Retourne false si Android demande d'abord
  /// l'autorisation « installer des applis inconnues » (écran ouvert).
  static Future<bool> install(File apk) async {
    final r = await _channel
        .invokeMethod<String>('installApk', {'path': apk.path});
    return r == 'started';
  }
}
