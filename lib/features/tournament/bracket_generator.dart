import 'package:uuid/uuid.dart';
import '../../data/models/match_model.dart';
import '../../data/models/team.dart';

const _uuid = Uuid();

class BracketGenerator {
  static List<MatchModel> generate(
    List<Team> teams,
    String tournamentId,
  ) {
    switch (teams.length) {
      case 2:
        return _twoTeams(teams, tournamentId);
      case 3:
        return _threeTeams(teams, tournamentId);
      case 4:
        return _fourTeams(teams, tournamentId);
      case 5:
        return _fiveTeams(teams, tournamentId);
      default:
        throw ArgumentError('Unsupported team count: ${teams.length}');
    }
  }

  static List<MatchModel> _twoTeams(List<Team> teams, String tournamentId) {
    return [
      _match(tournamentId, MatchPhase.finalMatch, 0, teams[0].id, teams[1].id),
    ];
  }

  static List<MatchModel> _threeTeams(List<Team> teams, String tournamentId) {
    final pairs = [(0, 1), (0, 2), (1, 2)];
    final group = _roundRobin(
      tournamentId,
      MatchPhase.group,
      pairs.map((p) => (teams[p.$1].id, teams[p.$2].id)).toList(),
      0,
    );
    final finalMatch = _match(tournamentId, MatchPhase.finalMatch, group.length, '', '');
    return [...group, finalMatch];
  }

  static List<MatchModel> _fourTeams(List<Team> teams, String tournamentId) {
    final pairs = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)];
    final group = _roundRobin(
      tournamentId,
      MatchPhase.group,
      pairs.map((p) => (teams[p.$1].id, teams[p.$2].id)).toList(),
      0,
    );
    int order = group.length;
    final semi1 = _match(tournamentId, MatchPhase.semifinal, order++, '', '');
    final semi2 = _match(tournamentId, MatchPhase.semifinal, order++, '', '');
    final finalMatch = _match(tournamentId, MatchPhase.finalMatch, order, '', '');
    return [...group, semi1, semi2, finalMatch];
  }

  static List<MatchModel> _fiveTeams(List<Team> teams, String tournamentId) {
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
    final playin = _match(tournamentId, MatchPhase.playoff, order++, '', '');
    final semi1 = _match(tournamentId, MatchPhase.semifinal, order++, '', '');
    final semi2 = _match(tournamentId, MatchPhase.semifinal, order++, '', '');
    final finalMatch = _match(tournamentId, MatchPhase.finalMatch, order, '', '');
    return [...group, playin, semi1, semi2, finalMatch];
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
    String awayId,
  ) {
    return MatchModel(
      id: _uuid.v4(),
      tournamentId: tournamentId,
      phase: phase,
      scheduledOrder: order,
      homeTeamId: homeId,
      awayTeamId: awayId,
      scorers: const [],
      status: MatchStatus.pending,
    );
  }
}
