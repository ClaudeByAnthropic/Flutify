import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Shared Apple-style timing for the Android player's coordinated transitions.
abstract final class PlayerLyricsMotion {
  // Responsive takeoff with a long, gentle landing; no bounce or second easing
  // on any component. The scene's geometry receives this already-eased value.
  static const curve = Cubic(0.22, 0.8, 0.22, 1);
  static const duration = Duration(milliseconds: 640);
  static const chromeDuration = Duration(milliseconds: 300);
  static const idleDelay = Duration(milliseconds: 3500);
}

/// UI-only motion and inactivity state; playback ticks must not call [activity].
class PlayerLyricsController extends ChangeNotifier {
  PlayerLyricsController({required TickerProvider vsync})
    : transition = AnimationController(vsync: vsync),
      chrome = AnimationController(vsync: vsync, value: 1) {
    transition.addListener(notifyListeners);
    chrome.addListener(notifyListeners);
  }

  final AnimationController transition;
  final AnimationController chrome;
  final Set<int> _pointers = {};
  Timer? _timer;
  bool _lyrics = false;
  bool _idle = false;
  bool _active = true;
  bool _reduceMotion = false;
  bool _accessibleNavigation = false;
  bool _interactionSuspended = false;
  bool _disposed = false;

  bool get controlsVisible => !_idle;

  void configure({
    required bool reduceMotion,
    required bool accessibleNavigation,
  }) {
    if (_reduceMotion == reduceMotion &&
        _accessibleNavigation == accessibleNavigation) {
      return;
    }
    _reduceMotion = reduceMotion;
    _accessibleNavigation = accessibleNavigation;
    if (reduceMotion) {
      transition.value = _lyrics ? 1 : 0;
      chrome.value = _idle ? 0 : 1;
    }
    if (accessibleNavigation) {
      activity();
    } else {
      _scheduleIdle();
    }
  }

  void setLyrics(bool value) {
    if (_lyrics == value) return;
    _lyrics = value;
    _timer?.cancel();
    _reveal();
    // Easing the controller itself starts every reversal at its current value.
    // Switching between forward/reverse CurvedAnimations can otherwise jump.
    transition
        .animateTo(
          value ? 1 : 0,
          duration: _reduceMotion ? Duration.zero : PlayerLyricsMotion.duration,
          curve: PlayerLyricsMotion.curve,
        )
        .whenCompleteOrCancel(() {
          if (!_disposed) _scheduleIdle();
        });
    notifyListeners();
  }

  void _reveal() {
    final changed = _idle;
    _idle = false;
    chrome.animateTo(
      1,
      duration: _reduceMotion
          ? Duration.zero
          : PlayerLyricsMotion.chromeDuration,
      curve: PlayerLyricsMotion.curve,
    );
    if (changed) notifyListeners();
  }

  void activity() {
    _timer?.cancel();
    if (!_active) return;
    _reveal();
    _scheduleIdle();
  }

  void pointerDown(int pointer) {
    _pointers.add(pointer);
    activity();
  }

  void pointerUp(int pointer) {
    // Global release/cancel recovery also observes unrelated pointers.
    if (!_pointers.remove(pointer)) return;
    activity();
  }

  void setInteractionSuspended(bool suspended) {
    if (_interactionSuspended == suspended) return;
    _interactionSuspended = suspended;
    activity();
  }

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _timer?.cancel();
    _pointers.clear();
    if (active) activity();
  }

  void _scheduleIdle() {
    _timer?.cancel();
    if (!_active ||
        !_lyrics ||
        _accessibleNavigation ||
        _interactionSuspended ||
        _pointers.isNotEmpty ||
        transition.isAnimating ||
        transition.value != 1) {
      return;
    }
    _timer = Timer(PlayerLyricsMotion.idleDelay, () {
      _idle = true;
      chrome.animateTo(
        0,
        duration: _reduceMotion
            ? Duration.zero
            : PlayerLyricsMotion.chromeDuration,
        curve: PlayerLyricsMotion.curve,
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    transition.dispose();
    chrome.dispose();
    super.dispose();
  }
}
