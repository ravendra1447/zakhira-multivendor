// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MessageAdapter extends TypeAdapter<Message> {
  @override
  final int typeId = 0;

  @override
  Message read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Message(
      messageId: fields[0] as String,
      chatId: fields[1] as int,
      senderId: fields[2] as int,
      receiverId: fields[3] as int,
      messageContent: fields[4] as String,
      messageType: fields[5] as String,
      isRead: fields[6] as int,
      timestamp: fields[7] as DateTime,
      isDelivered: fields[8] as int,
      senderName: fields[9] as String?,
      receiverName: fields[10] as String?,
      senderPhoneNumber: fields[11] as String?,
      receiverPhoneNumber: fields[12] as String?,
      isDeletedSender: fields[13] as int,
      isDeletedReceiver: fields[14] as int,
      thumbnail: fields[15] as Uint8List?,
      blurImagePath: fields[16] as String?,
      isImageLoaded: fields[17] as bool,
      lowQualityUrl: fields[18] as String?,
      extraData: (fields[19] as Map?)?.cast<String, dynamic>(),
      highQualityUrl: fields[20] as String?,
      blurHash: fields[21] as String?,
      thumbnailBase64: fields[22] as String?,
      replyToMessageId: fields[24] as String?,
      isForwarded: fields[25] as bool,
      forwardedFrom: fields[26] as String?,
    ).._imageLoadStage = fields[23] as int;
  }

  @override
  void write(BinaryWriter writer, Message obj) {
    writer
      ..writeByte(27)
      ..writeByte(0)
      ..write(obj.messageId)
      ..writeByte(1)
      ..write(obj.chatId)
      ..writeByte(2)
      ..write(obj.senderId)
      ..writeByte(3)
      ..write(obj.receiverId)
      ..writeByte(4)
      ..write(obj.messageContent)
      ..writeByte(5)
      ..write(obj.messageType)
      ..writeByte(6)
      ..write(obj.isRead)
      ..writeByte(7)
      ..write(obj.timestamp)
      ..writeByte(8)
      ..write(obj.isDelivered)
      ..writeByte(13)
      ..write(obj.isDeletedSender)
      ..writeByte(14)
      ..write(obj.isDeletedReceiver)
      ..writeByte(15)
      ..write(obj.thumbnail)
      ..writeByte(16)
      ..write(obj.blurImagePath)
      ..writeByte(17)
      ..write(obj.isImageLoaded)
      ..writeByte(18)
      ..write(obj.lowQualityUrl)
      ..writeByte(19)
      ..write(obj.extraData)
      ..writeByte(20)
      ..write(obj.highQualityUrl)
      ..writeByte(21)
      ..write(obj.blurHash)
      ..writeByte(22)
      ..write(obj.thumbnailBase64)
      ..writeByte(23)
      ..write(obj._imageLoadStage)
      ..writeByte(24)
      ..write(obj.replyToMessageId)
      ..writeByte(25)
      ..write(obj.isForwarded)
      ..writeByte(26)
      ..write(obj.forwardedFrom)
      ..writeByte(9)
      ..write(obj.senderName)
      ..writeByte(10)
      ..write(obj.receiverName)
      ..writeByte(11)
      ..write(obj.senderPhoneNumber)
      ..writeByte(12)
      ..write(obj.receiverPhoneNumber);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ChatAdapter extends TypeAdapter<Chat> {
  @override
  final int typeId = 1;

  @override
  Chat read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Chat(
      chatId: fields[0] as int,
      contactId: fields[1] as int,
      userIds: (fields[2] as List).cast<int>(),
      chatTitle: fields[3] as String,
      lastMessage: fields[4] as String?,
      lastMessageTime: fields[5] as DateTime?,
      unreadCount: fields[6] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Chat obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.chatId)
      ..writeByte(1)
      ..write(obj.contactId)
      ..writeByte(2)
      ..write(obj.userIds)
      ..writeByte(3)
      ..write(obj.chatTitle)
      ..writeByte(4)
      ..write(obj.lastMessage)
      ..writeByte(5)
      ..write(obj.lastMessageTime)
      ..writeByte(6)
      ..write(obj.unreadCount);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
