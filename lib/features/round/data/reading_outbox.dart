import 'package:meterread/app/database/app_database.dart';
import 'package:meterread/core/failure.dart';
import 'package:meterread/features/round/data/round_repository.dart';
import 'package:meterread/features/round/domain/meter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'reading_outbox.g.dart';

/// Readings go through the outbox: kept on the phone first, then sent, so
/// a reading taken with no signal isn't lost.
///
/// One reading, one key: the Idempotency-Key is made when the reader taps
/// Save, kept with the reading, and every attempt to send it uses it. A
/// lost answer and a second try are one reading on the server, not two.
final class ReadingOutbox {
  /// Creates the outbox.
  const new(this._database, this._repository, {String Function()? newKey})
    : _newKey = newKey ?? _uuid;

  final AppDatabase _database;
  final RoundRepository _repository;
  final String Function() _newKey;

  static String _uuid() => const Uuid().v4();

  /// Keeps the reading on the phone with its one key, then tries to send
  /// it. Null when it couldn't be sent (no answer): it stays in the outbox
  /// for "Send now". Throws [FieldErrors] when the server refuses it.
  Future<AcceptedReading?> capture(
    String meterId, {
    required int value,
    required bool meterReplaced,
  }) async {
    await _database.outboxDao.capture(
      meterId,
      value: value,
      meterReplaced: meterReplaced,
      idempotencyKey: _newKey(),
    );
    return await send(meterId);
  }

  /// Sends the reading waiting for [meterId], with the key it was saved
  /// with. Null when there was no answer: it stays in the outbox. A
  /// refusal ([FieldErrors], [NotFound]) takes it out and is thrown; any
  /// other failure leaves it waiting and is thrown.
  Future<AcceptedReading?> send(String meterId) async {
    final outbox = _database.outboxDao;
    final pending = await outbox.readFor(meterId);
    if (pending == null) return null;
    var key = pending.idempotencyKey;
    if (key == null) {
      key = _newKey();
      await outbox.setKey(meterId, key);
    }
    try {
      final accepted = await _repository.submitReading(
        meterId,
        value: pending.value,
        meterReplaced: pending.meterReplaced,
        idempotencyKey: key,
      );
      await outbox.remove(meterId);
      return accepted;
    } on NoSignal {
      await outbox.setError(meterId, OutboxError.noSignal.name);
      return null;
    } on FieldErrors {
      await outbox.remove(meterId);
      rethrow;
    } on NotFound {
      await outbox.remove(meterId);
      rethrow;
    } on Failure {
      await outbox.setError(meterId, OutboxError.server.name);
      rethrow;
    }
  }

  /// Throws the waiting reading away.
  Future<void> discard(String meterId) => _database.outboxDao.remove(meterId);
}

/// Why a waiting reading's last attempt didn't get through, as kept in the
/// outbox's lastError column. The screen puts it in the reader's words.
enum OutboxError {
  /// No answer at all.
  noSignal,

  /// The server's fault.
  server;

  /// The value kept in the outbox, or null.
  static OutboxError? fromStored(String? stored) =>
      values.where((error) => error.name == stored).firstOrNull;
}

/// The outbox.
@riverpod
ReadingOutbox readingOutbox(Ref ref) => ReadingOutbox(
  ref.watch(appDatabaseProvider),
  ref.watch(roundRepositoryProvider),
);
