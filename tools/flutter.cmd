@echo off
rem Compatibility wrapper. The pinned environment lives in toolchain.psm1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-flutter.ps1" %*
exit /b %ERRORLEVEL%
