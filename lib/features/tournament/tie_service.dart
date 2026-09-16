import '../../data/models/match_model.dart';
import '../../data/models/tournament.dart';

/// Regras de confronto — vale tanto para jogo único quanto para ida e volta.
///
/// Um "confronto" (tie) é o par de times que se enfrenta numa fase. Em jogo
/// único ele tem uma partida; em ida e volta, duas partidas com o mesmo
/// [MatchModel.tieId], e quem passa é decidido pelo placar agregado.
class TieService {
  /// Os confrontos de uma fase, na ordem em que serão disputados.
  /// Cada item é a lista de partidas daquele confronto (1 ou 2 jogos).
  static List<List<MatchModel>> tiesOfPhase(Tournament t, MatchPhase phase) {
    final matches = t.matches.where((m) => m.phase == phase).toList()
      ..sort((a, b) => a.scheduledOrder.compareTo(b.scheduledOrder));

    final groups = <String, List<MatchModel>>{};
    for (final m in matches) {
      groups.putIfAbsent(m.tieId ?? m.id, () => []).add(m);
    }
    final ties = groups.values.toList();
    for (final legs in ties) {
      legs.sort((a, b) => a.leg.compareTo(b.leg));
    }
    ties.sort((a, b) => a.first.scheduledOrder.compareTo(b.first.scheduledOrder));
    return ties;
  }

  /// Os dois times do confronto, lidos do jogo de ida.
  /// Null enquanto os classificados ainda não foram definidos.
  static (String, String)? teamsOf(List<MatchModel> legs) {
    final first = legs.first;
    if (first.homeTeamId.isEmpty || first.awayTeamId.isEmpty) return null;
    return (first.homeTeamId, first.awayTeamId);
  }

  /// Define os times de um confronto. No jogo de volta o mando é invertido.
  static List<MatchModel> assignTeams(
    List<MatchModel> legs,
    String homeId,
    String awayId,
  ) {
    return legs.map((m) {
      final swap = m.leg == 2;
      return m.copyWith(
        homeTeamId: swap ? awayId : homeId,
        awayTeamId: swap ? homeId : awayId,
      );
    }).toList();
  }

  /// Gols de cada time somando todas as partidas já encerradas do confronto.
  /// [overrideMatchId] com [overrideHome]/[overrideAway] permite considerar um
  /// placar que ainda está na tela e não foi gravado.
  static Map<String, int> aggregate(
    List<MatchModel> legs, {
    String? overrideMatchId,
    int? overrideHome,
    int? overrideAway,
  }) {
    final totals = <String, int>{};
    for (final m in legs) {
      final isOverride = m.id == overrideMatchId;
      if (!isOverride && m.status != MatchStatus.finished) continue;

      final home = isOverride ? overrideHome : m.homeScore;
      final away = isOverride ? overrideAway : m.awayScore;
      if (home == null || away == null) continue;

      totals[m.homeTeamId] = (totals[m.homeTeamId] ?? 0) + home;
      totals[m.awayTeamId] = (totals[m.awayTeamId] ?? 0) + away;
    }
    return totals;
  }

  static bool isComplete(List<MatchModel> legs) =>
      legs.every((m) => m.status == MatchStatus.finished);

  /// A partida que decide o confronto — a volta, no caso de ida e volta.
  /// Serve para exibição; para saber quem decide de fato, use
  /// [isLastToFinish], porque nada obriga a jogar na ordem.
  static MatchModel decisiveLeg(List<MatchModel> legs) => legs.last;

  /// True quando todas as outras partidas do confronto já acabaram — ou seja,
  /// encerrar [match] fecha o confronto.
  ///
  /// Não dá para usar a posição (`legs.last`): os dois cards ficam clicáveis
  /// assim que os times são definidos, então a volta pode ser jogada antes da
  /// ida. Nesse caso quem decide é a ida.
  static bool isLastToFinish(List<MatchModel> legs, MatchModel match) => legs
      .where((m) => m.id != match.id)
      .every((m) => m.status == MatchStatus.finished);

  /// Pênaltis registrados em qualquer partida do confronto. Fica em qualquer
  /// uma porque a decisão é gravada na partida encerrada por último.
  static String? penaltyWinnerOf(List<MatchModel> legs) {
    for (final m in legs.reversed) {
      if (m.penaltyWinnerId != null) return m.penaltyWinnerId;
    }
    return null;
  }

  /// Confronto terminado, mas empatado no agregado e sem pênaltis gravados.
  /// Estado travado: a fase seguinte não avança até alguém decidir.
  static bool needsPenaltyDecision(List<MatchModel> legs) =>
      isComplete(legs) && winnerId(legs) == null && teamsOf(legs) != null;

  /// Vencedor do confronto, ou null se ainda não foi decidido.
  /// Pênaltis registrados na partida decisiva têm prioridade sobre o agregado.
  static String? winnerId(
    List<MatchModel> legs, {
    String? overrideMatchId,
    int? overrideHome,
    int? overrideAway,
  }) {
    final penalty = penaltyWinnerOf(legs);
    if (penalty != null) return penalty;

    final allFinished = legs.every(
      (m) => m.status == MatchStatus.finished || m.id == overrideMatchId,
    );
    if (!allFinished) return null;

    final teams = teamsOf(legs);
    if (teams == null) return null;

    final totals = aggregate(
      legs,
      overrideMatchId: overrideMatchId,
      overrideHome: overrideHome,
      overrideAway: overrideAway,
    );
    final a = totals[teams.$1] ?? 0;
    final b = totals[teams.$2] ?? 0;
    if (a > b) return teams.$1;
    if (b > a) return teams.$2;
    return null; // agregado empatado — vai para os pênaltis
  }

  /// True quando o confronto terminaria empatado no agregado e precisa de
  /// pênaltis. Só faz sentido na partida decisiva.
  static bool needsPenalties(
    List<MatchModel> legs, {
    required String overrideMatchId,
    required int overrideHome,
    required int overrideAway,
  }) {
    final teams = teamsOf(legs);
    if (teams == null) return false;

    final othersFinished = legs
        .where((m) => m.id != overrideMatchId)
        .every((m) => m.status == MatchStatus.finished);
    if (!othersFinished) return false;

    final totals = aggregate(
      legs,
      overrideMatchId: overrideMatchId,
      overrideHome: overrideHome,
      overrideAway: overrideAway,
    );
    return (totals[teams.$1] ?? 0) == (totals[teams.$2] ?? 0);
  }
}
