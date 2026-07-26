@echo off
REM ------------------------------------------------------------------
REM  Build onote_core and drop the DLL next to the app executable(s).
REM  Put this file in the repo root and double-click it (or run it
REM  from a terminal) after changing any Rust code. No file-explorer
REM  copying needed.
REM ------------------------------------------------------------------
setlocal
cd /d "%~dp0"

echo.
echo [1/2] Building onote_core (release)...
cargo build --release --manifest-path rust\onote_core\Cargo.toml
if errorlevel 1 (
  echo.
  echo   Build FAILED. Is cargo on PATH? ^(reopen your terminal if you
  echo   just installed Rust^) Nothing was copied.
  echo.
  pause
  exit /b 1
)

set "DLL=rust\onote_core\target\release\onote_core.dll"

echo [2/2] Copying DLL next to openote.exe...
set "COPIED="
for %%D in (Debug Release) do (
  if exist "app\build\windows\x64\runner\%%D\openote.exe" (
    copy /Y "%DLL%" "app\build\windows\x64\runner\%%D\" >nul
    echo    -^> app\build\windows\x64\runner\%%D\
    set "COPIED=1"
  )
)

if not defined COPIED (
  echo    No build output found yet. Build/run the app once, then
  echo    re-run this script.
) else (
  echo.
  echo Done. Launch the app - the status bar chip should be green.
)
echo.
pause