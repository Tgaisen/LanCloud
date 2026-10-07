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

  // Single instance: only one window may run at a time.
  //
  // Two instances would read and write the same local data (SQLite database,
  // settings, cache folder), so a named mutex blocks the second launch: when a
  // window already exists, bring it to the foreground (restoring it first if
  // minimized) and exit without creating another window.
  //
  // The mutex has no "Global\" prefix, so its scope is the current logon
  // session: each user/session may run its own instance (separate %APPDATA%).
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, FALSE, L"LanCloud_SingleInstance_Mutex");
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Keep in sync with kWindowClassName in win32_window.cpp
    if (HWND existing =
            ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr)) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      }
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Size size(850, 576);

  // Center the window on the primary monitor's work area (desktop minus
  // taskbar). Create() scales both origin and size by the monitor DPI, so the
  // work area (physical pixels) is converted back to logical units here.
  RECT work_area{0, 0, 1280, 720};
  ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  const double scale_factor =
      FlutterDesktopGetDpiForMonitor(
          ::MonitorFromRect(&work_area, MONITOR_DEFAULTTONEAREST)) /
      96.0;
  const int window_width = static_cast<int>(size.width * scale_factor);
  const int window_height = static_cast<int>(size.height * scale_factor);
  const int work_width = work_area.right - work_area.left;
  const int work_height = work_area.bottom - work_area.top;
  Win32Window::Point origin(
      static_cast<int>((work_area.left + (work_width - window_width) / 2) /
                       scale_factor),
      static_cast<int>((work_area.top + (work_height - window_height) / 2) /
                       scale_factor));

  // Window title follows the Windows UI language, matching the Android app
  // name: 蓝云 on Chinese systems, LanCloud elsewhere. The Chinese name is
  // written with \u escapes so the source file encoding (UTF-8 without BOM,
  // compiled under code page 936) cannot garble it.
  const bool chinese_ui =
      PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_CHINESE;
  const std::wstring title = chinese_ui ? L"\u84dd\u4e91" : L"LanCloud";
  if (!window.Create(title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
