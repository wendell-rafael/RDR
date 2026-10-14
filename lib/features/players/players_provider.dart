import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/match_model.dart';
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

  /// Desfaz [awardTitle] e [incrementGoals] de um torneio que deixou de
  /// estar encerrado (final reaberta para corrigir o resultado).
  Future<void> revokeTournamentStats({
    required List<String> titlePlayerIds,
    required Map<String, int> goals,
  }) async {
    final repo = ref.read(playerRepositoryProvider);
    final ids = {...titlePlayerIds, ...goals.keys};
    for (final id in ids) {
      final player = repo.getById(id);
      if (player == null) continue;
      final titles = titlePlayerIds.where((p) => p == id).length;
      await repo.save(player.copyWith(
        titles: (player.titles - titles).clamp(0, player.titles),
        goals: (player.goals - (goals[id] ?? 0)).clamp(0, player.goals),
      ));
    }
    state = _sorted(repo.getAll());
  }

  /// Grava uma importação de lista de uma vez só: cria, renomeia e remove
  /// num lote, com um único envio para a nuvem no fim.
  Future<void> applyImport({
    List<String> namesToCreate = const [],
    double starsForNew = 2.5,
    List<Player> toRename = const [],
    List<String> idsToDelete = const [],
  }) async {
    final repo = ref.read(playerRepositoryProvider);

    for (final name in namesToCreate) {
      await repo.save(Player(
        id: _uuid.v4(),
        name: name.trim(),
        stars: starsForNew,
        createdAt: DateTime.now(),
      ));
    }
    for (final player in toRename) {
      await repo.save(player);
    }
    for (final id in idsToDelete) {
      await repo.delete(id);
    }

    state = _sorted(repo.getAll());
    _pushToCloud();
  }

  /// Zera gols e títulos de todos os jogadores, preservando nome e estrelas.
  /// Não envia para a nuvem: o envio fica a cargo de "Enviar agora".
  Future<int> resetStats() async {
    final repo = ref.read(playerRepositoryProvider);
    final players = repo.getAll();
    var touched = 0;
    for (final p in players) {
      if (p.goals == 0 && p.titles == 0) continue;
      await repo.save(p.copyWith(goals: 0, titles: 0));
      touched++;
    }
    state = _sorted(repo.getAll());
    return touched;
  }

  Player? getById(String id) => ref.read(playerRepositoryProvider).getById(id);

  /// Recalcula título e gols de todo mundo do zero, a partir dos torneios
  /// já salvos — corrige contagens infladas por qualquer bug de finalização
  /// duplicada. Não mexe em nome/estrelas. Não envia pra nuvem: quem chama
  /// decide quando enviar.
  Future<int> recomputeStats(List<Tournament> tournaments) async {
    final repo = ref.read(playerRepositoryProvider);
    final titles = <String, int>{};
    final goals = <String, int>{};

    for (final tournament in tournaments) {
      if (tournament.status != TournamentStatus.finished) continue;
      if (tournament.isTest) continue;
      if (tournament.championTeamId != null) {
        final champion = tournament.teams
            .where((t) => t.id == tournament.championTeamId)
            .firstOrNull;
        if (champion != null) {
          for (final pid in champion.playerIds) {
            titles[pid] = (titles[pid] ?? 0) + 1;
          }
        }
      }
      for (final match in tournament.matches) {
        if (match.status != MatchStatus.finished) continue;
        for (final goal in match.scorers) {
          goals[goal.playerId] = (goals[goal.playerId] ?? 0) + 1;
        }
      }
    }

    var touched = 0;
    for (final player in repo.getAll()) {
      final nextTitles = titles[player.id] ?? 0;
      final nextGoals = goals[player.id] ?? 0;
      if (nextTitles == player.titles && nextGoals == player.goals) continue;
      await repo.save(player.copyWith(titles: nextTitles, goals: nextGoals));
      touched++;
    }
    state = _sorted(repo.getAll());
    return touched;
  }
}
