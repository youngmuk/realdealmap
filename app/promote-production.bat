@echo off
chcp 65001 > nul
setlocal
cd /d "%~dp0"

REM ---------------------------------------------------------------
REM  promote the newest internal-test build to PRODUCTION
REM  Staged rollout. Default 10 percent.
REM
REM  Usage:  promote-production.bat          -> 10%%
REM          promote-production.bat 0.5      -> 50%%
REM          promote-production.bat 1        -> 100%% (everyone)
REM
REM  The script asks for a typed "yes" before it publishes.
REM ---------------------------------------------------------------

set "FRACTION=%~1"
if "%FRACTION%"=="" set "FRACTION=0.1"

where python >nul 2>nul
if errorlevel 1 (
  echo [ERROR] python not found in PATH.
  goto :fail
)

echo ============================================================
echo  current track status
echo ============================================================
python tool\play_publish.py status
echo.

echo ============================================================
echo  promote internal -^> production   (fraction %FRACTION%)
echo ============================================================
python tool\play_publish.py promote --from internal --to production --fraction %FRACTION%
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
echo  NOT PUBLISHED
echo ============================================================
endlocal
exit /b 1
