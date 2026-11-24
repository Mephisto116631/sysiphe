import 'package:flutter/material.dart';
import '../models/avatar.dart';

/// Rond du profil : lettres sur fond coloré, image prédéfinie ou photo.
class AvatarView extends StatelessWidget {
  final String initials;
  final ProfileAvatar avatar;
  final double radius;

  const AvatarView(
      {super.key,
      required this.initials,
      this.avatar = ProfileAvatar.defaut,
      this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final a = avatar;
    if (a.kind == AvatarKind.photo) {
      final bytes = avatarBytes(a.photo!);
      if (bytes != null) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: a.background,
          backgroundImage: MemoryImage(bytes),
        );
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: a.background,
      child: a.kind == AvatarKind.image
          ? Text(a.emoji!, style: TextStyle(fontSize: radius * 1.05))
          : Text(initials,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.7)),
    );
  }
}
