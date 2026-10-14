import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/match_model.dart';
import '../../data/models/team.dart';
import '../../data/models/tournament.dart';
import '../../data/repositories/player_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/whatsapp_export.dart';
import '../match/timer_provider.dart';
import '../tournament/standings_service.dart';
import '../tournament/tie_service.dart';
import '../tournament/tournament_provider.dart';
import '../../app/theme.dart';
import '../../widgets/dialog_action.dart';

class TournamentScreen extends ConsumerStatefulWidget {
  final String tournamentId;

  const TournamentScreen({super.key, required this.tournamentId});

  @override
  ConsumerState<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends ConsumerState<TournamentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tournament = ref.watch(activeTournamentProvider);

    if (tournament == null) {
      // Torneio encerrado ou não encontrado — redireciona para home
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Se o torneio já foi finalizado, vai para a tela de campeão. Só quando
    // esta tela está visível: ela fica embaixo da de campeão na pilha, e
    // redirecionar de lá derrubaria a partida aberta por cima (corrigir final).
    if (tournament.status == TournamentStatus.finished &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.goNamed('champion', pathParameters: {'id': tournament.id});
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_formatTitle(tournament.format)),
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: Text('Copiar tabela')),
              const PopupMenuItem(
                  value: 'share', child: Text('Compartilhar tabela')),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: 'test',
                checked: tournament.isTest,
                child: const Text('Torneio de teste'),
              ),
              const PopupMenuItem(
                  value: 'cancel', child: Text('Cancelar torneio')),
            ],
            onSelected: (v) async {
              if (v == 'copy' || v == 'share') {
                final message = WhatsAppExport.standings(
                  tournament,
                  ref.read(playerRepositoryProvider).getAll(),
                );
                if (v == 'copy') {
                  if (context.mounted) {
                    await ShareActions.copy(context, message);
                  }
                } else {
                  await ShareActions.share(message);
                }
                return;
              }
              if (v == 'test') {
                await ref
                    .read(activeTournamentProvider.notifier)
                    .setTest(!tournament.isTest);
                return;
              }
              if (v == 'cancel') {
                final confirmed = await _confirmCancel(context);
                if (confirmed && context.mounted) {
                  await ref
                      .read(activeTournamentProvider.notifier)
                      .cancelTournament();
                  if (context.mounted) context.goNamed('home');
                }
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Confrontos'),
            Tab(text: 'Classificação'),
            Tab(text: 'Mata-Mata'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (tournament.isTest) const _TestBanner(),
          _RunningMatchBanner(tournament: tournament),
          _StuckTieBanner(tournament: tournament),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _MatchesTab(tournament: tournament),
                _StandingsTab(tournament: tournament),
                _FinalTab(tournament: tournament),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTitle(TournamentFormat f) {
    switch (f) {
      case TournamentFormat.twoTeams:
        return 'Final Direta';
      case TournamentFormat.threeTeams:
        return 'Torneio (3 times)';
      case TournamentFormat.fourTeams:
        return 'Torneio (4 times)';
      case TournamentFormat.fiveTeams:
        return 'Torneio (5 times)';
    }
  }

  Future<bool> _confirmCancel(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cancelar torneio'),
            content: const Text(
                'Deseja cancelar o torneio atual? Ele é apagado e não fica no histórico.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Não'),
              ),
              DialogAction(
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Cancelar torneio'),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}

// ── Matches Tab ──────────────────────────────────────────────────────────────

class _MatchesTab extends ConsumerWidget {
  final Tournament tournament;

  const _MatchesTab({required this.tournament});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allMatches = [
      ...tournament.groupMatches,
      ...tournament.playoffMatches,
      ...tournament.semifinalMatches,
      ...tournament.finalMatches,
    ];

    // Show all matches; knockout slots with empty IDs show "A definir"
    return ListView(
      padding: const EdgeInsets.all(12),
      children: allMatches.map((m) {
        final hasTeams = m.homeTeamId.isNotEmpty && m.awayTeamId.isNotEmpty;
        return _MatchCard(
          match: m,
          tournament: tournament,
          onTap: hasTeams
              ? () => context.pushNamed(
                    'match',
                    pathParameters: {
                      'id': tournament.id,
                      'matchId': m.id,
                    },
                  )
              : null,
        );
      }).toList(),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final MatchModel match;
  final Tournament tournament;
  final VoidCallback? onTap;

  const _MatchCard({
    required this.match,
    required this.tournament,
    required this.onTap,
  });

  Team? _team(String id) =>
      tournament.teams.where((t) => t.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final home = _team(match.homeTeamId);
    final away = _team(match.awayTeamId);
    final cs = Theme.of(context).colorScheme;

    String phaseLabel;
    switch (match.phase) {
      case MatchPhase.playoff:
        phaseLabel = 'PLAY-IN';
        break;
      case MatchPhase.group:
        phaseLabel = 'GRUPOS';
        break;
      case MatchPhase.semifinal:
        phaseLabel = 'SEMI';
        break;
      case MatchPhase.finalMatch:
        phaseLabel = 'FINAL';
        break;
    }
    if (match.isTwoLegged) {
      phaseLabel += match.leg == 1 ? ' · IDA' : ' · VOLTA';
    }

    Color statusColor;
    switch (match.status) {
      case MatchStatus.pending:
        statusColor = cs.onSurface.withValues(alpha: 0.4);
        break;
      case MatchStatus.inProgress:
        statusColor = AppTheme.warning;
        break;
      case MatchStatus.finished:
        statusColor = cs.primary;
        break;
    }

    return Card(
      child: InkWell(
        // Partida encerrada também abre, para conferir ou corrigir.
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    phaseLabel,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: statusColor),
                  ),
                  if (match.status == MatchStatus.inProgress)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sports_soccer,
                            size: 14, color: AppTheme.warning),
                        SizedBox(width: 4),
                        Text('Em andamento',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.warning)),
                      ],
                    ),
                  if (match.status == MatchStatus.finished)
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: AppTheme.success),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TeamInfo(team: home, align: TextAlign.left),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: match.status == MatchStatus.finished
                        ? Text(
                            '${match.homeScore} × ${match.awayScore}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          )
                        : Text(
                            'vs',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                  ),
                  Expanded(
                    child: _TeamInfo(team: away, align: TextAlign.right),
                  ),
                ],
              ),
              if (match.isTwoLegged && match.leg == 2) _aggregateLine(context),
            ],
          ),
        ),
      ),
    );
  }

  /// No jogo de volta, mostra como está o confronto somando os dois jogos.
  Widget _aggregateLine(BuildContext context) {
    final legs = tournament.legsOf(match);
    final pair = TieService.teamsOf(legs);
    if (pair == null) return const SizedBox.shrink();

    final totals = TieService.aggregate(legs);
    final nameA = _team(pair.$1)?.name ?? '?';
    final nameB = _team(pair.$2)?.name ?? '?';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Agregado: $nameA ${totals[pair.$1] ?? 0} × '
        '${totals[pair.$2] ?? 0} $nameB',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

// ── Torneio de teste ─────────────────────────────────────────────────────────

class _TestBanner extends StatelessWidget {
  const _TestBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.science_outlined,
                size: 18, color: cs.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Torneio de teste: não vai para o site nem conta título/gols.',
                style: TextStyle(color: cs.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Confronto travado ────────────────────────────────────────────────────────

/// Um confronto pode terminar completo e sem vencedor: agregado empatado e
/// nenhum pênalti registrado. Nesse estado a fase seguinte não avança, e sem
/// esta faixa não haveria como destravar — a partida já está encerrada, então
/// o botão de encerrar não aparece mais.
class _StuckTieBanner extends ConsumerWidget {
  final Tournament tournament;

  const _StuckTieBanner({required this.tournament});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    for (final phase in [
      MatchPhase.playoff,
      MatchPhase.semifinal,
      MatchPhase.finalMatch,
    ]) {
      for (final legs in TieService.tiesOfPhase(tournament, phase)) {
        if (TieService.needsPenaltyDecision(legs)) {
          return _banner(context, ref, legs);
        }
      }
    }
    return const SizedBox.shrink();
  }

  Widget _banner(BuildContext context, WidgetRef ref, List<MatchModel> legs) {
    final cs = Theme.of(context).colorScheme;
    final pair = TieService.teamsOf(legs)!;
    final totals = TieService.aggregate(legs);

    Team? team(String id) =>
        tournament.teams.where((t) => t.id == id).firstOrNull;

    final a = team(pair.$1);
    final b = team(pair.$2);

    return Material(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 20, color: cs.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Confronto empatado no agregado',
                    style: TextStyle(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${a?.name ?? '?'} ${totals[pair.$1] ?? 0} × '
              '${totals[pair.$2] ?? 0} ${b?.name ?? '?'} — '
              'o torneio só avança depois dos pênaltis.',
              style: TextStyle(color: cs.onErrorContainer),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.sports_soccer),
              label: const Text('Decidir nos pênaltis'),
              onPressed: () => _decide(context, ref, legs, a, b),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref,
      List<MatchModel> legs, Team? a, Team? b) async {
    Widget button(BuildContext ctx, Team t) {
      final color = Color(t.colorValue);
      return DialogAction(
        child: FilledButton(
          onPressed: () => Navigator.of(ctx).pop(t.id),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor:
                color.computeLuminance() > 0.4 ? Colors.black : Colors.white,
          ),
          child: Text(t.name),
        ),
      );
    }

    final winner = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disputa de Pênaltis'),
        content: const Text(
            'O confronto terminou empatado no agregado.\nQuem ganhou nos pênaltis?'),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          if (a != null) button(ctx, a),
          if (b != null) button(ctx, b),
        ],
      ),
    );
    if (winner == null) return;

    // Grava na última partida do confronto e reprocessa o avanço de fase:
    // updateMatch dispara o preenchimento porque o status já é `finished`.
    final decisive = TieService.decisiveLeg(legs);
    await ref
        .read(activeTournamentProvider.notifier)
        .updateMatch(decisive.copyWith(penaltyWinnerId: winner));
  }
}

