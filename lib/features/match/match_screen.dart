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
import '../tournament/tie_service.dart';
import '../tournament/tournament_provider.dart';
import 'timer_provider.dart';
import '../../app/theme.dart';
import '../../widgets/dialog_action.dart';

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
  /// Duração escolhida antes de iniciar. Depois que o cronômetro roda, a
  /// duração vive em AppSettings para sobreviver a sair da tela.
  int? _customDurationMinutes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  // ── Leitura do estado atual ────────────────────────────────────────────────

  Tournament? _readTournament() => ref.read(activeTournamentProvider);

  MatchModel? _readMatch() => _readTournament()
      ?.matches
      .where((m) => m.id == widget.matchId)
      .firstOrNull;

  Team? _teamById(Tournament? tournament, String id) =>
      tournament?.teams.where((t) => t.id == id).firstOrNull;

  Future<void> _persist(MatchModel updated) =>
      ref.read(activeTournamentProvider.notifier).updateMatch(updated);

  // ── Cronômetro ─────────────────────────────────────────────────────────────

  Future<void> _startTimer() async {
    final duration = _customDurationMinutes != null
        ? Duration(minutes: _customDurationMinutes!)
        : null;
    await ref.read(timerProvider.notifier).start(
          matchId: widget.matchId,
          duration: duration,
        );

    final m = _readMatch();
    if (m != null && m.status == MatchStatus.pending) {
      await _persist(m.copyWith(status: MatchStatus.inProgress));
    }
  }

  Future<void> _changeDuration() async {
    const options = [5, 7, 10, 15, 20, 25, 30];
    const defaultRacha = 7;
    final settings = ref.read(settingsProvider);
    final current = _customDurationMinutes ?? settings.defaultMatchMinutes;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duração da partida'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((min) {
            return ChoiceChip(
              label: Text(min == defaultRacha ? '$min min ★' : '$min min'),
              selected: current == min,
              onSelected: (_) => Navigator.of(ctx).pop(min),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _customDurationMinutes = result);
    }
  }

  // ── Gols ───────────────────────────────────────────────────────────────────

  Future<void> _addGoal(String teamId, bool isHome) async {
    final m = _readMatch();
    if (m == null || m.status == MatchStatus.finished) return;

    // Grava o gol na hora: assim dá para sair da tela sem perder o placar.
    final withGoal = m.copyWith(
      status: MatchStatus.inProgress,
      homeScore: isHome ? (m.homeScore ?? 0) + 1 : (m.homeScore ?? 0),
      awayScore: isHome ? (m.awayScore ?? 0) : (m.awayScore ?? 0) + 1,
    );
    await _persist(withGoal);

    if (!mounted) return;
    final scorer = await _selectScorer(teamId);
    if (scorer == null) return;

    final current = _readMatch();
    if (current == null) return;
    await _persist(current.copyWith(
      scorers: [
        ...current.scorers,
        GoalEvent(playerId: scorer.id, teamId: teamId),
      ],
    ));
  }

  Future<void> _removeGoal(String teamId, bool isHome) async {
    final m = _readMatch();
    if (m == null || m.status == MatchStatus.finished) return;

    final currentScore = isHome ? (m.homeScore ?? 0) : (m.awayScore ?? 0);
    if (currentScore <= 0) return;

    // Tira também o último artilheiro registrado para esse time, senão a
    // lista de gols fica maior que o placar.
    final scorers = List<GoalEvent>.from(m.scorers);
    final lastIndex = scorers.lastIndexWhere((g) => g.teamId == teamId);
    if (lastIndex != -1) scorers.removeAt(lastIndex);

    await _persist(m.copyWith(
      homeScore: isHome ? currentScore - 1 : (m.homeScore ?? 0),
      awayScore: isHome ? (m.awayScore ?? 0) : currentScore - 1,
      scorers: scorers,
    ));
  }

  /// Lista todos os jogadores do banco, com os do time no topo — às vezes
  /// alguém de fora completa o time e marca.
  Future<Player?> _selectScorer(String teamId) async {
    final tournament = _readTournament();
    final team = _teamById(tournament, teamId);
    final all = ref.read(playerRepositoryProvider).getAll()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (all.isEmpty) return null;

    final teamPlayers =
        all.where((p) => team?.playerIds.contains(p.id) ?? false).toList();
    final others =
        all.where((p) => !(team?.playerIds.contains(p.id) ?? false)).toList();

    return showModalBottomSheet<Player>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ScorerPicker(
        teamName: team?.name ?? 'Time',
        teamPlayers: teamPlayers,
        otherPlayers: others,
      ),
    );
  }

  // ── Encerramento ───────────────────────────────────────────────────────────

  Future<void> _finishMatch() async {
    final tournament = _readTournament();
    final m = _readMatch();
    if (tournament == null || m == null) return;

    final homeScore = m.homeScore ?? 0;
    final awayScore = m.awayScore ?? 0;
    final legs = tournament.legsOf(m);
    final isKnockout = m.phase != MatchPhase.group;
    final isDecisive = TieService.isLastToFinish(legs, m);

    String? penaltyWinnerId;
    // No mata-mata, só a partida decisiva vai para os pênaltis — e pelo
    // agregado, não pelo placar do jogo. O jogo de ida pode acabar empatado.
    if (isKnockout &&
        isDecisive &&
        TieService.needsPenalties(
          legs,
          overrideMatchId: m.id,
          overrideHome: homeScore,
          overrideAway: awayScore,
        )) {
      penaltyWinnerId = await _askPenaltyWinner(tournament, legs);
      if (penaltyWinnerId == null) return; // usuário cancelou
    }

    await ref.read(timerProvider.notifier).stop();

    await _persist(m.copyWith(
      status: MatchStatus.finished,
      homeScore: homeScore,
      awayScore: awayScore,
      penaltyWinnerId: penaltyWinnerId,
    ));

    if (!mounted) return;

    final fresh = ref.read(activeTournamentProvider);
    if (fresh?.status == TournamentStatus.finished) {
      context.goNamed('champion', pathParameters: {'id': widget.tournamentId});
    } else {
      context.pop();
    }
  }

  Future<String?> _askPenaltyWinner(
      Tournament tournament, List<MatchModel> legs) async {
    final pair = TieService.teamsOf(legs);
    if (pair == null) return null;

    final home = _teamById(tournament, pair.$1);
    final away = _teamById(tournament, pair.$2);
    final twoLegged = legs.length > 1;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Disputa de Pênaltis'),
        content: Text(twoLegged
            ? 'O confronto terminou empatado no agregado.\nQuem ganhou nos pênaltis?'
            : 'A partida terminou empatada.\nQuem ganhou nos pênaltis?'),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          if (home != null) _penaltyButton(ctx, home),
          if (away != null) _penaltyButton(ctx, away),
        ],
      ),
    );
  }

  Widget _penaltyButton(BuildContext ctx, Team team) {
    final color = Color(team.colorValue);
    return DialogAction(
      child: FilledButton(
        onPressed: () => Navigator.of(ctx).pop(team.id),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor:
              color.computeLuminance() > 0.4 ? Colors.black : Colors.white,
        ),
        child: Text(team.name),
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tournament = ref.watch(activeTournamentProvider);
    final m = tournament?.matches
        .where((mm) => mm.id == widget.matchId)
        .firstOrNull;

    if (m == null || tournament == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Partida')),
        body: const Center(child: Text('Partida não encontrada')),
      );
    }

    final home = _teamById(tournament, m.homeTeamId);
    final away = _teamById(tournament, m.awayTeamId);
    final timer = ref.watch(timerProvider);
    final settings = ref.watch(settingsProvider);
    final isFinished = m.status == MatchStatus.finished;

    // O cronômetro pertence a esta partida enquanto não for encerrado.
    final timerStarted = settings.timerMatchId == widget.matchId;
    final legs = tournament.legsOf(m);

    return Scaffold(
      appBar: AppBar(
        title: Text(home != null && away != null
            ? '${home.name} × ${away.name}'
            : 'Partida'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _TimerWidget(
            timer: timer,
            onStart: timerStarted ? null : _startTimer,
            onPause: (timerStarted && timer.running)
                ? () => ref.read(timerProvider.notifier).pause()
                : null,
            onResume: (timerStarted && !timer.running && !timer.finished)
                ? () => ref.read(timerProvider.notifier).resume()
                : null,
            onAddMinutes: (timerStarted && !isFinished)
                ? (minutes) =>
                    ref.read(timerProvider.notifier).addMinutes(minutes)
                : null,
            customDurationMinutes: timerStarted ? null : _customDurationMinutes,
            onChangeDuration: timerStarted ? null : _changeDuration,
          ),
          const Divider(height: 1),

          if (legs.length > 1)
            _TieBanner(tournament: tournament, match: m, legs: legs),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _TeamScoreColumn(
                          team: home,
                          score: m.homeScore ?? 0,
                          isFinished: isFinished,
                          onAdd: () => _addGoal(m.homeTeamId, true),
                          onRemove: () => _removeGoal(m.homeTeamId, true),
                        ),
                      ),
                      Text(
                        '×',
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                      Expanded(
                        child: _TeamScoreColumn(
                          team: away,
                          score: m.awayScore ?? 0,
                          isFinished: isFinished,
                          onAdd: () => _addGoal(m.awayTeamId, false),
                          onRemove: () => _removeGoal(m.awayTeamId, false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _ScorersList(match: m, tournament: tournament),
                  const SizedBox(height: 24),
                  if (!isFinished)
                    FilledButton.icon(
                      onPressed: _finishMatch,
                      icon: const Icon(Icons.sports_score),
                      label: const Text('Encerrar Partida'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: AppTheme.success),
                        SizedBox(width: 8),
                        Text('Partida encerrada'),
                      ],
                    ),
                  if (!isFinished) ...[
                    const SizedBox(height: 12),
                    Text(
                      'O cronômetro continua rodando se você voltar para ver a tabela.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Faixa de ida e volta ──────────────────────────────────────────────────────

class _TieBanner extends StatelessWidget {
  final Tournament tournament;
  final MatchModel match;
  final List<MatchModel> legs;

  const _TieBanner({
    required this.tournament,
    required this.match,
    required this.legs,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pair = TieService.teamsOf(legs);

    String teamName(String id) =>
        tournament.teams.where((t) => t.id == id).firstOrNull?.name ?? '?';

    final legLabel = match.leg == 1 ? 'Jogo de ida' : 'Jogo de volta';

    String aggregateLabel = '';
    if (pair != null) {
      final totals = TieService.aggregate(legs);
      aggregateLabel = 'Agregado: ${teamName(pair.$1)} '
          '${totals[pair.$1] ?? 0} × ${totals[pair.$2] ?? 0} '
          '${teamName(pair.$2)}';
    }

    return Container(
      width: double.infinity,
      color: cs.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.repeat, size: 14, color: cs.onSecondaryContainer),
              const SizedBox(width: 6),
              Text(
                legLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          if (aggregateLabel.isNotEmpty)
            Text(
              aggregateLabel,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSecondaryContainer),
            ),
        ],
      ),
    );
  }
}

// ── Lista de artilheiros da partida ──────────────────────────────────────────

class _ScorersList extends ConsumerWidget {
  final MatchModel match;
  final Tournament tournament;

  const _ScorersList({required this.match, required this.tournament});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (match.scorers.isEmpty) return const SizedBox.shrink();

    final repo = ref.watch(playerRepositoryProvider);
    final counts = <(String, String), int>{};
    for (final g in match.scorers) {
      final key = (g.teamId, g.playerId);
      counts[key] = (counts[key] ?? 0) + 1;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: counts.entries.map((e) {
        final team =
            tournament.teams.where((t) => t.id == e.key.$1).firstOrNull;
        final name = repo.getById(e.key.$2)?.name ?? 'Removido';
        final color = team != null ? Color(team.colorValue) : Colors.grey;
        return Chip(
          avatar: CircleAvatar(backgroundColor: color, radius: 6),
          label: Text(e.value > 1 ? '$name (${e.value})' : name),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }
}

// ── Seletor de artilheiro ────────────────────────────────────────────────────

class _ScorerPicker extends StatefulWidget {
  final String teamName;
  final List<Player> teamPlayers;
  final List<Player> otherPlayers;

  const _ScorerPicker({
    required this.teamName,
    required this.teamPlayers,
    required this.otherPlayers,
  });

  @override
  State<_ScorerPicker> createState() => _ScorerPickerState();
}

class _ScorerPickerState extends State<_ScorerPicker> {
  String _query = '';

  bool _matches(Player p) =>
      _query.isEmpty || p.name.toLowerCase().contains(_query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final team = widget.teamPlayers.where(_matches).toList();
    final others = widget.otherPlayers.where(_matches).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Text(
              'Quem fez o gol?',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                autofocus: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar jogador',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  if (team.isNotEmpty) _sectionLabel(ctx, widget.teamName),
                  ...team.map((p) => _playerTile(ctx, p)),
                  if (others.isNotEmpty)
                    _sectionLabel(ctx, 'Completou para o time'),
                  ...others.map((p) => _playerTile(ctx, p)),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.close),
                    title: const Text('Não registrar'),
                    onTap: () => Navigator.pop(ctx, null),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );

  Widget _playerTile(BuildContext context, Player p) => ListTile(
        leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
        title: Text(p.name),
        onTap: () => Navigator.pop(context, p),
      );
}

// ── Cronômetro ───────────────────────────────────────────────────────────────

class _TimerWidget extends StatelessWidget {
  final TimerState timer;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final void Function(int minutes)? onAddMinutes;
  final int? customDurationMinutes;
  final VoidCallback? onChangeDuration;

  const _TimerWidget({
    required this.timer,
    this.onStart,
    this.onPause,
    this.onResume,
    this.onAddMinutes,
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
    final effectiveDuration = (onStart != null && customDurationMinutes != null)
        ? Duration(minutes: customDurationMinutes!)
        : timer.duration;
    final elapsed = timer.elapsed;
    final display = timer.isCountdown ? effectiveDuration - elapsed : elapsed;
    final isZero = timer.isCountdown && elapsed >= effectiveDuration;
    final cs = Theme.of(context).colorScheme;

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
                      Icon(Icons.edit, size: 12, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              if (onAddMinutes != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AddMinutesButton(
                      label: '+1 min',
                      onPressed: () => onAddMinutes!(1),
                    ),
                    const SizedBox(width: 8),
                    _AddMinutesButton(
                      label: '+5 min',
                      onPressed: () => onAddMinutes!(5),
                    ),
                  ],
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

class _AddMinutesButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _AddMinutesButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: VisualDensity.compact,
        textStyle: Theme.of(context).textTheme.labelSmall,
      ),
      child: Text(label),
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
