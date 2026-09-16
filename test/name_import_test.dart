import 'package:flutter_test/flutter_test.dart';
import 'package:rdr_app/data/models/player.dart';
import 'package:rdr_app/data/services/name_import.dart';

Player _player(String id, String name) =>
    Player(id: id, name: name, stars: 3, createdAt: DateTime(2026, 1, 1));

void main() {
  group('NameImporter.parse', () {
    test('tira numeração e marcadores dos formatos comuns de lista', () {
      const text = '''
1. Augusto
2 - Rafael
3) Wendell
- Franklin
• Pietro
Rona
''';
      expect(NameImporter.parse(text), [
        'Augusto',
        'Rafael',
        'Wendell',
        'Franklin',
        'Pietro',
        'Rona',
      ]);
    });

    test('ignora linhas vazias e linhas sem letra', () {
      const text = '1. Augusto\n\n   \n---\n2. Rafael';
      expect(NameImporter.parse(text), ['Augusto', 'Rafael']);
    });
  });

  group('NameImporter.matchAll', () {
    final players = [
      _player('1', 'Augusto'),
      _player('2', 'Rafael'),
      _player('3', 'Caio Davi'),
      _player('4', 'Vinícius'),
      _player('5', 'Lázaro'),
    ];

    test('casa nome exato ignorando caixa e acento', () {
      final result = NameImporter.matchAll(
        ['AUGUSTO', 'vinicius', 'lazaro'],
        players,
      );

      expect(result[0].match?.id, '1');
      expect(result[1].match?.id, '4');
      expect(result[2].match?.id, '5');
    });

    test('casa parcial quando o candidato é único', () {
      final result = NameImporter.matchAll(['Caio'], players);
      expect(result[0].match?.id, '3');
    });

    test('nome desconhecido fica em branco', () {
      final result = NameImporter.matchAll(['Zezinho da Silva'], players);
      expect(result[0].match, isNull);
      expect(result[0].isMatched, isFalse);
      expect(result[0].rawName, 'Zezinho da Silva');
    });

    test('não usa o mesmo jogador em dois nomes', () {
      final result = NameImporter.matchAll(['Rafael', 'Rafael'], players);
      expect(result[0].match?.id, '2');
      expect(result[1].match, isNull);
    });

    test('nome ambíguo não é adivinhado', () {
      final ambiguous = [
        _player('1', 'Carlos Alberto'),
        _player('2', 'Carlos Eduardo'),
      ];
      final result = NameImporter.matchAll(['Carlos'], ambiguous);
      expect(result[0].match, isNull);
    });
  });

  group('NameImporter.normalize', () {
    test('remove acento, pontuação e espaço extra', () {
      expect(NameImporter.normalize('  José   da Silva!  '), 'jose da silva');
      expect(NameImporter.normalize('Vinícius'), 'vinicius');
      expect(NameImporter.normalize('João'), 'joao');
    });
  });
}
