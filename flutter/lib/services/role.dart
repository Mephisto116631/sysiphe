import 'package:flutter/foundation.dart';

/// Le profil actif est-il administrateur ? Lu côté serveur (RPC profile_role)
/// à l'ouverture ; faux par défaut (hors ligne : options admin masquées).
final isAdminNotifier = ValueNotifier<bool>(false);
