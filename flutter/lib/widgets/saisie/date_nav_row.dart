import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';

/// Date de la saisie : ◀ jour précédent · sélecteur · retour à aujourd'hui
/// (pas de jour suivant : pas de saisie dans le futur).
class DateNavRow extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final VoidCallback onPrevious;
  final VoidCallback onPick;
  final VoidCallback onToday;

  const DateNavRow({
    super.key,
    required this.date,
    required this.isToday,
    required this.onPrevious,
    required this.onPick,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Jour précédent',
          onPressed: onPrevious,
        ),
        Expanded(
          child: GestureDetector(
            onTap: onPick,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.borderColor),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 18, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isToday
                          ? "Aujourd'hui"
                          : DateFormat('EEE d MMM', 'fr_FR').format(date),
                      style: const TextStyle(fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isToday)
          const IconButton(icon: Icon(Icons.chevron_right), onPressed: null)
        else
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: "Revenir à aujourd'hui",
            onPressed: onToday,
          ),
      ],
    );
  }
}
