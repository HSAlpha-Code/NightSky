import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sky/upload_consent.dart';

void main() {
  test('upload consent applies only to the agreed server and can be revoked', () {
    final consent = UploadConsent();
    expect(consent.covers('https://one.example'), isFalse);
    consent.accept('https://one.example');
    expect(consent.covers('https://one.example'), isTrue);
    expect(consent.covers('https://two.example'), isFalse);
    consent.revoke();
    expect(consent.covers('https://one.example'), isFalse);
  });

  testWidgets('disclosure names recipient and optional GPS; cancel does not consent', (
    tester,
  ) async {
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  accepted = await requestUploadConsent(context, 'https://receiver.example');
                },
                child: const Text('Capture'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();
    expect(find.textContaining('https://receiver.example'), findsOneWidget);
    expect(find.textContaining('latitude, longitude and altitude'), findsOneWidget);
    expect(find.textContaining('auto-capture'), findsOneWidget);
    expect(accepted, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
  });

  testWidgets('affirmative upload consent is returned only by Agree', (tester) async {
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  accepted = await requestUploadConsent(context, 'https://receiver.example');
                },
                child: const Text('Capture'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });
}
