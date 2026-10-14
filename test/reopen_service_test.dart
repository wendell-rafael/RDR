import 'package:flutter_test/flutter_test.dart';
import 'package:rdr_app/data/models/match_model.dart';
import 'package:rdr_app/data/models/team.dart';
import 'package:rdr_app/data/models/tournament.dart';
import 'package:rdr_app/features/tournament/bracket_generator.dart';
import 'package:rdr_app/features/tournament/reopen_service.dart';
import 'package:rdr_app/features/tournament/tie_service.dart';

Team _team(String id) =>
    Team(id: id, name: 'Time $id', playerIds: const [], colorValue: 0xFF000000);

Tournament _tournament(int teamCount, {bool twoLegged = false}) {
  final teams = List.generate(teamCount, (i) => _team('T$i'));
  return Tournament(
    id: 't',
    createdAt: DateTime(2026, 1, 1),
    teams: teams,
    format: TournamentFormat.values[teamCount - 2],
    matches: BracketGenerator.generate(teams, 't', twoLegged: twoLegged),
    twoLegged: twoLegged,
  );
}

MatchModel _finish(MatchModel m, int home, int away, {String? penalty}) =>
    m.copyWith(
      status: MatchStatus.finished,
      homeScore: home,
      awayScore: away,
      penaltyWinnerId: penalty,
    );

Tournament _replace(Tournament t, Iterable<MatchModel> updated) {
  final byId = {for (final m in updated) m.id: m};
  return t.copyWith(matches: t.matches.map((m) => byId[m.id] ?? m).toList());
}

Tournament _finishGroup(Tournament t) =>
    _replace(t, t.groupMatches.map((m) => _finish(m, 1, 0)));

Tournament _assignSemis(Tournament t) {
  final semis = TieService.tiesOfPhase(t, MatchPhase.semifinal);
  return _replace(t, [
    ...TieService.assignTeams(semis[0], 'T0', 'T3'),
    ...TieService.assignTeams(semis[1], 'T1', 'T2'),
  ]);
}

void main() {
  group('blockedReason', () {
    test('partida não encerrada não reabre', () {
      final t = _tournament(4);
      expect(ReopenService.blockedReason(t, t.groupMatches.first), isNotNull);
    });

    test('grupo reabre enquanto o mata-mata não começou', () {
      final t = _assignSemis(_finishGroup(_tournament(4)));
      expect(ReopenService.blockedReason(t, t.groupMatches.first), isNull);
    });

    test('grupo não reabre depois que uma semi começou', () {
      var t = _assignSemis(_finishGroup(_tournament(4)));
      t = _replace(t, [
        t.semifinalMatches.first.copyWith(status: MatchStatus.inProgress),
      ]);
      expect(ReopenService.blockedReason(t, t.groupMatches.first), isNotNull);
    });

    test('play-in não depende da semi 2', () {
      var t = _finishGroup(_tournament(5));
      t = _replace(t, [_finish(t.playoffMatches.first, 2, 1)]);
      final semis = TieService.tiesOfPhase(t, MatchPhase.semifinal);
      t = _replace(t, [
        semis[1].first.copyWith(status: MatchStatus.inProgress),
      ]);
      expect(ReopenService.blockedReason(t, t.playoffMatches.first), isNull);
    });

    test('final sempre reabre', () {
      final t = _tournament(2);
      final done = _replace(t, [_finish(t.finalMatches.first, 3, 1)]);
      expect(
          ReopenService.blockedReason(done, done.finalMatches.first), isNull);
    });
  });

  group('reopen', () {
    test('volta a partida para em andamento mantendo placar e artilheiros',
        () {
      final t = _assignSemis(_finishGroup(_tournament(4)));
      final m = t.groupMatches.first;
      final result = ReopenService.reopen(t, m);
      final reopened = result.matches.firstWhere((x) => x.id == m.id);
      expect(reopened.status, MatchStatus.inProgress);
      expect(reopened.homeScore, 1);
      expect(reopened.awayScore, 0);
    });

    test('apaga os times já definidos na fase seguinte', () {
      final t = _assignSemis(_finishGroup(_tournament(4)));
      expect(ReopenService.clearsNextPhase(t, t.groupMatches.first), isTrue);
      final result = ReopenService.reopen(t, t.groupMatches.first);
      for (final m in result.matches.where((m) => m.phase != MatchPhase.group)) {
        expect(m.homeTeamId, isEmpty);
        expect(m.awayTeamId, isEmpty);
      }
    });

    test('descarta os pênaltis de todo o confronto de ida e volta', () {
      var t = _tournament(2, twoLegged: true);
      final legs = t.finalMatches..sort((a, b) => a.leg.compareTo(b.leg));
      t = _replace(t, [
        _finish(legs[0], 1, 0),
        _finish(legs[1], 1, 0, penalty: 'T0'),
      ]);
      final result = ReopenService.reopen(t, legs[0]);
      expect(result.finalMatches.every((m) => m.penaltyWinnerId == null),
          isTrue);
      final other = result.matches.firstWhere((m) => m.id == legs[1].id);
      expect(other.status, MatchStatus.finished);
    });

    test('final de torneio encerrado volta o torneio para ativo', () {
      var t = _tournament(2);
      t = _replace(t, [_finish(t.finalMatches.first, 3, 1)]).copyWith(
        status: TournamentStatus.finished,
        championTeamId: 'T0',
      );
      final result = ReopenService.reopen(t, t.finalMatches.first);
      expect(result.status, TournamentStatus.active);
      expect(result.championTeamId, isNull);
      // Na final de 2 times os times vêm do sorteio, não podem sumir.
      expect(result.finalMatches.first.homeTeamId, 'T0');
    });
  });
}
