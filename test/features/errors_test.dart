import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Pumps in small steps, up to [total]: no pumpAndSettle, so a test can
/// say "within half a second".
Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 50);
  for (var spent = Duration.zero; spent < total; spent += step) {
    await tester.pump(step);
  }
}

void main() {
  testWidgets('a meter not on the round: "Meter not found."', (tester) async {
    await pumpMeterRead(
      tester,
      deepLink: '/round/meters/M-9999',
      settle: false,
    );
    await pumpFor(tester, const Duration(milliseconds: 500));

    expect(find.text('Meter not found.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets("the server's fault: words, a reference, a way to try again", (
    tester,
  ) async {
    final harness = await pumpMeterRead(
      tester,
      deepLink: '/round/meters/M-1012',
      settle: false,
    );
    await pumpFor(tester, const Duration(milliseconds: 500));

    expect(find.text('Something went wrong on our side.'), findsOneWidget);
    expect(find.textContaining('Reference 00-4bf92f35'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);

    // A 500 is an answer: it is never retried by itself.
    final received = harness.server.requestsReceived;
    await tester.pump(const Duration(seconds: 3));
    expect(harness.server.requestsReceived, received);
  });

  testWidgets('no signal: says so, and "Try again" opens it once back', (
    tester,
  ) async {
    final harness = await pumpMeterRead(tester);
    harness.server.online = false;

    await tester.tap(find.text('4 Lwandle Street'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No signal'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);

    harness.server.online = true;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('4 Lwandle Street'), findsOneWidget);
    expect(find.textContaining('Last reading 30'), findsOneWidget);
  });

  testWidgets("a wrong password: That email and password don't match.", (
    tester,
  ) async {
    await pumpMeterRead(tester, signedInAs: null);

    await tester.enterText(find.bySemanticsLabel('Email'), thandeka);
    await tester.enterText(find.bySemanticsLabel('Password'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text("That email and password don't match."), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('sign-in with no signal says so', (tester) async {
    final harness = await pumpMeterRead(tester, signedInAs: null);
    harness.server.online = false;

    await tester.enterText(find.bySemanticsLabel('Email'), thandeka);
    await tester.enterText(find.bySemanticsLabel('Password'), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No signal'), findsOneWidget);
  });
}
