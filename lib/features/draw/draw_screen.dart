import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/player.dart';
import '../../data/repositories/player_repository.dart';
import '../../data/services/whatsapp_export.dart';
import '../../widgets/star_rating.dart';
import 'draw_provider.dart';
import 'import_names_screen.dart';

class DrawScreen extends ConsumerWidget {
  const DrawScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(drawProvider);
    final allPlayers = ref.watch(playerRepositoryProvider).getAll()
      ..sort((a, b) => b.stars.compareTo(a.stars));

    if (state.teams != null) {
      return _DrawResultScreen(players: allPlayers);
    }
    return _DrawConfigScreen(players: allPlayers);
  }
}

// ── Config ──────────────────────────────────────────────────────────────────

class _DrawConfigScreen extends ConsumerWidget {
  final List<Player> players;

  const _DrawConfigScreen({required this.players});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(drawProvider);
    final notifier = ref.read(drawProvider.notifier);

    final canDraw = state.selectedPlayerIds.length >= state.teamCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sorteio de Times'),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Importar lista de nomes',
            onPressed: () => _importNames(context, ref),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: canDraw ? notifier.draw : null,
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text('Sortear Times'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Team count selector
          Text(
            'Número de times',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: List.generate(4, (i) {
              final n = i + 2;
              return ChoiceChip(
                label: Text('$n times'),
                selected: state.teamCount == n,
                onSelected: (_) => notifier.setTeamCount(n),
              );
            }),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: state.twoLegged,
            onChanged: notifier.setTwoLegged,
            contentPadding: EdgeInsets.zero,
            title: const Text('Ida e volta no mata-mata'),
            subtitle: const Text(
              'Semifinais e final em dois jogos, decididos pelo placar '
              'agregado. Empatou no agregado, vai para os pênaltis.',
            ),
          ),
          const SizedBox(height: 8),
          if (state.unmatchedImportedNames.isNotEmpty)
            _UnmatchedNamesCard(
              names: state.unmatchedImportedNames,
              onDismiss: notifier.clearUnmatchedNames,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Jogadores presentes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: notifier.selectAllPlayers,
                child: const Text('Todos'),
              ),
              TextButton(
                onPressed: state.selectedPlayerIds.isEmpty
                    ? null
                    : notifier.clearSelectedPlayers,
                child: const Text('Nenhum'),
              ),
            ],
          ),
          if (players.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('Cadastre jogadores primeiro'),
              ),
            )
          else
            ...players.map(
              (p) => CheckboxListTile(
                value: state.selectedPlayerIds.contains(p.id),
                onChanged: (_) => notifier.togglePlayer(p.id),
                title: Text(p.name),
                subtitle: StarRating(value: p.stars, size: 16),
                secondary: CircleAvatar(
                  child: Text(p.name[0].toUpperCase()),
                ),
                controlAffinity: ListTileControlAffinity.trailing,
              ),
            ),
          if (!canDraw && players.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Selecione pelo menos ${state.teamCount} jogadores',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _importNames(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<ImportResult>(
      MaterialPageRoute(builder: (_) => const ImportNamesScreen()),
    );
    if (result == null) return;

    ref.read(drawProvider.notifier).applyImport(
          matchedPlayerIds: result.playerIds,
          unmatchedNames: result.unresolvedNames,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.playerIds.length} jogadores marcados'
          '${result.unresolvedNames.isEmpty ? '' : ', ${result.unresolvedNames.length} sem correspondência'}',
        ),
      ),
    );
  }
}

/// Lembrete dos nomes importados que não bateram com ninguém do banco.
class _UnmatchedNamesCard extends StatelessWidget {
  final List<String> names;
  final VoidCallback onDismiss;

