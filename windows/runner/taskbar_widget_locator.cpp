#include "taskbar_widget_locator.h"

#include <UIAutomation.h>
#include <oleauto.h>

#include <algorithm>

namespace {

// COM 接口的最小 RAII 包装（避免为一个文件引入 WRL / ATL）。
template <typename T>
class ComPtr {
 public:
  ComPtr() = default;
  ~ComPtr() { Reset(); }
  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;

  T** Put() {
    Reset();
    return &ptr_;
  }
  T* operator->() const { return ptr_; }
  T* Get() const { return ptr_; }
  explicit operator bool() const { return ptr_ != nullptr; }
  void Reset() {
    if (ptr_) ptr_->Release();
    ptr_ = nullptr;
  }

 private:
  T* ptr_ = nullptr;
};

// 每轮间隔与「重新完整查找」的周期（轮数）。
constexpr int kIntervalMs = 1000;
constexpr int kRefindRounds = 15;

}  // namespace

TaskbarWidgetLocator::~TaskbarWidgetLocator() { Stop(); }

void TaskbarWidgetLocator::Start() {
  if (running_.exchange(true)) return;
  thread_ = std::thread([this] { Run(); });
}

void TaskbarWidgetLocator::Stop() {
  running_ = false;
  if (thread_.joinable()) thread_.join();
}

void TaskbarWidgetLocator::Run() {
  if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED))) return;
  {
    ComPtr<IUIAutomation> uia;
    ComPtr<IUIAutomationCondition> condition;
    if (SUCCEEDED(CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER, __uuidof(IUIAutomation),
                                   reinterpret_cast<void**>(uia.Put())))) {
      VARIANT id;
      VariantInit(&id);
      id.vt = VT_BSTR;
      id.bstrVal = SysAllocString(L"WidgetsButton");
      uia->CreatePropertyCondition(UIA_AutomationIdPropertyId, id, condition.Put());
      VariantClear(&id);
    }

    ComPtr<IUIAutomationElement> tray;
    ComPtr<IUIAutomationElement> widget;
    int null_runs = 0;
    int since_find = kRefindRounds;
    while (running_) {
      if (uia && condition) {
        HWND tray_hwnd = FindWindowW(L"Shell_TrayWnd", nullptr);
        bool ok = tray_hwnd != nullptr;
        if (ok && (!tray || since_find >= kRefindRounds)) {
          since_find = 0;
          widget.Reset();
          ok = SUCCEEDED(uia->ElementFromHandle(tray_hwnd, tray.Put())) && tray &&
               SUCCEEDED(tray->FindFirst(TreeScope_Descendants, condition.Get(), widget.Put()));
        }
        since_find++;
        if (!ok) {
          // 元素失效（资源管理器重启等）：下一轮重找
          widget_right_ = kUnknown;
          null_runs = 0;
          tray.Reset();
        } else if (!widget) {
          since_find = kRefindRounds;
          if (++null_runs >= 2) widget_right_ = kNone;
        } else {
          RECT box{};
          RECT tray_rect{};
          BOOL offscreen = FALSE;
          if (SUCCEEDED(widget->get_CurrentBoundingRectangle(&box)) &&
              SUCCEEDED(widget->get_CurrentIsOffscreen(&offscreen)) && GetWindowRect(tray_hwnd, &tray_rect)) {
            if (box.right > box.left && !offscreen) {
              widget_right_ = (std::max)(0L, box.right - tray_rect.left);
            }
            null_runs = 0;
          } else {
            widget_right_ = kUnknown;
            tray.Reset();
          }
        }
      }
      for (int waited = 0; waited < kIntervalMs && running_; waited += 100) Sleep(100);
    }
  }
  CoUninitialize();
}
