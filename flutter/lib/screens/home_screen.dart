import 'package:flutter/material.dart';
import '../models/profile.dart';
import 'saisie_screen.dart';
import 'stats_screen.dart';
import 'calendar_screen.dart';
import 'records_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Profile profile;

  const HomeScreen({super.key, required this.profile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _idx = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    final uid = widget.profile.id;
    _screens = [
      SaisieScreen(userId: uid),
      StatsScreen(userId: uid),
      CalendarScreen(userId: uid),
      RecordsScreen(userId: uid),
      SettingsScreen(userId: uid, profile: widget.profile),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        onTap: (i) => setState(() => _idx = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.fitness_center), label: 'Saisie'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Stats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month), label: 'Calendrier'),
          BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events), label: 'Records'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Paramètres'),
        ],
      ),
    );
  }
}
