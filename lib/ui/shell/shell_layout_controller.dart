import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shell_breakpoints.dart';

/// 右侧面板当前显示的内容。
enum NowPlayingTab { details, queue, lyrics }

/// 桌面端布局状态：音乐库栏宽度 / 是否收起、右栏是否打开及当前标签。
///
/// 右栏有两种形态，开关状态分开记：
/// - 停靠（窗口 ≥ [ShellBreakpoints.threeColumn]）：用户的开关偏好写入 SharedPreferences，下次启动恢复；
/// - 浮层（更窄的窗口）：会遮住内容，所以默认关闭、只在用户点击时临时打开，不落盘；
///   跨越断点时浮层自动收起。
///
/// 窗口过窄时的「强制收起音乐库」由 DesktopShell 按分档计算，不写回这里。
class ShellLayoutController extends ChangeNotifier {
  static const String _keySidebarWidth = 'shell_sidebar_width';
  static const String _keySidebarCollapsed = 'shell_sidebar_collapsed';
  static const String _keyRightPanelOpen = 'shell_right_panel_open';

  SharedPreferences? _prefs;

  double _sidebarWidth = ShellBreakpoints.sidebarDefault;
  bool _sidebarCollapsed = false;
  bool _dockedOpen = true;
  bool _overlayOpen = false;
  bool _docked = true;
  NowPlayingTab _tab = NowPlayingTab.details;

  ShellLayoutController() {
    _restore();
  }

  double get sidebarWidth => _sidebarWidth;
  bool get sidebarCollapsed => _sidebarCollapsed;
  NowPlayingTab get tab => _tab;

  /// 右栏是否停靠为第三栏（否则以浮层显示）。
  bool get docked => _docked;

  /// 右栏当前是否可见（按当前形态取对应的开关）。
  bool get rightPanelVisible => _docked ? _dockedOpen : _overlayOpen;

  /// 由 MainShell 在构建时按窗口宽度同步，不触发通知（子树随后会一起重建）。
  set docked(bool value) {
    if (value == _docked) return;
    _docked = value;
    _overlayOpen = false;
  }

  Future<void> _restore() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _sidebarWidth = (prefs.getDouble(_keySidebarWidth) ?? _sidebarWidth)
        .clamp(ShellBreakpoints.sidebarMin, ShellBreakpoints.sidebarMax);
    _sidebarCollapsed = prefs.getBool(_keySidebarCollapsed) ?? _sidebarCollapsed;
    _dockedOpen = prefs.getBool(_keyRightPanelOpen) ?? _dockedOpen;
    notifyListeners();
  }

  /// 拖动过程中实时更新；[persist] 为 true（松手）时才落盘。
  void setSidebarWidth(double width, {bool persist = false}) {
    _sidebarWidth = width.clamp(ShellBreakpoints.sidebarMin, ShellBreakpoints.sidebarMax);
    if (persist) _prefs?.setDouble(_keySidebarWidth, _sidebarWidth);
    notifyListeners();
  }

  void toggleSidebar() {
    _sidebarCollapsed = !_sidebarCollapsed;
    _prefs?.setBool(_keySidebarCollapsed, _sidebarCollapsed);
    notifyListeners();
  }

  /// 点击播放栏上的面板按钮：同一标签再点一次关闭，不同标签则切换过去。
  void showTab(NowPlayingTab tab) {
    final open = !(rightPanelVisible && _tab == tab);
    _tab = tab;
    _setVisible(open);
  }

  void selectTab(NowPlayingTab tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  void closeRightPanel() {
    if (!rightPanelVisible) return;
    _setVisible(false);
  }

  void _setVisible(bool open) {
    if (_docked) {
      _dockedOpen = open;
      _prefs?.setBool(_keyRightPanelOpen, open);
    } else {
      _overlayOpen = open;
    }
    notifyListeners();
  }
}
