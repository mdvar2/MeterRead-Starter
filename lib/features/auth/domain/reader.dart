/// The meter reader who is signed in.
final class Reader {
  /// Creates the reader.
  const new({required this.name, required this.email});

  /// Their name, as the API sends it: "Thandeka Mokoena".
  final String name;

  /// Their email address, which they sign in with.
  final String email;
}

/// Whether anyone is signed in. The router listens to it.
sealed class AuthState {
  const new();
}

/// Launching: asking the API whether the stored session is still good.
final class Restoring extends AuthState {
  /// Creates the state.
  const new();
}

/// Nobody is signed in.
final class SignedOut extends AuthState {
  /// Creates the state.
  const new();
}

/// [reader] is signed in.
final class SignedIn extends AuthState {
  /// Creates the state.
  const new(this.reader);

  /// Who.
  ///
  /// Null when the app launched with a stored session but couldn't
  /// reach the API to ask: the reader keeps working from the phone, and
  /// the first request that gets through refreshes the session.
  final Reader? reader;
}