// ── Faixa da partida em andamento ────────────────────────────────────────────

/// Mostra o cronômetro correndo quando você sai da partida para ver a tabela,
/// com atalho para voltar.
class _RunningMatchBanner extends ConsumerWidget {
  final Tournament tournament;

  const _RunningMatchBanner({required this.tournament});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final matchId = settings.timerMatchId;
    if (matchId == null) return const SizedBox.shrink();

    final match = tournament.matches.where((m) => m.id == matchId).firstOrNull;
    if (match == null || match.status == MatchStatus.finished) {
      return const SizedBox.shrink();
    }

    final timer = ref.watch(timerProvider);
    final cs = Theme.of(context).colorScheme;

    String teamName(String id) =>
        tournament.teams.where((t) => t.id == id).firstOrNull?.name ?? '?';

    final display =
        timer.isCountdown ? timer.duration - timer.elapsed : timer.elapsed;
    final clamped = display.isNegative ? Duration.zero : display;
    final minutes = clamped.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = clamped.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Material(
      color: timer.running ? cs.primaryContainer : cs.surfaceContainerHighest,
      child: InkWell(
        onTap: () => context.pushNamed(
          'match',
          pathParameters: {'id': tournament.id, 'matchId': match.id},
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                timer.running
                    ? Icons.timer_outlined
                    : Icons.pause_circle_outline,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                '$minutes:$seconds',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${teamName(match.homeTeamId)} ${match.homeScore ?? 0} × '
                  '${match.awayScore ?? 0} ${teamName(match.awayTeamId)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamInfo extends StatelessWidget {
  final Team? team;
  final TextAlign align;

  const _TeamInfo({required this.team, required this.align});

  @override
  Widget build(BuildContext context) {
    if (team == null) {
      return Text(
        'A definir',
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontStyle: FontStyle.italic),
        textAlign: align,
      );
    }
    final color = Color(team!.colorValue);
    return Column(
      crossAxisAlignment: align == TextAlign.left
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 4),
        Text(
          team!.name,
          style: Theme.of(context).textTheme.titleSmall,
          textAlign: align,
        ),
      ],
    );
  }
}

