import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Avatar d'un profil : lettres colorées (défaut), image prédéfinie (emoji)
/// ou photo (petit JPEG en base64). Stocké dans profiles.avatar.
enum AvatarKind { lettres, image, photo }

/// Couleurs proposées (la première est le bleu de l'app, celle d'avant).
const kAvatarColors = <Color>[
  Color(0xFF1976D2), // bleu
  Color(0xFF00897B), // vert d'eau
  Color(0xFF43A047), // vert
  Color(0xFFF4511E), // orange
  Color(0xFFE53935), // rouge
  Color(0xFF8E24AA), // violet
  Color(0xFF6D4C41), // brun
  Color(0xFF546E7A), // gris bleu
];

/// Images prédéfinies.
const kAvatarEmojis = [
  '🐶', '🐱', '🦊', '🐻', '🐼', '🐯', '🦁', '🐸',
  '🐵', '🦄', '🐺', '🦅', '🐢', '🐙', '🦈', '🐝',
  '💪', '🏋️', '🤸', '🧗', '🏃', '🚴', '🥊', '🧘',
  '🔥', '⚡', '⭐', '🌙', '🏔️', '🌊', '🍀', '🎯',
];

class ProfileAvatar {
  final AvatarKind kind;
  final int color; // index dans kAvatarColors
  final String? emoji;
  final String? photo; // JPEG en base64

  const ProfileAvatar.lettres([this.color = 0])
      : kind = AvatarKind.lettres,
        emoji = null,
        photo = null;
  const ProfileAvatar.image(String this.emoji, [this.color = 0])
      : kind = AvatarKind.image,
        photo = null;
  const ProfileAvatar.photo(String this.photo)
      : kind = AvatarKind.photo,
        color = 0,
        emoji = null;

  static const defaut = ProfileAvatar.lettres();

  Color get background =>
      kAvatarColors[color.clamp(0, kAvatarColors.length - 1)];

  Map<String, dynamic> toJson() => switch (kind) {
        AvatarKind.lettres => {'type': 'lettres', 'couleur': color},
        AvatarKind.image => {'type': 'image', 'emoji': emoji, 'couleur': color},
        AvatarKind.photo => {'type': 'photo', 'data': photo},
      };

  /// Lecture tolérante : tout ce qui n'est pas reconnu → lettres bleues.
  static ProfileAvatar fromJson(Object? j) {
    if (j is String) {
      try {
        j = jsonDecode(j);
      } catch (_) {
        return defaut;
      }
    }
    if (j is! Map) return defaut;
    final c = (j['couleur'] as num?)?.toInt() ?? 0;
    switch (j['type']) {
      case 'image':
        final e = j['emoji'];
        return e is String && e.isNotEmpty
            ? ProfileAvatar.image(e, c)
            : ProfileAvatar.lettres(c);
      case 'photo':
        final d = j['data'];
        return d is String && d.isNotEmpty ? ProfileAvatar.photo(d) : defaut;
      default:
        return ProfileAvatar.lettres(c);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileAvatar &&
      other.kind == kind &&
      other.color == color &&
      other.emoji == emoji &&
      other.photo == photo;

  @override
  int get hashCode => Object.hash(kind, color, emoji, photo);
}

/// Photo décodée une seule fois (la liste des profils se reconstruit souvent).
final _decoded = <int, Uint8List>{};
Uint8List? avatarBytes(String base64Data) {
  final key = base64Data.hashCode ^ base64Data.length;
  final hit = _decoded[key];
  if (hit != null) return hit;
  try {
    if (_decoded.length > 32) _decoded.clear();
    return _decoded[key] = base64Decode(base64Data);
  } catch (_) {
    return null;
  }
}
