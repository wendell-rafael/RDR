import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_ce/hive.dart';
import '../models/goal_event.dart';
import '../models/match_model.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../models/tournament.dart';

class SyncService {
  static final _doc =
      FirebaseFirestore.instance.collection('racha').doc('main');

  // ── Push ──────────────────────────────────────────────────────────────────

  /// Envia todos os jogadores e torneios para a nuvem.
  /// Fire-and-forget: use [push] sem await para não bloquear a UI.
  static Future<void> push({
    required Box<Player> players,
    required Box<Tournament> tournaments,
  }) async {
    await _doc.set({
      'updatedAt': FieldValue.serverTimestamp(),
      'players': players.values.map(_playerToMap).toList(),
      'tournaments': tournaments.values.map(_tournamentToMap).toList(),
    });
  }

  // ── Pull ──────────────────────────────────────────────────────────────────

  /// Baixa os dados da nuvem e substitui os locais.
  /// Retorna [false] se ainda não houver dados na nuvem.
  static Future<bool> pull({
    required Box<Player> players,
    required Box<Tournament> tournaments,
  }) async {
    final snap = await _doc.get();
    if (!snap.exists) return false;

    final data = snap.data()!;

    await players.clear();
    for (final p in (data['players'] as List?)?.cast<Map>() ?? []) {
      final player = _playerFromMap(Map<String, dynamic>.from(p));
      await players.put(player.id, player);
    }

    await tournaments.clear();
    for (final t in (data['tournaments'] as List?)?.cast<Map>() ?? []) {
      final tournament = _tournamentFromMap(Map<String, dynamic>.from(t));
      await tournaments.put(tournament.id, tournament);
    }

    return true;
  }

  /// Retorna o timestamp da última sincronização, ou null se nunca sincronizou.
  static Future<DateTime?> lastSyncAt() async {
    final snap = await _doc.get();
    if (!snap.exists) return null;
    final ts = snap.data()?['updatedAt'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _playerToMap(Player p) => {
        'id': p.id,
        'name': p.name,
        'stars': p.stars,
        'goals': p.goals,
        'titles': p.titles,
        'createdAt': p.createdAt.millisecondsSinceEpoch,
      };

  static Player _playerFromMap(Map<String, dynamic> m) => Player(
        id: m['id'] as String,
        name: m['name'] as String,
        stars: (m['stars'] as num).toDouble(),
        goals: (m['goals'] as num?)?.toInt() ?? 0,
        titles: (m['titles'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      );

  static Map<String, dynamic> _teamToMap(Team t) => {
        'id': t.id,
        'name': t.name,
        'playerIds': t.playerIds,
        'colorValue': t.colorValue,
        'averageStars': t.averageStars,
      };

  static Team _teamFromMap(Map<String, dynamic> m) => Team(
        id: m['id'] as String,
        name: m['name'] as String,
        playerIds: List<String>.from(m['playerIds'] as List),
        colorValue: m['colorValue'] as int,
        averageStars: (m['averageStars'] as num).toDouble(),
      );

  static Map<String, dynamic> _goalEventToMap(GoalEvent g) => {
        'playerId': g.playerId,
        'teamId': g.teamId,
      };

  static GoalEvent _goalEventFromMap(Map<String, dynamic> m) => GoalEvent(
        playerId: m['playerId'] as String,
        teamId: m['teamId'] as String,
      );

  static Map<String, dynamic> _matchToMap(MatchModel m) => {
        'id': m.id,
        'tournamentId': m.tournamentId,
        'phase': m.phase.index,
        'scheduledOrder': m.scheduledOrder,
        'homeTeamId': m.homeTeamId,
        'awayTeamId': m.awayTeamId,
        'homeScore': m.homeScore,
        'awayScore': m.awayScore,
        'status': m.status.index,
        'scorers': m.scorers.map(_goalEventToMap).toList(),
      };

  static MatchModel _matchFromMap(Map<String, dynamic> m) => MatchModel(
        id: m['id'] as String,
        tournamentId: m['tournamentId'] as String,
        phase: MatchPhase.values[m['phase'] as int],
        scheduledOrder: m['scheduledOrder'] as int,
        homeTeamId: m['homeTeamId'] as String,
        awayTeamId: m['awayTeamId'] as String,
        homeScore: m['homeScore'] as int?,
        awayScore: m['awayScore'] as int?,
        status: MatchStatus.values[m['status'] as int],
        scorers: ((m['scorers'] as List?)?.cast<Map>() ?? [])
            .map((e) => _goalEventFromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );

  static Map<String, dynamic> _tournamentToMap(Tournament t) => {
        'id': t.id,
        'createdAt': t.createdAt.millisecondsSinceEpoch,
        'format': t.format.index,
        'status': t.status.index,
        'championTeamId': t.championTeamId,
        'teams': t.teams.map(_teamToMap).toList(),
        'matches': t.matches.map(_matchToMap).toList(),
      };

  static Tournament _tournamentFromMap(Map<String, dynamic> m) => Tournament(
        id: m['id'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
        format: TournamentFormat.values[m['format'] as int],
        status: TournamentStatus.values[m['status'] as int],
        championTeamId: m['championTeamId'] as String?,
        teams: ((m['teams'] as List?)?.cast<Map>() ?? [])
            .map((e) => _teamFromMap(Map<String, dynamic>.from(e)))
            .toList(),
        matches: ((m['matches'] as List?)?.cast<Map>() ?? [])
            .map((e) => _matchFromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
