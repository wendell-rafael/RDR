import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/player.dart';
import '../../data/models/team.dart';
import '../../data/models/tournament.dart';
import '../../data/repositories/player_repository.dart';
import '../../data/repositories/tournament_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../tournament/bracket_generator.dart';
import 'snake_draft.dart';

const _uuid = Uuid();

class DrawState {
  final int teamCount;
  final List<String> selectedPlayerIds;
  final List<Team>? teams;
  final int seed;

  /// Semifinais e final em ida e volta, com placar agregado.
  final bool twoLegged;

  /// Torneio de teste: fora do site e sem contar título/gols.
  final bool isTest;

  /// Nomes da lista importada que não bateram com ninguém do banco.
  /// Ficam só como aviso na tela — a seleção deles é manual.
  final List<String> unmatchedImportedNames;

  const DrawState({
    this.teamCount = 2,
    this.selectedPlayerIds = const [],
    this.teams,
    this.seed = 0,
    this.twoLegged = false,
    this.isTest = false,
    this.unmatchedImportedNames = const [],
  });

  DrawState copyWith({
    int? teamCount,
    List<String>? selectedPlayerIds,
    List<Team>? teams,
    int? seed,
    bool? twoLegged,
    bool? isTest,
    List<String>? unmatchedImportedNames,
  }) {
    return DrawState(
      teamCount: teamCount ?? this.teamCount,
      selectedPlayerIds: selectedPlayerIds ?? this.selectedPlayerIds,
      teams: teams ?? this.teams,
      seed: seed ?? this.seed,
      twoLegged: twoLegged ?? this.twoLegged,
      isTest: isTest ?? this.isTest,
      unmatchedImportedNames:
          unmatchedImportedNames ?? this.unmatchedImportedNames,
    );
  }

  DrawState clearTeams() {
    return DrawState(
      teamCount: teamCount,
      selectedPlayerIds: selectedPlayerIds,
      teams: null,
      seed: seed,
      twoLegged: twoLegged,
      isTest: isTest,
      unmatchedImportedNames: unmatchedImportedNames,
    );
  }
}

final drawProvider =
    NotifierProvider<DrawNotifier, DrawState>(DrawNotifier.new);

class DrawNotifier extends Notifier<DrawState> {
  @override
  DrawState build() {
    final allPlayers = ref.watch(playerRepositoryProvider).getAll();
    return DrawState(
      selectedPlayerIds: allPlayers.map((p) => p.id).toList(),
    );
  }

  void setTwoLegged(bool value) {
    state = state.copyWith(twoLegged: value);
  }

  void setTest(bool value) {
    state = state.copyWith(isTest: value);
  }

  /// Aplica a lista importada: só os jogadores reconhecidos ficam marcados.
  /// Os nomes sem correspondência ficam registrados para seleção manual.
  void applyImport({
    required List<String> matchedPlayerIds,
    required List<String> unmatchedNames,
  }) {
    state = state
        .copyWith(
          selectedPlayerIds: matchedPlayerIds.toSet().toList(),
          unmatchedImportedNames: unmatchedNames,
        )
        .clearTeams();
  }

  void clearUnmatchedNames() {
    state = state.copyWith(unmatchedImportedNames: const []);
  }

  void setTeamCount(int count) {
    state = state.copyWith(teamCount: count).clearTeams();
  }

  void togglePlayer(String playerId) {
    final selected = List<String>.from(state.selectedPlayerIds);
    if (selected.contains(playerId)) {
      selected.remove(playerId);
    } else {
      selected.add(playerId);
    }
    state = state.copyWith(selectedPlayerIds: selected).clearTeams();
  }

  void selectAllPlayers() {
    final all =
        ref.read(playerRepositoryProvider).getAll().map((p) => p.id).toList();
    state = state.copyWith(selectedPlayerIds: all).clearTeams();
  }

  void clearSelectedPlayers() {
    state = state.copyWith(selectedPlayerIds: const []).clearTeams();
  }

  void draw({int? forceSeed}) {
    final seed = forceSeed ?? Random().nextInt(999999);
    final repo = ref.read(playerRepositoryProvider);
    final players = state.selectedPlayerIds
        .map((id) => repo.getById(id))
        .whereType<Player>()
        .toList();

    final teams = snakeDraft(players, state.teamCount, seed: seed);
    state = state.copyWith(teams: teams, seed: seed);
  }

  void redraw() {
    draw(forceSeed: Random().nextInt(999999));
  }

  void resetToDraw() {
    state = state.clearTeams();
  }

  void swapPlayer(String playerId, String fromTeamId, String toTeamId) {
    if (state.teams == null) return;
    final teams = state.teams!.map((t) => t.copyWith()).toList();

    final from = teams.indexWhere((t) => t.id == fromTeamId);
    final to = teams.indexWhere((t) => t.id == toTeamId);
    if (from == -1 || to == -1) return;

    final fromIds = List<String>.from(teams[from].playerIds)..remove(playerId);
    final toIds = List<String>.from(teams[to].playerIds)..add(playerId);

    final repo = ref.read(playerRepositoryProvider);

    double avg(List<String> ids) {
      if (ids.isEmpty) return 0;
      final total = ids
          .map((id) => repo.getById(id)?.stars ?? 0)
          .fold<double>(0, (a, b) => a + b);
      return total / ids.length;
    }

    teams[from] = teams[from].copyWith(
      playerIds: fromIds,
      averageStars: avg(fromIds),
    );
    teams[to] = teams[to].copyWith(
      playerIds: toIds,
      averageStars: avg(toIds),
    );

    state = state.copyWith(teams: teams);
  }

  void changeTeamColor(String teamId, int colorValue) {
    if (state.teams == null) return;
    final teams = state.teams!.map((t) {
      if (t.id == teamId) return t.copyWith(colorValue: colorValue);
      return t.copyWith();
    }).toList();
    state = state.copyWith(teams: teams);
  }

  Future<String> confirmAndCreateTournament() async {
    final teams = state.teams!;
    final format = _formatFor(teams.length);
    final tournamentId = _uuid.v4();
    final tournament = Tournament(
      id: tournamentId,
      createdAt: DateTime.now(),
      teams: teams,
      format: format,
      twoLegged: state.twoLegged,
      isTest: state.isTest,
      matches: BracketGenerator.generate(
        teams,
        tournamentId,
        twoLegged: state.twoLegged,
      ),
    );

    final tournamentRepo = ref.read(tournamentRepositoryProvider);
    await tournamentRepo.save(tournament);
    // Teste vale só para este torneio; o próximo sai oficial por padrão.
    state = state.copyWith(isTest: false);

    await ref
        .read(settingsProvider.notifier)
        .setActiveTournament(tournament.id);

    return tournament.id;
  }

  TournamentFormat _formatFor(int count) {
    switch (count) {
      case 2:
        return TournamentFormat.twoTeams;
      case 3:
        return TournamentFormat.threeTeams;
      case 4:
        return TournamentFormat.fourTeams;
      default:
        return TournamentFormat.fiveTeams;
    }
  }
}
