import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sysiphe/services/google_account.dart';

User _user({bool anonymous = false, String? email}) => User(
      id: 'u',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-18',
      email: email,
      isAnonymous: anonymous,
    );

AuthState _signedIn({bool anonymous = false}) => AuthState(
    AuthChangeEvent.signedIn,
    Session(
        accessToken: 'a',
        tokenType: 'bearer',
        user: _user(anonymous: anonymous)));

void main() {
  late StreamController<AuthState> auth;
  late List<String> calls;
  setUp(() {
    auth = StreamController<AuthState>.broadcast();
    calls = [];
  });
  tearDown(() => auth.close());

  GoogleAccount make({
    Future<String> Function()? create,
    Future<int> Function(String)? redeem,
    bool launched = true,
    bool returns = true,
  }) =>
      GoogleAccount(
        createToken: create ??
            () async {
              calls.add('create');
              return 'tok';
            },
        redeemToken: redeem ??
            (t) async {
              calls.add('redeem:$t');
              return 2;
            },
        launchSignIn: () async {
          calls.add('launch');
          if (returns) {
            // Une session anonyme ne compte pas ; seul Google termine.
            Timer.run(() => auth.add(_signedIn(anonymous: true)));
            Timer.run(() => auth.add(_signedIn()));
          }
          return launched;
        },
        authChanges: () => auth.stream,
        timeout: const Duration(milliseconds: 200),
      );

  test('associer : jeton créé avant Google, échangé après', () async {
    final out = await make().connect(link: true);
    expect(calls, ['create', 'launch', 'redeem:tok']);
    expect(out.result, GoogleResult.linked);
    expect(out.profiles, 2);
  });

  test('se connecter : pas de jeton', () async {
    final out = await make().connect(link: false);
    expect(calls, ['launch']);
    expect(out.result, GoogleResult.signedIn);
  });

  test('aucun profil sur ce téléphone : Google n\'est pas ouvert', () async {
    final out = await make(create: () async => throw Exception('no_profile'))
        .connect(link: true);
    expect(out.result, GoogleResult.noProfile);
    expect(calls, isEmpty);
  });

  test('navigateur fermé sans connexion : annulé, jeton non utilisé', () async {
    final out = await make(returns: false).connect(link: true);
    expect(out.result, GoogleResult.cancelled);
    expect(calls, ['create', 'launch']);
  });

  test('échange refusé (jeton expiré) : message clair', () async {
    final out = await make(redeem: (_) async => throw Exception('expired'))
        .connect(link: true);
    expect(out.result, GoogleResult.tokenError);
    expect(out.message, contains('expired'));
  });

  test('adresse Google : null pour une session anonyme', () {
    expect(GoogleAccount.emailOf(null), isNull);
    expect(GoogleAccount.emailOf(_user(anonymous: true)), isNull);
    expect(GoogleAccount.emailOf(_user(email: 'a@b.fr')), 'a@b.fr');
  });

  test('retour dans l\'app sans connexion : annulé sans attendre', () async {
    final resumes = StreamController<void>.broadcast();
    final g = GoogleAccount(
      createToken: () async => 'tok',
      redeemToken: (_) async => 1,
      launchSignIn: () async {
        Timer.run(() => resumes.add(null));
        return true;
      },
      authChanges: () => auth.stream,
      resumes: () => resumes.stream,
      resumeGrace: const Duration(milliseconds: 20),
      timeout: const Duration(minutes: 5),
    );
    final out = await g.connect(link: true).timeout(const Duration(seconds: 2));
    expect(out.result, GoogleResult.cancelled);
    await resumes.close();
  });
}
