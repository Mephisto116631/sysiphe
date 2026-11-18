import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lien de retour de Google vers l'app (déclaré dans AndroidManifest.xml et
/// dans les « Redirect URLs » de Supabase).
const kGoogleRedirect = 'com.sysiphe.app://login-callback';

enum GoogleResult { linked, signedIn, cancelled, noProfile, tokenError, error }

/// Résultat d'une connexion Google : [profiles] = profils rattachés grâce au
/// jeton (association depuis les Réglages), [message] = détail d'une erreur.
class GoogleOutcome {
  final GoogleResult result;
  final int profiles;
  final String? message;
  const GoogleOutcome(this.result, {this.profiles = 0, this.message});
}

/// Compte Google (étape 3 de la sécurité) :
/// - **associer** (Réglages) : la session du téléphone crée un jeton à usage
///   unique (`create_link_token`), ouvre une session Google, puis l'échange
///   (`redeem_link_token`) : le compte Google reçoit les mêmes profils ;
/// - **se connecter** (autre téléphone) : session Google seule, ses profils
///   associés s'ouvrent sans PIN.
/// Fonctionne que le compte Google existe déjà ou non. Les accès réseau sont
/// injectables pour les tests.
class GoogleAccount {
  final Future<String> Function() createToken;
  final Future<int> Function(String token) redeemToken;
  final Future<bool> Function() launchSignIn;
  final Stream<AuthState> Function() authChanges;

  /// Retours dans l'app (navigateur fermé) : sans connexion Google peu après,
  /// on considère la connexion annulée au lieu d'attendre [timeout].
  final Stream<void> Function()? resumes;
  final Duration resumeGrace;
  final Duration timeout;

  GoogleAccount({
    required this.createToken,
    required this.redeemToken,
    required this.launchSignIn,
    required this.authChanges,
    this.resumes,
    this.resumeGrace = const Duration(seconds: 5),
    this.timeout = const Duration(minutes: 5),
  });

  factory GoogleAccount.supabase() {
    final db = Supabase.instance.client;
    return GoogleAccount(
      createToken: () async => await db.rpc('create_link_token') as String,
      redeemToken: (t) async =>
          (await db.rpc('redeem_link_token', params: {'p_token': t}) as num)
              .toInt(),
      launchSignIn: () => db.auth
          .signInWithOAuth(OAuthProvider.google, redirectTo: kGoogleRedirect),
      authChanges: () => db.auth.onAuthStateChange,
      resumes: _appResumes,
    );
  }

  static Stream<void> _appResumes() {
    late final AppLifecycleListener l;
    final c = StreamController<void>(onCancel: () => l.dispose());
    l = AppLifecycleListener(onResume: () => c.add(null));
    return c.stream;
  }

  /// Adresse du compte Google de la session actuelle (null si anonyme).
  static String? emailOf(User? user) {
    if (user == null || user.isAnonymous) return null;
    for (final i in user.identities ?? const <UserIdentity>[]) {
      if (i.provider == 'google') {
        return (i.identityData?['email'] as String?) ?? user.email;
      }
    }
    return user.email;
  }

  static String? get currentEmail =>
      emailOf(Supabase.instance.client.auth.currentUser);

  /// [link] = true : associe les profils de ce téléphone au compte Google.
  Future<GoogleOutcome> connect({required bool link}) async {
    String? token;
    if (link) {
      try {
        token = await createToken();
      } catch (e) {
        return '$e'.contains('no_profile')
            ? const GoogleOutcome(GoogleResult.noProfile)
            : GoogleOutcome(GoogleResult.error, message: '$e');
      }
    }

    // Abonnement avant d'ouvrir le navigateur : le retour peut être rapide.
    final signedIn = Completer<void>();
    final sub = authChanges().listen((s) {
      final u = s.session?.user;
      if (s.event == AuthChangeEvent.signedIn &&
          u != null &&
          !u.isAnonymous &&
          !signedIn.isCompleted) {
        signedIn.complete();
      }
    });
    Timer? grace;
    final back = resumes?.call().listen((_) {
      grace?.cancel();
      grace = Timer(resumeGrace, () {
        if (!signedIn.isCompleted) signedIn.completeError(TimeoutException(''));
      });
    });
    try {
      if (!await launchSignIn()) {
        return const GoogleOutcome(GoogleResult.cancelled);
      }
      await signedIn.future.timeout(timeout);
    } on TimeoutException {
      return const GoogleOutcome(GoogleResult.cancelled);
    } catch (e) {
      return GoogleOutcome(GoogleResult.error, message: '$e');
    } finally {
      grace?.cancel();
      await back?.cancel();
      await sub.cancel();
    }

    if (token == null) return const GoogleOutcome(GoogleResult.signedIn);
    try {
      final n = await redeemToken(token);
      return GoogleOutcome(GoogleResult.linked, profiles: n);
    } catch (e) {
      return GoogleOutcome(GoogleResult.tokenError, message: '$e');
    }
  }
}
