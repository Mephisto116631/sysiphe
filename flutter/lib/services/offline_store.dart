import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/course.dart';
import '../models/perf.dart';

/// Une opération en attente d'envoi (mode hors ligne).
/// - `insert` : [data] = la série complète (toJson), avec son `client_id` ;
///   [localId] (négatif) la désigne dans l'app tant qu'elle n'est pas envoyée.
/// - `update` : [data] = `{id, performance, effort_pondere?}` (série envoyée).
/// - `delete` : [data] = `{id}` (série envoyée).
/// - `course_insert` / `course_delete` : même chose pour une course.
class PendingOp {
  final String kind;
  final String userId;
  final int? localId;
  final Map<String, dynamic> data;

  const PendingOp(this.kind, this.userId, this.data, {this.localId});

  Map<String, dynamic> toJson() =>
      {'kind': kind, 'user': userId, 'local': localId, 'data': data};

  factory PendingOp.fromJson(Map<String, dynamic> j) => PendingOp(
        j['kind'] as String,
        j['user'] as String,
        Map<String, dynamic>.from(j['data'] as Map),
        localId: (j['local'] as num?)?.toInt(),
      );
}

/// Identifiant aléatoire (UUID v4) créé sur le téléphone : le serveur ignore
/// un second envoi de la même série (`perfs.client_id` unique).
String newClientId([Random? rng]) {
  final r = rng ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = List.generate(16, h).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}

/// Copie locale des données (séries et réglages, par profil) et file des
/// opérations en attente, enregistrées dans un fichier JSON sur le téléphone.
/// Sans réseau, l'app lit cette copie complétée de la file ([view]).
class OfflineStore {
  OfflineStore({Future<File> Function()? file})
      : _fileFn = file ?? _defaultFile,
        _persist = true;

  /// Copie en mémoire seulement (tests d'écran : pas de fichier).
  OfflineStore.memory()
      : _fileFn = _defaultFile,
        _persist = false;

  final bool _persist;

  static OfflineStore instance = OfflineStore();

  static Future<File> _defaultFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/offline_v1.json');

  final Future<File> Function() _fileFn;
  final Map<String, List<Map<String, dynamic>>> _perfs = {};
  final Map<String, Map<String, dynamic>> _settings = {};
  final Map<String, List<Map<String, dynamic>>> _courses = {};
  final List<PendingOp> _outbox = [];
  int _nextLocal = -1;
  bool _loaded = false;

  List<PendingOp> get outbox => List.unmodifiable(_outbox);
  bool hasCache(String userId) => _perfs.containsKey(userId);

