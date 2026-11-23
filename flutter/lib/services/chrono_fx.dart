import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// Bips activés (ancien réglage, repris s'il existe).
const kChronoSoundKey = 'chrono_sound';

/// Son du chrono et du repos : 0 = muet, 1 = bips, 2 = bips + voix (défaut).
const kChronoSoundModeKey = 'chrono_sound_mode';

/// Réglage son actuel (jamais bloquant : voix + bips par défaut).
Future<int> chronoSoundMode() async {
  try {
    final p = await SharedPreferences.getInstance();
    return (p.getInt(kChronoSoundModeKey) ??
            (p.getBool(kChronoSoundKey) == false ? 0 : 2))
        .clamp(0, 2);
  } catch (_) {
    return 2;
  }
}

/// Les trois sons du chrono (fichiers dans `assets/`).
enum Bip { court, depart, objectif }

/// Effets du chrono hors écran : bips et écran maintenu allumé.
/// Interface injectable : les tests passent une version factice.
abstract class ChronoFx {
  void bip(Bip b);
  void keepAwake(bool on);

  /// Annonce vocale (« 10 secondes », « Objectif atteint »…).
  void say(String text);
}

/// Version réelle : audioplayers en mode basse latence, la musique en cours
/// est juste baissée le temps du bip (pas coupée). Jamais bloquant.
class DeviceChronoFx implements ChronoFx {
  DeviceChronoFx._();
  static final instance = DeviceChronoFx._();

  final Map<Bip, AudioPlayer> _players = {};
  FlutterTts? _tts;

  Future<FlutterTts> _voice() async {
    final t = _tts;
    if (t != null) return t;
    final n = FlutterTts();
    await n.setLanguage('fr-FR');
    await n.setSpeechRate(0.5);
    await n.awaitSpeakCompletion(false);
    return _tts = n;
  }

  @override
  void say(String text) async {
    try {
      final t = await _voice();
      await t.stop(); // la dernière annonce remplace la précédente
      await t.speak(text);
    } catch (_) {/* synthèse vocale indisponible : les bips suffisent */}
  }

  static const _files = {
    Bip.court: 'bip_court.wav',
    Bip.depart: 'bip_depart.wav',
    Bip.objectif: 'bip_objectif.wav',
  };

  Future<AudioPlayer> _player(Bip b) async {
    final p = _players[b];
    if (p != null) return p;
    final n = AudioPlayer();
    await n.setAudioContext(AudioContextConfig(
      focus: AudioContextConfigFocus.duckOthers,
    ).build());
    await n.setPlayerMode(PlayerMode.lowLatency);
    await n.setReleaseMode(ReleaseMode.stop);
    await n.setSource(AssetSource(_files[b]!));
    return _players[b] = n;
  }

  @override
  void bip(Bip b) async {
    try {
      final p = await _player(b);
      await p.stop();
      await p.resume();
    } catch (_) {/* son indisponible : la vibration suffit */}
  }

  @override
  void keepAwake(bool on) async {
    try {
      on ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {}
  }
}
