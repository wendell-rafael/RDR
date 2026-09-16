import 'package:hive_ce/hive.dart';

part 'goal_event.g.dart';

@HiveType(typeId: 2)
class GoalEvent {
  @HiveField(0)
  String playerId;

  @HiveField(1)
  String teamId;

  /// Minuto decorrido de partida no momento do gol (tempo corrido desde o
  /// início, independente do cronômetro estar em contagem regressiva).
  /// Nulo em gols registrados antes desse campo existir.
  @HiveField(2)
  int? minute;

  GoalEvent({required this.playerId, required this.teamId, this.minute});
}
