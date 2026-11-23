import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../models/profile.dart';
import '../models/perf.dart';
import 'offline_store.dart';
import 'sync_service.dart';

class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseService get instance => _instance ??= SupabaseService._();
  SupabaseService._();

  final _db = Supabase.instance.client;

  // ─── Mode hors ligne ──────────────────────────────────────────────────────
  // Les lectures réussies sont copiées sur le téléphone (OfflineStore) ; sans
  // réseau on relit cette copie. Les séries saisies sans réseau partent dans
  // une file d'attente envoyée par SyncService au retour du réseau.

  OfflineStore get _offline => OfflineStore.instance;
  static const _timeout = Duration(seconds: 12);

  /// Branche l'envoi de la file d'attente (appelé au démarrage).
  void startSync() {
    SyncService.instance.sender = sendPending;
    SyncService.instance.start();
  }

  /// Envoie une opération en attente (insert idempotent grâce à client_id).
  Future<Map<String, dynamic>?> sendPending(PendingOp op) async {
    switch (op.kind) {
      case 'insert':
        final res = await _db
            .from('perfs')
            .upsert(op.data, onConflict: 'client_id', ignoreDuplicates: true)
            .select()
            .timeout(_timeout);
        final rows = res as List;
        return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
      case 'update':
        final d = {...op.data}..remove('id');
        await _db.from('perfs').update(d).eq('id', op.data['id']).timeout(_timeout);
        return null;
      case 'delete':
        await _db.from('perfs').delete().eq('id', op.data['id']).timeout(_timeout);
        return null;
    }
    return null;
  }

  // ─── Session ──────────────────────────────────────────────────────────────

  Future<void>? _sessionReady;

  /// Garantit une session Supabase (anonyme si besoin). Le SDK la conserve
  /// sur le téléphone et la renouvelle seul : elle n'est créée qu'une fois.
  /// Les appels suivants ne coûtent rien (pas de réseau).
  Future<void> ensureSession() {
    if (_db.auth.currentSession != null) return Future.value();
    return _sessionReady ??= _db.auth.signInAnonymously().then((_) {}).whenComplete(
          () => _sessionReady = null,
        );
  }

  /// true si une session est disponible ; false si elle ne peut pas être
  /// ouverte (connexions anonymes désactivées côté Supabase, réseau…).
  /// Dans ce cas, l'app reprend l'ancien fonctionnement au lieu de bloquer :
  /// possible tant que la RLS n'est pas activée (étape 2 du PLAN). Dès que la
  /// session redevient possible, on repasse automatiquement par le serveur.
  Future<bool> _hasSession() async {
    try {
      await ensureSession();
      return _db.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();

  /// Ferme la session (« Changer de profil »). Erreurs réseau ignorées : la
  /// session locale est supprimée de toute façon.
  Future<void> signOut() async {
    try {
      await _db.auth.signOut();
    } catch (_) {}
  }

  // ─── Profils ──────────────────────────────────────────────────────────────

  /// Profils pour l'écran de connexion (RPC : le hash du PIN n'est pas
  /// exposé ; is_member indique si cet appareil est déjà rattaché).
  Future<List<Profile>> getProfiles() async {
    if (!await _hasSession()) {
      // Repli de transition : lecture directe (hash lu mais non affiché).
      final rows = await _db
          .from('profiles')
          .select('id, name, pin_hash, last_login')
          .order('last_login', ascending: false, nullsFirst: false)
          .order('created_at', ascending: true);
      return (rows as List)
          .map((j) => Profile.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    final res = await _db.rpc('list_profiles');
    return (res as List)
        .map((j) => Profile.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Vérifie le PIN côté serveur et rattache cet appareil au profil.
  /// [pin] null pour un profil sans PIN.
  Future<ClaimResult> claimProfile(String profileId, {String? pin}) async {
    if (!await _hasSession()) {
      // Repli de transition : vérification locale, comme en v2.1.
      final p = (pin ?? '').trim();
      final q = _db.from('profiles').select('id').eq('id', profileId);
      final rows = p.isEmpty
          ? await q.isFilter('pin_hash', null)
          : await q.eq('pin_hash', _sha256(p));
      return (rows as List).isNotEmpty ? ClaimResult.ok : ClaimResult.badPin;
    }
    final res = await _db.rpc('claim_profile',
        params: {'p_profile': profileId, 'p_pin': pin?.trim()});
    return switch (res as String?) {
      'ok' => ClaimResult.ok,
      'locked' => ClaimResult.locked,
      _ => ClaimResult.badPin,
    };
  }

  /// Cet appareil a-t-il déjà accès au profil ?
  Future<bool> isMember(String profileId) async {
    // Sans session, pas de rattachement possible : ne pas redemander le PIN.
    if (!await _hasSession()) return true;
    final res = await _db
        .rpc('is_profile_member', params: {'p_profile': profileId});
    return res == true;
  }

  /// Rôle du profil, lu par le serveur (« admin » seulement si cet appareil
  /// est rattaché à un profil admin). Faux hors ligne ou en cas d'erreur.
  Future<bool> isAdmin(String profileId) async {
    if (!await _hasSession()) return false;
    try {
      final res =
          await _db.rpc('profile_role', params: {'p_profile': profileId});
      return res == 'admin';
    } catch (_) {
      return false;
    }
  }

  /// Export admin : toutes les séries de tous les profils, au format CSV.
  /// La vérification du rôle est faite par le serveur (RPC admin_export_perfs).
  Future<(String csv, int rows)> exportAllPerfsCsv() async {
    final data = await _db.rpc('admin_export_perfs') as List;
    final names = {for (final p in await getProfiles()) p.id: p.name};
    const cols = [
      'date', 'exercice', 'serie', 'performance', 'unite', 'charge',
      'categorie', 'variante', 'forme', 'elastique', 'tension', 'ecartement',
      'effort_pondere'
    ];
    String q(Object? v) {
      final t = v?.toString() ?? '';
      return t.contains(RegExp(r'[",;\n]')) ? '"${t.replaceAll('"', '""')}"' : t;
    }

    final sb = StringBuffer('profil,${cols.join(',')}\n');
    for (final r in data.cast<Map<String, dynamic>>()) {
      sb.writeln([
        q(names[r['user_id']] ?? r['user_id']),
        for (final c in cols) q(r[c]),
      ].join(','));
    }
    return (sb.toString(), data.length);
  }

  /// Crée un profil (PIN facultatif) rattaché à cet appareil et le renvoie.
  Future<Profile> createProfile(String name, {String? pin}) async {
    if (!await _hasSession()) {
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
    final id = await _db.rpc('create_profile', params: {
      'p_name': name.trim(),
      'p_pin': (pin == null || pin.trim().isEmpty) ? null : pin.trim(),
    }) as String;
    return Profile(
        id: id,
        name: name.trim(),
        hasPin: pin != null && pin.trim().isNotEmpty,
        isMember: true);
  }

  Future<void> renameProfile(String profileId, String name) async {
    await _db
        .from('profiles')
        .update({'name': name.trim()}).eq('id', profileId);
  }

  /// Supprime le profil (admin seulement, vérifié par le serveur) ; ses
  /// séries restent en base. Erreurs : forbidden, admin_profile, not_found.
  Future<void> deleteProfile(String profileId) async {
    await _db.rpc('admin_delete_profile', params: {'p_profile': profileId});
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
  }) async =>
      [
        for (final r in await _fetchRows(userId,
            fromDate: fromDate, onDate: onDate, ascending: ascending))
          Perf.fromJson(r)
      ];

  Future<List<Map<String, dynamic>>> _fetchRows(
    String userId, {
    String? fromDate,
    String? onDate,
    bool ascending = false,
  }) async {
    final out = <Map<String, dynamic>>[];
    for (var start = 0;; start += _pageSize) {
      var q = _db.from('perfs').select('*').eq('user_id', userId);
      if (fromDate != null) q = q.gte('date', fromDate);
      if (onDate != null) q = q.eq('date', onDate);
      final res = await q
          .order('date', ascending: ascending)
          .order('id', ascending: ascending)
          .range(start, start + _pageSize - 1)
          .timeout(_timeout);
      final rows = res as List;
      out.addAll(rows.map((j) => Map<String, dynamic>.from(j as Map)));
      if (rows.length < _pageSize) break;
    }
    return out;
  }

  /// Tout l'historique (copie locale + séries en attente si pas de réseau).
  Future<List<Perf>> getAllPerfs(String userId) async {
    try {
      _offline.setAllPerfs(userId, await _fetchRows(userId));
      SyncService.instance.markOnline();
    } catch (e) {
      if (!isNetworkError(e) || !_offline.hasCache(userId)) rethrow;
      SyncService.instance.markOffline();
    }
    return _offline.view(userId);
  }

  /// Séries d'un jour, séries en attente comprises.
  Future<List<Perf>> getPerfsForDate(String userId, DateTime date) async {
    final day = DateFormat('yyyy-MM-dd').format(date);
    bool sameDay(Perf p) => DateFormat('yyyy-MM-dd').format(p.date) == day;
    try {
      final rows = await _fetchRows(userId, onDate: day);
      SyncService.instance.markOnline();
      if (!_offline.hasCache(userId)) {
        // Pas encore de copie complète : le jour lu + ses séries en attente.
        return [
          ..._offline.view(userId).where((p) => p.pending && sameDay(p)),
          for (final r in rows) Perf.fromJson(r),
        ];
      }
      _offline.setDayPerfs(userId, date, rows);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      SyncService.instance.markOffline();
    }
    return _offline.view(userId).where(sameDay).toList();
  }

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
    try {
      return await _previousSessionOnline(userId, before);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      SyncService.instance.markOffline();
      // Hors ligne : la dernière date avant [before] dans la copie locale.
      final b = DateTime(before.year, before.month, before.day);
      final older = _offline.view(userId).where((p) => p.date.isBefore(b));
      if (older.isEmpty) return [];
      final last = older.first.date; // vue du plus récent au plus ancien
      return older.where((p) => p.date == last).toList().reversed.toList();
    }
  }

  Future<List<Perf>> _previousSessionOnline(
      String userId, DateTime before) async {
    final last = await _db
        .from('perfs')
        .select('date')
        .eq('user_id', userId)
        .lt('date', DateFormat('yyyy-MM-dd').format(before))
        .order('date', ascending: false)
        .limit(1)
        .timeout(_timeout);
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

  /// Range un exercice dans une catégorie, sur tout son historique.
  Future<void> setExerciseCategory(
      String userId, String exercice, String categorie) async {
    await _db
        .from('perfs')
        .update({'categorie': categorie.trim()})
        .eq('user_id', userId)
        .eq('exercice', exercice);
  }

  /// Insère plusieurs séries en une requête (saisie « 12 10 8 »).
  /// Renvoie true si elles sont envoyées, false si elles attendent le réseau
  /// (enregistrées sur le téléphone, envoyées automatiquement plus tard).
  Future<bool> savePerfs(List<Perf> perfs) async {
    if (perfs.isEmpty) return true;
    final userId = perfs.first.userId;
    final rows = [
      for (final p in perfs)
        {...p.toJson(), 'client_id': p.clientId ?? newClientId()}
    ];
    try {
      final res = await _db
          .from('perfs')
          .upsert(rows, onConflict: 'client_id', ignoreDuplicates: true)
          .select()
          .timeout(_timeout);
      _offline.addPerfs(userId,
          [for (final r in res as List) Map<String, dynamic>.from(r as Map)]);
      SyncService.instance.markOnline();
      return true;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      _offline.enqueueInserts(userId, rows);
      SyncService.instance.onQueued();
      return false;
    }
  }

  /// Corrige la valeur d'une série déjà enregistrée (et son effort).
  /// Série en attente ou pas de réseau : corrigée sur le téléphone.
  Future<void> updatePerfValue(int id, double performance,
      {int? effortPondere}) async {
    if (id < 0) {
      _offline.updateValue(id, performance, effortPondere: effortPondere);
      return;
    }
    try {
      await _db.from('perfs').update({
        'performance': performance,
        if (effortPondere != null) 'effort_pondere': effortPondere,
      }).eq('id', id).timeout(_timeout);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      _offline.updateValue(id, performance, effortPondere: effortPondere);
      SyncService.instance.onQueued();
    }
  }

  /// Remplace les séries d'un exercice pour un jour (petites cartes de
  /// Saisie, comme les blocs du web) : réenregistrer ne crée pas de doublon.
  Future<void> replaceExerciseOnDate(
      String userId, DateTime date, String exercice, List<Perf> perfs) async {
    await _db
        .from('perfs')
        .delete()
        .eq('user_id', userId)
        .eq('date', DateFormat('yyyy-MM-dd').format(date))
        .eq('exercice', exercice);
    await savePerfs(perfs);
  }

  /// Supprime toutes les séries d'un jour (« Supprimer la séance »).
  Future<void> deleteSession(String userId, DateTime date) async {
    final day = DateFormat('yyyy-MM-dd').format(date);
    final ofDay = _offline
        .view(userId)
        .where((p) => DateFormat('yyyy-MM-dd').format(p.date) == day)
        .toList();
    // Les séries de ce jour encore en attente ne partiront pas.
    for (final p in ofDay.where((p) => p.pending)) {
      _offline.delete(p.id!);
    }
    try {
      await _db
          .from('perfs')
          .delete()
          .eq('user_id', userId)
          .eq('date', day)
          .timeout(_timeout);
      _offline.setDayPerfs(userId, date, const []);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      for (final p in ofDay.where((p) => !p.pending)) {
        _offline.delete(p.id!);
      }
      SyncService.instance.onQueued();
    }
    SyncService.instance.refresh();
  }

  /// Supprime une série (en attente : retirée de la file ; sans réseau :
  /// suppression mise en file).
  Future<void> deletePerf(int id) async {
    if (id < 0) {
      _offline.delete(id);
      SyncService.instance.refresh();
      return;
    }
    try {
      await _db.from('perfs').delete().eq('id', id).timeout(_timeout);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      _offline.delete(id);
      SyncService.instance.onQueued();
    }
  }

  Future<List<String>> getExerciceNames(String userId) async {
    final perfs = await getAllPerfs(userId);
    final set = <String>{
      for (final p in perfs)
        if (p.exercice.isNotEmpty) p.exercice,
    };
    return set.toList()..sort();
  }

  /// Tous les exercices de l'historique avec leur dernière unité et catégorie
  /// (et pas seulement ceux des 90 derniers jours).
  Future<Map<String, (String, String)>> getExerciceMeta(String userId) async {
    final perfs = await getAllPerfs(userId); // du plus récent au plus ancien
    final out = <String, (String, String)>{};
    for (final p in perfs) {
      if (p.exercice.isNotEmpty) {
        out.putIfAbsent(p.exercice, () => (p.unite, p.categorie));
      }
    }
    return out;
  }

  // ─── Calendrier : jours actifs ────────────────────────────────────────────

  /// Nombre de séries par jour ; [months] null = tout l'historique.
  Future<Map<DateTime, int>> getActiveDays(String userId, {int? months}) async {
    // Tout l'historique (copie locale sans réseau), filtré sur la période.
    final from = months == null
        ? null
        : DateTime.now().subtract(Duration(days: months * 30));
    final perfs = (await getAllPerfs(userId))
        .where((p) => from == null || !p.date.isBefore(from));
    final map = <DateTime, int>{};
    for (final p in perfs) {
      final key = DateTime(p.date.year, p.date.month, p.date.day);
      map[key] = (map[key] ?? 0) + 1;
    }
    return map;
  }

  // ─── Paramètres utilisateur (table user_settings, partagée avec Streamlit) ─

  Future<Map<String, dynamic>> getSettings(String userId) async {
    try {
      final res = await _db
          .from('user_settings')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(_timeout);
      _offline.setSettings(userId, res ?? {});
      return res ?? {};
    } catch (_) {
      // Réseau : derniers réglages connus ; sinon valeurs par défaut (même
      // règle que Python).
      return _offline.settings(userId) ?? {};
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
    if (!await _hasSession()) {
      await _db
          .from('profiles')
          .update({'pin_hash': _sha256(pin.trim())}).eq('id', profileId);
      return;
    }
    await _db.rpc('set_profile_pin',
        params: {'p_profile': profileId, 'p_pin': pin.trim()});
  }
}

/// Réponse de la vérification du PIN par le serveur.
enum ClaimResult { ok, badPin, locked }
