import 'package:flutter_test/flutter_test.dart';
import 'package:rdr_app/data/models/match_model.dart';
import 'package:rdr_app/data/models/team.dart';
import 'package:rdr_app/data/models/tournament.dart';
import 'package:rdr_app/features/tournament/bracket_generator.dart';
import 'package:rdr_app/features/tournament/tie_service.dart';

Team _team(String id) =>
    Team(id: id, name: 'Time $id', playerIds: const [], colorValue: 0xFF000000);

Tournament _tournament(List<MatchModel> matches,
        {bool twoLegged = false, int teamCount = 4}) =>
    Tournament(
      id: 't',
      createdAt: DateTime(2026, 1, 1),
      teams: List.generate(teamCount, (i) => _team('T$i')),
      format: TournamentFormat.fourTeams,
      matches: matches,
      twoLegged: twoLegged,
    );

MatchModel _leg({
  required String id,
  required String tieId,
  required int leg,
  required String home,
  required String away,
  int? homeScore,
  int? awayScore,
  String? penaltyWinnerId,
  MatchStatus status = MatchStatus.pending,
}) =>
    MatchModel(
      id: id,
      tournamentId: 't',
      phase: MatchPhase.semifinal,
      scheduledOrder: leg,
      homeTeamId: home,
      awayTeamId: away,
      homeScore: homeScore,
      awayScore: awayScore,
      status: status,
      penaltyWinnerId: penaltyWinnerId,
      tieId: tieId,
      leg: leg,
    );

