import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'data/services/cloud_auth_service.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'data/models/player.dart';
import 'data/models/team.dart';
import 'data/models/goal_event.dart';
import 'data/models/match_model.dart';
import 'data/models/tournament.dart';
import 'data/models/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CloudAuthService.clearLegacyAnonymousSession();
  await Hive.initFlutter();
  Hive.registerAdapter(PlayerAdapter());
  Hive.registerAdapter(TeamAdapter());
  Hive.registerAdapter(GoalEventAdapter());
  Hive.registerAdapter(MatchPhaseAdapter());
  Hive.registerAdapter(MatchStatusAdapter());
  Hive.registerAdapter(MatchModelAdapter());
  Hive.registerAdapter(TournamentFormatAdapter());
  Hive.registerAdapter(TournamentStatusAdapter());
  Hive.registerAdapter(TournamentAdapter());
  Hive.registerAdapter(TimerDirectionAdapter());
  Hive.registerAdapter(AppSettingsAdapter());
  await Hive.openBox<Player>('players');
  await Hive.openBox<Tournament>('tournaments');
  await Hive.openBox<AppSettings>('settings');
  await Hive.openBox<int>('sync_meta');
  await _seedPlayers();
  if (!kIsWeb) {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rdr_timer_channel',
        channelName: 'Timer do Racha',
        channelDescription: 'Timer de partida em andamento',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        allowWifiLock: false,
      ),
    );
  }
  runApp(const ProviderScope(child: RdrApp()));
}

Future<void> _seedPlayers() async {
  final box = Hive.box<Player>('players');
  const uuid = Uuid();
  final now = DateTime.now();
  final existingNames =
      box.values.map((p) => p.name.toLowerCase().trim()).toSet();
  final players = [
    ('Augusto', 2.5),
    ('Rafael', 5.0),
    ('Wendell', 2.0),
    ('Franklin', 3.5),
    ('Pietro', 3.0),
    ('Rona', 4.0),
    ('Ponce', 4.0),
    ('Ezequias', 2.5),
    ('Caio Davi', 4.0),
    ('Matteus', 5.0),
    ('Gleydson', 4.0),
    ('Bruno', 5.0),
    ('Messias', 4.0),
    ('Lázaro', 3.5),
    ('Vinícius', 4.0),
    ('Kayamori', 3.0),
    ('JH', 3.5),
    ('Oscar', 5.0),
    ('Jardel', 3.0),
    ('Araújo', 5.0),
  ];
  for (final (name, stars) in players) {
    if (existingNames.contains(name.toLowerCase().trim())) continue;
    final player = Player(
      id: uuid.v4(),
      name: name,
      stars: stars,
      createdAt: now,
    );
    await box.put(player.id, player);
  }
}

class RdrApp extends ConsumerWidget {
  const RdrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Racha dos Ruins',
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