  const _UnmatchedNamesCard({required this.names, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: cs.onErrorContainer, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sem correspondência na lista importada',
                    style: TextStyle(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: cs.onErrorContainer,
                  onPressed: onDismiss,
                  tooltip: 'Dispensar',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              names.join(', '),
              style: TextStyle(color: cs.onErrorContainer),
            ),
            const SizedBox(height: 6),
            Text(
              'Marque na mão quem corresponde, ou cadastre em Jogadores.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Result ───────────────────────────────────────────────────────────────────

class _DrawResultScreen extends ConsumerWidget {
  final List<Player> players;

  const _DrawResultScreen({required this.players});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(drawProvider);
    final notifier = ref.read(drawProvider.notifier);
    final teams = state.teams!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Times Sorteados'),
        leading: BackButton(
          onPressed: () => ref.read(drawProvider.notifier).resetToDraw(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copiar para o WhatsApp',
            onPressed: () => ShareActions.copy(
              context,
              WhatsAppExport.teams(
                teams: teams,
                allPlayers: players,
                twoLegged: state.twoLegged,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Compartilhar',
            onPressed: () => ShareActions.share(
              WhatsAppExport.teams(
                teams: teams,
                allPlayers: players,
                twoLegged: state.twoLegged,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: notifier.redraw,
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Re-sortear'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () async {
                  final id = await notifier.confirmAndCreateTournament();
                  if (context.mounted) {
                    context.goNamed(
                      'tournament',
                      pathParameters: {'id': id},
                    );
                  }
                },
                icon: const Icon(Icons.emoji_events_outlined),
                label: const Text('Confirmar e Iniciar Torneio'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: teams.map((team) {
          final teamPlayers =
              players.where((p) => team.playerIds.contains(p.id)).toList();
          return _TeamCard(
            team: team,
            players: teamPlayers,
            allTeams: teams,
            onSwap: (playerId, fromId, toId) =>
                notifier.swapPlayer(playerId, fromId, toId),
            onColorChange: (colorValue) =>
                notifier.changeTeamColor(team.id, colorValue),
          );
        }).toList(),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final dynamic team;
  final List<Player> players;
  final List<dynamic> allTeams;
  final void Function(String, String, String) onSwap;
  final void Function(int colorValue) onColorChange;

  const _TeamCard({
    required this.team,
    required this.players,
    required this.allTeams,
    required this.onSwap,
    required this.onColorChange,
  });

  static const List<Color> _palette = [
    Color(0xFF4C8DFF), // azul
    Color(0xFF2F6FE0), // azul escuro
    Color(0xFF3FD8E0), // ciano
    Color(0xFF19B3C4), // ciano escuro
    Color(0xFF3DD68C), // verde
    Color(0xFF1F9E63), // verde escuro
    Color(0xFF9BE15D), // lima
    Color(0xFFFFD84C), // amarelo
    Color(0xFFFFA33C), // laranja
    Color(0xFFFF7A2F), // laranja escuro
    Color(0xFFFF5C5C), // vermelho
    Color(0xFFD93A3A), // vermelho escuro
    Color(0xFFFF6FA5), // rosa
    Color(0xFFE0479B), // magenta
    Color(0xFFB07CFF), // roxo
    Color(0xFF7C5CFF), // violeta
    Color(0xFF6E7BFF), // índigo
    Color(0xFF9C8B7A), // bege
    Color(0xFF7E8CA0), // cinza azulado
    Color(0xFFFFFFFF), // branco
  ];

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cor do time: ${team.name}',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: _palette.length,
                itemBuilder: (_, i) {
                  final c = _palette[i];
                  final isSelected = team.colorValue == c.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      onColorChange(c.toARGB32());
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: Theme.of(ctx).colorScheme.onSurface,
                                width: 3,
                              )
                            : Border.all(color: Colors.transparent, width: 3),
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              color: c.computeLuminance() > 0.4
                                  ? Colors.black
                                  : Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(team.colorValue);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _showColorPicker(context),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 12,
                      color: color.computeLuminance() > 0.4
                          ? Colors.black54
                          : Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    team.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StarRating(value: team.averageStars, size: 16),
                const SizedBox(width: 4),
                Text(
                  team.averageStars.toStringAsFixed(1),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          ...players.map(
            (p) => ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.3),
                child: Text(p.name[0].toUpperCase()),
              ),
              title: Text(p.name),
              subtitle: StarRating(value: p.stars, size: 14),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.swap_horiz),
                tooltip: 'Mover para outro time',
                itemBuilder: (_) => allTeams
                    .where((t) => t.id != team.id)
                    .map<PopupMenuItem<String>>(
                      (t) => PopupMenuItem(
                        value: t.id as String,
                        child: Text('→ ${t.name}'),
                      ),
                    )
                    .toList(),
                onSelected: (toId) => onSwap(p.id, team.id as String, toId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
