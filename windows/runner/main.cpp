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
  // Default 856x620:
  // - Width 856: the client area lands right on the profile page's 840dp
  //   two-pane breakpoint (_twoPaneBreakpoint in lib/ui/profile_page.dart), so
  //   the page opens as list-detail by default. The window frame costs 16dp in
  //   total at 100% display scaling and slightly less in logical pixels at
  //   other scales, so the client area stays >= 840dp.
  // - Height 620: the profile page's left pane needs about 540dp (3 section
  //   labels + 7 rows + paddings); 576 would clip its last row by default.
  Win32Window::Size size(856, 620);

  // Center the window on the primary monitor's work area (desktop minus
  // taskbar). Create() scales both origin and size by the monitor DPI, so the
  // work area (physical pixels) is converted back to logical units here.
  RECT work_area{0, 0, 1280, 720};
  ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  const double scale_factor =
      FlutterDesktopGetDpiForMonitor(
          ::MonitorFromRect(&work_area, MONITOR_DEFAULTTONEAREST)) /
      96.0;
  const int work_width = work_area.right - work_area.left;
  const int work_height = work_area.bottom - work_area.top;
  // Never open larger than the work area (small panels at high display
  // scaling): shrink to fit instead of spilling off the screen.
  if (static_cast<double>(size.width) * scale_factor > work_width) {
    size.width = static_cast<unsigned int>(work_width / scale_factor);
  }
  if (static_cast<double>(size.height) * scale_factor > work_height) {
    size.height = static_cast<unsigned int>(work_height / scale_factor);
  }
  const int window_width = static_cast<int>(size.width * scale_factor);
  const int window_height = static_cast<int>(size.height * scale_factor);
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
