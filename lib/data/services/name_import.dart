import '../models/player.dart';

/// Um nome da lista colada e o jogador do banco correspondente (se houver).
class ImportedName {
  final String rawName;
  final Player? match;

  const ImportedName({required this.rawName, this.match});

  bool get isMatched => match != null;

  ImportedName withMatch(Player? player) =>
      ImportedName(rawName: rawName, match: player);
}

/// Lê uma lista de nomes colada (tipicamente a lista de presença do grupo)
/// e tenta casar cada nome com um jogador já cadastrado.
class NameImporter {
  /// Quebra o texto em nomes, ignorando numeração, marcadores e linhas vazias.
  ///
  /// Aceita os formatos comuns de lista de WhatsApp:
  /// `1. Fulano`, `1 - Fulano`, `1) Fulano`, `- Fulano`, `• Fulano`.
  static List<String> parse(String text) {
    final names = <String>[];
    for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;

      // Numeração ou marcador no começo da linha.
      line = line.replaceFirst(RegExp(r'^\d+\s*[\).\-–—:]*\s*'), '');
      line = line.replaceFirst(RegExp(r'^[-–—•*·]+\s*'), '');
      line = line.trim();

      // Sobrou só pontuação/emoji ou nada.
      if (line.isEmpty) continue;
      if (!RegExp(r'[a-zA-ZÀ-ÿ]').hasMatch(line)) continue;

      names.add(line);
    }
    return names;
  }

  /// Casa cada nome com um jogador do banco. Um jogador nunca é usado duas
  /// vezes; nomes sem correspondência voltam com [ImportedName.match] nulo
  /// para você escolher na mão.
  static List<ImportedName> matchAll(
    List<String> names,
    List<Player> players,
  ) {
    final used = <String>{};
    final result = <ImportedName>[];

    // Passo 1: correspondência exata (ignorando acento, caixa e espaços).
    final pending = <int>[];
    for (var i = 0; i < names.length; i++) {
      final key = normalize(names[i]);
      final exact = players
          .where((p) => normalize(p.name) == key && !used.contains(p.id))
          .firstOrNull;
      if (exact != null) {
        used.add(exact.id);
        result.add(ImportedName(rawName: names[i], match: exact));
      } else {
        pending.add(i);
        result.add(ImportedName(rawName: names[i]));
      }
    }

    // Passo 2: correspondência parcial, só quando é candidato único.
    for (final i in pending) {
      final key = normalize(names[i]);
      if (key.isEmpty) continue;

      final candidates = players.where((p) {
        if (used.contains(p.id)) return false;
        final name = normalize(p.name);
        return name.startsWith(key) ||
            key.startsWith(name) ||
            name.contains(key) ||
            key.contains(name);
      }).toList();

      if (candidates.length == 1) {
        used.add(candidates.first.id);
        result[i] = result[i].withMatch(candidates.first);
      }
    }

    return result;
  }

  /// Minúsculas, sem acento, sem pontuação e com espaços colapsados.
  static String normalize(String value) {
    final lower = value.toLowerCase().trim();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_accents[char] ?? char);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static const _accents = {
    'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
}
