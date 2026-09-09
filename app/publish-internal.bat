@echo off
chcp 65001 > nul
setlocal
cd /d "%~dp0"

REM ---------------------------------------------------------------
REM  bump build number  ->  build release AAB  ->  upload to internal
REM  Usage:  publish-internal.bat ["release note"]
REM ---------------------------------------------------------------

set "FLUTTER=C:\dev\flutter\bin\flutter.bat"
if not exist "%FLUTTER%" set "FLUTTER=flutter"

where python >nul 2>nul
if errorlevel 1 (
  echo [ERROR] python not found in PATH.
  goto :fail
)

echo ============================================================
echo  STEP 1/3  bump build number
echo ============================================================
python tool\play_publish.py bump
if errorlevel 1 goto :fail
echo.

echo ============================================================
echo  STEP 2/3  build release AAB
echo ============================================================
call "%FLUTTER%" build appbundle --release --dart-define-from-file=dart_defines.json
if errorlevel 1 (
  echo.
  echo [ERROR] build failed. The build number was already bumped;
  echo         just run this script again after fixing the build.
  goto :fail
)
echo.

echo ============================================================
echo  STEP 3/3  upload to internal test track
echo ============================================================
if "%~1"=="" (
  python tool\play_publish.py upload --track internal
) else (
  python tool\play_publish.py upload --track internal --notes "%~1"
)
if errorlevel 1 goto :fail

echo.
echo ============================================================
echo  DONE
echo ============================================================
endlocal
exit /b 0

:fail
echo.
echo ============================================================
echo  FAILED - nothing was published
echo ============================================================
endlocal
exit /b 1
