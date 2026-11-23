import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meterread/core/network/access_token.dart';
import 'package:meterread/features/auth/domain/reader.dart';
import 'package:meterread/features/auth/presentation/auth_controller.dart';

import '../support/harness.dart';

void main() {
  testWidgets('tokens expire, then a screen with two requests: one refresh', (
    tester,
  ) async {
    final harness = await pumpMeterRead(tester);
    final before = harness.server.refreshCalls;

    harness.server.expireAccessTokens();
    // 4 Lwandle Street: GET /meters/M-1002 and its readings, together.
    await tester.tap(find.text('4 Lwandle Street'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Last reading 30'), findsOneWidget);
    expect(harness.server.refreshCalls, before + 1);
    expect(harness.container.read(authControllerProvider), isA<SignedIn>());
    expect(harness.tokens.refreshToken, isNotNull);
  });

  testWidgets('launching with no signal keeps the reader signed in', (
    tester,
  ) async {
    // Stored session, but no signal at launch.
    final harness = await pumpMeterRead(tester, settle: false);
    harness.server.online = false;
    await tester.pumpAndSettle();

    expect(harness.container.read(authControllerProvider), isA<SignedIn>());
    expect(harness.tokens.refreshToken, isNotNull);
  });

  testWidgets('a session the API ends: back to sign-in, nothing left', (
    tester,
  ) async {
    final harness = await pumpMeterRead(tester);

    harness.server.expireAccessTokens();
    harness.tokens.refreshToken = 'rt-spent';
    await tester.tap(find.text('4 Lwandle Street'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(harness.tokens.refreshToken, isNull);
    expect(harness.container.read(accessTokenProvider), isNull);
    expect(await rowsInDatabase(tester, harness.container), 0);
  });
}
