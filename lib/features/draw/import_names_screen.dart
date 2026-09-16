import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/player.dart';
import '../../data/repositories/player_repository.dart';
import '../../widgets/star_rating.dart';
import '../../data/services/name_import.dart';

/// O que a importação devolve para a tela de sorteio.
class ImportResult {
  /// Jogadores do banco reconhecidos (ou escolhidos na mão).
  final List<String> playerIds;

  /// Nomes que continuaram sem correspondência.
  final List<String> unresolvedNames;

  const ImportResult({required this.playerIds, required this.unresolvedNames});
}

/// Cola a lista de presença do grupo e casa cada nome com o banco.
/// Quem não bater fica em branco para seleção manual.
class ImportNamesScreen extends ConsumerStatefulWidget {
  const ImportNamesScreen({super.key});

  @override
  ConsumerState<ImportNamesScreen> createState() => _ImportNamesScreenState();
}

class _ImportNamesScreenState extends ConsumerState<ImportNamesScreen> {
  final _controller = TextEditingController();
  List<ImportedName>? _entries;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Player> get _allPlayers => ref.read(playerRepositoryProvider).getAll();

  void _process() {
    final names = NameImporter.parse(_controller.text);
    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum nome encontrado no texto')),
      );
      return;
    }
    setState(() {
      _entries = NameImporter.matchAll(names, _allPlayers);
    });
  }

  Future<void> _pickManually(int index) async {
    final used = <String>{
      for (var i = 0; i < _entries!.length; i++)
        if (i != index && _entries![i].match != null) _entries![i].match!.id,
    };
    final available =
        _allPlayers.where((p) => !used.contains(p.id)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    final picked = await showModalBottomSheet<Player>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PlayerPicker(
        title: _entries![index].rawName,
        players: available,
        showClear: _entries![index].match != null,
      ),
    );

    if (picked == null) return;
    setState(() {
      // O picker devolve o jogador escolhido; o "limpar" volta como _noPlayer.
      _entries![index] = _entries![index]
          .withMatch(identical(picked, _PlayerPicker.noPlayer) ? null : picked);
    });
  }

  void _apply() {
    final entries = _entries!;
    Navigator.of(context).pop(ImportResult(
      playerIds: [
        for (final e in entries)
          if (e.match != null) e.match!.id,
      ],
      unresolvedNames: [
        for (final e in entries)
          if (e.match == null) e.rawName,
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar lista'),
        actions: [
          if (entries != null)
            TextButton(
              onPressed: () => setState(() => _entries = null),
              child: const Text('Editar texto'),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: entries == null
              ? FilledButton.icon(
                  onPressed: _process,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Conferir nomes'),
                )
              : FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.check),
                  label: Text(
                    'Usar ${entries.where((e) => e.isMatched).length} jogadores',
                  ),
                ),
        ),
      ),
      body: entries == null ? _pasteStep() : _reviewStep(entries),
    );
  }

  Widget _pasteStep() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cole a lista do grupo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Um nome por linha. Numeração e marcadores são ignorados '
            '(1. Fulano, 1 - Fulano, • Fulano).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '1. Fulano\n2. Beltrano\n3. Ciclano',
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep(List<ImportedName> entries) {
    final matched = entries.where((e) => e.isMatched).length;
    final missing = entries.length - matched;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    missing == 0
                        ? '$matched nomes reconhecidos.'
                        : '$matched reconhecidos, $missing sem correspondência. '
                            'Toque para escolher na mão ou deixe em branco.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...entries.asMap().entries.map((e) {
          final index = e.key;
          final entry = e.value;
          final player = entry.match;

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: player == null
                  ? Theme.of(context).colorScheme.errorContainer
                  : null,
              child: Icon(
                player == null ? Icons.help_outline : Icons.check,
                size: 18,
              ),
            ),
            title: Text(entry.rawName),
            subtitle: player == null
                ? Text(
                    'Sem correspondência',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : Row(
                    children: [
                      Expanded(child: Text(player.name)),
                      StarRating(value: player.stars, size: 12),
                    ],
                  ),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: () => _pickManually(index),
          );
        }),
      ],
    );
  }
}

class _PlayerPicker extends StatefulWidget {
  final String title;
  final List<Player> players;
  final bool showClear;

  /// Sentinela devolvida quando o usuário escolhe "deixar em branco".
  static final Player noPlayer = Player(
    id: '',
    name: '',
    stars: 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  const _PlayerPicker({
    required this.title,
    required this.players,
    required this.showClear,
  });

  @override
  State<_PlayerPicker> createState() => _PlayerPickerState();
}

class _PlayerPickerState extends State<_PlayerPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.players
        .where((p) =>
            _query.isEmpty ||
            NameImporter.normalize(p.name)
                .contains(NameImporter.normalize(_query)))
        .toList();

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
              widget.title,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
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
                  if (widget.showClear)
                    ListTile(
                      leading: const Icon(Icons.clear),
                      title: const Text('Deixar em branco'),
                      onTap: () =>
                          Navigator.pop(ctx, _PlayerPicker.noPlayer),
                    ),
                  ...filtered.map(
                    (p) => ListTile(
                      leading:
                          CircleAvatar(child: Text(p.name[0].toUpperCase())),
                      title: Text(p.name),
                      subtitle: StarRating(value: p.stars, size: 12),
                      onTap: () => Navigator.pop(ctx, p),
                    ),
                  ),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Nenhum jogador disponível')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
