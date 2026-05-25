import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import '../models/app_settings.dart';

final settingsBoxProvider = Provider<Box<AppSettings>>((ref) {
  return Hive.box<AppSettings>('settings');
});

class SettingsRepository {
  static const _key = 'settings';
  final Box<AppSettings> _box;

  SettingsRepository(this._box);

  AppSettings get() {
    return _box.get(_key) ?? AppSettings();
  }

  Future<void> save(AppSettings settings) => _box.put(_key, settings);
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(settingsBoxProvider));
});

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    return ref.read(settingsRepositoryProvider).get();
  }

  Future<void> update(AppSettings settings) async {
    await ref.read(settingsRepositoryProvider).save(settings);
    state = settings;
  }

  Future<void> setActiveTournament(String? id) async {
    final updated = state..activeTournamentId = id;
    await ref.read(settingsRepositoryProvider).save(updated);
    state = AppSettings(
      defaultMatchMinutes: updated.defaultMatchMinutes,
      timerDirection: updated.timerDirection,
      soundEnabled: updated.soundEnabled,
      vibrationEnabled: updated.vibrationEnabled,
      activeTournamentId: id,
      timerStartEpochMs: updated.timerStartEpochMs,
      timerDurationMs: updated.timerDurationMs,
      timerPausedOffsetMs: updated.timerPausedOffsetMs,
      timerRunning: updated.timerRunning,
      timerMatchId: updated.timerMatchId,
    );
  }
}
