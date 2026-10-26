@echo off
rem Wrapper that pins the toolchain environment for this project.
for /d %%i in ("C:\dev\java17\*") do set "JAVA_HOME=%%i"
set "ANDROID_HOME=C:\dev\android-sdk"
set "FLUTTER_STORAGE_BASE_URL=https://storage.googleapis.com"
set "PUB_HOSTED_URL=https://pub.dev"
set "PATH=C:\dev\flutter\bin;%JAVA_HOME%\bin;%PATH%"
call C:\dev\flutter\bin\flutter.bat %*
exit /b %ERRORLEVEL%
