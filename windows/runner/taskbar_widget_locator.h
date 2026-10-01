#ifndef RUNNER_TASKBAR_WIDGET_LOCATOR_H_
#define RUNNER_TASKBAR_WIDGET_LOCATOR_H_

#include <windows.h>

#include <atomic>
#include <thread>

// 任务栏「小组件」（天气）按钮的右缘，歌词窗口紧贴它右侧摆放。
//
// 独立后台线程（MTA）每秒用 UI Automation 查一次 AutomationId = "WidgetsButton" 的元素矩形：
// 跨进程 UIA 调用可能阻塞，不能放在窗口线程里。AutomationId 跨语言稳定，矩形含悬浮高亮 / 新闻滚动的完整占位。
// 元素查找（遍历后代）很贵：找到后缓存元素只读矩形，每 15 秒或读取失败时再完整查找。
// 连续两次查不到才判定「没有小组件」，避免资源管理器启动初期误判导致歌词左右横跳。
class TaskbarWidgetLocator {
 public:
  // 不可用（UIA 失败 / 尚未测到）
  static constexpr int kUnknown = -1;
  // 确认没有小组件
  static constexpr int kNone = 0;

  TaskbarWidgetLocator() = default;
  ~TaskbarWidgetLocator();

  TaskbarWidgetLocator(const TaskbarWidgetLocator&) = delete;
  TaskbarWidgetLocator& operator=(const TaskbarWidgetLocator&) = delete;

  void Start();
  void Stop();

  // 小组件按钮右缘（物理像素，相对任务栏左缘）；或 kUnknown / kNone。
  int widget_right() const { return widget_right_.load(); }

 private:
  void Run();

  std::thread thread_;
  std::atomic<bool> running_{false};
  std::atomic<int> widget_right_{kUnknown};
};

#endif  // RUNNER_TASKBAR_WIDGET_LOCATOR_H_
