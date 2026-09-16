import 'dart:math';
import 'package:uuid/uuid.dart';
import '../../data/models/player.dart';
import '../../data/models/team.dart';
import '../../app/theme.dart';

const _uuid = Uuid();

/// Snake draft: distributes players in zigzag order by stars (desc).
/// Returns balanced teams with computed averageStars.
List<Team> snakeDraft(List<Player> players, int teamCount, {int? seed}) {
  assert(teamCount >= 2 && teamCount <= 5);
  if (players.isEmpty) return [];

  final rng = Random(seed);

  // Sort by stars desc, break ties randomly
  final sorted = List<Player>.from(players)
    ..sort((a, b) {
      final cmp = b.stars.compareTo(a.stars);
      return cmp != 0 ? cmp : (rng.nextBool() ? 1 : -1);
    });

  // Initialize teams
  final teams = List.generate(teamCount, (i) {
    return _MutableTeam(
      id: _uuid.v4(),
      name: 'Time ${String.fromCharCode(65 + i)}',
      color: AppTheme.teamColors[i % AppTheme.teamColors.length].toARGB32(),
    );
  });

  // Snake distribution
  bool forward = true;
  int teamIndex = 0;
  for (final player in sorted) {
    teams[teamIndex].playerIds.add(player.id);
    teams[teamIndex].totalStars += player.stars;
    teams[teamIndex].count++;

    if (forward) {
      teamIndex++;
      if (teamIndex >= teamCount) {
        teamIndex = teamCount - 1;
        forward = false;
      }
    } else {
      teamIndex--;
      if (teamIndex < 0) {
        teamIndex = 0;
        forward = true;
      }
    }
  }

  return teams.map((t) => t.toTeam()).toList();
}

class _MutableTeam {
  final String id;
  final String name;
  final int color;
  final List<String> playerIds = [];
  double totalStars = 0;
  int count = 0;

  _MutableTeam({required this.id, required this.name, required this.color});

  Team toTeam() {
    return Team(
      id: id,
      name: name,
      playerIds: playerIds,
      colorValue: color,
      averageStars: count > 0 ? (totalStars / count) : 0,
    );
  }
}
