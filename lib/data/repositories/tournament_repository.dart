import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import '../models/tournament.dart';

final tournamentBoxProvider = Provider<Box<Tournament>>((ref) {
  return Hive.box<Tournament>('tournaments');
});

class TournamentRepository {
  final Box<Tournament> _box;

  TournamentRepository(this._box);

  List<Tournament> getAll() =>
      _box.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Tournament? getById(String id) {
    try {
      return _box.values.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  Tournament? getActive() {
    try {
      return _box.values.firstWhere(
        (t) => t.status == TournamentStatus.active,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Tournament tournament) =>
      _box.put(tournament.id, tournament);

  Future<void> delete(String id) => _box.delete(id);
}

final tournamentRepositoryProvider = Provider<TournamentRepository>((ref) {
  return TournamentRepository(ref.watch(tournamentBoxProvider));
});
