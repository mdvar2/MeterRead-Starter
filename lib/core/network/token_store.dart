import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'token_store.g.dart';

/// Where the refresh token is kept between launches. Keep this interface
/// and its three methods: the test harness gives the app its own store.
abstract interface class TokenStore {
  /// The stored refresh token, or null when nobody is signed in.
  Future<String?> read();

  /// Keeps [refreshToken], replacing any earlier one.
  Future<void> write(String refreshToken);

  /// Forgets the token.
  Future<void> delete();
}

/// Keeps the refresh token in the app's preferences.
///
/// Not any more: in the Android Keystore / iOS Keychain, through
/// flutter_secure_storage. The access token never comes here: it stays in
/// memory (see AccessToken).
final class SecureTokenStore implements TokenStore {
  /// Creates the store.
  new([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _key = 'refresh_token';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String refreshToken) =>
      _storage.write(key: _key, value: refreshToken);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// The app's token store. Keep this name: the test harness overrides it.
@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) => SecureTokenStore();
