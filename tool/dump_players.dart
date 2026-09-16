// Lê uma caixa Hive de jogadores fora do app (backup) e imprime como JSON.
// Uso: dart run tool/dump_players.dart <diretorio-com-players.hive>
import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:rdr_app/data/models/player.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('informe o diretório que contém players.hive');
    return;
  }
  Hive.init(args.first);
  Hive.registerAdapter(PlayerAdapter());
  final box = await Hive.openBox<Player>('players');
  final list = box.values
      .map((p) => {
            'id': p.id,
            'name': p.name,
            'stars': p.stars,
            'goals': p.goals,
            'titles': p.titles,
            'createdAt': p.createdAt.millisecondsSinceEpoch,
          })
      .toList();
  stdout.writeln(jsonEncode(list));
  await box.close();
}
