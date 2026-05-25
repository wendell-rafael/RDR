import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/team.dart';
import '../../data/models/tournament.dart';
import '../../data/repositories/tournament_repository.dart';
import '../../data/repositories/player_repository.dart';
import '../../widgets/star_rating.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tournaments = ref.watch(tournamentRepositoryProvider).getAll()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final finished = tournaments
        .where((t) => t.status == TournamentStatus.finished)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Torneios'),
            Tab(text: 'Jogadores'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _TournamentsTab(tournaments: finished),
          _PlayersStatsTab(),
        ],
      ),
    );
  }
}

// ── Tournaments Tab ──────────────────────────────────────────────────────────

class _TournamentsTab extends StatelessWidget {
  final List<Tournament> tournaments;

  const _TournamentsTab({required this.tournaments});

  @override
  Widget build(BuildContext context) {
    if (tournaments.isEmpty) {
      return const Center(child: Text('Nenhum torneio finalizado ainda.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tournaments.length,
      itemBuilder: (ctx, i) => _TournamentHistoryCard(t: tournaments[i]),
    );
  }
}

class _TournamentHistoryCard extends StatelessWidget {
  final Tournament t;

  const _TournamentHistoryCard({required this.t});

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Team? get champion =>
      t.teams.where((tm) => tm.id == t.championTeamId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final champ = champion;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _fmt(t.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.5),
                      ),
                ),
                const Spacer(),
                Text(
                  '${t.teams.length} times',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (champ != null) ...[
              Row(
                children: [
                  const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(champ.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    champ.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ] else
              Text(
                'Sem campeão definido',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.4),
                      fontStyle: FontStyle.italic,
                    ),
              ),
            const Divider(),
            Wrap(
              spacing: 8,
              children: t.teams.map((team) {
                return Chip(
                  label: Text(team.name),
                  avatar: CircleAvatar(
                    backgroundColor: Color(team.colorValue),
                    radius: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Players Stats Tab ────────────────────────────────────────────────────────

class _PlayersStatsTab extends ConsumerStatefulWidget {
  const _PlayersStatsTab();

  @override
  ConsumerState<_PlayersStatsTab> createState() => _PlayersStatsTabState();
}

class _PlayersStatsTabState extends ConsumerState<_PlayersStatsTab> {
  bool _sortByTitles = true;

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(playerRepositoryProvider).getAll();
    final sorted = List.from(players);

    if (_sortByTitles) {
      sorted.sort((a, b) {
        final byTitles = b.titles.compareTo(a.titles);
        return byTitles != 0 ? byTitles : b.goals.compareTo(a.goals);
      });
    } else {
      sorted.sort((a, b) {
        final byGoals = b.goals.compareTo(a.goals);
        return byGoals != 0 ? byGoals : b.titles.compareTo(a.titles);
      });
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<bool>(
            selected: {_sortByTitles},
            onSelectionChanged: (v) => setState(() => _sortByTitles = v.first),
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Por títulos'),
                icon: Icon(Icons.emoji_events),
              ),
              ButtonSegment(
                value: false,
                label: Text('Por gols'),
                icon: Icon(Icons.sports_soccer),
              ),
            ],
          ),
        ),
        Expanded(
          child: players.isEmpty
              ? const Center(child: Text('Nenhum jogador cadastrado.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: sorted.length,
                  itemBuilder: (ctx, i) {
                    final p = sorted[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(p.name[0].toUpperCase()),
                      ),
                      title: Text(p.name),
                      subtitle: StarRating(value: p.stars, size: 14),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.emoji_events,
                              size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text('${p.titles}'),
                          const SizedBox(width: 12),
                          const Icon(Icons.sports_soccer, size: 16),
                          const SizedBox(width: 4),
                          Text('${p.goals}'),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
