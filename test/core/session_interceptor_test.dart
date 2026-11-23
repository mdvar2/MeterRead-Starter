import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meterread/core/fakes/meter_server.dart';
import 'package:meterread/core/network/access_token.dart';
import 'package:meterread/core/network/session_interceptor.dart';
import 'package:meterread/features/auth/data/auth_api.dart';

import '../support/in_memory_token_store.dart';

/// The meter server, with the signal dropping the moment it answers 401:
/// the refresh that follows gets no answer.
final class _SignalDropsOn401 implements HttpClientAdapter {
  new(this.server);

  final MeterServer server;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await server.fetch(options, requestStream, cancelFuture);
    if (response.statusCode == 401) server.online = false;
    return response;
  }

  @override
  void close({bool force = false}) {}
}

typedef _Client = ({
  Dio dio,
  InMemoryTokenStore store,
  List<String> ended,
  SessionToken? Function() access,
});

_Client _client(MeterServer server, HttpClientAdapter adapter) {
  Dio make() =>
      Dio(BaseOptions(baseUrl: 'https://api.kwanele.test/v1'))
        ..httpClientAdapter = adapter;
  final bare = make();
  final store = InMemoryTokenStore(
    server.issueRefreshTokenFor('thandeka@kwanele.test'),
  );
  final ended = <String>[];
  SessionToken? access;
  final dio = make()
    ..interceptors.add(
      SessionInterceptor(
        api: AuthApi(bare),
        store: store,
        readAccess: () => access,
        writeAccess: (token) => access = token,
        retryWith: bare,
        onSessionEnded: () => ended.add('ended'),
      ),
    );
  return (dio: dio, store: store, ended: ended, access: () => access);
}

void main() {
  test('two requests failing together refresh once', () async {
    final server = MeterServer(latency: Duration.zero);
    final client = _client(server, server);

    final answers = await Future.wait([
      client.dio.get<Object?>('/meters/M-1001'),
      client.dio.get<Object?>('/meters/M-1001/readings'),
      client.dio.get<Object?>('/round/today'),
    ]);

    expect(answers.map((a) => a.statusCode), everyElement(200));
    expect(server.refreshCalls, 1);
    expect(client.ended, isEmpty);
  });

  test('no signal for a refresh never signs anyone out', () async {
    final server = MeterServer(latency: Duration.zero);
    final client = _client(server, _SignalDropsOn401(server));
    final stored = client.store.refreshToken;

    await expectLater(
      client.dio.get<Object?>('/meters/M-1001'),
      throwsA(isA<DioException>()),
    );

    expect(client.ended, isEmpty);
    expect(client.store.refreshToken, stored);
  });

  test('the API refusing a refresh ends the session', () async {
    final server = MeterServer(latency: Duration.zero);
    final client = _client(server, server);
    client.store.refreshToken = 'rt-not-a-real-one';

    await expectLater(
      client.dio.get<Object?>('/meters/M-1001'),
      throwsA(isA<DioException>()),
    );

    expect(client.ended, ['ended']);
  });
}
