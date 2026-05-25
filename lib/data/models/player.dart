import 'package:hive_ce/hive.dart';

part 'player.g.dart';

@HiveType(typeId: 0)
class Player extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double stars;

  @HiveField(3)
  int goals;

  @HiveField(4)
  int titles;

  @HiveField(5)
  DateTime createdAt;

  Player({
    required this.id,
    required this.name,
    required this.stars,
    this.goals = 0,
    this.titles = 0,
    required this.createdAt,
  });

  Player copyWith({
    String? id,
    String? name,
    double? stars,
    int? goals,
    int? titles,
    DateTime? createdAt,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      stars: stars ?? this.stars,
      goals: goals ?? this.goals,
      titles: titles ?? this.titles,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
