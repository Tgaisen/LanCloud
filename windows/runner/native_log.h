#ifndef RUNNER_NATIVE_LOG_H_
#define RUNNER_NATIVE_LOG_H_

#include <windows.h>

#include <string>

namespace lancloud {

/// Appends process-level diagnostics to the same file exported by AppLog.
///
/// Dart error hooks never see failures that terminate the native process, so
/// this logger deliberately uses synchronous Win32 file I/O and can be called
/// from the Windows unhandled-exception filter.
class NativeLog {
 public:
  NativeLog() = delete;

  static void Initialize();
  static void InstallCrashHandler();
  static void LogStartupEnvironment();

  static void Info(const std::string& tag, const std::string& message);
  static void Error(const std::string& tag, const std::string& message);

 private:
  static void Write(char level,
                    const std::string& tag,
                    const std::string& message);
};

}  // namespace lancloud

#endif  // RUNNER_NATIVE_LOG_H_
