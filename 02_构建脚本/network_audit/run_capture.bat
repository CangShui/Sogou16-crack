@echo off
REM ============================================================================
REM  run_capture.bat - one-click full-system network capture + Excel export
REM  Usage:
REM    run_capture.bat              (default 30 minutes)
REM    run_capture.bat 60           (capture 60 minutes)
REM    run_capture.bat 720 15       (capture 12 hours, sample every 15s)
REM  After capture it auto-analyzes raw.csv into xlsx (needs Python pandas/openpyxl)
REM ============================================================================
setlocal
set MINS=%1
if "%MINS%"=="" set MINS=30
set IVAL=%2
if "%IVAL%"=="" set IVAL=10

echo Capture %MINS% minutes, sample every %IVAL% seconds...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sysnet_capture.ps1" -Minutes %MINS% -Interval %IVAL% -OutDir "%~dp0netout"

echo.
echo Generating Excel analysis...
for %%f in ("%~dp0netout\*.raw.csv") do (
  python "%~dp0analyze_net.py" "%%f"
)

echo.
echo Done. Results in %~dp0netout\
endlocal
