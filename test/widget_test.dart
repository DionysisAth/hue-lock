import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/app.dart';
import 'package:hue_lock/services/ads_service.dart';
import 'package:hue_lock/services/analytics.dart';
import 'package:hue_lock/services/feedback.dart';
import 'package:hue_lock/services/profile_store.dart';
import 'package:hue_lock/services/purchase_service.dart';

import 'test_helpers.dart';

AppServices fakeServices({PlayerProfile? profile}) => AppServices(
  config: loadTestConfig(),
  profile: ProfileStore.memory(profile),
  audio: AudioService(enabled: false),
  haptics: HapticsService()..enabled = false,
  ads: NoAdsService(),
  purchases: NoPurchaseService(),
  analytics: NoAnalytics(),
);

void main() {
  testWidgets('home screen shows title and best, tap starts a run', (
    tester,
  ) async {
    final s = fakeServices(profile: PlayerProfile()..bestScore = 42);
    await tester.pumpWidget(HueLockApp(services: s));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('HUE LOCK'), findsOneWidget);
    expect(find.text('BEST 42'), findsOneWidget);
    expect(find.text('TAP TO PLAY'), findsOneWidget);

    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('TAP TO PLAY'), findsNothing);
    expect(find.text('0'), findsOneWidget);
    expect(s.profile.profile.totalRuns, 1);
  });

  testWidgets('shop buys and equips a skin with coins', (tester) async {
    final s = fakeServices(profile: PlayerProfile()..coins = 1000);
    await tester.pumpWidget(HueLockApp(services: s));
    await tester.pump();
    await tester.tap(find.text('SHOP'));
    await _settle(tester);

    await tester.tap(find.text('Planet'));
    await _settle(tester);
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(s.profile.profile.ownedBalls, contains('planet'));
    expect(s.profile.profile.ball, 'planet');
    expect(s.profile.profile.coins, 1000 - 150);
  });

  testWidgets('settings toggles colorblind mode', (tester) async {
    final s = fakeServices();
    await tester.pumpWidget(HueLockApp(services: s));
    await tester.pump();
    await tester.tap(find.text('SETTINGS'));
    await _settle(tester);
    await tester.tap(find.text('Colorblind mode'));
    await tester.pump();
    expect(s.profile.profile.colorblind, isTrue);
  });

  testWidgets('game over screen appears after a miss', (tester) async {
    final s = fakeServices();
    await tester.pumpWidget(HueLockApp(services: s));
    await tester.pump();
    // Start, then tap straight away: the first target is always well ahead
    // of the pointer, so an immediate tap is a miss.
    await tester.tapAt(const Offset(200, 300));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tapAt(const Offset(200, 300));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('TAP TO RETRY'), findsOneWidget);
    expect(s.profile.profile.totalRuns, 1);
    await tester.pump(const Duration(milliseconds: 200));
  });
}

/// The game canvas animates forever, so pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
