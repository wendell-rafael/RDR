import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/tournament_repository.dart';
import '../../data/models/tournament.dart';
import '../../app/theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournamentRepo = ref.watch(tournamentRepositoryProvider);
    final activeTournament = tournamentRepo.getActive();

    return Scaffold(
      appBar: AppBar(
        title: const Text('⚽ Racha dos Ruins'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.pushNamed('settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (activeTournament != null) ...[
            _TournamentBanner(tournament: activeTournament),
            const SizedBox(height: 8),
          ],
          _HomeCard(
            icon: Icons.group_outlined,
            title: 'Jogadores',
            subtitle: 'Cadastrar, editar e ver estatísticas',
            color: AppTheme.homeAccents[0],
            onTap: () => context.pushNamed('players'),
          ),
          _HomeCard(
            icon: Icons.shuffle_rounded,
            title: 'Novo Sorteio',
            subtitle: 'Sortear times balanceados',
            color: AppTheme.homeAccents[1],
            onTap: () => context.pushNamed('draw'),
          ),
          if (activeTournament != null)
            _HomeCard(
              icon: Icons.emoji_events_outlined,
              title: 'Torneio em Andamento',
              subtitle: _tournamentSubtitle(activeTournament),
              color: AppTheme.homeAccents[2],
              onTap: () => context.pushNamed('tournament', pathParameters: {
                'id': activeTournament.id,
              }),
            ),
          _HomeCard(
            icon: Icons.history_rounded,
            title: 'Histórico',
            subtitle: 'Estatísticas e torneios passados',
            color: AppTheme.homeAccents[3],
            onTap: () => context.pushNamed('history'),
          ),
        ],
      ),
    );
  }

  String _tournamentSubtitle(Tournament t) {
    final finished = t.matches.where((m) => m.status.index == 2).length;
    final total = t.matches.length;
    return '${t.teams.length} times · $finished/$total partidas';
  }
}

class _TournamentBanner extends StatelessWidget {
  final Tournament tournament;

  const _TournamentBanner({required this.tournament});

  @override
  Widget build(BuildContext context) {
    final next = tournament.nextPendingMatch;
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.sports_soccer, color: cs.primary, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Torneio Ativo',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                      ),
                ),
                if (next != null)
                  Text(
                    _matchLabel(tournament, next),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _matchLabel(Tournament t, dynamic match) {
    final home = t.teams.where((tm) => tm.id == match.homeTeamId).firstOrNull;
    final away = t.teams.where((tm) => tm.id == match.awayTeamId).firstOrNull;
    return 'Próxima: ${home?.name ?? '?'} × ${away?.name ?? '?'}';
  }
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _HomeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
