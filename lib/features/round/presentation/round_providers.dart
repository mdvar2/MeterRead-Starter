import 'package:meterread/app/database/app_database.dart';
import 'package:meterread/core/cache/snapshot.dart';
import 'package:meterread/features/round/data/round_repository.dart';
import 'package:meterread/features/round/domain/meter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:meterread/features/round/data/reading_outbox.dart'
    show OutboxError, ReadingOutbox, readingOutboxProvider;

part 'round_providers.g.dart';

/// Today's round, from the server.
///
/// From the phone first: what the phone kept, at once, and again every
/// time `roundSyncProvider` saves a newer one. Null until the first fetch.
@riverpod
Stream<Snapshot<Round>?> round(Ref ref) =>
    ref.watch(roundRepositoryProvider).watchRound();

/// Fetches the round in the background and saves it on the phone. Its
/// error is the last fetch's failure: the round screen says so, and how
/// old the round on the phone is.
@riverpod
Future<void> roundSync(Ref ref) =>
    ref.watch(roundRepositoryProvider).refreshRound();

/// One meter, from the server.
@riverpod
Future<Meter> meterDetail(Ref ref, String meterId) =>
    ref.watch(roundRepositoryProvider).fetchMeter(meterId);

/// The reading waiting to be sent for one meter, if any.
@riverpod
Stream<WaitingReading?> pendingReading(Ref ref, String meterId) =>
    ref.watch(appDatabaseProvider).outboxDao.watchFor(meterId);

/// How many readings are waiting on the phone.
@riverpod
Stream<int> waitingCount(Ref ref) =>
    ref.watch(appDatabaseProvider).outboxDao.watchCount();

/// The meters with a reading waiting on the phone.
@riverpod
Stream<Set<String>> waitingMeters(Ref ref) =>
    ref.watch(appDatabaseProvider).outboxDao.watchMeterIds();
