import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/models/profile.dart';
import 'package:sysiphe/services/session_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('aucun profil mémorisé au premier lancement', () async {
    expect(await SessionStore.load(), isNull);
  });

  test('le profil choisi est retrouvé à la réouverture', () async {
    await SessionStore.save(
        const Profile(id: 'abc', name: 'Medhi', hasPin: true));
    final p = await SessionStore.load();
    expect(p?.id, 'abc');
    expect(p?.name, 'Medhi');
    expect(p?.hasPin, isTrue);
  });

  test('« Changer de profil » oublie la session', () async {
    await SessionStore.save(
        const Profile(id: 'abc', name: 'Medhi', hasPin: true));
    await SessionStore.clear();
    expect(await SessionStore.load(), isNull);
  });
}
