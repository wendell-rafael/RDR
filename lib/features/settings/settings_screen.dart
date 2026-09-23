import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/player.dart';
import '../../data/models/tournament.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/backup_service.dart';
import '../../data/services/cloud_auth_service.dart';
import '../../data/services/cloud_revision.dart';
import '../../widgets/dialog_action.dart';
import '../../data/repositories/tournament_repository.dart';
import '../players/players_provider.dart';

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
                      .withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 12),
          const _CloudAccountCard(),
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
          const SizedBox(height: 8),
          Text(
            'Manutenção',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Apaga todo o histórico de torneios e zera gols e títulos de '
            'todos os jogadores. Nomes e estrelas são preservados. '
            'A nuvem só muda depois que você usar "Enviar agora".',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt),
            label: const Text('Zerar torneios e estatísticas'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            onPressed: () => _doReset(context, ref),
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
                            .withValues(alpha: 0.4),
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

  /// Zera histórico de torneios e estatísticas. Duas confirmações, porque
  /// não há como desfazer pelo app.
  Future<void> _doReset(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final tournaments = ref.read(tournamentRepositoryProvider).getAll().length;
    final players = ref.read(playersProvider);
    final withStats = players.where((p) => p.goals > 0 || p.titles > 0).length;

    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zerar tudo?'),
        content: Text(
          'Isso vai apagar $tournaments torneios do histórico e zerar gols e '
          'títulos de $withStats jogadores.\n\n'
          'Nomes e estrelas continuam. Não dá para desfazer pelo app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          DialogAction(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continuar'),
            ),
          ),
        ],
      ),
    );
    if (first != true) return;

    if (!context.mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text(
          'Última confirmação. O histórico de torneios e as estatísticas '
          'serão apagados deste aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          DialogAction(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Zerar agora'),
            ),
          ),
        ],
      ),
    );
    if (second != true) return;

    // Solta o torneio ativo antes de apagar, senão a home aponta para um id
    // que não existe mais.
    await ref.read(settingsProvider.notifier).setActiveTournament(null);
    final removed = await ref.read(tournamentRepositoryProvider).clear();
    final reset = await ref.read(playersProvider.notifier).resetStats();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$removed torneios apagados, $reset jogadores zerados. '
          'A nuvem ainda tem os dados antigos.',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _doSend(BuildContext context, {bool force = false}) async {
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
        force: force,
      );
      if (context.mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Dados enviados com sucesso!')),
      );
    } on CloudDataChangedException catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (!context.mounted) return;
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Conflito com a nuvem'),
          content: Text(
            '${e.toString()}\n\n'
            'Se você já conferiu e tem certeza que os dados deste '
            'aparelho são os mais atuais, pode enviar mesmo assim — '
            'isso substitui o que está na nuvem.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            DialogAction(
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Enviar mesmo assim'),
              ),
            ),
          ],
        ),
      );
      if (overwrite == true && context.mounted) {
        await _doSend(context, force: true);
      }
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
          DialogAction(
            child: FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Atualizar'),
            ),
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
            content:
                Text('Dados atualizados! Reinicie o app para ver as mudanças.'),
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

class _CloudAccountCard extends StatefulWidget {
  const _CloudAccountCard();

  @override
  State<_CloudAccountCard> createState() => _CloudAccountCardState();
}

class _CloudAccountCardState extends State<_CloudAccountCard> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await CloudAuthService.signInWithGoogle();
    } on SignInCancelledException {
      // O seletor de contas foi fechado pelo usuário.
    } on WriterNotAuthorizedException catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Conta sem autorização'),
          content: Text(
            'A conta ${error.email} entrou corretamente, mas não está na lista '
            'de responsáveis. Cadastre esse e-mail na coleção rdr_writers.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível entrar com o Google: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: CloudAuthService.userChanges,
      initialData: CloudAuthService.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null || user.isAnonymous) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_outline),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Nuvem protegida',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Entre com uma conta Google autorizada para enviar dados.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar com Google'),
                  ),
                ],
              ),
            ),
          );
        }

        return FutureBuilder<bool>(
          future: CloudAuthService.isAuthorizedWriter(user.email),
          builder: (context, authorization) {
            final checking =
                authorization.connectionState != ConnectionState.done;
            final authorized = authorization.data ?? false;
            return Card(
              child: ListTile(
                leading: Icon(
                  checking
                      ? Icons.sync
                      : authorized
                          ? Icons.verified_user_outlined
                          : Icons.gpp_bad_outlined,
                ),
                title: Text(user.email ?? 'Conta autenticada'),
                subtitle: Text(
                  checking
                      ? 'Verificando autorização…'
                      : authorized
                          ? 'Autorizado a enviar dados'
                          : 'Conta sem autorização para escrever',
                ),
                trailing: TextButton(
                  onPressed: CloudAuthService.signOut,
                  child: const Text('Sair'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
