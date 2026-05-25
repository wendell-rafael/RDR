// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MatchPhaseAdapter extends TypeAdapter<MatchPhase> {
  @override
  final int typeId = 3;

  @override
  MatchPhase read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MatchPhase.group;
      case 1:
        return MatchPhase.playoff;
      case 2:
        return MatchPhase.finalMatch;
      case 3:
        return MatchPhase.semifinal;
      default:
        return MatchPhase.group;
    }
  }

  @override
  void write(BinaryWriter writer, MatchPhase obj) {
    switch (obj) {
      case MatchPhase.group:
        writer.writeByte(0);
      case MatchPhase.playoff:
        writer.writeByte(1);
      case MatchPhase.finalMatch:
        writer.writeByte(2);
      case MatchPhase.semifinal:
        writer.writeByte(3);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchPhaseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MatchStatusAdapter extends TypeAdapter<MatchStatus> {
  @override
  final int typeId = 4;

  @override
  MatchStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MatchStatus.pending;
      case 1:
        return MatchStatus.inProgress;
      case 2:
        return MatchStatus.finished;
      default:
        return MatchStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, MatchStatus obj) {
    switch (obj) {
      case MatchStatus.pending:
        writer.writeByte(0);
      case MatchStatus.inProgress:
        writer.writeByte(1);
      case MatchStatus.finished:
        writer.writeByte(2);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MatchModelAdapter extends TypeAdapter<MatchModel> {
  @override
  final int typeId = 5;

  @override
  MatchModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MatchModel(
      id: fields[0] as String,
      tournamentId: fields[1] as String,
      phase: fields[2] as MatchPhase,
      scheduledOrder: fields[3] as int,
      homeTeamId: fields[4] as String,
      awayTeamId: fields[5] as String,
      homeScore: fields[6] as int?,
      awayScore: fields[7] as int?,
      scorers: (fields[8] as List?)?.cast<GoalEvent>(),
      status: fields[9] as MatchStatus,
      penaltyWinnerId: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MatchModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.tournamentId)
      ..writeByte(2)
      ..write(obj.phase)
      ..writeByte(3)
      ..write(obj.scheduledOrder)
      ..writeByte(4)
      ..write(obj.homeTeamId)
      ..writeByte(5)
      ..write(obj.awayTeamId)
      ..writeByte(6)
      ..write(obj.homeScore)
      ..writeByte(7)
      ..write(obj.awayScore)
      ..writeByte(8)
      ..write(obj.scorers)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.penaltyWinnerId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
