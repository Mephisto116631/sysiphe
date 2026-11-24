import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/avatar.dart';
import 'package:sysiphe/models/profile.dart';
import 'package:sysiphe/widgets/avatar_editor.dart';
import 'package:sysiphe/widgets/avatar_view.dart';

/// PNG 1×1 transparent (photo factice).
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

void main() {
  group('avatar : données', () {
    test('aller-retour JSON des trois sortes', () {
      for (final a in [
        const ProfileAvatar.lettres(3),
        const ProfileAvatar.image('🦊', 5),
        const ProfileAvatar.photo(_png),
      ]) {
        expect(ProfileAvatar.fromJson(a.toJson()), a);
        expect(ProfileAvatar.fromJson(jsonEncode(a.toJson())), a);
      }
    });

    test('lecture tolérante : par défaut, lettres bleues', () {
      expect(ProfileAvatar.fromJson(null), ProfileAvatar.defaut);
      expect(ProfileAvatar.fromJson('pas du json'), ProfileAvatar.defaut);
      expect(ProfileAvatar.fromJson({'type': 'photo'}), ProfileAvatar.defaut);
      expect(ProfileAvatar.fromJson({'type': 'image', 'couleur': 2}),
          const ProfileAvatar.lettres(2));
      expect(const ProfileAvatar.lettres(99).background, kAvatarColors.last);
    });

    test('profil : avatar lu depuis list_profiles', () {
      final p = Profile.fromJson({
        'id': 'a',
        'name': 'La bouille',
        'has_pin': false,
        'avatar': {'type': 'image', 'emoji': '🐼', 'couleur': 1},
      });
      expect(p.avatar, const ProfileAvatar.image('🐼', 1));
      expect(Profile.fromJson({'id': 'b', 'name': 'X'}).avatar,
          ProfileAvatar.defaut);
      expect(p.copyWith(avatar: ProfileAvatar.defaut).name, 'La bouille');
    });
  });

  group('avatar : écrans', () {
    Future<void> show(WidgetTester t, ProfileAvatar a) =>
        t.pumpWidget(MaterialApp(
            home: Scaffold(body: AvatarView(initials: 'LB', avatar: a))));

    testWidgets('lettres, image, photo', (t) async {
      await show(t, const ProfileAvatar.lettres(2));
      expect(find.text('LB'), findsOneWidget);
      expect(t.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundColor,
          kAvatarColors[2]);
      await show(t, const ProfileAvatar.image('🦊'));
      expect(find.text('🦊'), findsOneWidget);
      expect(find.text('LB'), findsNothing);
      await show(t, const ProfileAvatar.photo(_png));
      expect(
          t.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
          isA<MemoryImage>());
      // Photo illisible : retour aux lettres.
      await show(t, const ProfileAvatar.photo('%%%'));
      expect(find.text('LB'), findsOneWidget);
    });

    testWidgets('choisir couleur, image puis photo', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      ProfileAvatar? got;
      var cameraAsked = false;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => got = await editAvatar(ctx,
                initials: 'LB',
                current: ProfileAvatar.defaut,
                picker: ({required bool camera}) async {
                  cameraAsked = camera;
                  return _png;
                }),
            child: const Text('ouvrir'),
          ),
        ),
      ));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      final save = find.byKey(const ValueKey('avatar-save'));
      expect(t.widget<FilledButton>(save).onPressed, isNull); // rien changé

      await t.tap(find.byKey(const ValueKey('avatar-color-4')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('avatar-emoji-🐻')));
      await t.pump();
      expect(t.takeException(), isNull);
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(got, const ProfileAvatar.image('🐻', 4));

      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('avatar-camera')));
      await t.tap(find.byKey(const ValueKey('avatar-camera')));
      await t.pumpAndSettle();
      expect(cameraAsked, isTrue);
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(got, const ProfileAvatar.photo(_png));
    });
  });
}
