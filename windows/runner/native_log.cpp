#include "native_log.h"

#include <shlobj.h>
#include <winternl.h>

#include <cstdint>
#include <cstdio>
#include <iterator>
#include <string>
#include <vector>

#ifndef FLUTTER_VERSION
#define FLUTTER_VERSION "unknown"
#endif

#ifndef FLUTTER_ENGINE_VERSION
#define FLUTTER_ENGINE_VERSION "unknown"
#endif

#ifndef INAPPWEBVIEW_VERSION
#define INAPPWEBVIEW_VERSION "unknown"
#endif

#ifndef INAPPWEBVIEW_WINDOWS_VERSION
#define INAPPWEBVIEW_WINDOWS_VERSION "unknown"
#endif

namespace {

constexpr wchar_t kLogFileName[] = L"lancloud.log";
constexpr wchar_t kWebView2ClientKey[] =
    L"SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\"
    L"{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}";

std::wstring g_log_path;
LPTOP_LEVEL_EXCEPTION_FILTER g_previous_filter = nullptr;
bool g_crash_handler_installed = false;

std::string Utf8FromWide(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int size = ::WideCharToMultiByte(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (size <= 0) {
    return {};
  }
  std::string result(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.data(),
                        static_cast<int>(value.size()), result.data(), size,
                        nullptr, nullptr);
  return result;
}

std::wstring ExecutableDirectory() {
  std::wstring path(32768, L'\0');
  const DWORD length = ::GetModuleFileNameW(
      nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) {
    return {};
  }
  path.resize(length);
  const size_t separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return {};
  }
  return path.substr(0, separator);
}

std::string FileVersion(const std::wstring& path) {
  DWORD ignored = 0;
  const DWORD size = ::GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (size == 0) {
    return "no-version-resource";
  }
  std::vector<BYTE> buffer(size);
  if (!::GetFileVersionInfoW(path.c_str(), 0, size, buffer.data())) {
    return "version-read-failed";
  }
  VS_FIXEDFILEINFO* info = nullptr;
  UINT info_size = 0;
  if (!::VerQueryValueW(buffer.data(), L"\\",
                        reinterpret_cast<void**>(&info), &info_size) ||
      info == nullptr || info_size < sizeof(VS_FIXEDFILEINFO)) {
    return "version-missing";
  }
  char version[64] = {};
  std::snprintf(version, sizeof(version), "%u.%u.%u.%u",
                HIWORD(info->dwFileVersionMS), LOWORD(info->dwFileVersionMS),
                HIWORD(info->dwFileVersionLS), LOWORD(info->dwFileVersionLS));
  return version;
}

std::string FileModifiedTime(const FILETIME& file_time) {
  FILETIME local_time = {};
  SYSTEMTIME system_time = {};
  if (!::FileTimeToLocalFileTime(&file_time, &local_time) ||
      !::FileTimeToSystemTime(&local_time, &system_time)) {
    return "unknown";
  }
  char text[32] = {};
  std::snprintf(text, sizeof(text), "%04u-%02u-%02u %02u:%02u:%02u",
                system_time.wYear, system_time.wMonth, system_time.wDay,
                system_time.wHour, system_time.wMinute, system_time.wSecond);
  return text;
}

void LogFileInfo(const wchar_t* name) {
  const std::wstring directory = ExecutableDirectory();
  if (directory.empty()) {
    lancloud::NativeLog::Error("native-env", "cannot locate executable");
    return;
  }
  std::wstring path = directory + L"\\" + name;
  std::string source = "app-local";
  WIN32_FILE_ATTRIBUTE_DATA attributes = {};
  if (!::GetFileAttributesExW(path.c_str(), GetFileExInfoStandard,
                              &attributes)) {
    const HMODULE module = ::GetModuleHandleW(name);
    if (module == nullptr) {
      lancloud::NativeLog::Info("native-env",
                                Utf8FromWide(name) + " missing");
      return;
    }
    path.assign(32768, L'\0');
    const DWORD length = ::GetModuleFileNameW(
        module, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0 || length >= path.size() ||
        !::GetFileAttributesExW(path.c_str(), GetFileExInfoStandard,
                                &attributes)) {
      lancloud::NativeLog::Info("native-env",
                                Utf8FromWide(name) + " loaded-path-unknown");
      return;
    }
    path.resize(length);
    source = "system";
  }
  const uint64_t size =
      (static_cast<uint64_t>(attributes.nFileSizeHigh) << 32) |
      attributes.nFileSizeLow;
  lancloud::NativeLog::Info(
      "native-env",
      Utf8FromWide(name) + " source=" + source +
          " version=" + FileVersion(path) +
          " size=" + std::to_string(size) +
          " modified=" + FileModifiedTime(attributes.ftLastWriteTime));
}

std::string WebView2RuntimeVersion() {
  const HKEY roots[] = {HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER};
  for (HKEY root : roots) {
    wchar_t version[256] = {};
    DWORD bytes = sizeof(version);
    if (::RegGetValueW(root, kWebView2ClientKey, L"pv", RRF_RT_REG_SZ, nullptr,
                       version, &bytes) == ERROR_SUCCESS) {
      return Utf8FromWide(version);
    }
  }
  return "not-found";
}

std::string OsVersion() {
  using RtlGetVersionFunction = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
  const HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  const auto get_version = ntdll == nullptr
                               ? nullptr
                               : reinterpret_cast<RtlGetVersionFunction>(
                                     ::GetProcAddress(ntdll, "RtlGetVersion"));
  RTL_OSVERSIONINFOW info = {};
  info.dwOSVersionInfoSize = sizeof(info);
  if (get_version != nullptr && get_version(&info) == 0) {
    return std::to_string(info.dwMajorVersion) + "." +
           std::to_string(info.dwMinorVersion) + "." +
           std::to_string(info.dwBuildNumber);
  }
  return "unknown";
}

std::string Architecture() {
  SYSTEM_INFO info = {};
  ::GetNativeSystemInfo(&info);
  switch (info.wProcessorArchitecture) {
    case PROCESSOR_ARCHITECTURE_AMD64:
      return "x64";
    case PROCESSOR_ARCHITECTURE_ARM64:
      return "arm64";
    case PROCESSOR_ARCHITECTURE_INTEL:
      return "x86";
    default:
      return "other";
  }
}

std::string AddressLocation(const void* address) {
  HMODULE module = nullptr;
  if (address == nullptr ||
      !::GetModuleHandleExW(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCWSTR>(const_cast<void*>(address)), &module) ||
      module == nullptr) {
    return "unknown";
  }
  wchar_t path[32768] = {};
  const DWORD length = ::GetModuleFileNameW(
      module, path, static_cast<DWORD>(std::size(path)));
  if (length == 0 || length >= std::size(path)) {
    return "unknown";
  }
  std::wstring module_path(path, length);
  const size_t separator = module_path.find_last_of(L"\\/");
  const std::wstring name =
      separator == std::wstring::npos ? module_path
                                     : module_path.substr(separator + 1);
  const auto base = reinterpret_cast<uintptr_t>(module);
  const auto location = reinterpret_cast<uintptr_t>(address);
  char offset[32] = {};
  std::snprintf(offset, sizeof(offset), "+0x%llx",
                static_cast<unsigned long long>(location - base));
  return Utf8FromWide(name) + offset;
}

LONG WINAPI LogUnhandledException(EXCEPTION_POINTERS* exception_pointers) {
  if (exception_pointers != nullptr &&
      exception_pointers->ExceptionRecord != nullptr) {
    const EXCEPTION_RECORD* record = exception_pointers->ExceptionRecord;
    char code[32] = {};
    char address[32] = {};
    std::snprintf(code, sizeof(code), "0x%08lx", record->ExceptionCode);
    std::snprintf(address, sizeof(address), "0x%llx",
                  static_cast<unsigned long long>(
                      reinterpret_cast<uintptr_t>(record->ExceptionAddress)));
    std::string message =
        std::string("unhandled exception code=") + code + " address=" +
        address + " module=" + AddressLocation(record->ExceptionAddress) +
        " thread=" + std::to_string(::GetCurrentThreadId());
    if (record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION &&
        record->NumberParameters >= 2) {
      message += record->ExceptionInformation[0] == 0
                     ? " access=read"
                     : record->ExceptionInformation[0] == 1 ? " access=write"
                                                            : " access=execute";
      char target[32] = {};
      std::snprintf(
          target, sizeof(target), " target=0x%llx",
          static_cast<unsigned long long>(record->ExceptionInformation[1]));
      message += target;
    }
    lancloud::NativeLog::Error("native-crash", message);
  } else {
    lancloud::NativeLog::Error("native-crash",
                               "unhandled exception without record");
  }

  if (g_previous_filter != nullptr) {
    return g_previous_filter(exception_pointers);
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

namespace lancloud {

void NativeLog::Initialize() {
  PWSTR documents_path = nullptr;
  const HRESULT result = ::SHGetKnownFolderPath(
      FOLDERID_Documents, KF_FLAG_DEFAULT, nullptr, &documents_path);
  if (FAILED(result) || documents_path == nullptr) {
    if (documents_path != nullptr) {
      ::CoTaskMemFree(documents_path);
    }
    ::OutputDebugStringA(
        "[LanCloud] Unable to resolve the Documents folder for native logs.\n");
    return;
  }
  std::wstring logs_directory(documents_path);
  ::CoTaskMemFree(documents_path);
  logs_directory += L"\\logs";
  ::SHCreateDirectoryExW(nullptr, logs_directory.c_str(), nullptr);
  g_log_path = logs_directory + L"\\" + kLogFileName;
}

void NativeLog::InstallCrashHandler() {
  if (g_crash_handler_installed) {
    return;
  }
  g_crash_handler_installed = true;
  g_previous_filter = ::SetUnhandledExceptionFilter(LogUnhandledException);
}

void NativeLog::LogStartupEnvironment() {
  Info("native-env", "os=" + OsVersion() + " arch=" + Architecture() +
                         " app=" FLUTTER_VERSION +
                         " flutter_engine=" FLUTTER_ENGINE_VERSION +
                         " inappwebview=" INAPPWEBVIEW_VERSION +
                         " windows_plugin=" INAPPWEBVIEW_WINDOWS_VERSION);
  Info("native-env", "webview2_runtime=" + WebView2RuntimeVersion());
  LogFileInfo(L"MSVCP140.dll");
  LogFileInfo(L"VCRUNTIME140.dll");
  LogFileInfo(L"VCRUNTIME140_1.dll");
  LogFileInfo(L"VCRUNTIME140_threads.dll");
  LogFileInfo(L"flutter_windows.dll");
  LogFileInfo(L"flutter_inappwebview_windows_plugin.dll");
  LogFileInfo(L"WebView2Loader.dll");
}

void NativeLog::Info(const std::string& tag, const std::string& message) {
  Write('I', tag, message);
}

void NativeLog::Error(const std::string& tag, const std::string& message) {
  Write('E', tag, message);
}

void NativeLog::Write(char level,
                      const std::string& tag,
                      const std::string& message) {
  if (g_log_path.empty()) {
    return;
  }
  SYSTEMTIME now = {};
  ::GetLocalTime(&now);
  char prefix[96] = {};
  std::snprintf(prefix, sizeof(prefix),
                "%04u-%02u-%02u %02u:%02u:%02u.%03u [%c] %s: ", now.wYear,
                now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
                now.wMilliseconds, level, tag.c_str());

  const HANDLE file =
      ::CreateFileW(g_log_path.c_str(), FILE_APPEND_DATA,
                    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                    nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  ::WriteFile(
      file, prefix,
      static_cast<DWORD>(std::char_traits<char>::length(prefix)), &written,
      nullptr);
  ::WriteFile(file, message.data(), static_cast<DWORD>(message.size()),
              &written, nullptr);
  const char newline[] = "\r\n";
  ::WriteFile(file, newline, 2, &written, nullptr);
  ::CloseHandle(file);
  ::OutputDebugStringA("[LanCloud] ");
  ::OutputDebugStringA(prefix);
  ::OutputDebugStringA(message.c_str());
  ::OutputDebugStringA("\n");
}

}  // namespace lancloud
