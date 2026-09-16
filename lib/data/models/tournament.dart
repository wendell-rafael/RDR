import 'package:hive_ce/hive.dart';
import 'match_model.dart';
import 'team.dart';

part 'tournament.g.dart';

// Sentinel para distinguir "não foi passado" de "explicitamente null" no copyWith
const Object _unsetSentinel = Object();

@HiveType(typeId: 6)
enum TournamentFormat {
  @HiveField(0)
  twoTeams,
  @HiveField(1)
  threeTeams,
  @HiveField(2)
  fourTeams,
  @HiveField(3)
  fiveTeams,
}

@HiveType(typeId: 7)
enum TournamentStatus {
  @HiveField(0)
  active,
  @HiveField(1)
  finished,
}

@HiveType(typeId: 8)
class Tournament extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime createdAt;

  @HiveField(2)
  List<Team> teams;

  @HiveField(3)
  TournamentFormat format;

  @HiveField(4)
  TournamentStatus status;

  @HiveField(5)
  List<MatchModel> matches;

  @HiveField(6)
  String? championTeamId;

  /// Quando true, semifinais e final são disputadas em ida e volta,
  /// com o vencedor definido pelo placar agregado.
  @HiveField(7)
  bool twoLegged;

  Tournament({
    required this.id,
    required this.createdAt,
    required this.teams,
    required this.format,
    this.status = TournamentStatus.active,
    List<MatchModel>? matches,
    this.championTeamId,
    this.twoLegged = false,
  }) : matches = matches ?? [];

  Tournament copyWith({
    String? id,
    DateTime? createdAt,
    List<Team>? teams,
    TournamentFormat? format,
    TournamentStatus? status,
    List<MatchModel>? matches,
    Object? championTeamId = _unsetSentinel,
    bool? twoLegged,
  }) {
    return Tournament(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      teams: teams ?? this.teams,
      format: format ?? this.format,
      status: status ?? this.status,
      matches: matches ?? this.matches,
      championTeamId: championTeamId == _unsetSentinel
          ? this.championTeamId
          : championTeamId as String?,
      twoLegged: twoLegged ?? this.twoLegged,
    );
  }

  /// As partidas de um confronto de ida e volta, ordenadas por jogo.
  List<MatchModel> legsOfTie(String tieId) =>
      matches.where((m) => m.tieId == tieId).toList()
        ..sort((a, b) => a.leg.compareTo(b.leg));

  /// Todas as partidas que compõem o mesmo confronto de [match].
  /// Em jogo único, retorna só ela.
  List<MatchModel> legsOf(MatchModel match) =>
      match.tieId == null ? [match] : legsOfTie(match.tieId!);

  List<MatchModel> get groupMatches =>
      matches.where((m) => m.phase == MatchPhase.group).toList()
        ..sort((a, b) => a.scheduledOrder.compareTo(b.scheduledOrder));

  List<MatchModel> get playoffMatches =>
      matches.where((m) => m.phase == MatchPhase.playoff).toList();

  List<MatchModel> get semifinalMatches =>
      matches.where((m) => m.phase == MatchPhase.semifinal).toList()
        ..sort((a, b) => a.scheduledOrder.compareTo(b.scheduledOrder));

  List<MatchModel> get finalMatches =>
      matches.where((m) => m.phase == MatchPhase.finalMatch).toList();

  MatchModel? get nextPendingMatch {
    final pending = matches
        .where((m) => m.status == MatchStatus.pending)
        .toList()
      ..sort((a, b) => a.scheduledOrder.compareTo(b.scheduledOrder));
    return pending.isEmpty ? null : pending.first;
  }

  bool get isComplete =>
      status == TournamentStatus.finished ||
      matches.every((m) => m.status == MatchStatus.finished);

  Team? get champion => championTeamId != null
      ? teams.where((t) => t.id == championTeamId).firstOrNull
      : null;
}
