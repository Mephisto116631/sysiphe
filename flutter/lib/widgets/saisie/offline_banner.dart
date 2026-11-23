import 'package:flutter/material.dart';
import '../../services/sync_service.dart';

/// « Hors ligne · 3 séries en attente · Réessayer » : visible tant qu'il reste
/// des séries à envoyer, ou que le réseau manque. Disparaît une fois tout
/// envoyé.
class OfflineBanner extends StatelessWidget {
  final SyncService sync;
  const OfflineBanner({super.key, required this.sync});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([sync.pending, sync.offline]),
      builder: (context, _) {
        final n = sync.pending.value;
        final off = sync.offline.value;
        if (n == 0 && !off) return const SizedBox.shrink();
        final text = [
          if (off) 'Hors ligne',
          if (n > 0) '$n opération${n > 1 ? 's' : ''} en attente d\'envoi',
          if (off && n == 0) 'dernières données connues',
        ].join(' · ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Icon(off ? Icons.cloud_off : Icons.cloud_upload_outlined,
                      size: 18, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(
                            fontSize: 13, color: Colors.orange.shade900)),
                  ),
                  if (n > 0)
                    TextButton(
                      onPressed: sync.flush,
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      child: const Text('Réessayer'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
