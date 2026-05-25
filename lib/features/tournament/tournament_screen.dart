import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/match_model.dart';
import '../../data/models/team.dart';
import '../../data/models/tournament.dart';
import '../tournament/standings_service.dart';
import '../tournament/tournament_provider.dart';

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

    // Se o torneio já foi finalizado, vai para a tela de campeão
    if (tournament.status == TournamentStatus.finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.goNamed('champion',
              pathParameters: {'id': tournament.id});
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
              const PopupMenuItem(
                  value: 'cancel', child: Text('Cancelar torneio')),
            ],
            onSelected: (v) async {
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
      body: TabBarView(
        controller: _tabs,
        children: [
          _MatchesTab(tournament: tournament),
          _StandingsTab(tournament: tournament),
          _FinalTab(tournament: tournament),
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
                'Deseja cancelar o torneio atual? O histórico será salvo sem campeão.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Não'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancelar torneio'),
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

    Color statusColor;
    switch (match.status) {
      case MatchStatus.pending:
        statusColor = cs.onSurface.withOpacity(0.4);
        break;
      case MatchStatus.inProgress:
        statusColor = Colors.orange;
        break;
      case MatchStatus.finished:
        statusColor = cs.primary;
        break;
    }

    return Card(
      child: InkWell(
        onTap: match.status != MatchStatus.finished && onTap != null ? onTap : null,
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
                            size: 14, color: Colors.orange),
                        SizedBox(width: 4),
                        Text('Em andamento',
                            style:
                                TextStyle(fontSize: 12, color: Colors.orange)),
                      ],
                    ),
                  if (match.status == MatchStatus.finished)
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: Colors.green),
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
            const Icon(Icons.emoji_events, size: 80, color: Colors.amber),
            const SizedBox(height: 16),
            Text(
              'CAMPEÃO',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 4,
                    color: Colors.amber,
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
