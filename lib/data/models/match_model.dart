import 'package:hive_ce/hive.dart';
import 'goal_event.dart';

part 'match_model.g.dart';

// Sentinel para distinguir "não foi passado" de "explicitamente null" no copyWith
const Object _unsetSentinel = Object();

@HiveType(typeId: 3)
enum MatchPhase {
  @HiveField(0)
  group,
  @HiveField(1)
  playoff,
  @HiveField(2)
  finalMatch,
  @HiveField(3)
  semifinal,
}

@HiveType(typeId: 4)
enum MatchStatus {
  @HiveField(0)
  pending,
  @HiveField(1)
  inProgress,
  @HiveField(2)
  finished,
}

@HiveType(typeId: 5)
class MatchModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String tournamentId;

  @HiveField(2)
  MatchPhase phase;

  @HiveField(3)
  int scheduledOrder;

  @HiveField(4)
  String homeTeamId;

  @HiveField(5)
  String awayTeamId;

  @HiveField(6)
  int? homeScore;

  @HiveField(7)
  int? awayScore;

  @HiveField(8)
  List<GoalEvent> scorers;

  @HiveField(9)
  MatchStatus status;

  @HiveField(10)
  String? penaltyWinnerId;

  /// Identifica um confronto de ida e volta. As duas partidas do mesmo
  /// confronto compartilham o mesmo [tieId]. Null em jogo único.
  @HiveField(11)
  String? tieId;

  /// 1 = jogo de ida, 2 = jogo de volta. Sempre 1 em jogo único.
  @HiveField(12)
  int leg;

  MatchModel({
    required this.id,
    required this.tournamentId,
    required this.phase,
    required this.scheduledOrder,
    required this.homeTeamId,
    required this.awayTeamId,
    this.homeScore,
    this.awayScore,
    List<GoalEvent>? scorers,
    this.status = MatchStatus.pending,
    this.penaltyWinnerId,
    this.tieId,
    this.leg = 1,
  }) : scorers = scorers ?? [];

  bool get isTwoLegged => tieId != null;

  String? get winnerId {
    if (penaltyWinnerId != null) return penaltyWinnerId;
    if (homeScore == null || awayScore == null) return null;
    if (homeScore! > awayScore!) return homeTeamId;
    if (awayScore! > homeScore!) return awayTeamId;
    return null; // draw
  }

  MatchModel copyWith({
    String? id,
    String? tournamentId,
    MatchPhase? phase,
    int? scheduledOrder,
    String? homeTeamId,
    String? awayTeamId,
    int? homeScore,
    int? awayScore,
    List<GoalEvent>? scorers,
    MatchStatus? status,
    Object? penaltyWinnerId = _unsetSentinel,
    String? tieId,
    int? leg,
  }) {
    return MatchModel(
      id: id ?? this.id,
      tournamentId: tournamentId ?? this.tournamentId,
      phase: phase ?? this.phase,
      scheduledOrder: scheduledOrder ?? this.scheduledOrder,
      homeTeamId: homeTeamId ?? this.homeTeamId,
      awayTeamId: awayTeamId ?? this.awayTeamId,
      homeScore: homeScore ?? this.homeScore,
      awayScore: awayScore ?? this.awayScore,
      scorers: scorers ?? List.from(this.scorers),
      status: status ?? this.status,
      penaltyWinnerId: penaltyWinnerId == _unsetSentinel
          ? this.penaltyWinnerId
          : penaltyWinnerId as String?,
      tieId: tieId ?? this.tieId,
      leg: leg ?? this.leg,
    );
  }
}
