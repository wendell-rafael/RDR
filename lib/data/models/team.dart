import 'package:hive_ce/hive.dart';

part 'team.g.dart';

@HiveType(typeId: 1)
class Team extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  List<String> playerIds;

  @HiveField(3)
  int colorValue;

  @HiveField(4)
  double averageStars;

  Team({
    required this.id,
    required this.name,
    required this.playerIds,
    required this.colorValue,
    this.averageStars = 0.0,
  });

  Team copyWith({
    String? id,
    String? name,
    List<String>? playerIds,
    int? colorValue,
    double? averageStars,
  }) {
    return Team(
      id: id ?? this.id,
      name: name ?? this.name,
      playerIds: playerIds ?? List.from(this.playerIds),
      colorValue: colorValue ?? this.colorValue,
      averageStars: averageStars ?? this.averageStars,
    );
  }
}
