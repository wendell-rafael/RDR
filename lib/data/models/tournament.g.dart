// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tournament.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TournamentFormatAdapter extends TypeAdapter<TournamentFormat> {
  @override
  final int typeId = 6;

  @override
  TournamentFormat read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TournamentFormat.twoTeams;
      case 1:
        return TournamentFormat.threeTeams;
      case 2:
        return TournamentFormat.fourTeams;
      case 3:
        return TournamentFormat.fiveTeams;
      default:
        return TournamentFormat.twoTeams;
    }
  }

  @override
  void write(BinaryWriter writer, TournamentFormat obj) {
    switch (obj) {
      case TournamentFormat.twoTeams:
        writer.writeByte(0);
      case TournamentFormat.threeTeams:
        writer.writeByte(1);
      case TournamentFormat.fourTeams:
        writer.writeByte(2);
      case TournamentFormat.fiveTeams:
        writer.writeByte(3);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentFormatAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TournamentStatusAdapter extends TypeAdapter<TournamentStatus> {
  @override
  final int typeId = 7;

  @override
  TournamentStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TournamentStatus.active;
      case 1:
        return TournamentStatus.finished;
      default:
        return TournamentStatus.active;
    }
  }

  @override
  void write(BinaryWriter writer, TournamentStatus obj) {
    switch (obj) {
      case TournamentStatus.active:
        writer.writeByte(0);
      case TournamentStatus.finished:
        writer.writeByte(1);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TournamentAdapter extends TypeAdapter<Tournament> {
  @override
  final int typeId = 8;

  @override
  Tournament read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Tournament(
      id: fields[0] as String,
      createdAt: fields[1] as DateTime,
      teams: (fields[2] as List).cast<Team>(),
      format: fields[3] as TournamentFormat,
      status: fields[4] as TournamentStatus,
      matches: (fields[5] as List?)?.cast<MatchModel>(),
      championTeamId: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Tournament obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.createdAt)
      ..writeByte(2)
      ..write(obj.teams)
      ..writeByte(3)
      ..write(obj.format)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.matches)
      ..writeByte(6)
      ..write(obj.championTeamId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
