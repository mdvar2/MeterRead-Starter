import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meterread/app/retry_policy.dart';
import 'package:meterread/core/failure.dart';
import 'package:meterread/core/network/failure_from.dart';

final _request = RequestOptions(path: '/meters/M-1001');

DioException _answer(int status, [Object? body]) => DioException.badResponse(
  statusCode: status,
  requestOptions: _request,
  response: Response<Object?>(
    requestOptions: _request,
    statusCode: status,
    data: body,
  ),
);

Future<Object> _parallelWaitError() async {
  try {
    await [
      Future<int>.value(1),
      Future<int>.error(_answer(404, {'traceId': 't'})),
    ].wait;
  } on Object catch (error) {
    return error;
  }
  throw StateError('expected the wait to fail');
}

void main() {
  group('failureFrom', () {
    final table = <String, (Object, Matcher)>{
      'connection error': (
        DioException.connectionError(
          requestOptions: _request,
          reason: 'No signal',
        ),
        isA<NoSignal>(),
      ),
      'receive timeout (the answer was lost)': (
        DioException.receiveTimeout(
          timeout: const Duration(seconds: 20),
          requestOptions: _request,
        ),
        isA<NoSignal>(),
      ),
      'connection timeout': (
        DioException.connectionTimeout(
          timeout: const Duration(seconds: 10),
          requestOptions: _request,
        ),
        isA<NoSignal>(),
      ),
      'a socket exception': (
        const SocketException('Network is unreachable'),
        isA<NoSignal>(),
      ),
      '401': (_answer(401, {'title': 'Unauthorized'}), isA<SignedOutFailure>()),
      '404': (_answer(404, {'title': 'Not Found'}), isA<NotFound>()),
      '400 with errors': (
        _answer(400, {
          'errors': {
            'value': ['Too low.'],
          },
        }),
        isA<FieldErrors>().having(
          (f) => f.first('value'),
          'value error',
          'Too low.',
        ),
      ),
      '400 without errors': (
        _answer(400, {'title': 'Bad Request'}),
        isA<FieldErrors>().having((f) => f.errors, 'errors', isEmpty),
      ),
      '500 with a traceId': (
        _answer(500, {'traceId': '00-4bf92f35-01'}),
        isA<ServerFault>().having(
          (f) => f.reference,
          'reference',
          '00-4bf92f35-01',
        ),
      ),
      '503 without a body': (
        _answer(503),
        isA<ServerFault>().having((f) => f.reference, 'reference', isNull),
      ),
      'a Failure carried in a DioException': (
        DioException(requestOptions: _request, error: const NoSignal()),
        isA<NoSignal>(),
      ),
      'a Failure itself': (const NotFound(), isA<NotFound>()),
      'anything else': (StateError('bad json'), isA<ServerFault>()),
    };
    for (final MapEntry(key: name, value: (error, expected)) in table.entries) {
      test(name, () => expect(failureFrom(error), expected));
    }

    test('a ParallelWaitError: the error inside it', () async {
      final error = await _parallelWaitError();
      expect(error, isA<ParallelWaitError<Object?, Object?>>());
      expect(failureFrom(error), isA<NotFound>());
    });

    test('a ParallelWaitError from a record wait', () async {
      Object? caught;
      try {
        await (
          Future<int>.value(1),
          Future<int>.error(_answer(500, {'traceId': 'ref'})),
        ).wait;
      } on Object catch (error) {
        caught = error;
      }
      expect(
        failureFrom(caught!),
        isA<ServerFault>().having((f) => f.reference, 'reference', 'ref'),
      );
    });
  });

  group('appRetryPolicy', () {
    test('retries no answer at all, three times, backing off', () {
      expect(
        appRetryPolicy(0, const NoSignal()),
        const Duration(milliseconds: 200),
      );
      expect(
        appRetryPolicy(1, const NoSignal()),
        const Duration(milliseconds: 400),
      );
      expect(
        appRetryPolicy(2, const NoSignal()),
        const Duration(milliseconds: 800),
      );
      expect(appRetryPolicy(3, const NoSignal()), isNull);
    });

    final answers = <String, Object>{
      'a 400': const FieldErrors({}),
      'a 401': const SignedOutFailure(),
      'a 404': const NotFound(),
      'a 500': const ServerFault('ref'),
      'a bug': StateError('bug'),
      'a raw DioException (never above the data layer)': _answer(500),
    };
    for (final MapEntry(key: name, value: error) in answers.entries) {
      test('never retries $name', () {
        expect(appRetryPolicy(0, error), isNull);
      });
    }
  });
}
