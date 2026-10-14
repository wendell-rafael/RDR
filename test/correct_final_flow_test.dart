import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:rdr_app/app/router.dart';
import 'package:rdr_app/data/models/app_settings.dart';
import 'package:rdr_app/data/models/goal_event.dart';
import 'package:rdr_app/data/models/match_model.dart';
import 'package:rdr_app/data/models/player.dart';
import 'package:rdr_app/data/models/team.dart';
import 'package:rdr_app/data/models/tournament.dart';
import 'package:rdr_app/features/tournament/bracket_generator.dart';

void main() {
  // Regressão: a TournamentScreen fica embaixo da de campeão na pilha e,
  // com o torneio encerrado, derrubava a partida aberta por cima.
  testWidgets('corrigir final a partir da tela de campeão', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('rdr');
      Hive.init(dir.path);
      Hive.registerAdapter(PlayerAdapter());
      Hive.registerAdapter(TeamAdapter());
      Hive.registerAdapter(GoalEventAdapter());
      Hive.registerAdapter(MatchPhaseAdapter());
      Hive.registerAdapter(MatchStatusAdapter());
      Hive.registerAdapter(MatchModelAdapter());
      Hive.registerAdapter(TournamentFormatAdapter());
      Hive.registerAdapter(TournamentStatusAdapter());
      Hive.registerAdapter(TournamentAdapter());
      Hive.registerAdapter(TimerDirectionAdapter());
      Hive.registerAdapter(AppSettingsAdapter());
      await Hive.openBox<Player>('players');
      final tBox = await Hive.openBox<Tournament>('tournaments');
      final sBox = await Hive.openBox<AppSettings>('settings');
      await Hive.openBox<int>('sync_meta');

      final teams = [
        Team(id: 'A', name: 'Time A', playerIds: const [], colorValue: 0xFF0000FF),
        Team(id: 'B', name: 'Time B', playerIds: const [], colorValue: 0xFFFF0000),
      ];
      final matches = BracketGenerator.generate(teams, 't');
      final fin = matches.first.copyWith(
          status: MatchStatus.finished, homeScore: 1, awayScore: 0);
      await tBox.put('t', Tournament(
        id: 't',
        createdAt: DateTime(2026),
        teams: teams,
        format: TournamentFormat.twoTeams,
        status: TournamentStatus.finished,
        championTeamId: 'A',
        matches: [fin],
      ));
      await sBox.put('settings', AppSettings()..activeTournamentId = 't');
    });

    final container = ProviderContainer();
    final router = container.read(routerProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    router.goNamed('champion', pathParameters: {'id': 't'});
    await tester.pumpAndSettle();

    await tester.tap(find.text('Corrigir resultado da final'));
    await tester.pumpAndSettle();
    expect(find.text('Corrigir resultado'), findsOneWidget);

    await tester.tap(find.text('Corrigir resultado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corrigir'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('Encerrar Partida'), findsOneWidget,
        reason: 'partida reaberta continua na tela');

    // Tira o gol do Time A: 0x0 vai para os pênaltis, Time B vence.
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encerrar Partida'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Time B').last);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.text('CAMPEÃO'), findsOneWidget);
    expect(find.text('Time B'), findsOneWidget);
  });
}
