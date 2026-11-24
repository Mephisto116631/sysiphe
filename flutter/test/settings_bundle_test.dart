import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/models/profile.dart';
import 'package:sysiphe/models/settings_bundle.dart';
import 'package:sysiphe/screens/settings/admin_push_page.dart';
import 'package:sysiphe/services/settings_transfer.dart';
import 'package:sysiphe/widgets/settings_import_dialog.dart';

void main() {
  final settings = {
    'user_id': 'u',
    'updated_at': '2026-11-24',
    'weight': 72.5,
    'include_planche': false,
    'enable_charges': true,
    'intensity_config': {'orange': 30, 'rouge': 60},
    'variantes_config': {'Full': 1.0},
    'admin_push': {'id': 'x'},
    'app_theme': 'Abysse',
  };
  final device = <String, Object?>{
    'rest_seconds': 120,
    'chrono_sound_mode': 1,
    'chrono_sets:planche': 3,
    'reminders_on': false,
    'auto_update_download': true, // réglage technique : pas exporté
    'stats_period': 'm3', // filtre d'écran : pas exporté
  };

  group('fichier de paramètres', () {
    test('export : réglages connus seulement, puis relecture identique', () {
      final b = SettingsBundle.from(
          settings: settings,
          device: device,
          profileName: 'La bouille',
          now: DateTime(2026, 11, 24, 9));
      expect(b.profile.keys.toSet(), {
        'weight',
        'include_planche',
        'enable_charges',
        'intensity_config',
      }); // coefficients du modèle : communs, jamais dans un fichier
      expect(b.device.keys.toSet(),
          {'rest_seconds', 'chrono_sound_mode', 'chrono_sets:planche', 'reminders_on'});
      final text = b.encode();
      expect(text, contains('"format": "sysiphe-parametres"'));
      expect(text, contains('\n  "profil_reglages"')); // lisible (indenté)
      final back = SettingsBundle.parse(text);
      expect(back.profile, b.profile);
      expect(back.device, b.device);
      expect(back.profileName, 'La bouille');
      expect(back.exportedAt, DateTime(2026, 11, 24, 9));
      expect(back.ignored, isEmpty);
    });

    test('textes refusés avec un message clair', () {
      expect(() => SettingsBundle.parse('bonjour'),
          throwsA(isA<FormatException>().having(
              (e) => e.message, 'message', contains('JSON'))));
      expect(() => SettingsBundle.parse('{"a": 1}'),
          throwsA(isA<FormatException>().having(
              (e) => e.message, 'message', contains('Sysiphe'))));
      expect(
          () => SettingsBundle.parse(
              '{"format": "sysiphe-parametres", "version": 9}'),
          throwsA(isA<FormatException>().having(
              (e) => e.message, 'message', contains('mets-la à jour'))));
    });

    test('clés inconnues, mauvais types et poids aberrant ignorés', () {
      final b = SettingsBundle.parse('''{
        "format": "sysiphe-parametres", "version": 1,
        "profil_reglages": {"weight": 900, "include_planche": "oui",
                            "enable_charges": false, "pirate": 1},
        "appareil": {"rest_seconds": 90.0, "chrono_sets:": 3,
                     "chrono_target_seconds:gainage": 45, "inconnu": true}
      }''');
      expect(b.profile, {'enable_charges': false});
      expect(b.device, {'rest_seconds': 90, 'chrono_target_seconds:gainage': 45});
      expect(b.ignored.toSet(),
          {'weight', 'include_planche', 'pirate', 'chrono_sets:', 'inconnu'});
    });

    test('résumé de ce qui sera appliqué', () {
      final b = SettingsBundle.from(settings: settings, device: device);
      expect(
          b.describe(),
          containsAll([
            'Poids : 72.5 kg',
            'Planche : désactivée',
            'Couleurs d\'intensité',
            'Repos : 120 s',
            'Chrono (son, départ, objectifs…)',
            'Rappels de séance',
          ]));
    });
  });

  group('réglages de l\'appareil', () {
    test('lecture et écriture des préférences connues', () async {
      SharedPreferences.setMockInitialValues(
          {'rest_seconds': 60, 'stats_period': 'm3'});
      expect(await readDevicePrefs(), {'rest_seconds': 60});
      await applyDevicePrefs({'rest_seconds': 150, 'chrono_fullscreen': true});
      final p = await SharedPreferences.getInstance();
      expect(p.getInt('rest_seconds'), 150);
      expect(p.getBool('chrono_fullscreen'), isTrue);
    });

    test('envoi de l\'admin : appliqué une seule fois', () async {
      SharedPreferences.setMockInitialValues({});
      final s = {
        'admin_push': {
          'id': 'p1',
          'device': {'rest_seconds': 75, 'pirate': 1},
          'recalc': false,
        }
      };
      expect(await applyAdminPush('u', s), isTrue);
      final p = await SharedPreferences.getInstance();
      expect(p.getInt('rest_seconds'), 75);
      expect(p.get('pirate'), isNull);
      await p.setInt('rest_seconds', 30); // l'utilisateur change ensuite
      expect(await applyAdminPush('u', s), isFalse); // déjà appliqué
      expect(p.getInt('rest_seconds'), 30);
      expect(await applyAdminPush('u', {}), isFalse);
    });

    test('message de présentation : une fois par profil', () async {
      SharedPreferences.setMockInitialValues({});
      final s = {
        'presentation': {'id': 'm1', 'titre': '', 'texte': 'Bienvenue !'}
      };
      expect(await pendingPresentation('u', s), ('m1', 'Message', 'Bienvenue !'));
      await markPresentationSeen('u', 'm1');
      expect(await pendingPresentation('u', s), isNull);
      expect(await pendingPresentation('v', s), isNotNull); // autre profil
      expect(
          await pendingPresentation('u', {
            'presentation': {'id': 'm2', 'texte': '  '}
          }),
          isNull);
    });
  });

  group('écrans', () {
    testWidgets('importer : coller, résumé, appliquer', (t) async {
      SettingsBundle? got;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => got = await askSettingsBundle(ctx),
            child: const Text('ouvrir'),
          ),
        ),
      ));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      final apply = find.byKey(const ValueKey('import-apply'));
      expect(t.widget<FilledButton>(apply).onPressed, isNull);
      await t.enterText(find.byKey(const ValueKey('import-text')), 'nimporte');
      await t.pump();
      expect(find.text('Ce texte n\'est pas du JSON valide.'), findsOneWidget);
      final text = SettingsBundle.from(
              settings: {'weight': 80}, device: {}, profileName: 'Medhi')
          .encode();
      await t.enterText(find.byKey(const ValueKey('import-text')), text);
      await t.pump();
      expect(find.text('• Poids : 80 kg'), findsOneWidget);
      await t.tap(apply);
      await t.pumpAndSettle();
      expect(got!.profile, {'weight': 80});
    });

    testWidgets('admin : envoyer un message à un profil', (t) async {
      final sent = <(String, SettingsBundle?, Map<String, String>?)>[];
      await t.pumpWidget(MaterialApp(
        home: AdminPushPage(
          userId: 'admin',
          loadProfiles: () async => const [
            Profile(id: 'b', name: 'La bouille', hasPin: false, isMember: false),
          ],
          send: (id, b, m) async => sent.add((id, b, m)),
        ),
      ));
      await t.pumpAndSettle();
      final send = find.byKey(const ValueKey('push-send'));
      expect(t.widget<FilledButton>(send).onPressed, isNull);
      await t.tap(find.byKey(const ValueKey('push-target')));
      await t.pumpAndSettle();
      await t.tap(find.text('La bouille').last);
      await t.pumpAndSettle();
      await t.enterText(
          find.byKey(const ValueKey('push-text')), 'Active la planche !');
      await t.pump();
      await t.ensureVisible(send);
      await t.tap(send);
      await t.pumpAndSettle();
      expect(sent.single.$1, 'b');
      expect(sent.single.$2, isNull);
      expect(sent.single.$3, {'titre': '', 'texte': 'Active la planche !'});
      expect(find.textContaining('Envoyé à La bouille'), findsOneWidget);
    });
  });
}
