import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/screens/saisie_screen.dart';

void main() {
  test('normName : casse, accents et espaces ignorés', () {
    expect(normName('  Relevé  Planche '), 'releve planche');
    expect(normName('POMPE'), normName('pompe'));
    expect(normName('Abdos ( dragon press )'), 'abdos ( dragon press )');
  });

  test('normName : deux exercices proches restent distincts', () {
    expect(normName('Pompe'), isNot(normName('Pompes')));
    expect(normName('Planche'), isNot(normName('Push planche')));
  });
}
