// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final typeId = 10;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      defaultMatchMinutes: fields[0] == null ? 7 : (fields[0] as num).toInt(),
      timerDirection: fields[1] == null
          ? TimerDirection.countdown
          : fields[1] as TimerDirection,
      soundEnabled: fields[2] == null ? true : fields[2] as bool,
      vibrationEnabled: fields[3] == null ? true : fields[3] as bool,
      activeTournamentId: fields[4] as String?,
      timerStartEpochMs: (fields[5] as num?)?.toInt(),
      timerDurationMs: (fields[6] as num?)?.toInt(),
      timerPausedOffsetMs: (fields[7] as num?)?.toInt(),
      timerRunning: fields[8] == null ? false : fields[8] as bool,
      timerMatchId: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.defaultMatchMinutes)
      ..writeByte(1)
      ..write(obj.timerDirection)
      ..writeByte(2)
      ..write(obj.soundEnabled)
      ..writeByte(3)
      ..write(obj.vibrationEnabled)
      ..writeByte(4)
      ..write(obj.activeTournamentId)
      ..writeByte(5)
      ..write(obj.timerStartEpochMs)
      ..writeByte(6)
      ..write(obj.timerDurationMs)
      ..writeByte(7)
      ..write(obj.timerPausedOffsetMs)
      ..writeByte(8)
      ..write(obj.timerRunning)
      ..writeByte(9)
      ..write(obj.timerMatchId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TimerDirectionAdapter extends TypeAdapter<TimerDirection> {
  @override
  final typeId = 9;

  @override
  TimerDirection read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TimerDirection.countdown;
      case 1:
        return TimerDirection.countup;
      default:
        return TimerDirection.countdown;
    }
  }

  @override
  void write(BinaryWriter writer, TimerDirection obj) {
    switch (obj) {
      case TimerDirection.countdown:
        writer.writeByte(0);
      case TimerDirection.countup:
        writer.writeByte(1);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerDirectionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
