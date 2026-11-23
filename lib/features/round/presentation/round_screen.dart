import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:meterread/app/format.dart';
import 'package:meterread/app/router/routes.dart';
import 'package:meterread/app/widgets/failure_view.dart';
import 'package:meterread/core/cache/snapshot.dart';
import 'package:meterread/core/failure.dart';
import 'package:meterread/core/fakes/test_tools.dart';
import 'package:meterread/features/auth/presentation/auth_controller.dart';
import 'package:meterread/features/round/domain/meter.dart';
import 'package:meterread/features/round/presentation/round_providers.dart';
import 'package:meterread/l10n/app_localizations.dart';

/// Today's round: every meter the reader visits, in walking order.
///
/// From the phone first: the round the phone kept shows at once, while
/// [roundSyncProvider] fetches a newer one in the background. When that
/// fails, the header says so and says how old the round is.
class RoundScreen extends ConsumerWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sync = ref.watch(roundSyncProvider);
    final cached = ref.watch(roundProvider);
    final waiting = ref.watch(waitingCountProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.roundTitle),
        actions: [
          const TestToolsButton(),
          IconButton(
            tooltip: l10n.signOut,
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context, ref, waiting),
          ),
        ],
      ),
      body: switch (cached.value) {
        final snapshot? => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: _RoundList(
            snapshot: snapshot,
            lastFetchFailed: switch (sync) {
              AsyncError(:final error) => error,
              _ => null,
            },
            onRetry: () => ref.invalidate(roundSyncProvider),
          ),
        ),
        // Nothing on the phone yet: the first fetch decides.
        null => switch (sync) {
          AsyncError(:final error) when !cached.isLoading => FailureView(
            error: error,
            onRetry: () => ref.invalidate(roundSyncProvider),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      },
    );
  }

  static Future<void> _refresh(WidgetRef ref) async {
    try {
      ref.invalidate(roundSyncProvider);
      await ref.read(roundSyncProvider.future);
    } on Object {
      // The header says what went wrong.
    }
  }

  // Readings still waiting would be lost: ask first, and say how many.
  static Future<void> _signOut(
    BuildContext context,
    WidgetRef ref,
    int waiting,
  ) async {
    if (waiting > 0) {
      final l10n = AppLocalizations.of(context);
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.signOutTitle),
          content: Text(l10n.unsentReadings(waiting)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.signOut),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }
    await ref.read(authControllerProvider.notifier).signOut();
  }
}

class _RoundList extends ConsumerWidget {
  const new({
    required this.snapshot,
    required this.lastFetchFailed,
    required this.onRetry,
  });

  final Snapshot<Round> snapshot;
  final Object? lastFetchFailed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final round = snapshot.value;
    final waiting = ref.watch(waitingMetersProvider).value ?? const <String>{};
    final age = _age(context, snapshot.fetchedAt);
    final failed = lastFetchFailed;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ListTile(
          title: Text(round.name),
          subtitle: Text(l10n.metersLeft(round.metersLeft)),
        ),
        if (failed == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(l10n.lastUpdated(age)),
          )
        else
          MaterialBanner(
            content: Text(
              l10n.staleRound(switch (asFailure(failed)) {
                NoSignal() => l10n.noSignalShort,
                _ => l10n.roundNotUpdated,
              }, age),
            ),
            actions: [
              TextButton(onPressed: onRetry, child: Text(l10n.tryAgain)),
            ],
          ),
        const Divider(height: 1),
        for (final meter in round.meters)
          ListTile(
            leading: ExcludeSemantics(child: _StatusIcon(status: meter.status)),
            title: Text(meter.address),
            subtitle: Text(
              [
                l10n.meterRow(
                  meter.meterNumber,
                  statusWord(l10n, meter.status),
                ),
                if (waiting.contains(meter.id)) l10n.notSentYetRow,
              ].join('\n'),
            ),
            onTap: () => MeterRoute(meterId: meter.id).go(context),
          ),
      ],
    );
  }

  // 09:27 today; with the day when it's older.
  static String _age(BuildContext context, DateTime fetchedAt) {
    final locale = Localizations.localeOf(context).toString();
    final local = fetchedAt.toLocal();
    final now = DateTime.now();
    final time = DateFormat('HH:mm', locale).format(local);
    final today =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return today ? time : '${formatDay(context, local)} $time';
  }
}

/// A meter's status in words: the icon only helps.
String statusWord(AppLocalizations l10n, MeterStatus status) =>
    switch (status) {
      MeterStatus.due => l10n.statusDue,
      MeterStatus.read => l10n.statusRead,
      MeterStatus.query => l10n.statusQuery,
      MeterStatus.unknown => l10n.statusUnknown,
    };

class _StatusIcon extends StatelessWidget {
  const new({required this.status});

  final MeterStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (status) {
      MeterStatus.due => Icon(
        Icons.radio_button_unchecked,
        color: colors.outline,
      ),
      MeterStatus.read => Icon(Icons.check_circle, color: colors.primary),
      MeterStatus.query => Icon(Icons.error, color: colors.error),
      MeterStatus.unknown => Icon(Icons.help, color: colors.outline),
    };
  }
}
