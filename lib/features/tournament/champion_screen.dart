import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/player_repository.dart';
import '../draw/draw_provider.dart';
import '../tournament/tournament_provider.dart';
import '../../app/theme.dart';

class ChampionScreen extends ConsumerWidget {
  final String tournamentId;

  const ChampionScreen({super.key, required this.tournamentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournament = ref.watch(activeTournamentProvider);

    if (tournament == null) {
      // Torneio já foi fechado; volta à home
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final champion = tournament.champion;

    // Calcula artilheiro
    final goalCounts = <String, int>{};
    for (final m in tournament.matches) {
      for (final g in m.scorers) {
        goalCounts[g.playerId] = (goalCounts[g.playerId] ?? 0) + 1;
      }
    }

    String? artilheiroId;
    int maxGoals = 0;
    for (final entry in goalCounts.entries) {
      if (entry.value > maxGoals) {
        maxGoals = entry.value;
        artilheiroId = entry.key;
      }
    }

    final players = ref.read(playerRepositoryProvider).getAll();
    final artilheiro = artilheiroId != null
        ? players.where((p) => p.id == artilheiroId).firstOrNull
        : null;

    final cs = Theme.of(context).colorScheme;
    final teamColor =
        champion != null ? Color(champion.colorValue) : cs.primary;

    return PopScope(
      canPop: false, // impede voltar para a tela de partida
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Troféu
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.elasticOut,
                  builder: (_, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    size: 120,
                    color: AppTheme.gold,
                    shadows: const [
                      Shadow(color: AppTheme.warning, blurRadius: 24),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'CAMPEÃO',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        letterSpacing: 6,
                        color: AppTheme.gold,
                        fontWeight: FontWeight.bold,
                      ),
                ),

                const SizedBox(height: 12),

                if (champion != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: teamColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: teamColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        champion.name,
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    'Torneio encerrado',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),

                const SizedBox(height: 40),

                // Artilheiro
                if (artilheiro != null && maxGoals > 0)
                  Card(
                    color: cs.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sports_soccer,
                              size: 28, color: Colors.white70),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Artilheiro',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              Text(
                                artilheiro.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$maxGoals gol${maxGoals != 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const Spacer(),

                // Botão fechar
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await ref
                              .read(activeTournamentProvider.notifier)
                              .closeTournament();
                          ref.read(drawProvider.notifier).resetToDraw();
                          if (context.mounted) context.go('/');
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Fechar Torneio'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 56),
                          backgroundColor: AppTheme.gold,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
