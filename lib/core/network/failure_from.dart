import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:meterread/core/failure.dart';

/// Turns any error from the data layer into a [Failure]: the one place
/// that knows what a DioException means.
Failure failureFrom(Object error) => switch (error) {
  final Failure failure => failure,
  ParallelWaitError(:final errors) => _firstOf(errors),
  AsyncError(:final error) => failureFrom(error),
  DioException(error: final Failure failure) => failure,
  DioException(:final response?) => _fromResponse(response),
  DioException(
    type: DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.cancel,
  ) =>
    const NoSignal(),
  DioException(error: SocketException() || HttpException()) => const NoSignal(),
  SocketException() || TimeoutException() => const NoSignal(),
  _ => const ServerFault(),
};

/// Runs [call], turning whatever it throws into a [Failure].
Future<T> guarded<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on Object catch (error) {
    throw failureFrom(error);
  }
}

// `[a, b].wait` fails with a list of errors; `(a, b).wait` with a record.
Failure _firstOf(Object? errors) {
  final all = switch (errors) {
    final List<Object?> list => list,
    (final a, final b) => [a, b],
    (final a, final b, final c) => [a, b, c],
    _ => const <Object?>[],
  };
  for (final error in all) {
    if (error != null) return failureFrom(error);
  }
  return const ServerFault();
}

Failure _fromResponse(Response<Object?> response) {
  final body = response.data;
  final traceId = body is Map ? body['traceId'] : null;
  return switch (response.statusCode) {
    401 => const SignedOutFailure(),
    404 => const NotFound(),
    400 || 422 => FieldErrors(_errors(body)),
    _ => ServerFault(traceId is String ? traceId : null),
  };
}

Map<String, List<String>> _errors(Object? body) {
  if (body case {'errors': final Map<Object?, Object?> errors}) {
    return {
      for (final MapEntry(:key, :value) in errors.entries)
        if (key is String && value is List)
          key: [for (final message in value) '$message'],
    };
  }
  return const {};
}
