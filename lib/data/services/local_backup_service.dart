import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/player.dart';
import '../models/tournament.dart';
import 'backup_service.dart';

/// Uma cópia local do aparelho: jogadores e torneios num instante.
class LocalBackup {
  final String id;
  final DateTime at;
  final String label;
  final Map<String, dynamic> data;

  const LocalBackup({
    required this.id,
    required this.at,
    required this.label,
    required this.data,
  });

  int get tournamentCount => (data['tournaments'] as List?)?.length ?? 0;
  int get playerCount => (data['players'] as List?)?.length ?? 0;

  /// Partidas encerradas em todos os torneios (status 2 = encerrada).
  int get finishedMatches => ((data['tournaments'] as List?) ?? [])
      .expand((t) => ((t as Map)['matches'] as List?) ?? [])
      .where((m) => (m as Map)['status'] == 2)
      .length;

  /// Texto para guardar fora do aparelho (WhatsApp, e-mail). O JSON é o
  /// mesmo formato do documento da nuvem.
  String toShareText() => jsonEncode({
        'app': 'racha_dos_ruins',
        'backupAt': at.toIso8601String(),
        'label': label,
        ...data,
      });

  Map<String, dynamic> _toMap() =>
      {'at': at.millisecondsSinceEpoch, 'label': label, 'data': data};

  factory LocalBackup._fromMap(String id, Map m) => LocalBackup(
        id: id,
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()),
        label: m['label'] as String? ?? '',
        data: Map<String, dynamic>.from(m['data'] as Map),
      );
}

/// Cópias de segurança automáticas, só no aparelho.
///
/// Uma foto dos dados é guardada antes de cada partida começar e antes de
/// qualquer ação que apaga ou substitui dados (zerar, cancelar torneio,
/// reabrir partida, baixar da nuvem, restaurar). Ficam as [maxEntries] mais
/// recentes. Nunca atrapalha a ação: se a cópia falhar, o app segue.
class LocalBackupService {
  static const boxName = 'local_backups';
  static const maxEntries = 40;

  static Box<String>? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box<String>(boxName) : null;

  static Future<void> create(String label, {DateTime? now}) async {
    final box = _box;
    if (box == null) return;
    try {
      if (!Hive.isBoxOpen('players') || !Hive.isBoxOpen('tournaments')) return;
      final at = now ?? DateTime.now();
      final data = SyncService.snapshot(
        players: Hive.box<Player>('players'),
        tournaments: Hive.box<Tournament>('tournaments'),
      );
      final id = at.microsecondsSinceEpoch.toString().padLeft(20, '0');
      await box.put(
          id,
          jsonEncode(
              LocalBackup(id: id, at: at, label: label, data: data)._toMap()));
      await _prune(box);
    } catch (_) {/* cópia é um extra */}
  }

  static Future<void> _prune(Box<String> box) async {
    final keys = box.keys.cast<String>().toList()..sort();
    if (keys.length <= maxEntries) return;
    await box.deleteAll(keys.sublist(0, keys.length - maxEntries));
  }

  /// Mais recente primeiro.
  static List<LocalBackup> list() {
    final box = _box;
    if (box == null) return const [];
    final keys = box.keys.cast<String>().toList()..sort();
    return [
      for (final k in keys.reversed)
        if (_decode(k, box.get(k)) case final b?) b,
    ];
  }

  static LocalBackup? _decode(String id, String? raw) {
    if (raw == null) return null;
    try {
      return LocalBackup._fromMap(id, jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String id) async => _box?.delete(id);

  /// Volta o aparelho para [backup]. Antes, guarda o estado atual (dá para
  /// desfazer a restauração).
  static Future<void> restore(LocalBackup backup) async {
    await create('Antes de restaurar');
    await SyncService.replaceLocal(
      backup.data,
      players: Hive.box<Player>('players'),
      tournaments: Hive.box<Tournament>('tournaments'),
    );
  }
}
