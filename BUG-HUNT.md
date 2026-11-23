# Bug hunt

Eight short snippets, each with at least one bug from Week 11. For each, write
**what breaks, and for whom**, and **the fix**, in a line each.

## 1

```dart
Duration? retryPolicy(int retryCount, Object error) =>
    retryCount < 3 ? Duration(milliseconds: 200 * (1 << retryCount)) : null;
```

What breaks: Every error is retried three times, a 400, 404 or 500 included: the reader waits 1.4 s longer for the same answer, and the server gets the same bad request four times.

The fix: Retry only "no answer at all": `if (error is! NoSignal) return null;` before working out the delay.

## 2

```dart
AsyncError(:final error) => Center(child: Text('$error')),
```

What breaks: The reader sees `DioException [bad response]: …`, with no words they understand, no reference for support, and no way to try again.

The fix: Map the error to a `Failure` and show it in the reader's words (`failureMessage`), with the `traceId` as a reference when it's the server's fault, and a "Try again" that invalidates the provider.

## 3

```dart
try {
  final (meter, history) = await (api.meter(id), api.history(id)).wait;
  return MeterView(meter, history);
} on DioException catch (error) {
  throw failureFrom(error);
}
```

What breaks: `(a, b).wait` fails with a `ParallelWaitError`, not a `DioException`, so the `on DioException` never matches: the raw error escapes the data layer and reaches the screen.

The fix: Catch everything (`on Object`) and let `failureFrom` unwrap the `ParallelWaitError` to the first failure inside it.

## 4

```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('refresh_token', pair.refreshToken);
await prefs.setString('access_token', pair.accessToken);
```

What breaks: Both tokens sit in plain text in the app's preferences: anyone with a backup or a rooted phone can lift the reader's session. The access token is on disk too.

The fix: Refresh token in `flutter_secure_storage` behind `TokenStore`; access token in memory only (`AccessToken` provider).

## 5

```dart
class SessionInterceptor extends Interceptor {
  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      final pair = await api.refresh(await store.read());
      // ... store the pair, then send the request again
    }
  }
}
```

What breaks: A plain `Interceptor`: two requests that fail together both refresh. The second presents a spent refresh token and the API ends the session, so the reader is signed out. Non-401 errors never call the handler, so those requests hang forever.

The fix: A `QueuedInterceptor` that compares the token the failed request carried with the current one and only refreshes if they match. Call `handler.next(err)` for everything that isn't a 401.

## 6

```dart
try {
  final pair = await api.refresh(stored);
  await keep(pair);
} on DioException {
  await auth.signOut();          // wipes the tokens and the database
}
```

What breaks: Any `DioException` signs the reader out, no signal included: one dead spot on the round wipes the reader's tokens and the unsent readings in the database.

The fix: Sign out only when the API refuses the refresh (a 401 or 400 answer). With no signal, keep the session and fail just this request.

## 7

```dart
Future<void> send(PendingReading pending) => dio.post<void>(
  '/meters/${pending.meterId}/readings',
  data: {'value': pending.value},
  options: Options(headers: {'Idempotency-Key': const Uuid().v4()}),
);
```

What breaks: A new `Idempotency-Key` on every attempt: when an answer is lost, "Send now" stores the reading twice, and the billing office sees the meter as Query. `meterReplaced` is also never sent, so a replaced meter's lower reading is refused.

The fix: Make the key once, when the reader taps Save, keep it with the reading in the outbox, and send that same key on every attempt. Send `meterReplaced` too.

## 8

```dart
Text(left == 1 ? '1 meter left' : '$left meters left'),
```

What breaks: `n == 1` and English in a widget: an isiZulu reader gets English, and the plural is wrong in any language with other rules (isiZulu says "one" for 0 too).

The fix: One ICU plural message, `{count, plural, one{…} other{…}}`, in `app_en.arb` and `app_zu.arb`, called as `l10n.metersLeft(left)`.
