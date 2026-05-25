import 'package:hive_ce/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 9)
enum TimerDirection {
  @HiveField(0)
  countdown,
  @HiveField(1)
  countup,
}

@HiveType(typeId: 10)
class AppSettings extends HiveObject {
  @HiveField(0)
  int defaultMatchMinutes;

  @HiveField(1)
  TimerDirection timerDirection;

  @HiveField(2)
  bool soundEnabled;

  @HiveField(3)
  bool vibrationEnabled;

  @HiveField(4)
  String? activeTournamentId;

  @HiveField(5)
  int? timerStartEpochMs;

  @HiveField(6)
  int? timerDurationMs;

  @HiveField(7)
  int? timerPausedOffsetMs;

  @HiveField(8)
  bool timerRunning;

  @HiveField(9)
  String? timerMatchId;

  AppSettings({
    this.defaultMatchMinutes = 7,
    this.timerDirection = TimerDirection.countdown,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.activeTournamentId,
    this.timerStartEpochMs,
    this.timerDurationMs,
    this.timerPausedOffsetMs,
    this.timerRunning = false,
    this.timerMatchId,
  });

  AppSettings copyWith({
    int? defaultMatchMinutes,
    TimerDirection? timerDirection,
    bool? soundEnabled,
    bool? vibrationEnabled,
    Object? activeTournamentId = _sentinel,
    Object? timerStartEpochMs = _sentinel,
    Object? timerDurationMs = _sentinel,
    Object? timerPausedOffsetMs = _sentinel,
    bool? timerRunning,
    Object? timerMatchId = _sentinel,
  }) {
    return AppSettings(
      defaultMatchMinutes: defaultMatchMinutes ?? this.defaultMatchMinutes,
      timerDirection: timerDirection ?? this.timerDirection,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      activeTournamentId: activeTournamentId == _sentinel
          ? this.activeTournamentId
          : activeTournamentId as String?,
      timerStartEpochMs: timerStartEpochMs == _sentinel
          ? this.timerStartEpochMs
          : timerStartEpochMs as int?,
      timerDurationMs: timerDurationMs == _sentinel
          ? this.timerDurationMs
          : timerDurationMs as int?,
      timerPausedOffsetMs: timerPausedOffsetMs == _sentinel
          ? this.timerPausedOffsetMs
          : timerPausedOffsetMs as int?,
      timerRunning: timerRunning ?? this.timerRunning,
      timerMatchId: timerMatchId == _sentinel
          ? this.timerMatchId
          : timerMatchId as String?,
    );
  }
}

const _sentinel = Object();
