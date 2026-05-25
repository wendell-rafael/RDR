import 'package:hive_ce/hive.dart';

part 'goal_event.g.dart';

@HiveType(typeId: 2)
class GoalEvent {
  @HiveField(0)
  String playerId;

  @HiveField(1)
  String teamId;

  GoalEvent({required this.playerId, required this.teamId});
}
