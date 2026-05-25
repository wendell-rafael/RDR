import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/home/home_screen.dart';
import '../features/players/players_screen.dart';
import '../features/players/player_form_screen.dart';
import '../features/draw/draw_screen.dart';
import '../features/tournament/tournament_screen.dart';
import '../features/tournament/champion_screen.dart';
import '../features/match/match_screen.dart';
import '../features/history/history_screen.dart';
import '../features/settings/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/players',
        name: 'players',
        builder: (context, state) => const PlayersScreen(),
        routes: [
          GoRoute(
            path: 'edit',
            name: 'playerEdit',
            builder: (context, state) {
              final id = state.uri.queryParameters['id'];
              return PlayerFormScreen(playerId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/draw',
        name: 'draw',
        builder: (context, state) => const DrawScreen(),
      ),
      GoRoute(
        path: '/tournament/:id',
        name: 'tournament',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return TournamentScreen(tournamentId: id);
        },
        routes: [
          GoRoute(
            path: 'match/:matchId',
            name: 'match',
            builder: (context, state) {
              final tournamentId = state.pathParameters['id']!;
              final matchId = state.pathParameters['matchId']!;
              return MatchScreen(
                tournamentId: tournamentId,
                matchId: matchId,
              );
            },
          ),
          GoRoute(
            path: 'champion',
            name: 'champion',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ChampionScreen(tournamentId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/history',
        name: 'history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Rota não encontrada: ${state.error}')),
    ),
  );
});
