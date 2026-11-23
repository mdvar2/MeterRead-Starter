import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:meterread/core/failure.dart';
import 'package:meterread/l10n/app_localizations.dart';

/// The [Failure] behind [error], unwrapping Riverpod's ProviderException.
/// Anything that isn't one is the server's fault, with no reference.
Failure asFailure(Object error) => switch (error) {
  final Failure failure => failure,
  ProviderException(:final exception) => asFailure(exception),
  _ => const ServerFault(),
};

/// [error] in the reader's words. [notFound] and [signedOut] replace the
/// general words where a screen knows better ("Meter not found.").
String failureMessage(
  AppLocalizations l10n,
  Object error, {
  String? notFound,
  String? signedOut,
}) => switch (asFailure(error)) {
  NoSignal() => l10n.noSignal,
  NotFound() => notFound ?? l10n.notFound,
  SignedOutFailure() => signedOut ?? l10n.signedOutFailure,
  ServerFault() => l10n.serverFault,
  FieldErrors(:final errors) =>
    errors.values.expand((messages) => messages).firstOrNull ?? l10n.refused,
};

/// The reference support asks for, when it's the server's fault.
String? failureReference(Object error) => switch (asFailure(error)) {
  ServerFault(:final reference?) => reference,
  _ => null,
};

/// A failure's words, its reference when support will ask, and the way
/// forward.
class FailureView extends StatelessWidget {
  /// Creates the view for [error]. [onRetry] asks again.
  const new({
    required this.error,
    required this.onRetry,
    this.notFound,
    super.key,
  });

  /// What went wrong.
  final Object error;

  /// "Try again".
  final VoidCallback onRetry;

  /// The screen's own words for "not found".
  final String? notFound;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final reference = failureReference(error);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              failureMessage(l10n, error, notFound: notFound),
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (reference != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                l10n.reference(reference),
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l10n.tryAgain)),
          ],
        ),
      ),
    );
  }
}
