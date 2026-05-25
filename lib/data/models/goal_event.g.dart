// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'goal_event.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GoalEventAdapter extends TypeAdapter<GoalEvent> {
  @override
  final int typeId = 2;

  @override
  GoalEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GoalEvent(
      playerId: fields[0] as String,
      teamId: fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, GoalEvent obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.playerId)
      ..writeByte(1)
      ..write(obj.teamId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoalEventAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
