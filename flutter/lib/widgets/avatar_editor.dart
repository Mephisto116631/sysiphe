import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/avatar.dart';
import 'avatar_view.dart';

/// Photo choisie (galerie ou appareil photo), réduite à 256 px et en JPEG
/// compressé : quelques Ko en base64. null si annulé.
typedef PhotoPicker = Future<String?> Function({required bool camera});

Future<String?> pickAvatarPhoto({required bool camera}) async {
  final f = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 256,
    maxHeight: 256,
    imageQuality: 75,
    preferredCameraDevice: CameraDevice.front,
  );
  if (f == null) return null;
  return base64Encode(await f.readAsBytes());
}

/// Choix de l'avatar : lettres (couleur), image prédéfinie, photo.
/// Renvoie le nouvel avatar, ou null si annulé.
Future<ProfileAvatar?> editAvatar(BuildContext context,
        {required String initials,
        required ProfileAvatar current,
        PhotoPicker? picker}) =>
    showModalBottomSheet<ProfileAvatar>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => AvatarEditor(
          initials: initials, current: current, picker: picker),
    );

class AvatarEditor extends StatefulWidget {
  final String initials;
  final ProfileAvatar current;
  final PhotoPicker? picker;

  const AvatarEditor(
      {super.key, required this.initials, required this.current, this.picker});

  @override
  State<AvatarEditor> createState() => _AvatarEditorState();
}

class _AvatarEditorState extends State<AvatarEditor> {
  late ProfileAvatar _a = widget.current;
  String? _error;

  int get _color => _a.kind == AvatarKind.photo ? 0 : _a.color;

  Future<void> _photo(bool camera) async {
    try {
      final data = await (widget.picker ?? pickAvatarPhoto)(camera: camera);
      if (data == null || !mounted) return;
      setState(() {
        _a = ProfileAvatar.photo(data);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Photo indisponible ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: AvatarView(
                  key: const ValueKey('avatar-preview'),
                  initials: widget.initials,
                  avatar: _a,
                  radius: 40),
            ),
            const SizedBox(height: 16),
            Text('Couleur', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < kAvatarColors.length; i++)
                  InkWell(
                    key: ValueKey('avatar-color-$i'),
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _a = _a.kind == AvatarKind.image
                        ? ProfileAvatar.image(_a.emoji!, i)
                        : ProfileAvatar.lettres(i)),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: kAvatarColors[i],
                      child: i == _color && _a.kind != AvatarKind.photo
                          ? const Icon(Icons.check,
                              size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ChoiceChip(
                key: const ValueKey('avatar-letters'),
                label: Text('Lettres « ${widget.initials} »'),
                selected: _a.kind == AvatarKind.lettres,
                onSelected: (_) =>
                    setState(() => _a = ProfileAvatar.lettres(_color)),
              ),
            ),
            const SizedBox(height: 12),
            Text('Images', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in kAvatarEmojis)
                  InkWell(
                    key: ValueKey('avatar-emoji-$e'),
                    customBorder: const CircleBorder(),
                    onTap: () =>
                        setState(() => _a = ProfileAvatar.image(e, _color)),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: _a.kind == AvatarKind.image &&
                              _a.emoji == e
                          ? kAvatarColors[_color]
                          : theme.colorScheme.surfaceContainerHighest,
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Photo', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                key: const ValueKey('avatar-gallery'),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Galerie'),
                onPressed: () => _photo(false),
              ),
              OutlinedButton.icon(
                key: const ValueKey('avatar-camera'),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Appareil photo'),
                onPressed: () => _photo(true),
              ),
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('avatar-save'),
                onPressed: _a == widget.current
                    ? null
                    : () => Navigator.pop(context, _a),
                child: const Text('Enregistrer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
