import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meterread/app/database/app_database.dart';

import '../support/harness.dart';

void main() {
  testWidgets('no signal on the round: every meter stays, with its age', (
    tester,
  ) async {
    final harness = await pumpMeterRead(tester);
    harness.server.online = false;

    await tester.fling(
      find.text('2 Lwandle Street'),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(RegExp(r'^No signal\. Last updated \d\d:\d\d\.$')),
      findsOneWidget,
    );
    expect(find.text('2 Lwandle Street'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('21 Umthombo Road'), 200);
    expect(find.text('21 Umthombo Road'), findsOneWidget);
  });

  testWidgets('the whole round, every page, is kept on the phone', (
    tester,
  ) async {
    final harness = await pumpMeterRead(tester);
    final database = harness.container.read(appDatabaseProvider);
    final rows = await tester.runAsync(
      () => database.select(database.cachedMeters).get(),
    );
    expect(rows, hasLength(14));
  });

  testWidgets('a lost answer is stored once', (tester) async {
    final harness = await pumpMeterRead(tester);

    await tester.scrollUntilVisible(find.text('5 Isibaya Crescent'), 200);
    await tester.tap(find.text('5 Isibaya Crescent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Reading in kWh'), '31 250');
    await tester.tap(find.text('Save reading'));
    await tester.pumpAndSettle();

    // The server stored it, but the answer never came back.
    expect(find.textContaining('Not sent yet'), findsOneWidget);
    expect(harness.server.readingsFor('M-1007'), hasLength(1));

    await tester.tap(find.text('Send now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not sent yet'), findsNothing);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Query'), findsNothing);
    expect(harness.server.readingsFor('M-1007'), hasLength(1));
  });

  testWidgets('sign-out with a reading waiting leaves nothing', (tester) async {
    final harness = await pumpMeterRead(tester);

    await tester.tap(find.text('2 Lwandle Street'));
    await tester.pumpAndSettle();
    harness.server.online = false;
    await tester.enterText(find.bySemanticsLabel('Reading in kWh'), '48 590');
    await tester.tap(find.text('Save reading'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not sent yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    // Asks first, and says how many would be lost.
    expect(find.textContaining("1 reading hasn't been sent"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(await rowsInDatabase(tester, harness.container), 0);
    expect(harness.tokens.refreshToken, isNull);
  });

  testWidgets('sign-out can be cancelled while readings wait', (tester) async {
    final harness = await pumpMeterRead(tester);

    await tester.tap(find.text('2 Lwandle Street'));
    await tester.pumpAndSettle();
    harness.server.online = false;
    await tester.enterText(find.bySemanticsLabel('Reading in kWh'), '48 590');
    await tester.tap(find.text('Save reading'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // The round says which meter has a reading waiting.
    expect(find.textContaining('Not sent yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text("Today's round"), findsOneWidget);
    expect(harness.tokens.refreshToken, isNotNull);
  });

  testWidgets('signing in leaves nothing of the last reader', (tester) async {
    final harness = await pumpMeterRead(tester);
    expect(await rowsInDatabase(tester, harness.container), greaterThan(0));

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Email'), sipho);
    await tester.enterText(find.bySemanticsLabel('Password'), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('9 Ndlovu Lane'), findsOneWidget);
    expect(find.text('2 Lwandle Street'), findsNothing);
  });
}
