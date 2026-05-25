import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import '../models/player.dart';

final playerBoxProvider = Provider<Box<Player>>((ref) {
  return Hive.box<Player>('players');
});

class PlayerRepository {
  final Box<Player> _box;

  PlayerRepository(this._box);

  List<Player> getAll() => _box.values.toList();

  Player? getById(String id) {
    try {
      return _box.values.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Player player) => _box.put(player.id, player);

  Future<void> delete(String id) => _box.delete(id);

  Future<void> saveAll(List<Player> players) async {
    final map = {for (final p in players) p.id: p};
    await _box.putAll(map);
  }
}

final playerRepositoryProvider = Provider<PlayerRepository>((ref) {
  return PlayerRepository(ref.watch(playerBoxProvider));
});
