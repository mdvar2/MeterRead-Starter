import 'package:meterread/core/failure.dart';

/// When Riverpod may retry a provider that failed. Keep this name: main()
/// and the test harness both use it.
///
/// Three tries, 200 ms, 400 ms and 800 ms apart.
///
/// Only "no answer at all" is tried again: an answer (400, 404, 500) would
/// be the same answer again. Writes never go through a provider, so they
/// are never retried here.
Duration? appRetryPolicy(int retryCount, Object error) {
  if (retryCount >= 3) return null;
  if (error is! NoSignal) return null;
  return Duration(milliseconds: 200 * (1 << retryCount));
}
