import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meterread/app/format.dart';
import 'package:meterread/app/widgets/failure_view.dart';
import 'package:meterread/core/failure.dart';
import 'package:meterread/features/round/domain/meter.dart';
import 'package:meterread/features/round/presentation/round_providers.dart';
import 'package:meterread/l10n/app_localizations.dart';

/// The reading form: the number on the meter, in whole kWh.
///
/// It also shows the reading waiting on the phone, while there is one, so
/// the form (and what the reader typed) stays put through Save, send and
/// a refusal.
class ReadingForm extends ConsumerStatefulWidget {
  /// Creates the form for [meterId].
  const new({required this.meterId, super.key});

  /// The meter being read.
  final String meterId;

  @override
  ConsumerState<ReadingForm> createState() => _ReadingFormState();
}

/// What the reader typed, as a whole number of kWh: digits and spaces
/// only ("48 590"), never through a double. Null when it isn't one.
int? parseReading(String typed) {
  final trimmed = typed.trim();
  if (!RegExp(r'^[0-9][0-9  ]*$').hasMatch(trimmed)) return null;
  return int.tryParse(trimmed.replaceAll(RegExp('[  ]'), ''));
}

class _ReadingFormState extends ConsumerState<ReadingForm> {
  final _reading = TextEditingController();
  bool _meterReplaced = false;
  bool _saving = false;

  // Under the field: the phone's check, or the server's field error.
  String? _fieldError;

  // The last failure that wasn't about the field, for the waiting card.
  Object? _sendFailure;

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final typed = _reading.text;
    if (typed.trim().isEmpty) {
      setState(() => _fieldError = l10n.enterReading);
      return;
    }
    final value = parseReading(typed);
    if (value == null) {
      setState(() => _fieldError = l10n.digitsOnly);
      return;
    }
    await _run(
      (outbox) => outbox.capture(
        widget.meterId,
        value: value,
        meterReplaced: _meterReplaced,
      ),
    );
  }

  Future<void> _sendNow(WaitingReading pending) => _run(
    (outbox) => outbox.send(widget.meterId),
    // Refused: put the reading back in the field to correct.
    typedBack: formatKwh(pending.value),
  );

  Future<void> _run(
    Future<AcceptedReading?> Function(ReadingOutbox outbox) attempt, {
    String? typedBack,
  }) async {
    // The form may go once the reading is accepted: keep the container.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _saving = true;
      _fieldError = null;
      _sendFailure = null;
    });
    try {
      final accepted = await attempt(container.read(readingOutboxProvider));
      if (accepted != null) {
        container
          ..invalidate(meterDetailProvider(widget.meterId))
          ..invalidate(roundSyncProvider);
      } else if (mounted) {
        setState(() => _sendFailure = const NoSignal());
      }
    } on FieldErrors catch (refused) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        if (typedBack != null) _reading.text = typedBack;
        _fieldError =
            refused.first('value') ??
            failureMessage(l10n, refused, notFound: l10n.meterNotFound);
      });
    } on Failure catch (failure) {
      if (mounted) setState(() => _sendFailure = failure);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(pendingReadingProvider(widget.meterId)).value;
    if (pending != null && !_saving) return _waiting(l10n, pending);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _reading,
          keyboardType: TextInputType.number,
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: l10n.readingLabel,
            hintText: l10n.readingHint,
            errorText: _fieldError,
            errorMaxLines: 4,
          ),
          onChanged: (_) {
            if (_fieldError != null) setState(() => _fieldError = null);
          },
          onSubmitted: (_) => _save(),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.meterReplaced),
          value: _meterReplaced,
          onChanged: _saving
              ? null
              : (value) => setState(() => _meterReplaced = value ?? false),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.saveReading),
        ),
        if (_sendFailure case final failure? when pending == null) ...[
          const SizedBox(height: 8),
          Text(failureMessage(l10n, failure, notFound: l10n.meterNotFound)),
        ],
      ],
    );
  }

  Widget _waiting(AppLocalizations l10n, WaitingReading pending) {
    final failure = _sendFailure;
    final why = switch (OutboxError.fromStored(pending.lastError)) {
      OutboxError.noSignal => l10n.notSentNoSignal,
      OutboxError.server => l10n.notSentServer,
      null => null,
    };
    final reference = failure == null ? null : failureReference(failure);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.notSentYet(formatKwh(pending.value)),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (why != null) Text(why),
            if (reference != null) SelectableText(l10n.reference(reference)),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () =>
                      ref.read(readingOutboxProvider).discard(widget.meterId),
                  child: Text(l10n.discard),
                ),
                FilledButton.tonal(
                  onPressed: () => _sendNow(pending),
                  child: Text(l10n.sendNow),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
