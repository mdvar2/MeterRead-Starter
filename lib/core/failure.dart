/// Everything that can go wrong between the app and the API, as the app
/// means it. Screens see these, never Dio.
sealed class Failure implements Exception {
  const new();
}

/// No answer at all: no signal, a timeout, or the answer was lost on the
/// way back. The only failure worth trying again by itself.
final class NoSignal extends Failure {
  /// Creates the failure.
  const new();

  @override
  String toString() => 'NoSignal';
}

/// The API refused what was sent, field by field: `{"value": ["…"]}`.
final class FieldErrors extends Failure {
  /// Creates the failure with the API's [errors].
  const new(this.errors);

  /// Field name to the API's messages about it. May be empty.
  final Map<String, List<String>> errors;

  /// The first message about [field], if any.
  String? first(String field) => errors[field]?.firstOrNull;

  @override
  String toString() => 'FieldErrors($errors)';
}

/// The API doesn't accept this reader's session (or their password).
final class SignedOutFailure extends Failure {
  /// Creates the failure.
  const new();

  @override
  String toString() => 'SignedOutFailure';
}

/// What was asked for doesn't exist, or isn't this reader's.
final class NotFound extends Failure {
  /// Creates the failure.
  const new();

  @override
  String toString() => 'NotFound';
}

/// The server's fault. [reference] is the API's traceId: support asks
/// for it.
final class ServerFault extends Failure {
  /// Creates the failure.
  const new([this.reference]);

  /// The API's traceId, when it sent one.
  final String? reference;

  @override
  String toString() => 'ServerFault($reference)';
}
