import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/services/offline_store.dart';
import 'package:sysiphe/services/sync_service.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/saisie/offline_banner.dart';
import 'package:sysiphe/widgets/saisie/perf_tile.dart';

Map<String, dynamic> row(int id, String day, String ex, double v,
        {int serie = 1}) =>
    {
      'id': id,
      'user_id': 'u',
      'date': day,
      'exercice': ex,
      'serie': serie,
      'performance': v,
      'unite': 'Reps',
    };

Map<String, dynamic> newRow(String day, String ex, double v, {int serie = 1}) =>
    {
      ...row(0, day, ex, v, serie: serie)..remove('id'),
      'client_id': newClientId()
    };

void main() {
  late Directory tmp;
  late OfflineStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline');
    store = OfflineStore(file: () async => File('${tmp.path}/o.json'));
    await store.load();
  });
  tearDown(() async {
    await store.idle;
    await tmp.delete(recursive: true);
  });

  group('copie locale + file d\'attente', () {
    test('vue = copie + séries en attente, les plus récentes d\'abord', () {
      store.setAllPerfs('u', [
        row(10, '2026-11-22', 'Traction', 10),
        row(11, '2026-11-23', 'Traction', 12),
      ]);
      final ids = store.enqueueInserts('u', [
        newRow('2026-11-24', 'Traction', 8),
        newRow('2026-11-24', 'Traction', 7, serie: 2),
      ]);
      expect(ids, [-1, -2]);
      final v = store.view('u');
      expect(v.map((p) => p.id), [-2, -1, 11, 10]);
      expect(v.first.pending, isTrue);
      expect(v.last.pending, isFalse);
      expect(store.pendingCount(), 2);
    });

    test('série en attente corrigée puis supprimée : seule la file change', () {
      store.setAllPerfs('u', []);
      final id =
          store.enqueueInserts('u', [newRow('2026-11-24', 'Pompe', 20)]).single;
      store.updateValue(id, 25);
      expect(store.view('u').single.performance, 25);
      expect(store.outbox.single.kind, 'insert');
      expect(store.outbox.single.data['performance'], 25);
      store.delete(id);
      expect(store.view('u'), isEmpty);
      expect(store.pendingCount(), 0);
    });

    test('série déjà envoyée corrigée / supprimée hors ligne : mise en file',
        () {
      store.setAllPerfs('u', [
        row(10, '2026-11-23', 'Pompe', 20),
        row(11, '2026-11-23', 'Pompe', 18, serie: 2),
      ]);
      store.updateValue(10, 22, effortPondere: 0);
      store.delete(11);
      expect(store.outbox.map((o) => o.kind), ['update', 'delete']);
      // Une relecture en ligne remettant les anciennes valeurs ne les efface
      // pas tant que la file n'est pas envoyée.
      store.setAllPerfs('u', [
        row(10, '2026-11-23', 'Pompe', 20),
        row(11, '2026-11-23', 'Pompe', 18, serie: 2),
      ]);
      final v = store.view('u');
      expect(v.single.id, 10);
      expect(v.single.performance, 22);
    });

    test('tout est gardé sur le téléphone (relecture du fichier)', () async {
      store.setAllPerfs('u', [row(10, '2026-11-23', 'Pompe', 20)]);
      store.setSettings('u', {'weight': 82});
      store.enqueueInserts('u', [newRow('2026-11-24', 'Pompe', 21)]);
      await store.save();
      final again = OfflineStore(file: () async => File('${tmp.path}/o.json'));
      await again.load();
      addTearDown(() => again.idle);
      expect(again.view('u').map((p) => p.id), [-1, 10]);
      expect(again.settings('u'), {'weight': 82});
      expect(again.enqueueInserts('u', [newRow('2026-11-24', 'Pompe', 1)]),
          [-2]); // numérotation locale reprise
    });

    test('identifiant client : UUID v4', () {
      final id = newClientId();
      expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
              .hasMatch(id),
          isTrue);
      expect(newClientId(), isNot(id));
    });
  });

  group('envoi automatique', () {
    test('dans l\'ordre ; arrêt à la première erreur réseau, puis reprise',
        () async {
      store.setAllPerfs('u', [row(10, '2026-11-23', 'Pompe', 20)]);
      store.enqueueInserts('u', [newRow('2026-11-24', 'Pompe', 21)]);
      store.updateValue(10, 22);
      var reseau = false;
      final sentKinds = <String>[];
      var nextId = 100;
      final sync = SyncService(
        store: store,
        retryEvery: const Duration(hours: 1),
        sender: (op) async {
          if (!reseau) throw const SocketException('Failed host lookup');
          sentKinds.add(op.kind);
          return op.kind == 'insert' ? {...op.data, 'id': nextId++} : null;
        },
      );
      expect(await sync.flush(), 0);
      expect(sync.offline.value, isTrue);
      expect(sync.pending.value, 2);

      reseau = true;
      expect(await sync.flush(), 2);
      expect(sentKinds, ['insert', 'update']);
      expect(sync.pending.value, 0);
      expect(sync.offline.value, isFalse);
      // La série envoyée remplace la série en attente, avec son vrai id.
      expect(store.view('u').map((p) => p.id), [100, 10]);
      sync.dispose();
    });

    test('refus du serveur : retiré de la file et signalé', () async {
      store.setAllPerfs('u', []);
      store.enqueueInserts('u', [newRow('2026-11-24', 'Pompe', 21)]);
      final sync = SyncService(
        store: store,
        sender: (op) async => throw Exception('permission denied'),
      );
      await sync.flush();
      expect(store.pendingCount(), 0);
      expect(sync.lastError.value, contains('permission denied'));
      sync.dispose();
    });

    test('erreurs réseau et serveur distinguées', () {
      expect(isNetworkError(const SocketException('x')), isTrue);
      expect(isNetworkError(TimeoutException('x')), isTrue);
      expect(
          isNetworkError(Exception('Failed host lookup: supabase.co')), isTrue);
      expect(isNetworkError(Exception('new row violates row-level security')),
          isFalse);
    });
  });

  group('affichage', () {
    testWidgets('indicateur « 1 opération en attente » et série en attente',
        (t) async {
      final store = OfflineStore.memory()..clearForTest();
      store.setAllPerfs('u', []);
      final sync = SyncService(store: store, sender: (_) async => null);
      store.enqueueInserts('u', [newRow('2026-11-24', 'Pompe', 21)]);
      sync.onQueued();
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(children: [
            OfflineBanner(sync: sync),
            PerfTile(
                perf: store.view('u').single, onDelete: () {}, onEdit: () {}),
          ]),
        ),
      ));
      expect(find.text('Hors ligne · 1 opération en attente d\'envoi'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('perf-pending')), findsOneWidget);
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(find.textContaining('en attente'), findsNothing); // tout envoyé
      sync.dispose();
    });
  });
}
