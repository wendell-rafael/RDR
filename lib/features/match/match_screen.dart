import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/goal_event.dart';
import '../../data/models/match_model.dart';
import '../../data/models/player.dart';
import '../../data/models/team.dart';
import '../../data/models/tournament.dart';
import '../../data/repositories/player_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../tournament/tournament_provider.dart';
import 'timer_provider.dart';

class MatchScreen extends ConsumerStatefulWidget {
  final String tournamentId;
  final String matchId;

  const MatchScreen(
      {super.key, required this.tournamentId, required this.matchId});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen>
    with WidgetsBindingObserver {
  int _homeScore = 0;
  int _awayScore = 0;
  final List<GoalEvent> _scorers = [];
  bool _timerStarted = false;
  int? _customDurationMinutes;

  MatchModel? get _match => ref
      .watch(activeTournamentProvider)
      ?.matches
      .where((m) => m.id == widget.matchId)
      .firstOrNull;

  Tournament? get _tournament => ref.watch(activeTournamentProvider);

  Team? _teamById(String id) =>
      _tournament?.teams.where((t) => t.id == id).firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final m = _match;
      if (m != null) {
        setState(() {
          _homeScore = m.homeScore ?? 0;
          _awayScore = m.awayScore ?? 0;
          _scorers.addAll(m.scorers);
        });
      }

      // Check if there's already an active timer for this match
      final settings = ref.read(settingsProvider);
      if (settings.timerMatchId == widget.matchId && settings.timerRunning) {
        _timerStarted = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(timerProvider.notifier).syncFromResume();
    }
  }

  Future<void> _startTimer() async {
    setState(() => _timerStarted = true);
    final duration = _customDurationMinutes != null
        ? Duration(minutes: _customDurationMinutes!)
        : null;
    await ref.read(timerProvider.notifier).start(
      matchId: widget.matchId,
      duration: duration,
    );

    // Mark match as in-progress
    final m = _match;
    if (m != null && m.status == MatchStatus.pending) {
      await ref.read(activeTournamentProvider.notifier).updateMatch(
            m.copyWith(status: MatchStatus.inProgress),
          );
    }
  }

  Future<void> _finishMatch() async {
    final m = _match;
    if (m == null) return;

    // Para fases eliminatórias empatadas, perguntar o vencedor nos pênaltis
    final isKnockout = m.phase != MatchPhase.group;
    final isDraw = _homeScore == _awayScore;
    String? penaltyWinnerId;

    if (isKnockout && isDraw) {
      penaltyWinnerId = await _askPenaltyWinner(m);
      if (penaltyWinnerId == null) return; // usuário cancelou
    }

    await ref.read(timerProvider.notifier).stop();

    final updated = m.copyWith(
      status: MatchStatus.finished,
      homeScore: _homeScore,
      awayScore: _awayScore,
      scorers: List<GoalEvent>.from(_scorers),
      penaltyWinnerId: penaltyWinnerId,
    );

    await ref.read(activeTournamentProvider.notifier).updateMatch(updated);

    if (!mounted) return;

    // Se a partida era a final, vai para a tela de campeão
    final freshTournament = ref.read(activeTournamentProvider);
    if (freshTournament?.status == TournamentStatus.finished) {
      context.goNamed('champion',
          pathParameters: {'id': widget.tournamentId});
    } else {
      context.pop();
    }
  }

