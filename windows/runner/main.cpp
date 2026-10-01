#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"flutify_app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // 关窗收尾（保存播放进度等）已在 Dart 侧 DesktopWindow 的关闭钩子里完成。
  // 先销毁窗口与引擎（释放 SMTC 等 WinRT 对象），再反初始化 COM。
  window.Destroy();
  ::CoUninitialize();

  // 直接结束进程：正常退出时进程要等 Dart VM 的线程池收尾（进行中的网络请求等），
  // 实测会再卡 5–12 秒。此时引擎已释放、该保存的都已落盘，没有需要等的东西。
  ::TerminateProcess(::GetCurrentProcess(), EXIT_SUCCESS);
  return EXIT_SUCCESS;
}
