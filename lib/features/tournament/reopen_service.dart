import '../../data/models/match_model.dart';
import '../../data/models/tournament.dart';
import 'tie_service.dart';

/// Regras para reabrir uma partida já encerrada e corrigir o resultado
/// (placar fechado sem querer, gol creditado ao jogador errado...).
///
/// O resultado de uma partida decide quem joga a fase seguinte. Por isso:
/// - se alguma partida que depende dela já começou, não dá para reabrir;
/// - se a fase seguinte só tinha os times definidos, eles são apagados e
///   voltam a ser preenchidos quando a partida for encerrada de novo.
class ReopenService {
  /// Partidas cujos times dependem do resultado de [match].
  static List<MatchModel> dependents(Tournament t, MatchModel match) {
    switch (match.phase) {
      case MatchPhase.group:
        return t.matches.where((m) => m.phase != MatchPhase.group).toList();
      case MatchPhase.playoff:
        // O vencedor do play-in vai para a semifinal 1; a outra semi sai
        // direto da classificação.
        final semis = TieService.tiesOfPhase(t, MatchPhase.semifinal);
        return [
          if (semis.isNotEmpty) ...semis.first,
          ...t.finalMatches,
        ];
      case MatchPhase.semifinal:
        return t.finalMatches;
      case MatchPhase.finalMatch:
        return const [];
    }
  }

  /// Motivo para não poder reabrir, ou null se pode.
  static String? blockedReason(Tournament t, MatchModel match) {
    if (match.status != MatchStatus.finished) {
      return 'A partida ainda não foi encerrada.';
    }
    final started =
        dependents(t, match).where((m) => m.status != MatchStatus.pending);
    if (started.isNotEmpty) {
      return 'A fase seguinte já começou. Corrija a partida mais recente '
          'primeiro, ou ajuste pelo painel web.';
    }
    return null;
  }

  /// True quando reabrir vai apagar times já definidos na fase seguinte.
  static bool clearsNextPhase(Tournament t, MatchModel match) =>
      dependents(t, match).any((m) => m.homeTeamId.isNotEmpty);

  /// Devolve o torneio com [match] reaberto. Não valida: chame
  /// [blockedReason] antes.
  ///
  /// Os pênaltis do confronto são descartados, porque o agregado pode mudar;
  /// são pedidos de novo ao encerrar. Se era a final de um torneio já
  /// encerrado, o torneio volta a ficar ativo e sem campeão.
  static Tournament reopen(Tournament t, MatchModel match) {
    final tieIds = t.legsOf(match).map((m) => m.id).toSet();
    final dependentIds = dependents(t, match).map((m) => m.id).toSet();

    final matches = t.matches.map((m) {
      if (m.id == match.id) {
        return m.copyWith(
            status: MatchStatus.inProgress, penaltyWinnerId: null);
      }
      if (tieIds.contains(m.id)) return m.copyWith(penaltyWinnerId: null);
      if (dependentIds.contains(m.id)) {
        // Só chega aqui partida pendente, sem placar: basta tirar os times.
        return m.copyWith(
            homeTeamId: '', awayTeamId: '', penaltyWinnerId: null);
      }
      return m;
    }).toList();

    return t.copyWith(
      matches: matches,
      status: TournamentStatus.active,
      championTeamId: t.status == TournamentStatus.finished
          ? null
          : t.championTeamId,
    );
  }
}
