import 'package:flutter_test/flutter_test.dart';
import 'package:rdr_app/data/models/goal_event.dart';
import 'package:rdr_app/data/models/match_model.dart';
import 'package:rdr_app/data/models/player.dart';
import 'package:rdr_app/data/models/team.dart';
import 'package:rdr_app/data/models/tournament.dart';
import 'package:rdr_app/data/services/whatsapp_export.dart';

final _emoji = RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}]',
    unicode: true);

void main() {
  final players = [
    Player(id: 'p1', name: 'Ana', stars: 3, createdAt: DateTime(2026)),
    Player(id: 'p2', name: 'Bia', stars: 4, createdAt: DateTime(2026)),
  ];
  final teams = [
    Team(id: 'A', name: 'Time A', playerIds: const ['p1'], colorValue: 0xFF1E5BFF),
    Team(id: 'B', name: 'Time B', playerIds: const ['p2'], colorValue: 0xFFFFFFFF),
  ];

  test('times: sem emoji, cor por extenso e link do site', () {
    final text = WhatsAppExport.teams(teams: teams, allPlayers: players);
    expect(_emoji.hasMatch(text), isFalse, reason: text);
    expect(text, contains('*Time A* (azul)'));
    expect(text, contains('*Time B* (branco)'));
    expect(text, endsWith(WhatsAppExport.siteUrl));
  });

  test('tabela: classificação, artilharia, campeão e link, sem emoji', () {
    final t = Tournament(
      id: 't',
      createdAt: DateTime(2026, 10, 18),
      teams: teams,
      format: TournamentFormat.twoTeams,
      status: TournamentStatus.finished,
      championTeamId: 'A',
      matches: [
        MatchModel(
          id: 'm1',
          tournamentId: 't',
          phase: MatchPhase.group,
          scheduledOrder: 0,
          homeTeamId: 'A',
          awayTeamId: 'B',
          homeScore: 2,
          awayScore: 1,
          status: MatchStatus.finished,
          scorers: [
            GoalEvent(playerId: 'p1', teamId: 'A'),
            GoalEvent(playerId: 'p1', teamId: 'A'),
            GoalEvent(playerId: 'p2', teamId: 'B'),
          ],
        ),
      ],
    );
    final text = WhatsAppExport.standings(t, players);
    expect(_emoji.hasMatch(text), isFalse, reason: text);
    expect(text, contains('*Racha dos Ruins — 18/10/2026*'));
    expect(text, contains('1. Ana — 2 gols'));
    expect(text, contains('*Campeão: Time A*'));
    expect(text, endsWith(WhatsAppExport.siteUrl));
  });
}
