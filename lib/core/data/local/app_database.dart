import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class UsersTable extends Table {
  TextColumn get id => text()();
  TextColumn get phoneE164 => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get about => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class ConversationsTable extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get title => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get lastMessageId => text().nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class ConversationMembersTable extends Table {
  TextColumn get conversationId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text()();
  IntColumn get joinedAt => integer()();

  @override
  Set<Column<Object>>? get primaryKey => {conversationId, userId};
}

class MessagesTable extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get senderId => text()();
  TextColumn get type => text()();
  BlobColumn get ciphertext => blob()();
  IntColumn get clientMsgTs => integer()();
  IntColumn get serverSeq => integer().nullable()();
  IntColumn get editedAt => integer().nullable()();
  IntColumn get deletedForAllAt => integer().nullable()();
  TextColumn get localStatus => text()();
  TextColumn get replyToMessageId => text().nullable()();
  TextColumn get deviceId => text()();
  TextColumn get e2eeVersion =>
      text().withDefault(const Constant('signal-v1'))();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class ReactionsTable extends Table {
  TextColumn get messageId => text()();
  TextColumn get userId => text()();
  TextColumn get emoji => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>>? get primaryKey => {messageId, userId, emoji};
}

class ReceiptsTable extends Table {
  TextColumn get messageId => text()();
  TextColumn get userId => text()();
  IntColumn get deliveredAt => integer().nullable()();
  IntColumn get readAt => integer().nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {messageId, userId};
}

class StatusItemsTable extends Table {
  TextColumn get id => text()();
  TextColumn get authorId => text()();
  TextColumn get mediaType => text()();
  TextColumn get ciphertextRef => text()();
  IntColumn get createdAt => integer()();
  IntColumn get expiresAt => integer()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class OutboxOpsTable extends Table {
  TextColumn get id => text()();
  TextColumn get opType => text()();
  TextColumn get payloadJson => text()();
  IntColumn get createdAt => integer()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get nextRetryAt => integer().nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    UsersTable,
    ConversationsTable,
    ConversationMembersTable,
    MessagesTable,
    ReactionsTable,
    ReceiptsTable,
    StatusItemsTable,
    OutboxOpsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => m.createAll());

  Stream<List<ConversationsTableData>> watchConversations() {
    return select(conversationsTable).watch();
  }

  Stream<List<MessagesTableData>> watchMessages(String conversationIdValue) {
    final query = select(messagesTable)
      ..where((tbl) => tbl.conversationId.equals(conversationIdValue))
      ..orderBy([(tbl) => OrderingTerm.asc(tbl.clientMsgTs)]);
    return query.watch();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'chatify.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
