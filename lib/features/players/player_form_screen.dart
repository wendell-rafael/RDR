import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/player.dart';
import '../../widgets/star_rating.dart';
import 'players_provider.dart';

class PlayerFormScreen extends ConsumerStatefulWidget {
  final String? playerId;

  const PlayerFormScreen({super.key, this.playerId});

  @override
  ConsumerState<PlayerFormScreen> createState() => _PlayerFormScreenState();
}

class _PlayerFormScreenState extends ConsumerState<PlayerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  double _stars = 2.5;
  bool _saving = false;
  Player? _existing;

  @override
  void initState() {
    super.initState();
    if (widget.playerId != null) {
      _existing = ref.read(playersProvider.notifier).getById(widget.playerId!);
      if (_existing != null) {
        _nameController.text = _existing!.name;
        _stars = _existing!.stars;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final notifier = ref.read(playersProvider.notifier);

    if (_existing != null) {
      await notifier.updatePlayer(
        _existing!.copyWith(
          name: _nameController.text.trim(),
          stars: _stars,
        ),
      );
    } else {
      await notifier.addPlayer(
        name: _nameController.text.trim(),
        stars: _stars,
      );
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Jogador' : 'Novo Jogador'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: Theme.of(context).textTheme.titleLarge,
              decoration: const InputDecoration(
                labelText: 'Nome do jogador',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Informe o nome do jogador';
                }
                if (v.trim().length < 2) {
                  return 'Nome muito curto';
                }
                return null;
              },
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 32),
            Text(
              'Nível (estrelas)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _stars.toStringAsFixed(1),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 48,
                  ),
            ),
            const SizedBox(height: 8),
            Center(
              child: StarRatingInput(
                initialValue: _stars,
                size: 48,
                onChanged: (v) => setState(() => _stars = v),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Toque na estrela para definir meia ou estrela cheia',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(isEditing ? 'Salvar' : 'Adicionar'),
            ),
          ],
        ),
      ),
    );
  }
}
