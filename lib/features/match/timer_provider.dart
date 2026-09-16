import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../data/models/app_settings.dart';
import '../../data/repositories/settings_repository.dart';
import 'timer_task_handler.dart';

class TimerState {
  final Duration elapsed;
  final Duration duration;
  final bool running;
  final TimerDirection direction;
  final bool finished;

  const TimerState({
    required this.elapsed,
    required this.duration,
    required this.running,
    required this.direction,
    this.finished = false,
  });

  Duration get remaining => duration - elapsed;
  bool get isCountdown => direction == TimerDirection.countdown;
  double get progress => duration.inMilliseconds == 0
      ? 0
      : elapsed.inMilliseconds / duration.inMilliseconds;

  TimerState copyWith({
    Duration? elapsed,
    Duration? duration,
    bool? running,
    TimerDirection? direction,
    bool? finished,
  }) =>
      TimerState(
        elapsed: elapsed ?? this.elapsed,
        duration: duration ?? this.duration,
        running: running ?? this.running,
        direction: direction ?? this.direction,
        finished: finished ?? this.finished,
      );
}

final timerProvider =
    NotifierProvider<TimerNotifier, TimerState>(TimerNotifier.new);

class TimerNotifier extends Notifier<TimerState> {
  Timer? _ticker;

  @override
  TimerState build() {
    final settings = ref.watch(settingsProvider);
    ref.onDispose(() => _ticker?.cancel());

    final initial = _stateFromSettings(settings);
    // Qualquer gravação em settings recria este notifier e cancela o ticker.
    // Religar aqui mantém o relógio andando quando se sai da tela da partida.
    if (initial.running && !initial.finished) {
      _startTicker();
    } else {
      _ticker?.cancel();
    }
    return initial;
  }

  TimerState _stateFromSettings(AppSettings s) {
    final duration = Duration(
        milliseconds: s.timerDurationMs ?? (s.defaultMatchMinutes * 60 * 1000));
    final pausedOffset = Duration(milliseconds: s.timerPausedOffsetMs ?? 0);

    Duration elapsed;
    if (s.timerRunning && s.timerStartEpochMs != null) {
      final started = DateTime.fromMillisecondsSinceEpoch(s.timerStartEpochMs!);
      elapsed = DateTime.now().difference(started) + pausedOffset;
      if (elapsed > duration) elapsed = duration;
    } else {
      elapsed = pausedOffset;
    }

    return TimerState(
      elapsed: elapsed,
      duration: duration,
      running: s.timerRunning,
      direction: s.timerDirection,
      finished: elapsed >= duration && s.timerRunning,
    );
  }

  Future<void> start({required String matchId, Duration? duration}) async {
    final settings = ref.read(settingsProvider);
    final d = duration ?? Duration(minutes: settings.defaultMatchMinutes);

    await ref.read(settingsProvider.notifier).update(
          settings.copyWith(
            timerRunning: true,
            timerStartEpochMs: DateTime.now().millisecondsSinceEpoch,
            timerDurationMs: d.inMilliseconds,
            timerPausedOffsetMs: 0,
            timerMatchId: matchId,
          ),
        );

    await _startForegroundService();
    _startTicker();
  }

  Future<void> pause() async {
    _ticker?.cancel();
    final settings = ref.read(settingsProvider);
    final currentElapsed = state.elapsed.inMilliseconds;

    await ref.read(settingsProvider.notifier).update(
          settings.copyWith(
            timerRunning: false,
            timerPausedOffsetMs: currentElapsed,
            timerStartEpochMs: null,
          ),
        );

    if (!kIsWeb) await FlutterForegroundTask.stopService();
    state = state.copyWith(running: false);
  }

  Future<void> resume() async {
    final settings = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).update(
          settings.copyWith(
            timerRunning: true,
            timerStartEpochMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );

    await _startForegroundService();
    _startTicker();
  }

  /// Estende a partida em andamento. Se o tempo já tinha zerado, o cronômetro
  /// volta a correr com o tempo extra.
  Future<void> addMinutes(int minutes) async {
    if (minutes == 0) return;
    final settings = ref.read(settingsProvider);
    final currentMs = settings.timerDurationMs ??
        (settings.defaultMatchMinutes * 60 * 1000);
    final newMs = currentMs + minutes * 60 * 1000;
    if (newMs < 60 * 1000) return; // não deixa cair abaixo de 1 minuto

    await ref.read(settingsProvider.notifier).update(
          settings.copyWith(timerDurationMs: newMs),
        );

    final updated = _stateFromSettings(ref.read(settingsProvider));
    state = updated;
    if (updated.running) {
      await _startForegroundService();
      _startTicker();
    }
  }

  Future<void> stop() async {
    _ticker?.cancel();
    final settings = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).update(
          settings.copyWith(
            timerRunning: false,
            timerStartEpochMs: null,
            timerDurationMs: null,
            timerPausedOffsetMs: null,
            timerMatchId: null,
          ),
        );

    if (!kIsWeb) await FlutterForegroundTask.stopService();
    state = state.copyWith(running: false, elapsed: Duration.zero);
  }

  void syncFromResume() {
    final settings = ref.read(settingsProvider);
    if (!settings.timerRunning) return;
    // Recalcula o estado a partir do epoch e reinicia o ticker
    state = _stateFromSettings(settings);
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final settings = ref.read(settingsProvider);
      final newState = _stateFromSettings(settings);
      state = newState;

      if (newState.elapsed >= newState.duration && newState.running) {
        _ticker?.cancel();
        // Mark as finished
        state = state.copyWith(running: false, finished: true);
      }
    });
  }

  Future<void> _startForegroundService() async {
    if (kIsWeb) return;
    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: 'Cronômetro',
      notificationText: 'Partida em andamento',
      callback: startCallback,
    );
  }
}
