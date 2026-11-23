import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meterread/app/format.dart';
import 'package:meterread/app/widgets/failure_view.dart';
import 'package:meterread/core/fakes/test_tools.dart';
import 'package:meterread/features/round/domain/meter.dart';
import 'package:meterread/features/round/presentation/reading_form.dart';
import 'package:meterread/features/round/presentation/round_providers.dart';
import 'package:meterread/features/round/presentation/round_screen.dart';
import 'package:meterread/l10n/app_localizations.dart';

/// One meter: what the server knows about it, and the reading form while
/// it's due.
class MeterScreen extends ConsumerWidget {
  /// Creates the screen for [meterId].
  const new({required this.meterId, super.key});

  /// `M-1001`.
  final String meterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(meterId), actions: const [TestToolsButton()]),
      body: switch (ref.watch(meterDetailProvider(meterId))) {
        AsyncError(:final error) => FailureView(
          error: error,
          notFound: l10n.meterNotFound,
          onRetry: () => ref.invalidate(meterDetailProvider(meterId)),
        ),
        // While it's fetched again after a reading, keep showing it.
        AsyncValue(value: final Meter meter) => _MeterBody(meter: meter),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _MeterBody extends ConsumerWidget {
  const new({required this.meter});

  final Meter meter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final pending = ref.watch(pendingReadingProvider(meter.id)).value;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(meter.address, style: text.titleLarge),
        Text(l10n.meterAndAccount(meter.meterNumber, meter.accountNumber)),
        const SizedBox(height: 8),
        Text(statusWord(l10n, meter.status), style: text.titleMedium),
        Text(
          l10n.lastReading(
            formatKwh(meter.lastReading),
            formatDay(context, meter.lastReadOn),
          ),
        ),
        if (meter.thisCycle case final reading?) ...[
          // The usage and the flag are the server's answers, shown as sent.
          Text(
            l10n.thisCycle(
              formatKwh(reading.value),
              formatKwh(reading.consumption),
            ),
          ),
          if (reading.flagged) Text(l10n.flagged),
        ] else if (meter.status != MeterStatus.due)
          Text(l10n.readThisCycle),
        if (meter.status == MeterStatus.query) Text(l10n.queryExplained),
        const SizedBox(height: 16),
        // The form while it's due, and the reading waiting while there is
        // one: one widget, so what the reader typed survives a refusal.
        if (pending != null || meter.status == MeterStatus.due)
          ReadingForm(meterId: meter.id),
        const SizedBox(height: 16),
        Text(l10n.earlierReadings, style: text.titleMedium),
        for (final past in meter.history)
          Text(
            l10n.pastReading(
              formatKwh(past.value),
              formatDay(context, past.readOn),
            ),
          ),
      ],
    );
  }
}
