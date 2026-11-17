import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Les trois sons du chrono (fichiers dans `assets/`).
enum Bip { court, depart, objectif }

/// Effets du chrono hors écran : bips et écran maintenu allumé.
/// Interface injectable : les tests passent une version factice.
abstract class ChronoFx {
  void bip(Bip b);
  void keepAwake(bool on);
}

/// Version réelle : audioplayers en mode basse latence, la musique en cours
/// est juste baissée le temps du bip (pas coupée). Jamais bloquant.
class DeviceChronoFx implements ChronoFx {
  DeviceChronoFx._();
  static final instance = DeviceChronoFx._();

  final Map<Bip, AudioPlayer> _players = {};

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
