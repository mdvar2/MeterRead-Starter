import 'package:dio/dio.dart';
import 'package:meterread/core/failure.dart';
import 'package:meterread/core/network/access_token.dart';
import 'package:meterread/core/network/failure_from.dart';
import 'package:meterread/core/network/token_store.dart';
import 'package:meterread/features/auth/data/auth_api.dart';

/// Puts the access token on every request. On a 401 it refreshes the
/// tokens and sends the request again.
///
/// Once per expiry.
///
/// A [QueuedInterceptor]: when two requests fail together, their errors are
/// handled one after the other. The second sees that the token it carried
/// is no longer the current one, so someone has already refreshed, and
/// just sends again with the new token: one refresh per expiry. (Each
/// refresh token works once; a second refresh with it would end the
/// session.)
class SessionInterceptor extends QueuedInterceptor {
  /// Creates the interceptor. retryWith is a Dio without this interceptor.
  new({
    required this._api,
    required this._store,
    required this._readAccess,
    required this._writeAccess,
    required this._retryWith,
    required this._onSessionEnded,
  });

  final AuthApi _api;
  final TokenStore _store;
  final SessionToken? Function() _readAccess;
  final void Function(SessionToken token) _writeAccess;
  final Dio _retryWith;
  final void Function() _onSessionEnded;

  static const _bearer = 'Bearer ';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_readAccess() case final token?) {
      options.headers['Authorization'] = '$_bearer${token.value}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }
    final carried = _carriedToken(err.requestOptions);
    final current = _readAccess()?.value;

    // Someone refreshed while this request was out: send it again with
    // the new token, without refreshing again.
    if (current != null && current != carried) {
      await _sendAgain(err.requestOptions, current, handler);
      return;
    }

    final refreshToken = await _store.read();
    if (refreshToken == null) {
      _onSessionEnded();
      handler.next(err);
      return;
    }
    final TokenPair pair;
    try {
      pair = await _api.refresh(refreshToken);
    } on Failure catch (failure) {
      // Only the API refusing the refresh ends the session. No signal, or
      // the server's fault, leaves the reader signed in to try again.
      if (failure is SignedOutFailure || failure is FieldErrors) {
        _onSessionEnded();
      }
      handler.next(
        DioException(requestOptions: err.requestOptions, error: failure),
      );
      return;
    }
    await _store.write(pair.refreshToken);
    _writeAccess((value: pair.accessToken, expiresAt: pair.expiresAt));
    await _sendAgain(err.requestOptions, pair.accessToken, handler);
  }

  Future<void> _sendAgain(
    RequestOptions options,
    String accessToken,
    ErrorInterceptorHandler handler,
  ) async {
    options.headers['Authorization'] = '$_bearer$accessToken';
    try {
      handler.resolve(await _retryWith.fetch<Object?>(options));
    } on DioException catch (again) {
      handler.next(again);
    } on Object catch (again) {
      handler.next(
        DioException(requestOptions: options, error: failureFrom(again)),
      );
    }
  }

  static String? _carriedToken(RequestOptions options) {
    for (final MapEntry(:key, :value) in options.headers.entries) {
      if (key.toLowerCase() == 'authorization' &&
          value is String &&
          value.startsWith(_bearer)) {
        return value.substring(_bearer.length);
      }
    }
    return null;
  }
}
