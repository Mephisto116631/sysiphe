import 'package:flutter/material.dart';
import '../../theme.dart';
import 'form_bits.dart';

/// Options de la planche (dépliables) : variante, forme, élastique, tension.
/// Sans élastique, la tension est désactivée.
class PlancheOptions extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final String variante, forme, elastique, tension;
  final List<String> variantes, formes, elastiques, tensions;
  final ValueChanged<String> onVariante, onForme, onElastique, onTension;

  const PlancheOptions({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.variante,
    required this.forme,
    required this.elastique,
    required this.tension,
    required this.variantes,
    required this.formes,
    required this.elastiques,
    required this.tensions,
    required this.onVariante,
    required this.onForme,
    required this.onElastique,
    required this.onTension,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Row(
            children: [
              Text(
                'Options planche',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.primaryBlue, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: AppTheme.primaryBlue,
                size: 20,
              ),
            ],
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownField<String>(
                  label: 'Variante',
                  value: variante,
                  items: variantes,
                  onChanged: (v) => onVariante(v ?? 'Full'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownField<String>(
                  label: 'Forme',
                  value: forme,
                  items: formes,
                  onChanged: (v) => onForme(v ?? 'Normal'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownField<String>(
                  label: 'Élastique',
                  value: elastique,
                  items: elastiques,
                  onChanged: (v) => onElastique(v ?? 'Aucun'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownField<String>(
                  label: 'Tension',
                  value: tension,
                  items: tensions,
                  onChanged: elastique == 'Aucun'
                      ? null
                      : (v) => onTension(v ?? 'N/A'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Exercice assistable : élastique, tension et écartement des mains.
class AssistOptions extends StatelessWidget {
  final String elastique, tension, ecartement;
  final List<String> elastiques, tensions, ecartements;
  final ValueChanged<String> onElastique, onTension, onEcartement;

  const AssistOptions({
    super.key,
    required this.elastique,
    required this.tension,
    required this.ecartement,
    required this.elastiques,
    required this.tensions,
    required this.ecartements,
    required this.onElastique,
    required this.onTension,
    required this.onEcartement,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownField<String>(
                label: 'Élastique',
                value: elastique,
                items: elastiques,
                onChanged: (v) => onElastique(v ?? 'Aucun'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownField<String>(
                label: 'Tension',
                value: tension,
                items: tensions,
                onChanged: (v) => onTension(v ?? 'N/A'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DropdownField<String>(
          label: 'Écartement des mains',
          value: ecartement,
          items: ecartements,
          onChanged: (v) => onEcartement(v ?? 'Standard'),
        ),
      ],
    );
  }
}
