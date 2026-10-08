// End-to-end test on a real device / emulator, with the real services
// (audio, haptics, shared_preferences, ads SDK, billing) wired up by main().
//
//   flutter test integration_test -d <device>
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/main.dart' as app;
import 'package:hue_lock/ui/game_screen.dart';
import 'package:integration_test/integration_test.dart';

/// Pumps real frames until [finder] (dis)appears.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  bool present = true,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty == present) return;
  }
  throw TestFailure(
    'Timed out waiting for $finder to ${present ? 'appear' : 'disappear'}',
  );
}

/// Lets real time pass while frames keep rendering.
Future<void> waitMs(WidgetTester tester, int ms) async {
  final clock = Stopwatch()..start();
  while (clock.elapsedMilliseconds < ms) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Waits until the run is live. A slow device (e.g. a CI emulator on its
/// first frames) can stall for over 0.5 s, which the game treats as a pause
/// and answers with a short countdown.
Future<void> waitPlaying(WidgetTester tester, GameEngine e) async {
  if (e.phase != GamePhase.playing) {
    debugPrint('waiting for play, phase is ${e.phase}');
  }
  final clock = Stopwatch()..start();
  while (e.phase != GamePhase.playing) {
    if (clock.elapsed > const Duration(seconds: 30)) {
      throw TestFailure('run never resumed, phase is ${e.phase}');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Seconds until the pointer crosses the center of the current target.
double untilTargetCenter(GameEngine e) {
  final r = e.round!;
  final now = e.time > r.startTime ? e.time : r.startTime;
  final rel = r.spec.relativeSpeed;
  final travel = travelDistance(
    r.localPointerAt(now),
    r.spec.target.center,
    rel.sign.toInt(),
  );
  return (now - e.time) + travel / rel.abs();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('full game flow on device', (tester) async {
    app.main();
    await waitFor(tester, find.text('TAP TO PLAY'));
    expect(find.text('HUE LOCK'), findsOneWidget);

    final view = tester.view;
    final size = view.physicalSize / view.devicePixelRatio;
    // Above the ring: only non-interactive labels live here.
    final empty = Offset(size.width / 2, size.height * 0.3);

    GameEngine engine() =>
        (tester.state(find.byType(GameScreen)) as dynamic).engine as GameEngine;

    // 1. Start a run and clear 10 rounds with perfectly timed taps,
    //    exercising the real ticker, sounds and haptics.
    await tester.tapAt(empty);
    await waitFor(tester, find.text('TAP TO PLAY'), present: false);
    final e = engine();
    for (var i = 0; i < 10; i++) {
      await waitPlaying(tester, e);
      final wait = untilTargetCenter(e);
      e.tap(e.time + wait);
      expect(e.phase, GamePhase.playing, reason: 'round $i should be a hit');
      await waitMs(tester, (wait * 1000).round() + 40);
    }
    expect(e.level, 10);
    expect(e.multiplier, greaterThan(1));
    await waitFor(tester, find.text('${e.score}'));

    // 2. Miss on purpose: a new round's target is never at the pointer.
    await waitPlaying(tester, e);
    await tester.tapAt(empty);
    await waitFor(tester, find.text('TAP TO RETRY'));
    expect(find.text('CONTINUE'), findsOneWidget);

    // 3. Instant restart, then fail again straight away.
    await waitMs(tester, 300);
    await tester.tapAt(empty);
    await waitFor(tester, find.text('TAP TO RETRY'), present: false);
    expect(engine().score, 0);
    await waitPlaying(tester, engine());
    await tester.tapAt(empty);
    await waitFor(tester, find.text('TAP TO RETRY'));

    // 4. Back home (no interstitial during the first runs).
    await tester.tap(find.byTooltip('Home'));
    await waitFor(tester, find.text('TAP TO PLAY'));

    // 5. Shop.
    await tester.tap(find.text('SHOP'));
    await waitFor(tester, find.text('BALLS'));
    expect(find.text('Classic'), findsOneWidget);
    await tester.tap(find.text('RINGS'));
    await waitFor(tester, find.text('Neon'));
    await tester.pageBack();
    await waitFor(tester, find.text('TAP TO PLAY'));

    // 6. Settings: turn on colorblind mode, then play with it.
    await tester.tap(find.text('SETTINGS'));
    await waitFor(tester, find.text('Colorblind mode'));
    await tester.tap(find.text('Colorblind mode'));
    await waitMs(tester, 200);
    await tester.pageBack();
    await waitFor(tester, find.text('TAP TO PLAY'));

    await tester.tapAt(empty);
    await waitFor(tester, find.text('TAP TO PLAY'), present: false);
    await waitPlaying(tester, engine());
    final wait = untilTargetCenter(engine());
    engine().tap(engine().time + wait);
    expect(engine().level, 1);
    await waitMs(tester, (wait * 1000).round() + 40);
    await waitPlaying(tester, engine());
    await tester.tapAt(empty);
    await waitFor(tester, find.text('TAP TO RETRY'));
  });
}
