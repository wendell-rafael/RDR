import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/player.dart';
import '../../data/models/tournament.dart';
import '../../data/repositories/player_repository.dart';
import '../../data/services/backup_service.dart';

const _uuid = Uuid();

void _pushToCloud() {
  SyncService.push(
    players: Hive.box<Player>('players'),
    tournaments: Hive.box<Tournament>('tournaments'),
  ).catchError((_) {}); // fire-and-forget
}

final playersProvider =
    NotifierProvider<PlayersNotifier, List<Player>>(PlayersNotifier.new);

class PlayersNotifier extends Notifier<List<Player>> {
  @override
  List<Player> build() {
    return _sorted(ref.watch(playerRepositoryProvider).getAll());
  }

  List<Player> _sorted(List<Player> players) {
    return players..sort((a, b) {
      final cmp = b.stars.compareTo(a.stars);
      return cmp != 0 ? cmp : a.name.compareTo(b.name);
    });
  }

  Future<void> addPlayer({
    required String name,
    required double stars,
  }) async {
    final player = Player(
      id: _uuid.v4(),
      name: name.trim(),
      stars: stars,
      createdAt: DateTime.now(),
    );
    await ref.read(playerRepositoryProvider).save(player);
    state = _sorted(ref.read(playerRepositoryProvider).getAll());
    _pushToCloud();
  }

  Future<void> updatePlayer(Player player) async {
    await ref.read(playerRepositoryProvider).save(player);
    state = _sorted(ref.read(playerRepositoryProvider).getAll());
    _pushToCloud();
  }

  Future<void> deletePlayer(String id) async {
    await ref.read(playerRepositoryProvider).delete(id);
    state = _sorted(ref.read(playerRepositoryProvider).getAll());
    _pushToCloud();
  }

  Future<void> incrementGoals(String playerId, int count) async {
    final repo = ref.read(playerRepositoryProvider);
    final player = repo.getById(playerId);
    if (player == null) return;
    final updated = player.copyWith(goals: player.goals + count);
    await repo.save(updated);
    state = _sorted(repo.getAll());
  }

  Future<void> awardTitle(String playerId) async {
    final repo = ref.read(playerRepositoryProvider);
    final player = repo.getById(playerId);
    if (player == null) return;
    final updated = player.copyWith(titles: player.titles + 1);
    await repo.save(updated);
    state = _sorted(repo.getAll());
  }

  Player? getById(String id) => ref.read(playerRepositoryProvider).getById(id);
}
