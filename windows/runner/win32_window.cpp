#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// Minimum size of the client area, in logical pixels. The Flutter UI (drive
// list rows, MD3 list items) overflows when the window gets smaller than this.
constexpr int kMinClientWidth = 425;
constexpr int kMinClientHeight = 445;

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// System icon metrics: the title bar / taskbar ask for SM_CXSMICON (16px at
// 100%) and the large icon for Alt+Tab / Explorer uses SM_CXICON (32px at
// 100%). Both scale with the monitor DPI (125% -> 20 / 40, 150% -> 24 / 48).
// Title bar / notification area icon: SM_CXSMICON (16 logical px).
constexpr int kSmallIconBaseSize = 16;
// Taskbar button icon: the Windows 11 taskbar draws the window's *large* icon
// (verified by shrinking ICON_BIG: the taskbar followed it) at 24 logical px,
// i.e. 30 physical px at 125% scaling. Handing it a 32-logical-px image (what
// SM_CXICON says) makes the shell shrink it by 0.75 and the fine edges of the
// artwork turn soft; 24 logical px lands on an exact frame in app_icon.ico.
constexpr int kBigIconBaseSize = 24;

// The app icon at an exact pixel size. LoadIcon only ever returns the default
// (32px) image, so the shell has to rescale it for every other size, which is
// what makes the icon look soft / pixelated. LoadImage picks the frame with the
// requested size from app_icon.ico (it ships 16..256px frames) so no scaling is
// needed.
HICON LoadAppIconAtSize(int size) {
  return reinterpret_cast<HICON>(
      ::LoadImage(::GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON),
                  IMAGE_ICON, size, size, LR_DEFAULTCOLOR));
}

int ScaledIconSize(int base_size, UINT dpi) {
  const int size = ::MulDiv(base_size, static_cast<int>(dpi), 96);
  return size > 0 ? size : base_size;
}

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    // WNDCLASSEX (not the template's WNDCLASS): only it carries hIconSm, which
    // is what lets the title bar use the 16/20/24px frame as-is instead of a
    // rescaled copy.
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(WNDCLASSEXW);
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    // Register the class with icons already sized for the primary monitor's
    // DPI; each window then re-applies its own icons for its own monitor.
    const POINT primary_point{0, 0};
    const UINT system_dpi = FlutterDesktopGetDpiForMonitor(
        ::MonitorFromPoint(primary_point, MONITOR_DEFAULTTOPRIMARY));
    window_class.hIcon =
        LoadAppIconAtSize(ScaledIconSize(kBigIconBaseSize, system_dpi));
    window_class.hIconSm =
        LoadAppIconAtSize(ScaledIconSize(kSmallIconBaseSize, system_dpi));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClassExW(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateIconForDpi(dpi);
  UpdateTheme(window);

  return OnCreate();
}

void Win32Window::UpdateIconForDpi(UINT dpi) {
  if (window_handle_ == nullptr) {
    return;
  }

  // Don't name these locals `big` / `small`: rpcndr.h defines `small` as a
  // macro (`#define small char`), which breaks the declaration.
  HICON big_icon = LoadAppIconAtSize(ScaledIconSize(kBigIconBaseSize, dpi));
  HICON small_icon =
      LoadAppIconAtSize(ScaledIconSize(kSmallIconBaseSize, dpi));

  if (big_icon != nullptr) {
    ::SendMessage(window_handle_, WM_SETICON, ICON_BIG,
                  reinterpret_cast<LPARAM>(big_icon));
    if (icon_big_ != nullptr) {
      ::DestroyIcon(icon_big_);
    }
    icon_big_ = big_icon;
  }
  if (small_icon != nullptr) {
    ::SendMessage(window_handle_, WM_SETICON, ICON_SMALL,
                  reinterpret_cast<LPARAM>(small_icon));
    if (icon_small_ != nullptr) {
      ::DestroyIcon(icon_small_);
    }
    icon_small_ = small_icon;
  }
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      // Moving to a monitor with a different scale factor needs the icons at
      // the new DPI as well, otherwise the shell stretches the old bitmaps and
      // the title bar / taskbar icon looks blurry.
      UpdateIconForDpi(HIWORD(wparam));

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;

    case WM_GETMINMAXINFO: {
      // Clamp how small the user can drag the window: below 425x445 logical
      // pixels the Flutter layout overflows. ptMinTrackSize is the size of the
      // whole window (frame included), so grow the client-area target by the
      // non-client borders first.
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
      double scale_factor = dpi / 96.0;

      RECT rect = {0, 0, Scale(kMinClientWidth, scale_factor),
                   Scale(kMinClientHeight, scale_factor)};
      const DWORD style =
          static_cast<DWORD>(GetWindowLongPtr(hwnd, GWL_STYLE));
      const DWORD ex_style =
          static_cast<DWORD>(GetWindowLongPtr(hwnd, GWL_EXSTYLE));
      if (AdjustWindowRectExForDpi(&rect, style, FALSE, ex_style, dpi)) {
        info->ptMinTrackSize.x = rect.right - rect.left;
        info->ptMinTrackSize.y = rect.bottom - rect.top;
      }
      return 0;
    }
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (icon_big_ != nullptr) {
    ::DestroyIcon(icon_big_);
    icon_big_ = nullptr;
  }
  if (icon_small_ != nullptr) {
    ::DestroyIcon(icon_small_);
    icon_small_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
