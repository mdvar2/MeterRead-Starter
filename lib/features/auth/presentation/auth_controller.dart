import 'dart:async';

import 'package:meterread/app/database/app_database.dart';
import 'package:meterread/app/network/dio_provider.dart';
import 'package:meterread/core/failure.dart';
import 'package:meterread/core/network/access_token.dart';
import 'package:meterread/core/network/token_store.dart';
import 'package:meterread/features/auth/data/auth_api.dart';
import 'package:meterread/features/auth/domain/reader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_controller.g.dart';

/// Who is signed in. keepAlive: the session outlives every screen.
@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  @override
  AuthState build() {
    // After build returns: build itself must not change the state.
    unawaited(Future.microtask(_restore));
    return const Restoring();
  }

  // On launch: one refresh with the stored token, if there is one.
  Future<void> _restore() async {
    final store = ref.read(tokenStoreProvider);
    final stored = await store.read();
    if (stored == null) {
      state = const SignedOut();
      return;
    }
    try {
      final pair = await ref.read(authApiProvider).refresh(stored);
      await _keep(pair);
      state = SignedIn(pair.reader);
    } on SignedOutFailure {
      // The API refused the stored session.
      await _forget();
    } on FieldErrors {
      await _forget();
    } on Failure {
      // No signal, or the server's fault: the session may be fine. Keep the
      // refresh token and work from the phone; the session interceptor
      // refreshes on the first request that gets an answer.
      state = const SignedIn(null);
    }
  }

  /// Signs in. Throws whatever the API call throws.
  ///
  /// That's a Failure: a wrong password is a SignedOutFailure.
  Future<void> signIn(String email, String password) async {
    final pair = await ref
        .read(authApiProvider)
        .signIn(email.trim().toLowerCase(), password);
    // Nothing of an earlier reader stays on the phone.
    await ref.read(appDatabaseProvider).wipe();
    await _keep(pair);
    state = SignedIn(pair.reader);
  }

  /// Signs out: tells the API, then forgets the tokens.
  ///
  /// And everything the phone kept, readings waiting included.
  Future<void> signOut() async {
    final stored = await ref.read(tokenStoreProvider).read();
    if (stored != null) {
      try {
        await ref.read(authApiProvider).signOut(stored);
      } on Failure {
        // Signed out on the phone even if the API didn't hear.
      }
    }
    await _forget();
  }

  /// The API refused a refresh: sign in again.
  Future<void> sessionEnded() => _forget();

  Future<void> _forget() async {
    await ref.read(tokenStoreProvider).delete();
    ref.read(accessTokenProvider.notifier).clear();
    await ref.read(appDatabaseProvider).wipe();
    state = const SignedOut();
  }

  Future<void> _keep(TokenPair pair) async {
    await ref.read(tokenStoreProvider).write(pair.refreshToken);
    ref
        .read(accessTokenProvider.notifier)
        .save(pair.accessToken, expiresAt: pair.expiresAt);
  }
}
