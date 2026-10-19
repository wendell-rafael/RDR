import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:rdr_app/data/models/player.dart';
import 'package:rdr_app/data/models/tournament.dart';
import 'package:rdr_app/data/services/local_backup_service.dart';
import 'package:rdr_app/hive_registrar.g.dart';

void main() {
  late Box<Player> players;
  late Box<Tournament> tournaments;

  setUpAll(() async {
    Hive.init((await Directory.systemTemp.createTemp('rdr')).path);
    Hive.registerAdapters();
  });

  setUp(() async {
    players = await Hive.openBox<Player>('players');
    tournaments = await Hive.openBox<Tournament>('tournaments');
    await Hive.openBox<String>(LocalBackupService.boxName);
    await players.clear();
    await tournaments.clear();
    await Hive.box<String>(LocalBackupService.boxName).clear();
  });

  Player p(String id, {int goals = 0}) => Player(
      id: id, name: 'Jogador $id', stars: 3, goals: goals,
      createdAt: DateTime(2026, 1, 1));

  test('cópia guarda o estado e restaurar volta a ele', () async {
    await players.put('a', p('a', goals: 5));
    await LocalBackupService.create('Antes de A × B');

    await players.clear();
    await players.put('b', p('b'));

    final list = LocalBackupService.list();
    expect(list.single.label, 'Antes de A × B');
    expect(list.single.playerCount, 1);

    await LocalBackupService.restore(list.single);
    expect(players.keys, ['a']);
    expect(players.get('a')!.goals, 5);
    // restaurar guarda antes o estado de agora (dá para desfazer)
    final after = LocalBackupService.list();
    expect(after.first.label, 'Antes de restaurar');
    expect(after.length, 2);
  });

  test('mais recente primeiro e só as últimas ${LocalBackupService.maxEntries}',
      () async {
    final t0 = DateTime(2026, 10, 1);
    for (var i = 0; i < LocalBackupService.maxEntries + 5; i++) {
      await LocalBackupService.create('c$i', now: t0.add(Duration(minutes: i)));
    }
    final list = LocalBackupService.list();
    expect(list.length, LocalBackupService.maxEntries);
    expect(list.first.label, 'c${LocalBackupService.maxEntries + 4}');
    expect(list.last.label, 'c5');
  });

  test('sem a caixa aberta, criar não quebra nada', () async {
    await Hive.box<String>(LocalBackupService.boxName).close();
    await LocalBackupService.create('x');
    expect(LocalBackupService.list(), isEmpty);
  });
}
