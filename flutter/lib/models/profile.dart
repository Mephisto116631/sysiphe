import 'package:flutter/widgets.dart' show StringCharacters;

class Profile {
  final String id;
  final String name;
  final bool hasPin;
  final DateTime? lastLogin;

  /// Cet appareil est déjà rattaché au profil (PIN déjà vérifié par le
  /// serveur) : pas besoin de redemander le PIN.
  final bool isMember;

  const Profile({
    required this.id,
    required this.name,
    required this.hasPin,
    this.lastLogin,
    this.isMember = false,
  });

  /// Ligne de la RPC list_profiles (has_pin, is_member) — le hash du PIN
  /// n'est jamais renvoyé au client.
  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Profil',
        hasPin: json['has_pin'] as bool? ?? (json['pin_hash'] != null),
        isMember: json['is_member'] as bool? ?? false,
        lastLogin: json['last_login'] != null
            ? DateTime.tryParse(json['last_login'] as String)
            : null,
      );

  /// Deux premières initiales, en caractères complets (graphèmes) : un emoji
  /// comme « 🐶 » n'est pas coupé en deux, et les espaces multiples sont
  /// ignorés.
  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts[0].characters.first;
    if (parts.length == 1) return first.toUpperCase();
    return (first + parts[1].characters.first).toUpperCase();
  }
}
