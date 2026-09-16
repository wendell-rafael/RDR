import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/player.dart';
import '../../data/repositories/player_repository.dart';
import '../../data/services/name_import.dart';
import '../../widgets/star_rating.dart';
import 'players_provider.dart';
import '../../widgets/dialog_action.dart';

/// Estrelas dos jogadores criados pela importação. Ajustáveis depois em
/// Jogadores — a importação não tenta adivinhar nível.
const _starsForNew = 2.5;

/// O que fazer com cada nome da lista colada.
enum _Action {
  /// Já existe no banco, nada muda.
  useExisting,

  /// Já existe, mas grava a grafia da lista por cima do nome atual.
  renameExisting,

  /// Cria um jogador novo, mesmo que exista um parecido.
  createNew,

  /// Não faz nada com esse nome.
  ignore,
}

class _Entry {
  final String rawName;
  Player? linked;
  _Action action;

  _Entry({required this.rawName, this.linked})
      : action = linked == null ? _Action.createNew : _Action.useExisting;

  /// Só faz sentido renomear quando a grafia da lista é diferente da do banco.
  bool get canRename =>
      linked != null && linked!.name.trim() != rawName.trim();
}

/// Cadastro de jogadores em lote: cola a lista, confere o que bate com o
/// banco e decide nome a nome o que fazer.
class ImportPlayersScreen extends ConsumerStatefulWidget {
  const ImportPlayersScreen({super.key});

  @override
  ConsumerState<ImportPlayersScreen> createState() =>
      _ImportPlayersScreenState();
}

class _ImportPlayersScreenState extends ConsumerState<ImportPlayersScreen> {
  final _controller = TextEditingController();
  List<_Entry>? _entries;

  /// Remover do banco quem não aparece na lista importada. Desligado por
  /// padrão: remover apaga gols e títulos do jogador.
  bool _removeAbsent = false;

