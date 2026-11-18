import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/supabase_service.dart';
import '../../theme.dart';
import '../model_screen.dart';
import 'common.dart';

/// Réglages → Admin (profils admin seulement) : calibration planche et
/// export de toute la base.
class AdminPage extends StatelessWidget {
  final String userId;
  const AdminPage({super.key, required this.userId});

  /// Crée un vrai fichier .csv (toutes les séries de tous les profils, rôle
  /// vérifié côté serveur) et ouvre le partage Android.
  Future<void> _exportAll(BuildContext context) async {
    try {
      final (csv, n) = await SupabaseService.instance.exportAllPerfsCsv();
      final d = DateTime.now();
      final name = 'sysiphe-export-${d.year}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}.csv';
      final file = File('${Directory.systemTemp.path}/$name');
      // BOM UTF-8 : Excel affiche correctement les accents.
      await file.writeAsString('﻿$csv', flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: name)],
        subject: 'Export Sysiphe ($n séries)',
      );
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Export impossible : $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                NavTile(
                  icon: Icons.tune,
                  title: 'Calibration planche',
                  subtitle: 'Coefficients, grille des efforts, recalcul',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ModelScreen(userId: userId))),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined,
                      color: AppTheme.primaryBlue),
                  title: const Text('Exporter la base'),
                  subtitle: const Text(
                      'Toutes les séries de tous les profils, en CSV'),
                  onTap: () => _exportAll(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
