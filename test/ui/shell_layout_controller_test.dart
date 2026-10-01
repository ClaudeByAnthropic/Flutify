import 'package:flutify_app/ui/shell/shell_layout_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放栏「播放状态」键：开关右栏的「正在播放 / 歌词」，与播放队列键互不干扰。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('toggles the panel and keeps the last status tab', () {
    final layout = ShellLayoutController();
    expect(layout.playbackStatusVisible, isTrue); // 停靠右栏默认打开在「正在播放」

    layout.togglePlaybackStatus();
    expect(layout.rightPanelVisible, isFalse);

    layout.togglePlaybackStatus();
    expect(layout.tab, NowPlayingTab.details);
    expect(layout.playbackStatusVisible, isTrue);

    // 在右栏里切到歌词，关掉再打开仍是歌词
    layout.selectTab(NowPlayingTab.lyrics);
    layout.togglePlaybackStatus();
    layout.togglePlaybackStatus();
    expect(layout.tab, NowPlayingTab.lyrics);
  });

  test('when the queue is showing, switches to the status view instead of closing', () {
    final layout = ShellLayoutController();
    layout.showTab(NowPlayingTab.queue);
    expect(layout.playbackStatusVisible, isFalse);

    layout.togglePlaybackStatus();
    expect(layout.rightPanelVisible, isTrue);
    expect(layout.tab, NowPlayingTab.details);
  });
}
