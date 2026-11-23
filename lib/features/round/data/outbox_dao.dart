import 'package:drift/drift.dart';
import 'package:meterread/app/database/app_database.dart';
import 'package:meterread/features/round/data/outbox_tables.dart';
import 'package:meterread/features/round/domain/meter.dart';

part 'outbox_dao.g.dart';

/// The outbox: readings waiting for the server.
@DriftAccessor(tables: [PendingReadings])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  /// Creates the DAO.
  new(super.attachedDatabase);

  /// Keeps a reading for [meterId], replacing any earlier one.
  ///
  /// With the [idempotencyKey] made when the reader tapped Save. Every
  /// attempt to send this reading uses that key.
  Future<void> capture(
    String meterId, {
    required int value,
    required bool meterReplaced,
    required String idempotencyKey,
  }) => into(pendingReadings).insertOnConflictUpdate(
    PendingReadingsCompanion.insert(
      meterId: meterId,
      value: value,
      meterReplaced: meterReplaced,
      idempotencyKey: Value(idempotencyKey),
      capturedAt: DateTime.now(),
    ),
  );

  /// How many readings are waiting, and again whenever that changes.
  Stream<int> watchCount() {
    final count = pendingReadings.meterId.count();
    return (selectOnly(
      pendingReadings,
    )..addColumns([count])).map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// The meters with a reading waiting, and again whenever they change.
  Stream<Set<String>> watchMeterIds() =>
      select(pendingReadings)
          .watch()
          .map((rows) => {for (final row in rows) row.meterId});

  /// The reading waiting for [meterId], if any.
  Future<WaitingReading?> readFor(String meterId) async =>
      _waiting(await _one(meterId).getSingleOrNull());

  /// The reading waiting for [meterId], and again whenever it changes.
  Stream<WaitingReading?> watchFor(String meterId) =>
      _one(meterId).watchSingleOrNull().map(_waiting);

  /// Notes the key an attempt is about to be sent with.
  ///
  /// Only for a reading saved without a key: it gets its one key here,
  /// once. Never called for a reading that already has one.
  Future<void> setKey(String meterId, String idempotencyKey) =>
      (update(pendingReadings)..where((p) => p.meterId.equals(meterId))).write(
        PendingReadingsCompanion(idempotencyKey: Value(idempotencyKey)),
      );

  /// Notes why the last attempt didn't get through.
  Future<void> setError(String meterId, String message) =>
      (update(pendingReadings)..where((p) => p.meterId.equals(meterId))).write(
        PendingReadingsCompanion(lastError: Value(message)),
      );

  /// The server has it, or the reader discarded it.
  Future<void> remove(String meterId) =>
      (delete(pendingReadings)..where((p) => p.meterId.equals(meterId))).go();

  SimpleSelectStatement<$PendingReadingsTable, PendingReading> _one(
    String meterId,
  ) => select(pendingReadings)..where((p) => p.meterId.equals(meterId));

  static WaitingReading? _waiting(PendingReading? row) => switch (row) {
    null => null,
    final row => (
      meterId: row.meterId,
      value: row.value,
      meterReplaced: row.meterReplaced,
      idempotencyKey: row.idempotencyKey,
      lastError: row.lastError,
    ),
  };
}
