import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import '../../data/models/match_model.dart';
import '../../data/models/player.dart';
import '../../data/models/tournament.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/backup_service.dart';
import '../players/players_provider.dart';
import '../../data/repositories/tournament_repository.dart';
import 'standings_service.dart';
import 'tie_service.dart';

final activeTournamentProvider =
    NotifierProvider<TournamentNotifier, Tournament?>(TournamentNotifier.new);

class TournamentNotifier extends Notifier<Tournament?> {
  @override
  Tournament? build() {
    final settings = ref.watch(settingsProvider);
    final id = settings.activeTournamentId;
    if (id == null) return null;
    return ref.watch(tournamentRepositoryProvider).getById(id);
  }

  Future<void> updateMatch(MatchModel updated) async {
    final tournament = state;
    if (tournament == null) return;

    final matches = tournament.matches
        .map((m) => m.id == updated.id ? updated : m)
        .toList();

    Tournament newTournament = tournament.copyWith(matches: matches);
    var justFinalized = false;

    if (updated.status == MatchStatus.finished) {
      switch (updated.phase) {
        case MatchPhase.group:
          if (StandingsService.isGroupStageComplete(newTournament)) {
            newTournament = _fillKnockoutsAfterGroup(newTournament);
          }
          break;
        case MatchPhase.playoff:
          newTournament = _fillSemi1AfterPlayin(newTournament);
          break;
        case MatchPhase.semifinal:
          if (_areSemisComplete(newTournament)) {
            newTournament = _fillFinalAfterSemis(newTournament);
          }
          break;
        case MatchPhase.finalMatch:
          final finalTie =
              TieService.tiesOfPhase(newTournament, MatchPhase.finalMatch)
                  .firstOrNull;
          // Com ida e volta, o torneio só acaba depois do jogo de volta.
          if (finalTie != null && TieService.isComplete(finalTie)) {
            newTournament = await _finalizeTournament(newTournament, finalTie);
            justFinalized = true;
          }
          break;
      }
    }

    await ref.read(tournamentRepositoryProvider).save(newTournament);
    state = newTournament;

    // Envia pra nuvem assim que o torneio termina, sem depender do usuário
    // fechar a tela de campeão (closeTournament() também tenta, como reforço).
    if (justFinalized) {
      SyncService.push(
        players: Hive.box<Player>('players'),
        tournaments: Hive.box<Tournament>('tournaments'),
      ).catchError((_) {});
    }
  }

  // ── Avanço de fase ─────────────────────────────────────────────────────────

  Tournament _fillKnockoutsAfterGroup(Tournament tournament) {
    final standings = StandingsService.compute(tournament);
    final n = tournament.teams.length;
    var t = tournament;

    if (n == 3 && standings.length >= 2) {
      t = _assignTie(t, MatchPhase.finalMatch, 0,
          standings[0].team.id, standings[1].team.id);
    } else if (n == 4 && standings.length >= 4) {
      t = _assignTie(t, MatchPhase.semifinal, 0,
          standings[0].team.id, standings[3].team.id);
      t = _assignTie(t, MatchPhase.semifinal, 1,
          standings[1].team.id, standings[2].team.id);
    } else if (n == 5 && standings.length >= 5) {
      t = _assignTie(t, MatchPhase.playoff, 0,
          standings[3].team.id, standings[4].team.id);
      // A semifinal 1 só é definida depois do play-in.
      t = _assignTie(t, MatchPhase.semifinal, 1,
          standings[1].team.id, standings[2].team.id);
    }

    return t;
  }

  Tournament _fillSemi1AfterPlayin(Tournament tournament) {
    final playin = TieService.tiesOfPhase(tournament, MatchPhase.playoff);
    if (playin.isEmpty) return tournament;

    final winnerId = TieService.winnerId(playin.first);
    if (winnerId == null) return tournament;

    final standings = StandingsService.compute(tournament);
    if (standings.isEmpty) return tournament;

    return _assignTie(
        tournament, MatchPhase.semifinal, 0, standings[0].team.id, winnerId);
  }

  bool _areSemisComplete(Tournament tournament) {
    final semis = TieService.tiesOfPhase(tournament, MatchPhase.semifinal);
    return semis.isNotEmpty && semis.every(TieService.isComplete);
  }

  Tournament _fillFinalAfterSemis(Tournament tournament) {
    final semis = TieService.tiesOfPhase(tournament, MatchPhase.semifinal);
    if (semis.length < 2) return tournament;

    final winner1 = TieService.winnerId(semis[0]);
    final winner2 = TieService.winnerId(semis[1]);
    if (winner1 == null || winner2 == null) return tournament;

    return _assignTie(tournament, MatchPhase.finalMatch, 0, winner1, winner2);
  }

  /// Define os times do confronto [index] de uma fase, se ainda estiver vazio.
  /// Em ida e volta, preenche os dois jogos com o mando invertido na volta.
  Tournament _assignTie(
    Tournament t,
    MatchPhase phase,
    int index,
    String homeId,
    String awayId,
  ) {
    final ties = TieService.tiesOfPhase(t, phase);
    if (index >= ties.length) return t;

    final legs = ties[index];
    if (legs.first.homeTeamId.isNotEmpty) return t;

    final assigned = TieService.assignTeams(legs, homeId, awayId);
    final byId = {for (final m in assigned) m.id: m};
    return t.copyWith(
      matches: t.matches.map((m) => byId[m.id] ?? m).toList(),
    );
  }

  Future<Tournament> _finalizeTournament(
      Tournament tournament, List<MatchModel> finalTie) async {
    final winnerId = TieService.winnerId(finalTie);

    if (winnerId != null) {
      final winnerTeam =
          tournament.teams.where((t) => t.id == winnerId).firstOrNull;
      if (winnerTeam != null) {
        final playerNotifier = ref.read(playersProvider.notifier);
        for (final pid in winnerTeam.playerIds) {
          await playerNotifier.awardTitle(pid);
        }
      }
    }

    final playerNotifier = ref.read(playersProvider.notifier);
    final goalCounts = <String, int>{};
    for (final m in tournament.matches) {
      if (m.status != MatchStatus.finished) continue;
      for (final g in m.scorers) {
        goalCounts[g.playerId] = (goalCounts[g.playerId] ?? 0) + 1;
      }
    }
    for (final entry in goalCounts.entries) {
      await playerNotifier.incrementGoals(entry.key, entry.value);
    }

    return tournament.copyWith(
      status: TournamentStatus.finished,
      championTeamId: winnerId,
    );
    // Nota: setActiveTournament(null) e sync são feitos em closeTournament(),
    // chamado pelo usuário ao fechar a tela de campeão.
  }

  /// Chamado ao fechar a tela de campeão. Limpa o torneio ativo e sincroniza.
  Future<void> closeTournament() async {
    await ref.read(settingsProvider.notifier).setActiveTournament(null);
    SyncService.push(
      players: Hive.box<Player>('players'),
      tournaments: Hive.box<Tournament>('tournaments'),
    ).catchError((_) {});
  }

  /// Cancela o torneio ativo apagando-o por completo — não deve sobrar
  /// rastro no histórico, diferente de um torneio finalizado normalmente.
  Future<void> cancelTournament() async {
    final tournament = state;
    if (tournament == null) return;

    await ref.read(tournamentRepositoryProvider).delete(tournament.id);
    await ref.read(settingsProvider.notifier).setActiveTournament(null);
    state = null;
  }
}
