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

    Tournament newTournament = Tournament(
      id: tournament.id,
      createdAt: tournament.createdAt,
      teams: tournament.teams,
      format: tournament.format,
      status: tournament.status,
      matches: matches,
      championTeamId: tournament.championTeamId,
    );

    if (updated.status == MatchStatus.finished) {
      switch (updated.phase) {
        case MatchPhase.group:
          if (StandingsService.isGroupStageComplete(newTournament)) {
            newTournament = _fillKnockoutsAfterGroup(newTournament);
          }
          break;
        case MatchPhase.playoff:
          newTournament = _fillSemi1AfterPlayin(newTournament, updated);
          break;
        case MatchPhase.semifinal:
          if (_areSemisComplete(newTournament)) {
            newTournament = _fillFinalAfterSemis(newTournament);
          }
          break;
        case MatchPhase.finalMatch:
          newTournament = await _finalizeTournament(newTournament, updated);
          break;
      }
    }

    await ref.read(tournamentRepositoryProvider).save(newTournament);
    state = newTournament;
  }

  Tournament _fillKnockoutsAfterGroup(Tournament tournament) {
    final standings = StandingsService.compute(tournament);
    final n = tournament.teams.length;

    var matches = tournament.matches.toList();

    if (n == 3 && standings.length >= 2) {
      matches = matches.map((m) {
        if (m.phase == MatchPhase.finalMatch && m.homeTeamId.isEmpty) {
          return m.copyWith(
            homeTeamId: standings[0].team.id,
            awayTeamId: standings[1].team.id,
          );
        }
        return m;
      }).toList();
    } else if (n == 4 && standings.length >= 4) {
      final semis = matches
          .where((m) => m.phase == MatchPhase.semifinal)
          .toList()
        ..sort((a, b) => a.scheduledOrder.compareTo(b.scheduledOrder));
      matches = matches.map((m) {
        final idx = semis.indexWhere((s) => s.id == m.id);
        if (idx == 0) {
          return m.copyWith(
            homeTeamId: standings[0].team.id,
            awayTeamId: standings[3].team.id,
          );
        }
        if (idx == 1) {
          return m.copyWith(
            homeTeamId: standings[1].team.id,
            awayTeamId: standings[2].team.id,
          );
        }
        return m;
      }).toList();
    } else if (n == 5 && standings.length >= 5) {
      matches = matches.map((m) {
        if (m.phase == MatchPhase.playoff && m.homeTeamId.isEmpty) {
          return m.copyWith(
            homeTeamId: standings[3].team.id,
            awayTeamId: standings[4].team.id,
          );
        }
        return m;
      }).toList();
      final semis = matches
          .where((m) => m.phase == MatchPhase.semifinal)
          .toList()
        ..sort((a, b) => a.scheduledOrder.compareTo(b.scheduledOrder));
      if (semis.length >= 2) {
        final semi2Id = semis[1].id;
        matches = matches.map((m) {
          if (m.id == semi2Id && m.homeTeamId.isEmpty) {
            return m.copyWith(
              homeTeamId: standings[1].team.id,
              awayTeamId: standings[2].team.id,
            );
          }
          return m;
        }).toList();
      }
    }

    return _rebuildWith(tournament, matches);
  }

  Tournament _fillSemi1AfterPlayin(
      Tournament tournament, MatchModel playinMatch) {
    final winnerId = playinMatch.winnerId;
    if (winnerId == null) return tournament;

    final standings = StandingsService.compute(tournament);
    if (standings.isEmpty) return tournament;

    final firstPlaceId = standings[0].team.id;

    final semis = tournament.semifinalMatches;
    if (semis.isEmpty) return tournament;
    final semi1Id = semis[0].id;

    final matches = tournament.matches.map((m) {
      if (m.id == semi1Id && m.homeTeamId.isEmpty) {
        return m.copyWith(homeTeamId: firstPlaceId, awayTeamId: winnerId);
      }
      return m;
    }).toList();

    return _rebuildWith(tournament, matches);
  }

  bool _areSemisComplete(Tournament tournament) {
    final semis = tournament.semifinalMatches;
    return semis.isNotEmpty &&
        semis.every((m) => m.status == MatchStatus.finished);
  }

  Tournament _fillFinalAfterSemis(Tournament tournament) {
    final semis = tournament.semifinalMatches;
    if (semis.length < 2) return tournament;

    final winner1 = semis[0].winnerId;
    final winner2 = semis[1].winnerId;
    if (winner1 == null || winner2 == null) return tournament;

    final matches = tournament.matches.map((m) {
      if (m.phase == MatchPhase.finalMatch && m.homeTeamId.isEmpty) {
        return m.copyWith(homeTeamId: winner1, awayTeamId: winner2);
      }
      return m;
    }).toList();

    return _rebuildWith(tournament, matches);
  }

  Future<Tournament> _finalizeTournament(
      Tournament tournament, MatchModel finalMatch) async {
    final winnerId = finalMatch.winnerId;

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

    return Tournament(
      id: tournament.id,
      createdAt: tournament.createdAt,
      teams: tournament.teams,
      format: tournament.format,
      status: TournamentStatus.finished,
      matches: tournament.matches,
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

  Tournament _rebuildWith(Tournament t, List<MatchModel> matches) {
    return Tournament(
      id: t.id,
      createdAt: t.createdAt,
      teams: t.teams,
      format: t.format,
      status: t.status,
      matches: matches,
      championTeamId: t.championTeamId,
    );
  }

  Future<void> cancelTournament() async {
    final tournament = state;
    if (tournament == null) return;

    final cancelled = Tournament(
      id: tournament.id,
      createdAt: tournament.createdAt,
      teams: tournament.teams,
      format: tournament.format,
      status: TournamentStatus.finished,
      matches: tournament.matches,
      championTeamId: null,
    );

    await ref.read(tournamentRepositoryProvider).save(cancelled);
    await ref.read(settingsProvider.notifier).setActiveTournament(null);
    state = null;
  }
}
