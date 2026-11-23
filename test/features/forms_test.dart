import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meterread/app/format.dart';
import 'package:meterread/core/fakes/meter_server.dart';
import 'package:meterread/features/round/presentation/reading_form.dart';
import 'package:meterread/l10n/app_localizations.dart';

import '../support/harness.dart';

Future<void> _save(WidgetTester tester, String typed) async {
  // The label, then any error under the field.
  await tester.enterText(
    find.bySemanticsLabel(RegExp('^Reading in kWh')),
    typed,
  );
  await tester.ensureVisible(find.text('Save reading'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save reading'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the round lists every page, down to 21 Umthombo Road', (
    tester,
  ) async {
    await pumpMeterRead(tester);

    expect(find.text('11 meters left'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('21 Umthombo Road'), 200);
    expect(find.text('21 Umthombo Road'), findsOneWidget);
  });

  testWidgets('each status in words on the round', (tester) async {
    await pumpMeterRead(tester);

    expect(find.text('KW-58210431 · Due'), findsOneWidget);
    expect(find.text('KW-58210433 · Read'), findsOneWidget);
  });

  testWidgets('meters left, in isiZulu', (tester) async {
    await pumpMeterRead(tester, locale: const Locale('zu'));

    expect(find.text('Kusele amamitha angu-11'), findsOneWidget);
  });

  testWidgets('a finished round, in isiZulu', (tester) async {
    await pumpMeterRead(
      tester,
      server: MeterServer(latency: Duration.zero, roundDone: true),
      locale: const Locale('zu'),
    );

    expect(find.text('Kusele imitha engu-0'), findsOneWidget);
  });

  test('meters left is a plural, not n == 1', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final zu = lookupAppLocalizations(const Locale('zu'));
    expect(en.metersLeft(1), '1 meter left');
    expect(en.metersLeft(0), '0 meters left');
    expect(en.metersLeft(2), '2 meters left');
    expect(zu.metersLeft(1), 'Kusele imitha engu-1');
    expect(zu.metersLeft(2), 'Kusele amamitha angu-2');
  });

  test('a reading is digits and spaces, never a double', () {
    expect(parseReading('48 590'), 48590);
    expect(parseReading(' 48590 '), 48590);
    expect(parseReading('48 590'), 48590);
    expect(parseReading('48a90'), isNull);
    expect(parseReading('48.5'), isNull);
    expect(parseReading('48,590'), isNull);
    expect(parseReading('-1'), isNull);
    expect(parseReading(''), isNull);
  });

  testWidgets('the reading form on 2 Lwandle Street', (tester) async {
    await pumpMeterRead(tester, deepLink: '/round/meters/M-1001');

    await _save(tester, '');
    expect(find.text('Enter the reading.'), findsOneWidget);

    await _save(tester, '48a90');
    expect(find.text('Use digits only, like 48 590.'), findsOneWidget);

    // The server's field error, under the field, with what was typed kept.
    await _save(tester, '48 000');
    expect(
      find.textContaining("That's lower than the last reading (48 213 kWh)"),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '48 000');
    expect(field.decoration!.errorText, startsWith("That's lower"));

    await _save(tester, '48 590');
    expect(
      find.text(
        'This month: ${formatKwh(48590)} kWh, ${formatKwh(377)} kWh used',
      ),
      findsOneWidget,
    );
  });

  testWidgets('TalkBack reads the field as "Reading in kWh"', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpMeterRead(tester, deepLink: '/round/meters/M-1001');

    expect(
      tester.getSemantics(find.byType(TextField)),
      isSemantics(label: 'Reading in kWh', isTextField: true),
    );
    semantics.dispose();
  });

  testWidgets('with a reading waiting, the meter screen meets the guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await pumpMeterRead(
      tester,
      deepLink: '/round/meters/M-1001',
    );
    harness.server.online = false;
    await _save(tester, '48 590');
    expect(find.textContaining('Not sent yet'), findsOneWidget);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('the round meets the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpMeterRead(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  group('text at 200%', () {
    testWidgets('the round: nothing overflows', (tester) async {
      await pumpMeterRead(tester, textScale: 2);

      expect(find.text('11 meters left'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('21 Umthombo Road'), 200);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the meter screen with a reading waiting: nothing overflows', (
      tester,
    ) async {
      final harness = await pumpMeterRead(
        tester,
        deepLink: '/round/meters/M-1001',
        textScale: 2,
      );
      harness.server.online = false;
      await _save(tester, '48 590');
      expect(find.textContaining('Not sent yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the meter screen with a refusal: nothing overflows', (
      tester,
    ) async {
      await pumpMeterRead(
        tester,
        deepLink: '/round/meters/M-1001',
        textScale: 2,
      );
      await _save(tester, '48 000');
      expect(find.textContaining("That's lower"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
