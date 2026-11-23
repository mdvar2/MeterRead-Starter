import 'package:dio/dio.dart';
import 'package:meterread/app/database/app_database.dart';
import 'package:meterread/app/network/dio_provider.dart';
import 'package:meterread/core/cache/snapshot.dart';
import 'package:meterread/core/network/failure_from.dart';
import 'package:meterread/features/round/domain/meter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'round_repository.g.dart';

/// The round and meter endpoints.
///
/// Also the phone's copy of the round.
///
/// Every method throws a Failure, never a DioException.
final class RoundRepository {
  /// Creates the repository over the app's Dio client.
  ///
  /// And the app's database, for the phone's copy of the round.
  const new(this._dio, this._database);

  final Dio _dio;
  final AppDatabase _database;

  /// The round the phone kept, and again whenever it's saved. Null until
  /// the first round has been fetched.
  Stream<Snapshot<Round>?> watchRound() => _database.roundDao.watch();

  /// Fetches today's whole round, every page, and keeps it on the phone.
  Future<void> refreshRound() async {
    final round = await fetchRound();
    await _database.roundDao.save(round, fetchedAt: DateTime.now().toUtc());
  }

  /// GET /round/today: today's round.
  ///
  /// Page after page until the last page, which leaves nextPageToken out.
  Future<Round> fetchRound() => guarded(() async {
    final meters = <MeterSummary>[];
    Map<String, Object?>? first;
    String? pageToken;
    do {
      final response = await _dio.get<Map<String, Object?>>(
        '/round/today',
        queryParameters: {'pageToken': ?pageToken},
      );
      final json = response.data!;
      first ??= json;
      meters.addAll([
        for (final meter in json['meters']! as List<Object?>)
          MeterSummary.fromJson(meter! as Map<String, Object?>),
      ]);
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return Round(
      name: first['roundName']! as String,
      totalMeters: first['totalMeters']! as int,
      metersLeft: first['metersLeft']! as int,
      meters: meters,
    );
  });

  /// GET /meters/{id} and GET /meters/{id}/readings, together.
  Future<Meter> fetchMeter(String id) => guarded(() async {
    final [detail, history] = await [
      _dio.get<Map<String, Object?>>('/meters/$id'),
      _dio.get<Map<String, Object?>>('/meters/$id/readings'),
    ].wait;
    final json = detail.data!;
    return Meter(
      id: json['id']! as String,
      address: json['address']! as String,
      meterNumber: json['meterNumber']! as String,
      accountNumber: json['accountNumber']! as String,
      status: MeterStatus.fromWire(json['status']),
      lastReading: json['lastReading']! as int,
      lastReadOn: DateTime.parse(json['lastReadOn']! as String),
      thisCycle: switch (json['thisCycle']) {
        final Map<String, Object?> reading => AcceptedReading.fromJson(reading),
        _ => null,
      },
      history: [
        for (final past in history.data!['readings']! as List<Object?>)
          if (past case {
            'value': final int value,
            'readOn': final String readOn,
          })
            (value: value, readOn: DateTime.parse(readOn)),
      ],
    );
  });

  /// POST /meters/{id}/readings, with the Idempotency-Key the API asks for.
  ///
  /// The key is the reading's one key, made when the reader tapped Save.
  Future<AcceptedReading> submitReading(
    String meterId, {
    required int value,
    required bool meterReplaced,
    required String idempotencyKey,
  }) => guarded(() async {
    final response = await _dio.post<Map<String, Object?>>(
      '/meters/$meterId/readings',
      data: {'value': value, 'meterReplaced': meterReplaced},
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return AcceptedReading.fromJson(response.data!);
  });
}

/// The repository.
@riverpod
RoundRepository roundRepository(Ref ref) =>
    RoundRepository(ref.watch(dioProvider), ref.watch(appDatabaseProvider));
