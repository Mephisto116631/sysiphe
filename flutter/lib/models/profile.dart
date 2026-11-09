class Profile {
  final String id;
  final String name;
  final bool hasPin;
  final DateTime? lastLogin;

  const Profile({
    required this.id,
    required this.name,
    required this.hasPin,
    this.lastLogin,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Profil',
        hasPin: (json['pin_hash'] as String?) != null,
        lastLogin: json['last_login'] != null
            ? DateTime.tryParse(json['last_login'] as String)
            : null,
      );

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