  bool _saving = false;

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
    final matched = NameImporter.matchAll(names, _allPlayers);
    setState(() {
      _entries = [
        for (final m in matched) _Entry(rawName: m.rawName, linked: m.match),
      ];
      _removeAbsent = false;
    });
  }

  /// Jogadores do banco que nenhuma entrada da lista aponta.
  List<Player> get _absentPlayers {
    final referenced = <String>{
      for (final e in _entries ?? <_Entry>[])
        if (e.linked != null &&
            (e.action == _Action.useExisting ||
                e.action == _Action.renameExisting))
          e.linked!.id,
    };
    return _allPlayers.where((p) => !referenced.contains(p.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _link(int index) async {
    final entry = _entries![index];
    final taken = <String>{
      for (var i = 0; i < _entries!.length; i++)
        if (i != index && _entries![i].linked != null) _entries![i].linked!.id,
    };
    final available = _allPlayers.where((p) => !taken.contains(p.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _LinkPicker(
        title: entry.rawName,
        players: available,
        showUnlink: entry.linked != null,
      ),
    );
    if (picked == null) return;

    setState(() {
      if (picked is Player) {
        entry.linked = picked;
        entry.action = entry.canRename ? _Action.renameExisting : _Action.useExisting;
      } else {
        entry.linked = null;
        entry.action = _Action.createNew;
      }
    });
  }

  Future<void> _apply() async {
    final entries = _entries!;
    final absent = _absentPlayers;

    final toCreate = [
      for (final e in entries)
        if (e.action == _Action.createNew) e.rawName,
    ];
    final toRename = [
      for (final e in entries)
        if (e.action == _Action.renameExisting && e.linked != null)
          e.linked!.copyWith(name: e.rawName.trim()),
    ];
    final toDelete = _removeAbsent ? absent : <Player>[];

    if (toCreate.isEmpty && toRename.isEmpty && toDelete.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada a alterar')),
      );
      return;
    }

    final confirmed = await _confirm(toCreate, toRename, toDelete);
    if (confirmed != true) return;

    setState(() => _saving = true);
    await ref.read(playersProvider.notifier).applyImport(
          namesToCreate: toCreate,
          starsForNew: _starsForNew,
          toRename: toRename,
          idsToDelete: toDelete.map((p) => p.id).toList(),
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${toCreate.length} criados, ${toRename.length} renomeados'
          '${toDelete.isEmpty ? '' : ', ${toDelete.length} removidos'}',
        ),
      ),
    );
  }

  Future<bool?> _confirm(
    List<String> toCreate,
    List<Player> toRename,
    List<Player> toDelete,
  ) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar importação'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (toCreate.isNotEmpty) ...[
                Text('Criar ${toCreate.length}:',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(toCreate.join(', ')),
                const SizedBox(height: 12),
              ],
              if (toRename.isNotEmpty) ...[
                Text('Renomear ${toRename.length}:',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(toRename.map((p) => p.name).join(', ')),
                const SizedBox(height: 12),
              ],
              if (toDelete.isNotEmpty) ...[
                Text(
                  'Remover ${toDelete.length}:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: cs.error),
                ),
                Text(toDelete.map((p) => p.name).join(', ')),
                const SizedBox(height: 6),
                Text(
                  'Remover apaga os gols e títulos desses jogadores. '
                  'Não dá para desfazer.',
                  style: TextStyle(color: cs.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          DialogAction(
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aplicar'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar jogadores'),
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
                  onPressed: _saving ? null : _apply,
                  icon: const Icon(Icons.check),
                  label: Text(_saving ? 'Gravando…' : 'Aplicar'),
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
            'Cole a lista de nomes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Um nome por linha. Numeração e marcadores são ignorados '
            '(1. Fulano, 1 - Fulano, • Fulano). Cada nome é comparado com o '
            'cadastro e você decide o que fazer com ele.',
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

  Widget _reviewStep(List<_Entry> entries) {
    final create = entries.where((e) => e.action == _Action.createNew).length;
    final rename =
        entries.where((e) => e.action == _Action.renameExisting).length;
    final absent = _absentPlayers;

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
                    '${entries.length} nomes lidos · $create a criar · '
                    '$rename a renomear.\nNovos entram com '
                    '${_starsForNew.toStringAsFixed(1)} estrelas.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...entries.asMap().entries.map((e) => _entryCard(e.key, e.value)),
        if (absent.isNotEmpty) ...[
          const SizedBox(height: 8),
          _absentCard(absent),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _entryCard(int index, _Entry entry) {
    final cs = Theme.of(context).colorScheme;
    final linked = entry.linked;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.rawName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _link(index),
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(linked == null ? 'Vincular' : 'Trocar'),
                ),
              ],
            ),
            if (linked != null)
              Row(
                children: [
                  Icon(Icons.person, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No banco: ${linked.name}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  StarRating(value: linked.stars, size: 12),
                ],
              )
            else
              Text(
                'Sem correspondência no cadastro',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.tertiary),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (linked != null)
                  _actionChip(entry, _Action.useExisting, 'Usar existente'),
                if (entry.canRename)
                  _actionChip(entry, _Action.renameExisting,
                      'Renomear para "${entry.rawName}"'),
                _actionChip(entry, _Action.createNew, 'Criar novo'),
                _actionChip(entry, _Action.ignore, 'Ignorar'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChip(_Entry entry, _Action action, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: entry.action == action,
      onSelected: (_) => setState(() => entry.action = action),
    );
  }

  Widget _absentCard(List<Player> absent) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: _removeAbsent ? cs.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${absent.length} jogadores do cadastro não estão na lista',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              absent.map((p) => p.name).join(', '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _removeAbsent,
              onChanged: (v) => setState(() => _removeAbsent = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Remover esses jogadores'),
              subtitle: const Text(
                'Apaga também os gols e títulos deles. Sem isso, a importação '
                'só cria e renomeia.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Escolhe manualmente o jogador do cadastro que corresponde a um nome.
class _LinkPicker extends StatefulWidget {
  final String title;
  final List<Player> players;
  final bool showUnlink;

  const _LinkPicker({
    required this.title,
    required this.players,
    required this.showUnlink,
  });

  @override
  State<_LinkPicker> createState() => _LinkPickerState();
}

class _LinkPickerState extends State<_LinkPicker> {
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
            Text(widget.title, style: Theme.of(ctx).textTheme.titleMedium),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar jogador',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  if (widget.showUnlink)
                    ListTile(
                      leading: const Icon(Icons.link_off),
                      title: const Text('Desvincular'),
                      onTap: () => Navigator.pop(ctx, 'unlink'),
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
