import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'data_events.dart';
import 'offline_store.dart';

/// Erreur de réseau (pas de connexion, délai dépassé…) — à distinguer d'une
/// erreur du serveur (droits, données refusées), qui ne sert à rien de
/// renvoyer plus tard.
bool isNetworkError(Object e) {
  if (e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException) {
    return true;
  }
  final t = e.runtimeType.toString();
  if (t.contains('ClientException') || t.contains('AuthRetryableFetch')) {
    return true;
  }
  final m = '$e';
  return m.contains('SocketException') ||
      m.contains('Failed host lookup') ||
      m.contains('Network is unreachable') ||
      m.contains('Connection closed') ||
      m.contains('Connection refused');
}

/// Envoie au serveur une opération en attente ; pour un `insert`, renvoie la
/// série enregistrée (avec son vrai identifiant) si le serveur la renvoie.
typedef PendingSender = Future<Map<String, dynamic>?> Function(PendingOp op);

/// Envoi automatique de la file d'attente (mode hors ligne) : au démarrage,
/// au retour dans l'app, dès qu'un appel réseau réussit, et toutes les 60 s
/// tant qu'il reste quelque chose. [pending] et [offline] alimentent
/// l'indicateur de la Saisie.
class SyncService {
  SyncService(
      {OfflineStore? store,
      this.sender,
      this.retryEvery = const Duration(seconds: 60)})
      : _storeOverride = store;

  static SyncService instance = SyncService();

  final OfflineStore? _storeOverride;
  OfflineStore get store => _storeOverride ?? OfflineStore.instance;

  /// Envoi réel (branché par SupabaseService au démarrage).
  PendingSender? sender;
  final Duration retryEvery;

  final pending = ValueNotifier<int>(0);
  final offline = ValueNotifier<bool>(false);

  /// Dernière opération refusée par le serveur (affichée, puis oubliée).
  final lastError = ValueNotifier<String?>(null);

  Timer? _retry;
  bool _busy = false;
  AppLifecycleListener? _life;

  void start() {
    refresh();
    _life ??= AppLifecycleListener(onResume: flush);
    flush();
  }

  void refresh() => pending.value = store.pendingCount();

  void markOnline() {
    if (offline.value) offline.value = false;
    if (store.pendingCount() > 0) flush();
  }

  void markOffline() {
    offline.value = true;
    _scheduleRetry();
  }

  /// Une opération vient d'être mise en file (réseau absent).
  void onQueued() {
    refresh();
    markOffline();
  }

  void _scheduleRetry() {
    if (_retry?.isActive ?? false) return;
    _retry = Timer(retryEvery, () {
      _retry = null;
      flush();
    });
  }

  /// Envoie la file dans l'ordre ; s'arrête à la première erreur réseau
  /// (nouvel essai plus tard). Renvoie le nombre d'opérations envoyées.
  Future<int> flush() async {
    final send = sender;
    if (_busy || send == null || store.pendingCount() == 0) {
      refresh();
      return 0;
    }
    _busy = true;
    var sent = 0;
    try {
      for (final op in List.of(store.outbox)) {
        try {
          final row = await send(op);
          store.done(op);
          if (op.kind == 'insert' && row != null) {
            store.addPerfs(op.userId, [row]);
          }
          sent++;
        } catch (e) {
          if (isNetworkError(e)) {
            offline.value = true;
            _scheduleRetry();
            break;
          }
          // Refus du serveur : inutile de réessayer, on le signale.
          store.done(op);
          lastError.value = '$e';
        }
      }
      if (store.pendingCount() == 0) offline.value = false;
    } finally {
      _busy = false;
      refresh();
    }
    if (sent > 0) notifyDataChanged();
    return sent;
  }

  void dispose() {
    _retry?.cancel();
    _life?.dispose();
  }
}
