import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:meterread/features/round/data/outbox_dao.dart';
import 'package:meterread/features/round/data/outbox_tables.dart';
import 'package:meterread/features/round/data/round_dao.dart';
import 'package:meterread/features/round/data/round_tables.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_database.g.dart';

/// The phone's own SQLite database. Keep this class's name.
@DriftDatabase(
  tables: [CachedRounds, CachedMeters, PendingReadings],
  daos: [RoundDao, OutboxDao],
)
final class AppDatabase extends _$AppDatabase {
  /// Opens the database on a query executor: a file on the phone, or
  /// memory in tests.
  new(super.e);

  /// Bump with every change to a table, with a migration for it.
  @override
  int get schemaVersion => 1;

  /// Deletes every row of every table: the cached round and the outbox.
  /// Sign-in, sign-out and an ended session leave nothing of the last
  /// reader behind.
  Future<void> wipe() => transaction(() async {
    for (final table in allTables) {
      await delete(table).go();
    }
  });
}

/// The one database, opened once. Keep this name: the test harness
/// overrides it with one in memory.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final database = AppDatabase(driftDatabase(name: 'meterread'));
  ref.onDispose(database.close);
  return database;
}
