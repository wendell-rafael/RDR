import 'package:uuid/uuid.dart';
import '../../data/models/match_model.dart';
import '../../data/models/team.dart';
import 'tie_service.dart';

const _uuid = Uuid();

class BracketGenerator {
  /// Monta a tabela do torneio.
  ///
  /// Com [twoLegged], semifinais e final viram confrontos de ida e volta.
  /// A fase de grupos e o play-in de 5 times seguem em jogo único.
  static List<MatchModel> generate(
    List<Team> teams,
    String tournamentId, {
    bool twoLegged = false,
  }) {
    switch (teams.length) {
      case 2:
        return _twoTeams(teams, tournamentId, twoLegged);
      case 3:
        return _threeTeams(teams, tournamentId, twoLegged);
      case 4:
        return _fourTeams(teams, tournamentId, twoLegged);
      case 5:
        return _fiveTeams(teams, tournamentId, twoLegged);
      default:
        throw ArgumentError('Unsupported team count: ${teams.length}');
    }
  }

  static List<MatchModel> _twoTeams(
      List<Team> teams, String tournamentId, bool twoLegged) {
    final legs = _ties(tournamentId, MatchPhase.finalMatch, 1, 0, twoLegged);
    return TieService.assignTeams(legs, teams[0].id, teams[1].id);
  }

  static List<MatchModel> _threeTeams(
      List<Team> teams, String tournamentId, bool twoLegged) {
    final pairs = [(0, 1), (0, 2), (1, 2)];
    final group = _roundRobin(
      tournamentId,
      MatchPhase.group,
      pairs.map((p) => (teams[p.$1].id, teams[p.$2].id)).toList(),
      0,
    );
    final finals =
        _ties(tournamentId, MatchPhase.finalMatch, 1, group.length, twoLegged);
    return [...group, ...finals];
  }

  static List<MatchModel> _fourTeams(
      List<Team> teams, String tournamentId, bool twoLegged) {
    final pairs = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)];
    final group = _roundRobin(
      tournamentId,
      MatchPhase.group,
      pairs.map((p) => (teams[p.$1].id, teams[p.$2].id)).toList(),
      0,
    );
    int order = group.length;
    final semis =
        _ties(tournamentId, MatchPhase.semifinal, 2, order, twoLegged);
    order += semis.length;
    final finals =
        _ties(tournamentId, MatchPhase.finalMatch, 1, order, twoLegged);
    return [...group, ...semis, ...finals];
  }

  static List<MatchModel> _fiveTeams(
      List<Team> teams, String tournamentId, bool twoLegged) {
    final pairs = [
      (0, 1), (0, 2), (0, 3), (0, 4),
      (1, 2), (1, 3), (1, 4),
      (2, 3), (2, 4),
      (3, 4),
    ];
    final group = _roundRobin(
      tournamentId,
      MatchPhase.group,
      pairs.map((p) => (teams[p.$1].id, teams[p.$2].id)).toList(),
      0,
    );
    int order = group.length;
    // Play-in sempre em jogo único, mesmo com ida e volta ligado.
    final playin = _ties(tournamentId, MatchPhase.playoff, 1, order++, false);
    final semis =
        _ties(tournamentId, MatchPhase.semifinal, 2, order, twoLegged);
    order += semis.length;
    final finals =
        _ties(tournamentId, MatchPhase.finalMatch, 1, order, twoLegged);
    return [...group, ...playin, ...semis, ...finals];
  }

  /// Cria [tieCount] confrontos vazios de uma fase.
  /// Em ida e volta, todos os jogos de ida vêm antes de todos os de volta.
  static List<MatchModel> _ties(
    String tournamentId,
    MatchPhase phase,
    int tieCount,
    int startOrder,
    bool twoLegged,
  ) {
    final tieIds = List.generate(tieCount, (_) => _uuid.v4());
    final result = <MatchModel>[];
    int order = startOrder;

    for (var i = 0; i < tieCount; i++) {
      result.add(_match(tournamentId, phase, order++, '', '',
          tieId: twoLegged ? tieIds[i] : null, leg: 1));
    }
    if (twoLegged) {
      for (var i = 0; i < tieCount; i++) {
        result.add(_match(tournamentId, phase, order++, '', '',
            tieId: tieIds[i], leg: 2));
      }
    }
    return result;
  }

  static List<MatchModel> _roundRobin(
    String tournamentId,
    MatchPhase phase,
    List<(String, String)> pairs,
    int startOrder,
  ) {
    final scheduled = _spreadMatches(pairs);
    return scheduled.asMap().entries.map((e) {
      return _match(tournamentId, phase, startOrder + e.key, e.value.$1, e.value.$2);
    }).toList();
  }

  static List<(String, String)> _spreadMatches(List<(String, String)> pairs) {
    final result = <(String, String)>[];
    final remaining = List<(String, String)>.from(pairs);

    while (remaining.isNotEmpty) {
      final lastTeams =
          result.isNotEmpty ? {result.last.$1, result.last.$2} : <String>{};
      int pick = remaining.indexWhere(
          (p) => !lastTeams.contains(p.$1) && !lastTeams.contains(p.$2));
      if (pick == -1) pick = 0;
      result.add(remaining[pick]);
      remaining.removeAt(pick);
    }
    return result;
  }

  static MatchModel _match(
    String tournamentId,
    MatchPhase phase,
    int order,
    String homeId,
    String awayId, {
    String? tieId,
    int leg = 1,
  }) {
    return MatchModel(
      id: _uuid.v4(),
      tournamentId: tournamentId,
      phase: phase,
      scheduledOrder: order,
      homeTeamId: homeId,
      awayTeamId: awayId,
      scorers: const [],
      status: MatchStatus.pending,
      tieId: tieId,
      leg: leg,
    );
  }
}
