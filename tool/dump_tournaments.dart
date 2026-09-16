// Lê a caixa Hive de torneios de um backup e imprime um resumo.
import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:rdr_app/data/models/goal_event.dart';
import 'package:rdr_app/data/models/match_model.dart';
import 'package:rdr_app/data/models/team.dart';
import 'package:rdr_app/data/models/tournament.dart';

Future<void> main(List<String> args) async {
  Hive.init(args.first);
  Hive.registerAdapter(TeamAdapter());
  Hive.registerAdapter(GoalEventAdapter());
  Hive.registerAdapter(MatchPhaseAdapter());
  Hive.registerAdapter(MatchStatusAdapter());
  Hive.registerAdapter(MatchModelAdapter());
  Hive.registerAdapter(TournamentFormatAdapter());
  Hive.registerAdapter(TournamentStatusAdapter());
  Hive.registerAdapter(TournamentAdapter());
  final box = await Hive.openBox<Tournament>('tournaments');
  final out = box.values
      .map((t) => {
            'createdAt': t.createdAt.toIso8601String(),
            'status': t.status.name,
            'teams': t.teams.map((x) => x.name).toList(),
            'twoLegged': t.twoLegged,
            'champion': t.teams
                .where((x) => x.id == t.championTeamId)
                .map((x) => x.name)
                .firstOrNull,
            'matches': t.matches
                .map((m) => {
                      'phase': m.phase.name,
                      'leg': m.leg,
                      'tie': m.tieId != null,
                      'status': m.status.name,
                      'home': t.teams
                          .where((x) => x.id == m.homeTeamId)
                          .map((x) => x.name)
                          .firstOrNull,
                      'away': t.teams
                          .where((x) => x.id == m.awayTeamId)
                          .map((x) => x.name)
                          .firstOrNull,
                      'score': '${m.homeScore ?? '-'}x${m.awayScore ?? '-'}',
                      'pen': t.teams
                          .where((x) => x.id == m.penaltyWinnerId)
                          .map((x) => x.name)
                          .firstOrNull,
                    })
                .toList(),
          })
      .toList();
  stdout.writeln(jsonEncode(out));
  await box.close();
}
