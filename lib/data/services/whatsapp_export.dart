import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/match_model.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../models/tournament.dart';
import '../../features/tournament/standings_service.dart';
import '../../features/tournament/tie_service.dart';

/// Monta as mensagens de texto para colar/compartilhar no grupo do WhatsApp.
///
/// O WhatsApp formata com `*negrito*` e `_itálico_`; o resto é texto puro,
/// então a mensagem continua legível em qualquer lugar. Tom sóbrio, sem
/// emojis: a cor do colete vai por extenso, e o link do site fecha a
/// mensagem.
class WhatsAppExport {
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  /// Site público com estatísticas e histórico.
  static const siteUrl = 'https://racha-dos-ruins.web.app';

  static String get _footer => 'Estatísticas e histórico: $siteUrl';

  // ── Times sorteados ────────────────────────────────────────────────────────

  static String teams({
    required List<Team> teams,
    required List<Player> allPlayers,
    DateTime? date,
    bool twoLegged = false,
  }) {
    final buffer = StringBuffer()
      ..writeln('*Racha dos Ruins — Times*')
      ..writeln(_dateFormat.format(date ?? DateTime.now()));
    if (twoLegged) buffer.writeln('Mata-mata em ida e volta');
    buffer.writeln();

    final byId = {for (final p in allPlayers) p.id: p};

    for (final team in teams) {
      buffer.writeln(
          '*${team.name}* (${_colorName(team.colorValue)}) — '
          'média ${team.averageStars.toStringAsFixed(1)}');
      var i = 1;
      for (final id in team.playerIds) {
        final name = byId[id]?.name ?? 'Jogador removido';
        buffer.writeln('${i++}. $name');
      }
      buffer.writeln();
    }

    final total = teams.fold<int>(0, (a, t) => a + t.playerIds.length);
    buffer
      ..writeln('$total jogadores em ${teams.length} times')
      ..writeln()
      ..write(_footer);
    return buffer.toString();
  }

  // ── Tabela do campeonato ───────────────────────────────────────────────────

  static String standings(Tournament tournament, List<Player> allPlayers) {
    final buffer = StringBuffer()
      ..writeln('*Racha dos Ruins — ${_dateFormat.format(tournament.createdAt)}*');
    if (tournament.twoLegged) buffer.writeln('Mata-mata em ida e volta');
    buffer.writeln();

    final table = StandingsService.compute(tournament);
    if (tournament.groupMatches.isNotEmpty && table.isNotEmpty) {
      buffer.writeln('*Classificação*');
      var pos = 1;
      for (final s in table) {
        buffer.writeln(
          '$pos. ${s.team.name} — '
          '*${s.points} ${s.points == 1 ? 'pt' : 'pts'}* '
          '(${s.played}J ${s.wins}V ${s.draws}E ${s.losses}D, '
          'SG ${s.goalDiff > 0 ? '+' : ''}${s.goalDiff})',
        );
        pos++;
      }
      buffer.writeln();
    }

    final sections = <MatchPhase, String>{
      MatchPhase.group: 'Fase de grupos',
      MatchPhase.playoff: 'Play-in',
      MatchPhase.semifinal: 'Semifinais',
      MatchPhase.finalMatch: 'Final',
    };

    for (final entry in sections.entries) {
      final ties = TieService.tiesOfPhase(tournament, entry.key);
      if (ties.isEmpty) continue;

      buffer.writeln('*${entry.value}*');
      for (final legs in ties) {
        buffer.writeln(_tieLine(tournament, legs));
      }
      buffer.writeln();
    }

    final scorers = _topScorers(tournament, allPlayers);
    if (scorers.isNotEmpty) {
      buffer.writeln('*Artilharia*');
      for (final line in scorers) {
        buffer.writeln(line);
      }
      buffer.writeln();
    }

    final champion = tournament.champion;
    if (champion != null) {
      buffer
        ..writeln('*Campeão: ${champion.name}*')
        ..writeln();
    }

    buffer.write(_footer);
    return buffer.toString().trimRight();
  }

  /// Uma linha por confronto. Em ida e volta mostra os dois jogos e o agregado.
  static String _tieLine(Tournament tournament, List<MatchModel> legs) {
    String teamName(String id) =>
        tournament.teams.where((t) => t.id == id).firstOrNull?.name ??
        'A definir';

    final teams = TieService.teamsOf(legs);
    if (teams == null) return '• A definir';

    final nameA = teamName(teams.$1);
    final nameB = teamName(teams.$2);

    if (legs.length == 1) {
      final m = legs.first;
      if (m.status != MatchStatus.finished) return '• $nameA × $nameB — a jogar';
      final penalty = m.penaltyWinnerId != null
          ? ' (pênaltis: ${teamName(m.penaltyWinnerId!)})'
          : '';
      return '• $nameA *${m.homeScore}* × *${m.awayScore}* $nameB$penalty';
    }

    final buffer = StringBuffer('• $nameA × $nameB');
    for (final m in legs) {
      final label = m.leg == 1 ? 'ida' : 'volta';
      if (m.status != MatchStatus.finished) {
        buffer.write('\n   $label: a jogar');
        continue;
      }
      buffer.write(
          '\n   $label: ${teamName(m.homeTeamId)} ${m.homeScore} × '
          '${m.awayScore} ${teamName(m.awayTeamId)}');
    }

    if (TieService.isComplete(legs)) {
      final totals = TieService.aggregate(legs);
      buffer.write('\n   agregado: *${totals[teams.$1] ?? 0}* × '
          '*${totals[teams.$2] ?? 0}*');
      final penalty = TieService.penaltyWinnerOf(legs);
      if (penalty != null) {
        buffer.write(' (pênaltis: ${teamName(penalty)})');
      }
    }
    return buffer.toString();
  }

  static List<String> _topScorers(Tournament tournament, List<Player> players) {
    final byId = {for (final p in players) p.id: p};
    final counts = <String, int>{};
    for (final m in tournament.matches) {
      if (m.status != MatchStatus.finished) continue;
      for (final g in m.scorers) {
        counts[g.playerId] = (counts[g.playerId] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return [];

    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byGoals = b.value.compareTo(a.value);
        if (byGoals != 0) return byGoals;
        final nameA = byId[a.key]?.name ?? '';
        final nameB = byId[b.key]?.name ?? '';
        return nameA.compareTo(nameB);
      });

    var pos = 0;
    return ranked.take(10).map((e) {
      final name = byId[e.key]?.name ?? 'Jogador removido';
      return '${++pos}. $name — ${e.value} ${e.value == 1 ? 'gol' : 'gols'}';
    }).toList();
  }

  /// Nome da cor mais próxima do colete do time, por extenso.
  static String _colorName(int colorValue) {
    final hsv = HSVColor.fromColor(Color(colorValue));

    if (hsv.value < 0.18) return 'preto';
    if (hsv.saturation < 0.15) {
      return hsv.value > 0.75
          ? 'branco'
          : hsv.value < 0.35
              ? 'preto'
              : 'cinza';
    }

    final hue = hsv.hue;
    if (hue < 15 || hue >= 345) return 'vermelho';
    if (hue < 40) return hsv.value < 0.55 ? 'marrom' : 'laranja';
    if (hue < 65) return 'amarelo';
    if (hue < 170) return 'verde';
    if (hue < 260) return 'azul';
    if (hue < 290) return 'roxo';
    return 'rosa';
  }
}

/// Copiar e compartilhar, usados pelos botões de exportação.
class ShareActions {
  static Future<void> copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mensagem copiada')),
    );
  }

  static Future<void> share(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
