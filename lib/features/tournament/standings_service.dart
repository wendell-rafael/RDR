import '../../data/models/match_model.dart';
import '../../data/models/team.dart';
import '../../data/models/tournament.dart';

class Standing {
  final Team team;
  int wins;
  int draws;
  int losses;
  int goalsFor;
  int goalsAgainst;

  Standing({required this.team})
      : wins = 0,
        draws = 0,
        losses = 0,
        goalsFor = 0,
        goalsAgainst = 0;

  int get points => wins * 3 + draws;
  int get goalDiff => goalsFor - goalsAgainst;
  int get played => wins + draws + losses;
}

class StandingsService {
  /// Computes standings from group matches and returns a list sorted by
  /// points desc, then goal diff desc, then goals for desc.
  static List<Standing> compute(Tournament tournament) {
    final standings = {
      for (final t in tournament.teams) t.id: Standing(team: t)
    };

    for (final match in tournament.groupMatches) {
      if (match.status != MatchStatus.finished) continue;
      if (match.homeScore == null || match.awayScore == null) continue;

      final home = standings[match.homeTeamId];
      final away = standings[match.awayTeamId];
      if (home == null || away == null) continue;

      final hs = match.homeScore!;
      final as_ = match.awayScore!;

      home.goalsFor += hs;
      home.goalsAgainst += as_;
      away.goalsFor += as_;
      away.goalsAgainst += hs;

      if (hs > as_) {
        home.wins++;
        away.losses++;
      } else if (hs < as_) {
        away.wins++;
        home.losses++;
      } else {
        home.draws++;
        away.draws++;
      }
    }

    final list = standings.values.toList()
      ..sort((a, b) {
        final byPoints = b.points.compareTo(a.points);
        if (byPoints != 0) return byPoints;
        final byWins = b.wins.compareTo(a.wins);
        if (byWins != 0) return byWins;
        final byDiff = b.goalDiff.compareTo(a.goalDiff);
        if (byDiff != 0) return byDiff;
        return b.goalsFor.compareTo(a.goalsFor);
      });

    // Remove teams that are placeholders (empty id — TBD in 5-team bracket)
    return list.where((s) => s.team.id.isNotEmpty).toList();
  }

  /// After group stage is complete, returns the top N finalists (by standing).
  static List<Team> finalists(Tournament tournament, int count) {
    final standings = compute(tournament);
    return standings.take(count).map((s) => s.team).toList();
  }

  /// Determines if all group matches are finished.
  static bool isGroupStageComplete(Tournament tournament) {
    return tournament.groupMatches
        .every((m) => m.status == MatchStatus.finished);
  }

  /// Determines if the playoff (5-team) is complete.
  static bool isPlayoffComplete(Tournament tournament) {
    return tournament.playoffMatches
        .every((m) => m.status == MatchStatus.finished);
  }

  /// Gets the winner of the playoff match (first playoff match).
  static String? playoffWinnerId(Tournament tournament) {
    final playoff = tournament.playoffMatches
        .where((m) => m.status == MatchStatus.finished)
        .firstOrNull;
    return playoff?.winnerId;
  }
}
