@echo off
rem LanCloud agent entry shim. ASCII only: cmd.exe reads this file as the OEM
rem codepage, so non-ASCII comments would be garbled into bogus commands.
rem It only bypasses the PowerShell execution policy and forwards all args.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0agent.ps1" %*
exit /b %ERRORLEVEL%
