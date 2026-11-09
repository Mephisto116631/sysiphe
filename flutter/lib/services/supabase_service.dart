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

  String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  // ─── Profils ──────────────────────────────────────────────────────────────

  Future<List<Profile>> getProfiles() async {
    final res = await _db
        .from('profiles')
        .select('id, name, pin_hash, last_login')
        .order('last_login', ascending: false, nullsFirst: false)
        .order('created_at');
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

  Future<void> touchLogin(String profileId) async {
    try {
      await _db
          .from('profiles')
          .update({'last_login': DateTime.now().toIso8601String()})
          .eq('id', profileId);
    } catch (_) {}
  }

  // ─── Performances ─────────────────────────────────────────────────────────

  Future<List<Perf>> getAllPerfs(String userId) async {
    final res = await _db
        .from('perfs')
        .select('*')
        .eq('user_id', userId)
        .order('date', ascending: false)
        .order('created_at', ascending: false);
    return (res as List).map((j) => Perf.fromJson(j)).toList();
  }

  Future<List<Perf>> getPerfsForDate(String userId, DateTime date) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final res = await _db
        .from('perfs')
        .select('*')
        .eq('user_id', userId)
        .eq('date', dateStr)
        .order('created_at', ascending: false);
    return (res as List).map((j) => Perf.fromJson(j)).toList();
  }

  Future<List<Perf>> getRecentPerfs(String userId, {int days = 90}) async {
    final from =
        DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(Duration(days: days)));
    final res = await _db
        .from('perfs')
        .select('*')
        .eq('user_id', userId)
        .gte('date', from)
        .order('date', ascending: true)
        .order('created_at', ascending: true);
    return (res as List).map((j) => Perf.fromJson(j)).toList();
  }

  Future<Perf?> savePerf(Perf perf) async {
    final res =
        await _db.from('perfs').insert(perf.toJson()).select().single();
    return Perf.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deletePerf(String id) async {
    await _db.from('perfs').delete().eq('id', id);
  }

  Future<List<String>> getExerciceNames(String userId) async {
    final res = await _db
        .from('perfs')
        .select('exercice')
        .eq('user_id', userId);
    final set = <String>{};
    for (final row in res as List) {
      final ex = (row['exercice'] as String?)?.trim();
      if (ex != null && ex.isNotEmpty) set.add(ex);
    }
    final list = set.toList()..sort();
    return list;
  }

  // ─── Calendrier : jours actifs ────────────────────────────────────────────

  Future<Map<DateTime, int>> getActiveDays(String userId,
      {int months = 3}) async {
    final from = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(Duration(days: months * 30)));
    final res = await _db
        .from('perfs')
        .select('date')
        .eq('user_id', userId)
        .gte('date', from);
    final map = <DateTime, int>{};
    for (final row in res as List) {
      final d = DateTime.parse(row['date'] as String);
      final key = DateTime(d.year, d.month, d.day);
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
      if (existing == null || p.charge > existing.charge) {
        records[p.exercice] = p;
      }
    }
    return records.entries
        .map((e) => {'exercice': e.key, 'perf': e.value})
        .toList()
      ..sort((a, b) =>
          (a['exercice'] as String).compareTo(b['exercice'] as String));
  }

  // ─── Paramètres utilisateur ───────────────────────────────────────────────

  Future<Map<String, dynamic>> getSettings(String userId) async {
    try {
      final res = await _db
          .from('settings')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();
      return (res as Map<String, dynamic>?) ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSettings(
      String userId, Map<String, dynamic> data) async {
    await _db.from('settings').upsert({'user_id': userId, ...data});
  }

  Future<void> setPin(String profileId, String pin) async {
    final hash = _sha256(pin.trim());
    await _db
        .from('profiles')
        .update({'pin_hash': hash})
        .eq('id', profileId);
  }
}
