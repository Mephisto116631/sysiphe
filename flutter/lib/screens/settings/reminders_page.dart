import 'package:flutter/material.dart';
import '../../widgets/reminders_card.dart';

/// Réglages → Rappels de séance.
class RemindersPage extends StatelessWidget {
  final String userId;
  const RemindersPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rappels')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [RemindersCard(userId: userId)],
        ),
      );
}
