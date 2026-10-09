import 'package:flutify_app/ui/screens/player/player_lyrics_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unchanged dependency configuration cannot restart idle', (
    tester,
  ) async {
    final motion = PlayerLyricsController(vsync: const TestVSync());
    motion.configure(reduceMotion: true, accessibleNavigation: false);
    motion.setLyrics(true);
    for (var cycle = 0; cycle < 3; cycle++) {
      motion.activity();
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
        motion.configure(reduceMotion: true, accessibleNavigation: false);
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(motion.controlsVisible, isFalse, reason: 'idle cycle $cycle');
      motion.configure(reduceMotion: true, accessibleNavigation: false);
      expect(motion.chrome.value, 0);
    }
    motion.dispose();
  });

  testWidgets('untracked pointer releases do not reveal an idle card', (
    tester,
  ) async {
    final motion = PlayerLyricsController(vsync: const TestVSync());
    motion.configure(reduceMotion: true, accessibleNavigation: false);
    motion.setLyrics(true);
    await tester.pump(const Duration(milliseconds: 3500));
    motion.pointerUp(99);
    expect(motion.controlsVisible, isFalse);
    motion.dispose();
  });

  testWidgets('all scene motion eases nonlinearly and reverses in place', (
    tester,
  ) async {
    final motion = PlayerLyricsController(vsync: const TestVSync());
    motion.setLyrics(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(motion.transition.value, greaterThan(0.5));
    final before = motion.transition.value;
    motion.setLyrics(false);
    expect(motion.transition.value, before);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 641));
    expect(motion.transition.value, 0);
    expect(motion.controlsVisible, isTrue);
    motion.dispose();
  });

  testWidgets('idle begins after entry finishes and hides after 3.5 seconds', (
    tester,
  ) async {
    final motion = PlayerLyricsController(vsync: const TestVSync());
    motion.setLyrics(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 641));
    await tester.pump(const Duration(milliseconds: 3499));
    expect(motion.controlsVisible, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(motion.controlsVisible, isFalse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(motion.chrome.value, lessThan(0.5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(motion.chrome.value, 0);
    motion.dispose();
  });

  testWidgets('held gestures keep controls awake until release', (
    tester,
  ) async {
    final motion = PlayerLyricsController(vsync: const TestVSync());
    motion.setLyrics(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 641));
    motion.pointerDown(1);
    motion.pointerDown(2);
    await tester.pump(const Duration(seconds: 5));
    expect(motion.controlsVisible, isTrue);
    motion.pointerUp(1);
    await tester.pump(const Duration(seconds: 5));
    expect(motion.controlsVisible, isTrue);
    motion.pointerUp(2);
    await tester.pump(const Duration(milliseconds: 3500));
    expect(motion.controlsVisible, isFalse);
    motion.activity();
    expect(motion.controlsVisible, isTrue);
    await tester.pump(const Duration(milliseconds: 3400));
    motion.activity();
    await tester.pump(const Duration(milliseconds: 3400));
    expect(motion.controlsVisible, isTrue);
    motion.dispose();
  });

  testWidgets(
    'reduced motion, accessibility, lifecycle and disposal are safe',
    (tester) async {
      final motion = PlayerLyricsController(vsync: const TestVSync());
      motion.configure(reduceMotion: true, accessibleNavigation: false);
      motion.setLyrics(true);
      expect(motion.transition.value, 1);
      motion.setActive(false);
      await tester.pump(const Duration(seconds: 8));
      expect(motion.controlsVisible, isTrue);
      motion.setActive(true);
      await tester.pump(const Duration(milliseconds: 3500));
      expect(motion.chrome.value, 0);
      motion.configure(reduceMotion: true, accessibleNavigation: true);
      await tester.pump(const Duration(seconds: 8));
      expect(motion.controlsVisible, isTrue);
      motion.setLyrics(false);
      expect(motion.transition.value, 0);
      motion.dispose();
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    },
  );
}
