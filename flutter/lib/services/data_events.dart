import 'package:flutter/foundation.dart';

/// Incrémenté quand des données partagées changent en masse (recalcul des
/// efforts, nouveaux coefficients). Les onglets gardés en mémoire
/// (IndexedStack) l'écoutent pour se recharger.
final dataVersion = ValueNotifier<int>(0);

void notifyDataChanged() => dataVersion.value++;