  Future<String?> _askPenaltyWinner(MatchModel m) async {
    final home = _teamById(m.homeTeamId);
    final away = _teamById(m.awayTeamId);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Disputa de Pênaltis'),
        content: const Text(
            'A partida terminou empatada.\nQuem ganhou nos pênaltis?'),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          if (home != null)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(m.homeTeamId),
              style: FilledButton.styleFrom(
                backgroundColor: Color(home.colorValue),
                foregroundColor: Color(home.colorValue).computeLuminance() > 0.4
                    ? Colors.black
                    : Colors.white,
              ),
              child: Text(home.name),
            ),
          if (away != null)
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(m.awayTeamId),
              style: FilledButton.styleFrom(
                backgroundColor: Color(away.colorValue),
                foregroundColor: Color(away.colorValue).computeLuminance() > 0.4
                    ? Colors.black
                    : Colors.white,
              ),
              child: Text(away.name),
            ),
        ],
      ),
    );
  }

  Future<void> _changeDuration() async {
    const options = [5, 7, 10, 15, 20, 25, 30];
    const defaultRacha = 7;
    final settings = ref.read(settingsProvider);
    final current = _customDurationMinutes ?? settings.defaultMatchMinutes;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          int picked = current;
          return AlertDialog(
            title: const Text('Duração da partida'),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((min) {
                final isSelected = picked == min;
                final isDefault = min == defaultRacha;
                return ChoiceChip(
                  label: Text(
                    isDefault ? '$min min ★' : '$min min',
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    setS(() => picked = min);
                    Navigator.of(ctx).pop(min);
                  },
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) {
      setState(() => _customDurationMinutes = result);
    }
  }

  void _addGoal(String teamId, bool isHome) async {
    setState(() {
      if (isHome) {
        _homeScore++;
      } else {
        _awayScore++;
      }
    });
    // Optionally ask for scorer
    final team = _teamById(teamId);
    if (team == null) return;

    final players = ref.read(playerRepositoryProvider).getAll();
    final teamPlayers =
        players.where((p) => team.playerIds.contains(p.id)).toList();

    if (teamPlayers.isEmpty) return;

    final scorer = await _selectScorer(context, teamPlayers);
    if (scorer != null) {
      setState(() {
        _scorers.add(GoalEvent(playerId: scorer.id, teamId: teamId));
      });
    }
  }

  void _removeGoal(bool isHome) {
    setState(() {
      if (isHome && _homeScore > 0) _homeScore--;
      if (!isHome && _awayScore > 0) _awayScore--;
    });
  }

  Future<Player?> _selectScorer(
      BuildContext context, List<Player> players) async {
    return showModalBottomSheet<Player>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text(
            'Quem fez o gol?',
            style: Theme.of(ctx).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...players.map(
            (p) => ListTile(
              leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
              title: Text(p.name),
              onTap: () => Navigator.pop(ctx, p),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Não registrar'),
            onTap: () => Navigator.pop(ctx, null),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _match;
    final tournament = _tournament;

    if (m == null || tournament == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Partida')),
        body: const Center(child: Text('Partida não encontrada')),
      );
    }

    final home = _teamById(m.homeTeamId);
    final away = _teamById(m.awayTeamId);
    final timer = ref.watch(timerProvider);
    final isFinished = m.status == MatchStatus.finished;

    return Scaffold(
      appBar: AppBar(
        title: Text(home != null && away != null
            ? '${home.name} × ${away.name}'
            : 'Partida'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Timer Section
          _TimerWidget(
            timer: timer,
            matchId: widget.matchId,
            onStart: _timerStarted ? null : _startTimer,
            onPause: timer.running
                ? () => ref.read(timerProvider.notifier).pause()
                : null,
            onResume: (!timer.running && _timerStarted && !timer.finished)
                ? () => ref.read(timerProvider.notifier).resume()
                : null,
            customDurationMinutes: _timerStarted ? null : _customDurationMinutes,
            onChangeDuration: _timerStarted ? null : _changeDuration,
          ),
          const Divider(height: 1),

          // Score Section
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _TeamScoreColumn(
                          team: home,
                          score: _homeScore,
                          isFinished: isFinished,
                          onAdd: () => _addGoal(m.homeTeamId, true),
                          onRemove: () => _removeGoal(true),
                        ),
                      ),
                      Text(
                        '×',
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                      Expanded(
                        child: _TeamScoreColumn(
                          team: away,
                          score: _awayScore,
                          isFinished: isFinished,
                          onAdd: () => _addGoal(m.awayTeamId, false),
                          onRemove: () => _removeGoal(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  if (!isFinished)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _finishMatch,
                            icon: const Icon(Icons.sports_score),
                            label: const Text('Encerrar Partida'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 56),
                              backgroundColor: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (isFinished)
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Partida encerrada'),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerWidget extends StatelessWidget {
  final TimerState timer;
  final String matchId;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final int? customDurationMinutes;
  final VoidCallback? onChangeDuration;

  const _TimerWidget({
    required this.timer,
    required this.matchId,
    this.onStart,
    this.onPause,
    this.onResume,
    this.customDurationMinutes,
    this.onChangeDuration,
  });

  String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Se o timer ainda não foi iniciado e há um custom duration, usa ele
    final effectiveDuration = (onStart != null && customDurationMinutes != null)
        ? Duration(minutes: customDurationMinutes!)
        : timer.duration;
    final elapsed = timer.elapsed;
    final display = timer.isCountdown
        ? effectiveDuration - elapsed
        : elapsed;
    final isZero = timer.isCountdown && elapsed >= effectiveDuration;
    final cs = Theme.of(context).colorScheme;

    // Duração exibida quando o timer ainda não foi iniciado
    final showDurationHint = onStart != null;
    final durationLabel = customDurationMinutes != null
        ? '$customDurationMinutes min'
        : '${timer.duration.inMinutes} min';

    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(isZero ? Duration.zero : display),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isZero
                      ? cs.error
                      : (timer.running ? cs.primary : cs.onSurface),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (showDurationHint)
                GestureDetector(
                  onTap: onChangeDuration,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        durationLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit,
                        size: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (onStart != null)
            // Isola do FilledButtonTheme global (minimumSize: double.infinity)
            // para evitar overflow num Row
            Theme(
              data: Theme.of(context).copyWith(
                filledButtonTheme: const FilledButtonThemeData(),
              ),
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else if (onPause != null)
            IconButton.filled(
              onPressed: onPause,
              icon: const Icon(Icons.pause),
              tooltip: 'Pausar',
            )
          else if (onResume != null)
            IconButton.filled(
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Retomar',
            ),
        ],
      ),
    );
  }
}

class _TeamScoreColumn extends StatelessWidget {
  final Team? team;
  final int score;
  final bool isFinished;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _TeamScoreColumn({
    required this.team,
    required this.score,
    required this.isFinished,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = team != null ? Color(team!.colorValue) : Colors.grey;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 8),
        Text(
          team?.name ?? '?',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          '$score',
          style: Theme.of(context)
              .textTheme
              .displayLarge
              ?.copyWith(fontWeight: FontWeight.bold, fontSize: 72),
          textAlign: TextAlign.center,
        ),
        if (!isFinished) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                onPressed: score > 0 ? onRemove : null,
                icon: const Icon(Icons.remove),
                iconSize: 32,
                style: IconButton.styleFrom(
                  minimumSize: const Size(52, 52),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                iconSize: 32,
                style: IconButton.styleFrom(
                  minimumSize: const Size(52, 52),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
