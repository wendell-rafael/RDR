import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_ce/hive.dart';
import 'cloud_auth_service.dart';
import 'cloud_revision.dart';
import '../models/goal_event.dart';
import '../models/match_model.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../models/tournament.dart';

class SyncService {
  static final _doc =
      FirebaseFirestore.instance.collection('racha').doc('main');
  // Espelho público sem o nível/estrelas — é o que o site lê. O documento
  // 'main' completo só pode ser lido por quem está autenticado como writer.
  static final _publicDoc =
      FirebaseFirestore.instance.collection('racha').doc('public');
  static const _revisionKey = 'cloudRevision';

  /// Limite para qualquer operação de rede. Sem isso, em rede ruim ou sem
  /// permissão de INTERNET o Firestore fica pendente indefinidamente.
  static const _timeout = Duration(seconds: 15);

  // ── Push ──────────────────────────────────────────────────────────────────

  /// Envia todos os jogadores e torneios para a nuvem.
  /// Fire-and-forget: use [push] sem await para não bloquear a UI.
  static Future<void> push({
    required Box<Player> players,
    required Box<Tournament> tournaments,
  }) async {
    final writer = CloudAuthService.requireSignedInWriter();
    final metadata = Hive.box<int>('sync_meta');
    final localRevision = metadata.get(_revisionKey);
    late int savedRevision;

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(_doc);
      final cloudRevision =
          (snapshot.data()?['revision'] as num?)?.toInt() ?? 0;
      savedRevision = nextCloudRevision(
        localRevision: localRevision,
        cloudRevision: cloudRevision,
      );
      transaction.set(_doc, {
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': writer.uid,
        'revision': savedRevision,
        'players': players.values.map(_playerToMap).toList(),
        'tournaments': tournaments.values.map(_tournamentToMap).toList(),
      });
      // Espelho público: sem o nível/estrelas de cada jogador nem a média
      // do time (derivada do nível — vazaria a mesma informação privada).
      transaction.set(_publicDoc, {
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': writer.uid,
        'revision': savedRevision,
        'players': players.values.map(_playerToPublicMap).toList(),
        'tournaments':
            tournaments.values.map(_tournamentToPublicMap).toList(),
      });
    }).timeout(_timeout);
    await metadata.put(_revisionKey, savedRevision);
  }

  // ── Pull ──────────────────────────────────────────────────────────────────

  /// Baixa os dados da nuvem e substitui os locais.
  /// Retorna [false] se ainda não houver dados na nuvem.
  ///
  /// O documento completo (com o nível/estrelas de cada jogador) só pode ser
  /// lido por um writer autenticado — por isso exige login, diferente do
  /// espelho público que o site usa.
  static Future<bool> pull({
    required Box<Player> players,
    required Box<Tournament> tournaments,
  }) async {
    CloudAuthService.requireSignedInWriter();
    // Source.server: sem isso um app offline leria o cache local e o
    // resultado pareceria "nuvem vazia" em vez de erro de conexão.
    final snap = await _doc
        .get(const GetOptions(source: Source.server))
        .timeout(_timeout);
    if (!snap.exists) return false;

    final data = snap.data()!;
    final cloudRevision = (data['revision'] as num?)?.toInt() ?? 0;

    // Valida e desserializa tudo antes de apagar os dados locais. Assim um
    // documento incompatível ou malformado não deixa o aparelho sem backup.
    final downloadedPlayers = ((data['players'] as List?)?.cast<Map>() ?? [])
        .map((p) => _playerFromMap(Map<String, dynamic>.from(p)))
        .toList();
    final downloadedTournaments =
        ((data['tournaments'] as List?)?.cast<Map>() ?? [])
            .map((t) => _tournamentFromMap(Map<String, dynamic>.from(t)))
            .toList();

    await players.clear();
    for (final player in downloadedPlayers) {
      await players.put(player.id, player);
    }

    await tournaments.clear();
    for (final tournament in downloadedTournaments) {
      await tournaments.put(tournament.id, tournament);
    }
    await Hive.box<int>('sync_meta').put(_revisionKey, cloudRevision);

    return true;
  }

  /// Retorna o timestamp da última sincronização, ou null se nunca sincronizou.
  /// Lê do espelho público — assim qualquer usuário vê a última sincronização
  /// sem precisar estar logado como writer.
  static Future<DateTime?> lastSyncAt() async {
    final snap = await _publicDoc
        .get(const GetOptions(source: Source.server))
        .timeout(_timeout);
    if (!snap.exists) return null;
    final ts = snap.data()?['updatedAt'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _playerToMap(Player p) => {
        'id': p.id,
        'name': p.name,
        'stars': p.stars,
        'goals': p.goals,
        'titles': p.titles,
        'createdAt': p.createdAt.millisecondsSinceEpoch,
      };

  /// Igual a [_playerToMap], mas sem o nível/estrelas — é o que vai pro
  /// espelho público (/racha/public), lido por qualquer um sem autenticação.
  static Map<String, dynamic> _playerToPublicMap(Player p) => {
        'id': p.id,
        'name': p.name,
        'goals': p.goals,
        'titles': p.titles,
        'createdAt': p.createdAt.millisecondsSinceEpoch,
      };

  static Player _playerFromMap(Map<String, dynamic> m) => Player(
        id: m['id'] as String,
        name: m['name'] as String,
        stars: (m['stars'] as num).toDouble(),
        goals: (m['goals'] as num?)?.toInt() ?? 0,
        titles: (m['titles'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
      );

  static Map<String, dynamic> _teamToMap(Team t) => {
        'id': t.id,
        'name': t.name,
        'playerIds': t.playerIds,
        'colorValue': t.colorValue,
        'averageStars': t.averageStars,
      };

  /// Igual a [_teamToMap], mas sem `averageStars` — deriva do nível/estrelas
  /// (privado) de cada jogador do time, então não pode ir pro espelho
  /// público mesmo indiretamente.
  static Map<String, dynamic> _teamToPublicMap(Team t) => {
        'id': t.id,
        'name': t.name,
        'playerIds': t.playerIds,
        'colorValue': t.colorValue,
      };

  static Team _teamFromMap(Map<String, dynamic> m) => Team(
        id: m['id'] as String,
        name: m['name'] as String,
        playerIds: List<String>.from(m['playerIds'] as List),
        colorValue: m['colorValue'] as int,
        averageStars: (m['averageStars'] as num).toDouble(),
      );

  static Map<String, dynamic> _goalEventToMap(GoalEvent g) => {
        'playerId': g.playerId,
        'teamId': g.teamId,
        'minute': g.minute,
      };

  static GoalEvent _goalEventFromMap(Map<String, dynamic> m) => GoalEvent(
        playerId: m['playerId'] as String,
        teamId: m['teamId'] as String,
        minute: (m['minute'] as num?)?.toInt(),
      );

  static Map<String, dynamic> _matchToMap(MatchModel m) => {
        'id': m.id,
        'tournamentId': m.tournamentId,
        'phase': m.phase.index,
        'scheduledOrder': m.scheduledOrder,
        'homeTeamId': m.homeTeamId,
        'awayTeamId': m.awayTeamId,
        'homeScore': m.homeScore,
        'awayScore': m.awayScore,
        'status': m.status.index,
        'penaltyWinnerId': m.penaltyWinnerId,
        'tieId': m.tieId,
        'leg': m.leg,
        'scorers': m.scorers.map(_goalEventToMap).toList(),
      };

  static MatchModel _matchFromMap(Map<String, dynamic> m) => MatchModel(
        id: m['id'] as String,
        tournamentId: m['tournamentId'] as String,
        phase: MatchPhase.values[m['phase'] as int],
        scheduledOrder: m['scheduledOrder'] as int,
        homeTeamId: m['homeTeamId'] as String,
        awayTeamId: m['awayTeamId'] as String,
        homeScore: m['homeScore'] as int?,
        awayScore: m['awayScore'] as int?,
        status: MatchStatus.values[m['status'] as int],
        penaltyWinnerId: m['penaltyWinnerId'] as String?,
        tieId: m['tieId'] as String?,
        leg: (m['leg'] as num?)?.toInt() ?? 1,
        scorers: ((m['scorers'] as List?)?.cast<Map>() ?? [])
            .map((e) => _goalEventFromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );

  static Map<String, dynamic> _tournamentToMap(Tournament t) => {
        'id': t.id,
        'createdAt': t.createdAt.millisecondsSinceEpoch,
        'format': t.format.index,
        'status': t.status.index,
        'championTeamId': t.championTeamId,
        'twoLegged': t.twoLegged,
        'teams': t.teams.map(_teamToMap).toList(),
        'matches': t.matches.map(_matchToMap).toList(),
      };

  /// Igual a [_tournamentToMap], mas com times sem `averageStars` — usado
  /// só na gravação do espelho público (/racha/public).
  static Map<String, dynamic> _tournamentToPublicMap(Tournament t) => {
        'id': t.id,
        'createdAt': t.createdAt.millisecondsSinceEpoch,
        'format': t.format.index,
        'status': t.status.index,
        'championTeamId': t.championTeamId,
        'twoLegged': t.twoLegged,
        'teams': t.teams.map(_teamToPublicMap).toList(),
        'matches': t.matches.map(_matchToMap).toList(),
      };

  static Tournament _tournamentFromMap(Map<String, dynamic> m) => Tournament(
        id: m['id'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
        format: TournamentFormat.values[m['format'] as int],
        status: TournamentStatus.values[m['status'] as int],
        championTeamId: m['championTeamId'] as String?,
        twoLegged: m['twoLegged'] as bool? ?? false,
        teams: ((m['teams'] as List?)?.cast<Map>() ?? [])
            .map((e) => _teamFromMap(Map<String, dynamic>.from(e)))
            .toList(),
        matches: ((m['matches'] as List?)?.cast<Map>() ?? [])
            .map((e) => _matchFromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