void main() {
  group('BracketGenerator em ida e volta', () {
    test('4 times gera 6 jogos de grupo, 4 de semi e 2 de final', () {
      final teams = List.generate(4, (i) => _team('T$i'));
      final matches = BracketGenerator.generate(teams, 't', twoLegged: true);

      expect(matches.where((m) => m.phase == MatchPhase.group).length, 6);
      expect(matches.where((m) => m.phase == MatchPhase.semifinal).length, 4);
      expect(matches.where((m) => m.phase == MatchPhase.finalMatch).length, 2);
    });

    test('jogo único continua sendo o padrão', () {
      final teams = List.generate(4, (i) => _team('T$i'));
      final matches = BracketGenerator.generate(teams, 't');

      expect(matches.where((m) => m.phase == MatchPhase.semifinal).length, 2);
      expect(matches.where((m) => m.phase == MatchPhase.finalMatch).length, 1);
      expect(matches.every((m) => m.tieId == null), isTrue);
      expect(matches.every((m) => m.leg == 1), isTrue);
    });

    test('as duas idas das semis vêm antes das duas voltas', () {
      final teams = List.generate(4, (i) => _team('T$i'));
      final matches = BracketGenerator.generate(teams, 't', twoLegged: true);

      final semis = matches
          .where((m) => m.phase == MatchPhase.semifinal)
          .toList()
        ..sort((a, b) => a.scheduledOrder.compareTo(b.scheduledOrder));

      expect(semis.map((m) => m.leg).toList(), [1, 1, 2, 2]);
    });

    test('cada confronto tem um tieId próprio com ida e volta', () {
      final teams = List.generate(4, (i) => _team('T$i'));
      final matches = BracketGenerator.generate(teams, 't', twoLegged: true);
      final tournament = _tournament(matches, twoLegged: true);

      final ties = TieService.tiesOfPhase(tournament, MatchPhase.semifinal);
      expect(ties.length, 2);
      expect(ties.every((legs) => legs.length == 2), isTrue);
      expect(ties[0].first.tieId, isNot(ties[1].first.tieId));
    });

    test('play-in de 5 times segue em jogo único mesmo com ida e volta', () {
      final teams = List.generate(5, (i) => _team('T$i'));
      final matches = BracketGenerator.generate(teams, 't', twoLegged: true);

      final playoff =
          matches.where((m) => m.phase == MatchPhase.playoff).toList();
      expect(playoff.length, 1);
      expect(playoff.first.tieId, isNull);
    });
  });

  group('TieService.assignTeams', () {
    test('inverte o mando no jogo de volta', () {
      final legs = [
        _leg(id: 'a', tieId: 'tie', leg: 1, home: '', away: ''),
        _leg(id: 'b', tieId: 'tie', leg: 2, home: '', away: ''),
      ];

      final assigned = TieService.assignTeams(legs, 'A', 'B');

      expect(assigned[0].homeTeamId, 'A');
      expect(assigned[0].awayTeamId, 'B');
      expect(assigned[1].homeTeamId, 'B');
      expect(assigned[1].awayTeamId, 'A');
    });
  });

  group('TieService.winnerId', () {
    test('soma os dois jogos e aponta o vencedor do agregado', () {
      // A 1×2 B na ida, B 0×2 A na volta → agregado A 3 × 2 B
      final legs = [
        _leg(
            id: 'a',
            tieId: 'tie',
            leg: 1,
            home: 'A',
            away: 'B',
            homeScore: 1,
            awayScore: 2,
            status: MatchStatus.finished),
        _leg(
            id: 'b',
            tieId: 'tie',
            leg: 2,
            home: 'B',
            away: 'A',
            homeScore: 0,
            awayScore: 2,
            status: MatchStatus.finished),
      ];

      final totals = TieService.aggregate(legs);
      expect(totals['A'], 3);
      expect(totals['B'], 2);
      expect(TieService.winnerId(legs), 'A');
    });

    test('não decide nada enquanto a volta não terminou', () {
      final legs = [
        _leg(
            id: 'a',
            tieId: 'tie',
            leg: 1,
            home: 'A',
            away: 'B',
            homeScore: 3,
            awayScore: 0,
            status: MatchStatus.finished),
        _leg(id: 'b', tieId: 'tie', leg: 2, home: 'B', away: 'A'),
      ];

      expect(TieService.isComplete(legs), isFalse);
      expect(TieService.winnerId(legs), isNull);
    });

    test('agregado empatado fica sem vencedor até os pênaltis', () {
      final legs = [
        _leg(
            id: 'a',
            tieId: 'tie',
            leg: 1,
            home: 'A',
            away: 'B',
            homeScore: 2,
            awayScore: 1,
            status: MatchStatus.finished),
        _leg(
            id: 'b',
            tieId: 'tie',
            leg: 2,
            home: 'B',
            away: 'A',
            homeScore: 1,
            awayScore: 0,
            status: MatchStatus.finished),
      ];

      expect(TieService.winnerId(legs), isNull);
    });

    test('pênaltis na volta decidem o confronto', () {
      final legs = [
        _leg(
            id: 'a',
            tieId: 'tie',
            leg: 1,
            home: 'A',
            away: 'B',
            homeScore: 2,
            awayScore: 1,
            status: MatchStatus.finished),
        _leg(
            id: 'b',
            tieId: 'tie',
            leg: 2,
            home: 'B',
            away: 'A',
            homeScore: 1,
            awayScore: 0,
            penaltyWinnerId: 'B',
            status: MatchStatus.finished),
      ];

      expect(TieService.winnerId(legs), 'B');
    });

    test('jogo único continua decidindo pelo placar da partida', () {
      final single = MatchModel(
        id: 'x',
        tournamentId: 't',
        phase: MatchPhase.finalMatch,
        scheduledOrder: 0,
        homeTeamId: 'A',
        awayTeamId: 'B',
        homeScore: 0,
        awayScore: 1,
        status: MatchStatus.finished,
      );

      expect(TieService.winnerId([single]), 'B');
    });
  });

  group('Ordem de disputa fora do padrão', () {
    // Os dois cards ficam clicáveis assim que os times são definidos, então
    // nada impede encerrar a volta antes da ida.
    test('volta jogada antes da ida ainda decide o confronto', () {
      final legs = [
        _leg(
            id: 'ida',
            tieId: 'tie',
            leg: 1,
            home: 'A',
            away: 'B',
            homeScore: 1,
            awayScore: 0,
            status: MatchStatus.finished),
        _leg(
            id: 'volta',
            tieId: 'tie',
            leg: 2,
            home: 'B',
            away: 'A',
            homeScore: 1,
            awayScore: 0,
            status: MatchStatus.finished),
      ];

      // Agregado 1 × 1: sem pênaltis o confronto não tem vencedor.
      expect(TieService.isComplete(legs), isTrue);
      expect(TieService.winnerId(legs), isNull);

      // Ao encerrar a IDA por último, ela é que precisa perguntar os pênaltis.
      expect(TieService.isLastToFinish(legs, legs[0]), isTrue,
          reason: 'a ida foi a última a ser encerrada');
      expect(
        TieService.needsPenalties(legs,
            overrideMatchId: 'ida', overrideHome: 1, overrideAway: 0),
        isTrue,
      );
    });

    test('pênaltis gravados na ida decidem o confronto', () {
      final legs = [
        _leg(
            id: 'ida',
            tieId: 'tie',
            leg: 1,
            home: 'A',
            away: 'B',
            homeScore: 1,
            awayScore: 0,
            penaltyWinnerId: 'A',
            status: MatchStatus.finished),
        _leg(
            id: 'volta',
            tieId: 'tie',
            leg: 2,
            home: 'B',
            away: 'A',
            homeScore: 1,
            awayScore: 0,
            status: MatchStatus.finished),
      ];

      expect(TieService.winnerId(legs), 'A');
    });

    test('confronto completo sem vencedor é sinalizado', () {
      final legs = [
        _leg(id: 'a', tieId: 't', leg: 1, home: 'A', away: 'B',
            homeScore: 2, awayScore: 1, status: MatchStatus.finished),
        _leg(id: 'b', tieId: 't', leg: 2, home: 'B', away: 'A',
            homeScore: 1, awayScore: 0, status: MatchStatus.finished),
      ];
      expect(TieService.needsPenaltyDecision(legs), isTrue);
    });
  });

  group('TieService.needsPenalties', () {
    test('vai para os pênaltis quando o placar da tela empata o agregado', () {
      final legs = [
        _leg(
            id: 'a',
            tieId: 'tie',
            leg: 1,
            home: 'A',
            away: 'B',
            homeScore: 2,
            awayScore: 1,
            status: MatchStatus.finished),
        _leg(id: 'b', tieId: 'tie', leg: 2, home: 'B', away: 'A'),
      ];

      // Volta terminando B 1 × 0 A → agregado 2 × 2.
      expect(
        TieService.needsPenalties(legs,
            overrideMatchId: 'b', overrideHome: 1, overrideAway: 0),
        isTrue,
      );
      // Volta terminando B 0 × 0 A → agregado 2 × 1 para A.
      expect(
        TieService.needsPenalties(legs,
            overrideMatchId: 'b', overrideHome: 0, overrideAway: 0),
        isFalse,
      );
    });

    test('empate no jogo de ida não vai para os pênaltis', () {
      final legs = [
        _leg(id: 'a', tieId: 'tie', leg: 1, home: 'A', away: 'B'),
        _leg(id: 'b', tieId: 'tie', leg: 2, home: 'B', away: 'A'),
      ];

      expect(TieService.isLastToFinish(legs, legs[0]), isFalse);
      // A volta ainda não foi jogada, então nem se avalia o agregado.
      expect(
        TieService.needsPenalties(legs,
            overrideMatchId: 'a', overrideHome: 1, overrideAway: 1),
        isFalse,
      );
    });

    test('em jogo único, empate manda para os pênaltis', () {
      final single = MatchModel(
        id: 'x',
        tournamentId: 't',
        phase: MatchPhase.finalMatch,
        scheduledOrder: 0,
        homeTeamId: 'A',
        awayTeamId: 'B',
      );

      expect(TieService.isLastToFinish([single], single), isTrue);
      expect(
        TieService.needsPenalties([single],
            overrideMatchId: 'x', overrideHome: 2, overrideAway: 2),
        isTrue,
      );
      expect(
        TieService.needsPenalties([single],
            overrideMatchId: 'x', overrideHome: 3, overrideAway: 2),
        isFalse,
      );
    });
  });
}
