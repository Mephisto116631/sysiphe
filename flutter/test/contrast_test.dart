import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/theme.dart';

/// Ratio de contraste WCAG entre deux couleurs opaques.
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(int v) {
      final s = v / 255;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }
    return 0.2126 * ch(c.red) + 0.7152 * ch(c.green) + 0.0722 * ch(c.blue);
  }
  final l1 = lum(a), l2 = lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// Couleur effectivement peinte pour le texte [label] (opacité mise à plat
/// sur [bg]).
Color paintedTextColor(WidgetTester t, String label, Color bg) {
  final el = t.element(find.text(label));
  final style =
      DefaultTextStyle.of(el).style.merge(t.widget<Text>(find.text(label)).style);
  // Sans couleur, le moteur de rendu (Skia) peint le texte en BLANC :
  // c'était le bug des puces « Récents » (blanc sur gris clair).
  return Color.alphaBlend(style.color ?? const Color(0xFFFFFFFF), bg);
}

void main() {
  for (final selected in [false, true]) {
    testWidgets('puce ${selected ? "sélectionnée" : "normale"} lisible (≥ 4,5:1)',
        (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: ChoiceChip(
                label: const Text('Abdos'),
                selected: selected,
                onSelected: (_) {}),
          ),
        ),
      ));
      final chip = Theme.of(t.element(find.byType(ChoiceChip))).chipTheme;
      final bg = selected
          ? Color.alphaBlend(chip.selectedColor!, Colors.white)
          : chip.backgroundColor ?? Colors.white;
      final ratio = contrast(paintedTextColor(t, 'Abdos', bg), bg);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'contraste mesuré : ${ratio.toStringAsFixed(2)}:1');
    });
  }
}
