import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';

/// Demande le PIN et le fait vérifier par le serveur, qui rattache cet
/// appareil au profil. Renvoie true si l'accès est accordé.
///
/// Les erreurs (PIN faux, blocage après 5 essais, réseau) s'affichent dans
/// la fenêtre elle-même, pas dans un bandeau caché derrière.
Future<bool> askPinAndClaim(BuildContext context, Profile profile,
    {String? message}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PinDialog(profile: profile, message: message),
  );
  return ok == true;
}

class _PinDialog extends StatefulWidget {
  final Profile profile;
  final String? message;

  const _PinDialog({required this.profile, this.message});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _ctrl = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking || _ctrl.text.trim().isEmpty) return;
    setState(() { _checking = true; _error = null; });
    try {
      final r = await SupabaseService.instance
          .claimProfile(widget.profile.id, pin: _ctrl.text);
      if (!mounted) return;
      if (r == ClaimResult.ok) {
        Navigator.of(context).pop(true);
        return;
      }
      _ctrl.clear();
      setState(() {
        _checking = false;
        _error = r == ClaimResult.locked
            ? 'Trop d\'essais : réessayez dans 15 minutes'
            : 'PIN incorrect';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Connexion impossible, vérifiez le réseau';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('PIN — ${widget.profile.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              hintText: 'Entrez votre PIN',
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: _checking
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('OK'),
        ),
      ],
    );
  }
}
