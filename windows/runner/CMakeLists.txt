cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "native_log.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

set(FLUTTER_ENGINE_VERSION "unknown")
set(pubspec_file "${CMAKE_SOURCE_DIR}/../pubspec.yaml")
if(EXISTS "${pubspec_file}")
  file(STRINGS "${pubspec_file}" flutter_version_lines
    REGEX "^[ \t]*flutter:[ \t]*[0-9]+\\.[0-9]+\\.[0-9]+")
  if(flutter_version_lines)
    list(GET flutter_version_lines 0 flutter_version_line)
    string(REGEX REPLACE "^[ \t]*flutter:[ \t]*" ""
      FLUTTER_ENGINE_VERSION "${flutter_version_line}")
  endif()
endif()
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_ENGINE_VERSION=\"${FLUTTER_ENGINE_VERSION}\"")

# Keep the semantic plugin versions in native startup diagnostics. The
# Windows plugin DLL has no Windows version resource, so file metadata alone
# cannot identify its pub package version.
function(read_pubspec_lock_version package_name output_variable)
  set(lock_file "${CMAKE_SOURCE_DIR}/../pubspec.lock")
  set(package_found FALSE)
  set(package_version "unknown")
  if(EXISTS "${lock_file}")
    file(STRINGS "${lock_file}" lock_lines)
    foreach(line IN LISTS lock_lines)
      if(package_found)
        if(line MATCHES "^    version: \"([^\"]+)\"")
          set(package_version "${CMAKE_MATCH_1}")
          break()
        elseif(line MATCHES "^  [^ ]")
          break()
        endif()
      elseif(line MATCHES "^  ${package_name}:$")
        set(package_found TRUE)
      endif()
    endforeach()
  endif()
  set(${output_variable} "${package_version}" PARENT_SCOPE)
endfunction()

read_pubspec_lock_version("flutter_inappwebview" INAPPWEBVIEW_VERSION)
read_pubspec_lock_version("flutter_inappwebview_windows" INAPPWEBVIEW_WINDOWS_VERSION)
target_compile_definitions(${BINARY_NAME} PRIVATE "INAPPWEBVIEW_VERSION=\"${INAPPWEBVIEW_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "INAPPWEBVIEW_WINDOWS_VERSION=\"${INAPPWEBVIEW_WINDOWS_VERSION}\"")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "advapi32.lib" "shell32.lib" "version.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