  // ── Persistance ─────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _fileFn();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      (j['perfs'] as Map? ?? {}).forEach((k, v) => _perfs['$k'] = [
            for (final r in v as List) Map<String, dynamic>.from(r as Map)
          ]);
      (j['settings'] as Map? ?? {}).forEach(
          (k, v) => _settings['$k'] = Map<String, dynamic>.from(v as Map));
      (j['courses'] as Map? ?? {}).forEach((k, v) => _courses['$k'] = [
            for (final r in v as List) Map<String, dynamic>.from(r as Map)
          ]);
      _outbox.addAll([
        for (final o in j['outbox'] as List? ?? [])
          PendingOp.fromJson(Map<String, dynamic>.from(o as Map))
      ]);
      _nextLocal = (j['next_local'] as num?)?.toInt() ?? -1;
    } catch (_) {/* copie illisible : on repart de zéro */}
  }

  Future<void> _writing = Future.value();

  /// Écrit le fichier. Les écritures sont faites l'une après l'autre (jamais
  /// deux en même temps sur le même fichier), avec l'état le plus récent.
  Future<void> save() =>
      _persist ? _writing = _writing.then((_) => _write()) : Future.value();

  /// Attend la fin des écritures en cours (tests, fermeture).
  Future<void> get idle => _writing;

  Future<void> _write() async {
    try {
      final f = await _fileFn();
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'perfs': _perfs,
        'settings': _settings,
        'courses': _courses,
        'outbox': [for (final o in _outbox) o.toJson()],
        'next_local': _nextLocal,
      }));
      await tmp
          .rename(f.path); // remplacement d'un bloc : jamais à moitié écrit
    } catch (_) {/* stockage indisponible : la file reste en mémoire */}
  }

  // ── Copie des données lues en ligne ────────────────────────────────────

  void setAllPerfs(String userId, List<Map<String, dynamic>> rows) {
    _perfs[userId] = [for (final r in rows) Map<String, dynamic>.from(r)];
    save();
  }

  /// Remplace les séries d'un jour (lecture du jour en ligne).
  void setDayPerfs(
      String userId, DateTime day, List<Map<String, dynamic>> rows) {
    final d = _day(day);
    final list = _perfs[userId];
    if (list == null) return; // pas encore de copie complète
    list.removeWhere((r) => r['date'] == d);
    list.addAll([for (final r in rows) Map<String, dynamic>.from(r)]);
    save();
  }

  /// Séries envoyées avec succès : ajoutées à la copie.
  void addPerfs(String userId, List<Map<String, dynamic>> rows) {
    final list = _perfs[userId];
    if (list == null) return;
    final ids = {for (final r in rows) r['id']};
    list.removeWhere((r) => ids.contains(r['id']));
    list.addAll([for (final r in rows) Map<String, dynamic>.from(r)]);
    save();
  }

  void setSettings(String userId, Map<String, dynamic> s) {
    _settings[userId] = Map<String, dynamic>.from(s);
    save();
  }

  Map<String, dynamic>? settings(String userId) => _settings[userId];

  // ── Courses (module Course) ────────────────────────────────────────────

  bool hasCourses(String userId) => _courses.containsKey(userId);

  void setCourses(String userId, List<Map<String, dynamic>> rows) {
    _courses[userId] = [for (final r in rows) Map<String, dynamic>.from(r)];
    save();
  }

  /// Course envoyée avec succès : ajoutée à la copie.
  void addCourse(String userId, Map<String, dynamic> row) {
    final list = _courses[userId] ??= [];
    list.removeWhere((r) => r['id'] == row['id']);
    list.add(Map<String, dynamic>.from(row));
    save();
  }

  /// Met une course en attente ; renvoie son identifiant local (< 0).
  int enqueueCourse(String userId, Map<String, dynamic> row) {
    final id = _nextLocal--;
    _outbox.add(PendingOp('course_insert', userId,
        Map<String, dynamic>.from(row), localId: id));
    save();
    return id;
  }

  /// Suppression d'une course (en attente : simplement retirée).
  /// [queue] false : déjà supprimée sur le serveur, on retire la copie.
  void deleteCourse(String userId, int id, {bool queue = true}) {
    if (id < 0) {
      _outbox.removeWhere((o) => o.kind == 'course_insert' && o.localId == id);
    } else {
      if (queue) _outbox.add(PendingOp('course_delete', userId, {'id': id}));
      _courses[userId]?.removeWhere((r) => r['id'] == id);
    }
    save();
  }

  /// Courses du profil, en attente comprises, de la plus récente à la plus
  /// ancienne.
  List<Course> courses(String userId) {
    final deleted = {
      for (final o in _outbox)
        if (o.kind == 'course_delete' && o.userId == userId) o.data['id']
    };
    final out = [
      for (final r in _courses[userId] ?? const <Map<String, dynamic>>[])
        if (!deleted.contains(r['id'])) Course.fromJson(r),
      for (final o in _outbox)
        if (o.kind == 'course_insert' && o.userId == userId)
          Course.fromJson({...o.data, 'id': o.localId}),
    ]..sort((a, b) => b.debut.compareTo(a.debut));
    return out;
  }

  // ── File d'attente ─────────────────────────────────────────────────────

  /// Met des séries en attente ; renvoie leurs identifiants locaux (< 0).
  List<int> enqueueInserts(String userId, List<Map<String, dynamic>> rows) {
    final ids = <int>[];
    for (final r in rows) {
      final id = _nextLocal--;
      ids.add(id);
      _outbox.add(PendingOp('insert', userId, Map<String, dynamic>.from(r),
          localId: id));
    }
    save();
    return ids;
  }

  /// Correction hors ligne. Série en attente : on modifie l'envoi prévu ;
  /// série déjà envoyée : la correction est mise en file et appliquée à la
  /// copie.
  /// Profil auquel appartient la série [id] (copie ou file), '' si inconnu.
  String _ownerOf(int id) {
    for (final e in _perfs.entries) {
      if (e.value.any((r) => r['id'] == id)) return e.key;
    }
    for (final o in _outbox) {
      if (o.localId == id) return o.userId;
    }
    return '';
  }

  void updateValue(int id, double performance, {int? effortPondere}) {
    final userId = _ownerOf(id);
    final patch = {
      'performance': performance,
      if (effortPondere != null) 'effort_pondere': effortPondere,
    };
    if (id < 0) {
      for (final o in _outbox) {
        if (o.kind == 'insert' && o.localId == id) o.data.addAll(patch);
      }
    } else {
      _outbox.add(PendingOp('update', userId, {'id': id, ...patch}));
      for (final r in _perfs[userId] ?? const <Map<String, dynamic>>[]) {
        if (r['id'] == id) r.addAll(patch);
      }
    }
    save();
  }

  /// Suppression hors ligne (série en attente : simplement retirée).
  void delete(int id) {
    final userId = _ownerOf(id);
    if (id < 0) {
      _outbox.removeWhere((o) => o.kind == 'insert' && o.localId == id);
    } else {
      _outbox.removeWhere((o) => o.kind == 'update' && o.data['id'] == id);
      _outbox.add(PendingOp('delete', userId, {'id': id}));
      _perfs[userId]?.removeWhere((r) => r['id'] == id);
    }
    save();
  }

  /// Opération envoyée (ou refusée par le serveur) : retirée de la file.
  void done(PendingOp op) {
    _outbox.remove(op);
    save();
  }

  // ── Vue courante ───────────────────────────────────────────────────────

  /// Séries du profil : copie locale, plus les séries en attente (id < 0).
  /// Du plus récent au plus ancien, comme la lecture en ligne.
  List<Perf> view(String userId) {
    // Corrections et suppressions en attente appliquées à la copie (une
    // relecture en ligne peut avoir remis l'ancienne valeur).
    final deleted = <dynamic>{};
    final patches = <dynamic, Map<String, dynamic>>{};
    for (final o in _outbox) {
      if (o.userId != userId) continue;
      if (o.kind == 'delete') deleted.add(o.data['id']);
      if (o.kind == 'update') {
        (patches[o.data['id']] ??= {}).addAll({...o.data}..remove('id'));
      }
    }
    final rows = [
      for (final r in _perfs[userId] ?? const <Map<String, dynamic>>[])
        if (!deleted.contains(r['id']))
          patches.containsKey(r['id']) ? {...r, ...patches[r['id']]!} : r,
      for (final o in _outbox)
        if (o.kind == 'insert' && o.userId == userId)
          {...o.data, 'id': o.localId},
    ];
    final out = [for (final r in rows) Perf.fromJson(r)];
    out.sort((a, b) {
      final d = b.date.compareTo(a.date);
      if (d != 0) return d;
      // En attente (id < 0) après les séries envoyées, dans l'ordre de saisie.
      final ia = a.id ?? 0, ib = b.id ?? 0;
      if ((ia < 0) != (ib < 0)) return ia < 0 ? -1 : 1;
      return ia < 0 ? ia.compareTo(ib) : ib.compareTo(ia);
    });
    return out;
  }

  int pendingCount([String? userId]) =>
      _outbox.where((o) => userId == null || o.userId == userId).length;

  static String _day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// Pour les tests : repart d'une copie vide.
  void clearForTest() {
    _perfs.clear();
    _settings.clear();
    _courses.clear();
    _outbox.clear();
    _nextLocal = -1;
    _loaded = true;
  }
}