// ── Standings Tab ────────────────────────────────────────────────────────────

class _StandingsTab extends StatelessWidget {
  final Tournament tournament;

  const _StandingsTab({required this.tournament});

  @override
  Widget build(BuildContext context) {
    if (tournament.groupMatches.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Formato sem fase de grupos',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final standings = StandingsService.compute(tournament);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _StandingsTable(standings: standings, tournament: tournament),
          ],
        ),
      ),
    );
  }
}

class _StandingsTable extends StatelessWidget {
  final List<Standing> standings;
  final Tournament tournament;

  const _StandingsTable({required this.standings, required this.tournament});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodySmall;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(28),
            1: FlexColumnWidth(),
            2: FixedColumnWidth(36),
            3: FixedColumnWidth(36),
            4: FixedColumnWidth(36),
            5: FixedColumnWidth(36),
            6: FixedColumnWidth(42),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
              ),
              children: [
                _th(context, '#'),
                _th(context, 'Time'),
                _th(context, 'J'),
                _th(context, 'V'),
                _th(context, 'E'),
                _th(context, 'SG'),
                _th(context, 'Pts'),
              ],
            ),
            ...standings.asMap().entries.map((e) {
              final s = e.value;
              final color = Color(s.team.colorValue);
              return TableRow(
                children: [
                  _td(context, '${e.key + 1}'),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(s.team.name,
                              style: textStyle,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                  _td(context, '${s.played}'),
                  _td(context, '${s.wins}'),
                  _td(context, '${s.draws}'),
                  _td(context, '${s.goalDiff > 0 ? '+' : ''}${s.goalDiff}'),
                  _tdBold(context, '${s.points}'),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _th(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _td(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _tdBold(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Mata-Mata Tab ─────────────────────────────────────────────────────────────

class _FinalTab extends ConsumerWidget {
  final Tournament tournament;

  const _FinalTab({required this.tournament});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final champion = tournament.champion;

    if (champion != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, size: 80, color: AppTheme.gold),
            const SizedBox(height: 16),
            Text(
              'CAMPEÃO',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 4,
                    color: AppTheme.gold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              champion.name,
              style: Theme.of(context)
                  .textTheme
                  .displaySmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    final knockoutMatches = [
      ...tournament.playoffMatches,
      ...tournament.semifinalMatches,
      ...tournament.finalMatches,
    ];

    if (knockoutMatches.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'O mata-mata será definido após a fase de grupos',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: knockoutMatches.map((m) {
        final hasTeams = m.homeTeamId.isNotEmpty && m.awayTeamId.isNotEmpty;
        return _MatchCard(
          match: m,
          tournament: tournament,
          onTap: hasTeams
              ? () => context.pushNamed(
                    'match',
                    pathParameters: {
                      'id': tournament.id,
                      'matchId': m.id,
                    },
                  )
              : null,
        );
      }).toList(),
    );
  }
}
