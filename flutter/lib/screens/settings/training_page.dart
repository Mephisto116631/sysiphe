import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/data_events.dart';
import '../../services/settings_transfer.dart';
import '../../services/supabase_service.dart';
import '../../theme.dart';
import 'common.dart';

/// Réglages → Entraînement : poids corporel et champ « Lest (kg) ».
class TrainingPage extends StatefulWidget {
  final String userId;
  const TrainingPage({super.key, required this.userId});

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  final _weightCtrl = TextEditingController();
  bool _saving = false;
  bool _enableCharges = true; // user_settings.enable_charges
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await SupabaseService.instance.getSettings(widget.userId);
    if (!mounted) return;
    setState(() {
      _weightCtrl.text = ((s['weight'] as num?)?.toString() ?? '97');
      _enableCharges = s['enable_charges'] as bool? ?? true;
      _loading = false;
    });
  }

  /// Afficher ou masquer le champ « Lest (kg) » dans la saisie (réglage
  /// enable_charges, partagé avec le web). Les lests déjà enregistrés
  /// restent en base et comptent toujours dans les stats.
  Future<void> _setEnableCharges(bool v) async {
    setState(() => _enableCharges = v);
    try {
      await SupabaseService.instance
          .saveSettings(widget.userId, {'enable_charges': v});
      notifyDataChanged(); // la Saisie relit le réglage
    } catch (e) {
      if (!mounted) return;
      setState(() => _enableCharges = !v);
      showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _saveWeight() async {
    final weight = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    if (weight == null || weight <= 0) {
      showSnack(context, 'Poids invalide', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final svc = SupabaseService.instance;
      await svc.saveSettings(widget.userId, {'weight': weight});
      // Le poids entre dans l'effort de la planche : on recalcule les
      // séries avec les coefficients actuels du modèle.
      await recalcPlancheEfforts(widget.userId);
      notifyDataChanged();
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, 'Poids enregistré');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entraînement')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Poids corporel (kg)',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                            'Utilisé pour le calcul d\'effort (planche, '
                            'exercices assistables).',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _weightCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d.,]')),
                                ],
                                decoration: const InputDecoration(
                                    labelText: 'Poids', suffixText: 'kg'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _saving ? null : _saveWeight,
                              style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(80, 50)),
                              child: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Text('OK'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.fitness_center,
                        color: AppTheme.primaryBlue),
                    title: const Text('Champ « Lest (kg) »'),
                    subtitle: const Text(
                        'Désactivé : masqué dans la saisie, les lests déjà '
                        'enregistrés sont conservés'),
                    value: _enableCharges,
                    onChanged: _setEnableCharges,
                  ),
                ),
              ],
            ),
    );
  }
}
