import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/player.dart';
import '../../data/models/tournament.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/backup_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Duração padrão da partida',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: settings.defaultMatchMinutes.toDouble(),
                  min: 1,
                  max: 45,
                  divisions: 44,
                  label: '${settings.defaultMatchMinutes} min',
                  onChanged: (v) {
                    notifier.update(
                      settings.copyWith(defaultMatchMinutes: v.round()),
                    );
                  },
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${settings.defaultMatchMinutes} min',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          Text(
            'Tipo de cronômetro',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<TimerDirection>(
            selected: {settings.timerDirection},
            onSelectionChanged: (v) {
              notifier.update(settings.copyWith(timerDirection: v.first));
            },
            segments: const [
              ButtonSegment(
                value: TimerDirection.countdown,
                label: Text('Regressivo'),
                icon: Icon(Icons.hourglass_empty),
              ),
              ButtonSegment(
                value: TimerDirection.countup,
                label: Text('Crescente'),
                icon: Icon(Icons.timer_outlined),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),

          SwitchListTile(
            value: settings.soundEnabled,
            onChanged: (v) {
              notifier.update(settings.copyWith(soundEnabled: v));
            },
            title: const Text('Som ao final da partida'),
            secondary: const Icon(Icons.volume_up_outlined),
          ),

          SwitchListTile(
            value: settings.vibrationEnabled,
            onChanged: (v) {
              notifier.update(settings.copyWith(vibrationEnabled: v));
            },
            title: const Text('Vibração ao final da partida'),
            secondary: const Icon(Icons.vibration),
          ),

          const SizedBox(height: 24),
          const Divider(),

          const SizedBox(height: 8),
          Text(
            'Sincronização com a nuvem',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Os dados são enviados automaticamente ao fim de cada torneio '
            'e ao adicionar ou remover jogadores. '
            'Use "Atualizar" para puxar os dados mais recentes de outro celular.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Enviar agora'),
                  onPressed: () => _doSend(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Atualizar'),
                  onPressed: () => _doSync(context),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text(
                  'Racha dos Ruins',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'v1.0.0',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.4),
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doSend(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Enviando para a nuvem…'),
          ],
        ),
      ),
    );
    try {
      await SyncService.push(
        players: Hive.box<Player>('players'),
        tournaments: Hive.box<Tournament>('tournaments'),
      );
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Dados enviados com sucesso!')),
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao enviar: $e')),
      );
    }
  }

  Future<void> _doSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atualizar dados'),
        content: const Text(
          'Isso substituirá todos os dados locais pelos da nuvem. Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Atualizar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Atualizando…'),
            ],
          ),
        ),
      );
    }

    try {
      final found = await SyncService.pull(
        players: Hive.box<Player>('players'),
        tournaments: Hive.box<Tournament>('tournaments'),
      );
      if (context.mounted) Navigator.of(context).pop();
      if (found) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Dados atualizados! Reinicie o app para ver as mudanças.'),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nenhum dado encontrado na nuvem.')),
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao atualizar: $e')),
      );
    }
  }
}
