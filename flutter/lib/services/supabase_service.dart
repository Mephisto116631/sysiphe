import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../models/profile.dart';
import '../models/perf.dart';

class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService._();
  SupabaseService._();

  final _db = Supabase.instance.client;

  String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();

  // ─── Profils ──────────────────────────────────────────────────────────────

  Future<List<Profile>> getProfiles() async {
    final res = await _db
        .from('profiles')
        .select('id, name, pin_hash, last_login')
        .order('last_login', ascending: false, nullsFirst: false)
        .order('created_at', ascending: true); // même ordre que l'app web
    return (res as List).map((j) => Profile.fromJson(j)).toList();
  }

  Future<bool> verifyPin(String profileId, String pin) async {
    final hash = _sha256(pin.trim());
    final res = await _db
        .from('profiles')
        .select('id')
        .eq('id', profileId)
        .eq('pin_hash', hash);
    return (res as List).isNotEmpty;
  }

  /// Crée un profil (avec PIN facultatif) et le renvoie.
  Future<Profile> createProfile(String name, {String? pin}) async {
    final row = await _db
        .from('profiles')
        .insert({
          'name': name.trim(),
          if (pin != null && pin.trim().isNotEmpty)
            'pin_hash': _sha256(pin.trim()),
        })
        .select('id, name, pin_hash, last_login')
        .single();
    return Profile.fromJson(row);
  }

  Future<void> renameProfile(String profileId, String name) async {
    await _db
        .from('profiles')
        .update({'name': name.trim()}).eq('id', profileId);
  }

  /// Supprime le profil ; ses séries restent en base (comme le web).
  Future<void> deleteProfile(String profileId) async {
    await _db.from('profiles').delete().eq('id', profileId);
  }

  Future<void> touchLogin(String profileId) async {
    try {
      await _db.from('profiles').update(
          {'last_login': DateTime.now().toIso8601String()}).eq('id', profileId);
    } catch (_) {}
  }

  // ─── Performances ─────────────────────────────────────────────────────────

  // La table perfs n'a pas de colonne created_at : l'ordre d'insertion est
  // donné par `id` (bigint identity). Trier sur created_at renvoie une 400.

  /// Supabase plafonne chaque réponse à 1 000 lignes : on pagine.
  static const _pageSize = 1000;

  Future<List<Perf>> _fetchPerfs(
    String userId, {
    String? fromDate,
    String? onDate,
    bool ascending = false,
  }) async {
    final out = <Perf>[];
    for (var start = 0;; start += _pageSize) {
      var q = _db.from('perfs').select('*').eq('user_id', userId);
      if (fromDate != null) q = q.gte('date', fromDate);
      if (onDate != null) q = q.eq('date', onDate);
      final res = await q
          .order('date', ascending: ascending)
          .order('id', ascending: ascending)
          .range(start, start + _pageSize - 1);
      final rows = res as List;
      out.addAll(rows.map((j) => Perf.fromJson(j as Map<String, dynamic>)));
      if (rows.length < _pageSize) break;
    }
    return out;
  }

  Future<List<Perf>> getAllPerfs(String userId) => _fetchPerfs(userId);

  Future<List<Perf>> getPerfsForDate(String userId, DateTime date) =>
      _fetchPerfs(userId, onDate: DateFormat('yyyy-MM-dd').format(date));

  Future<List<Perf>> getRecentPerfs(String userId, {int days = 90}) =>
      _fetchPerfs(
        userId,
        fromDate: DateFormat('yyyy-MM-dd')
            .format(DateTime.now().subtract(Duration(days: days))),
        ascending: true,
      );

  Future<Perf?> savePerf(Perf perf) async {
    final res = await _db.from('perfs').insert(perf.toJson()).select().single();
    return Perf.fromJson(res);
  }

  /// Séries de la dernière séance strictement avant [before] (vide s'il n'y
  /// en a pas) : sert à reprendre la séance précédente dans Saisie.
  Future<List<Perf>> getPreviousSession(String userId, DateTime before) async {
    final last = await _db
        .from('perfs')
        .select('date')
        .eq('user_id', userId)
        .lt('date', DateFormat('yyyy-MM-dd').format(before))
        .order('date', ascending: false)
        .limit(1);
    if (last.isEmpty) return [];
    final perfs = await _fetchPerfs(userId,
        onDate: last.first['date'] as String, ascending: true);
    return perfs;
  }

  /// Renomme un exercice dans tout l'historique du profil.
  Future<void> renameExercice(
      String userId, String oldName, String newName) async {
    await _db
        .from('perfs')
        .update({'exercice': newName.trim()})
        .eq('user_id', userId)
        .eq('exercice', oldName);
  }

  /// Insère plusieurs séries en une requête (saisie « 12 10 8 »).
  Future<void> savePerfs(List<Perf> perfs) async {
    if (perfs.isEmpty) return;
    await _db.from('perfs').insert([for (final p in perfs) p.toJson()]);
  }

  /// Supprime toutes les séries d'un jour (« Supprimer la séance »).
  Future<void> deleteSession(String userId, DateTime date) async {
    await _db
        .from('perfs')
        .delete()
        .eq('user_id', userId)
        .eq('date', DateFormat('yyyy-MM-dd').format(date));
  }

  Future<void> deletePerf(int id) async {
    await _db.from('perfs').delete().eq('id', id);
  }

  Future<List<String>> getExerciceNames(String userId) async {
    final perfs = await _fetchPerfs(userId);
    final set = <String>{
      for (final p in perfs)
        if (p.exercice.isNotEmpty) p.exercice,
    };
    return set.toList()..sort();
  }

  // ─── Calendrier : jours actifs ────────────────────────────────────────────

  /// Nombre de séries par jour ; [months] null = tout l'historique.
  Future<Map<DateTime, int>> getActiveDays(String userId, {int? months}) async {
    final perfs = await _fetchPerfs(
      userId,
      fromDate: months == null
          ? null
          : DateFormat('yyyy-MM-dd')
              .format(DateTime.now().subtract(Duration(days: months * 30))),
    );
    final map = <DateTime, int>{};
    for (final p in perfs) {
      final key = DateTime(p.date.year, p.date.month, p.date.day);
      map[key] = (map[key] ?? 0) + 1;
    }
    return map;
  }

  // ─── Records : meilleure perf par exercice ────────────────────────────────

  Future<List<Map<String, dynamic>>> getRecords(String userId) async {
    final perfs = await getAllPerfs(userId);
    final records = <String, Perf>{};
    for (final p in perfs) {
      final existing = records[p.exercice];
      if (existing == null || isBetterRecord(p, existing)) {
        records[p.exercice] = p;
      }
    }
    return records.entries
        .map((e) => {'exercice': e.key, 'perf': e.value})
        .toList()
      ..sort((a, b) =>
          (a['exercice'] as String).compareTo(b['exercice'] as String));
  }

  // ─── Paramètres utilisateur (table user_settings, partagée avec Streamlit) ─

  Future<Map<String, dynamic>> getSettings(String userId) async {
    try {
      final res = await _db
          .from('user_settings')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();
      return res ?? {};
    } catch (_) {
      // Table absente ou réseau : valeurs par défaut (même règle que Python).
      return {};
    }
  }

  /// Upsert partiel : seules les colonnes de [data] sont modifiées, les
  /// réglages gérés par l'app web (calibration planche…) restent intacts.
  Future<void> saveSettings(String userId, Map<String, dynamic> data) async {
    await _db.from('user_settings').upsert({'user_id': userId, ...data});
  }

  /// Recalcule effort_pondere de toutes les séries de planche du profil avec
  /// le poids et la calibration donnés (équivalent de recalculate_all_efforts).
  /// Retourne le nombre de séries mises à jour.
  Future<int> recalculateEfforts(
    String userId, {
    required double weight,
    required Map<String, double> variantes,
    required Map<String, double> formes,
    required Map<String, double> elastiques,
    required Map<String, double> tensions,
  }) async {
    final planches =
        (await _fetchPerfs(userId)).where((p) => p.isPlanche).toList();
    // Upsert = INSERT … ON CONFLICT : les colonnes NOT NULL (user_id, date,
    // exercice) doivent être présentes, seule effort_pondere est modifiée.
    final rows = [
      for (final p in planches)
        {
          'id': p.id,
          'user_id': p.userId,
          'date': DateFormat('yyyy-MM-dd').format(p.date),
          'exercice': p.exercice,
          'effort_pondere': calculerEffort(
            variante: p.variante,
            elastique: p.elastique,
            tension: p.tension,
            forme: p.forme,
            temps: p.performance,
            weight: weight,
            variantes: variantes,
            formes: formes,
            elastiquesMap: elastiques,
            tensions: tensions,
          ),
        },
    ];
    for (var i = 0; i < rows.length; i += 500) {
      await _db.from('perfs').upsert(
          rows.sublist(i, i + 500 > rows.length ? rows.length : i + 500));
    }
    return rows.length;
  }

  Future<void> setPin(String profileId, String pin) async {
    final hash = _sha256(pin.trim());
    await _db.from('profiles').update({'pin_hash': hash}).eq('id', profileId);
  }
}
