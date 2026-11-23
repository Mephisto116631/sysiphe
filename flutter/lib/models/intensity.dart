import 'dart:ui' show Color;

/// Seuils des couleurs d'intensité d'un profil, en points d'effort
/// (user_settings.intensity_config) : vert en dessous d'[orange], orange à
/// [orange], rouge à partir de [rouge]. Sans seuils (« Automatique ») :
/// relatif au meilleur effort, comme avant.
class IntensityConfig {
  final int? orange;
  final int? rouge;
  const IntensityConfig({this.orange, this.rouge});

  bool get auto =>
      orange == null || rouge == null || orange! <= 0 || rouge! <= orange!;

  factory IntensityConfig.fromSettings(dynamic raw) {
    if (raw is! Map) return const IntensityConfig();
    int? n(dynamic v) => v is num ? v.toInt() : null;
    return IntensityConfig(orange: n(raw['orange']), rouge: n(raw['rouge']));
  }

  /// Valeur pour user_settings (null = automatique).
  Map<String, int>? toSettings() =>
      auto ? null : {'orange': orange!, 'rouge': rouge!};

  /// Position 0 (vert) → 0,5 (orange) → 1 (rouge) d'un effort.
  /// [best] : meilleur effort connu, utilisé en mode automatique.
  double ratio(num effort, {required num best}) {
    final e = effort.toDouble();
    if (auto) return best <= 0 ? 0 : (e / best).clamp(0.0, 1.0);
    final o = orange!.toDouble(), r = rouge!.toDouble();
    if (e <= 0) return 0;
    if (e <= o) return 0.5 * e / o;
    if (e >= r) return 1;
    return 0.5 + 0.5 * (e - o) / (r - o);
  }

  Color colorFor(num effort, {required num best}) =>
      intensityColor(ratio(effort, best: best));
}

/// Vert → orange → rouge selon l'intensité (comme _intensity_color du web).
Color intensityColor(double ratio) {
  final r = ratio.clamp(0.0, 1.0);
  return r < 0.5
      ? Color.lerp(const Color(0xFF22C55E), const Color(0xFFF59E0B), r / 0.5)!
      : Color.lerp(
          const Color(0xFFF59E0B), const Color(0xFFEF4444), (r - 0.5) / 0.5)!;
}
