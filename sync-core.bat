@echo off
REM ------------------------------------------------------------------
REM  Build Openote and drop the Rust DLL next to the app executable.
REM
REM  Order matters: `flutter build` recreates the runner directory, so
REM  the DLL must be copied AFTER it. Copying first (as an earlier
REM  version of this script did) meant the DLL was silently deleted.
REM
REM  It also builds the Flutter app, not just the Rust core. That
REM  omission cost a debugging round-trip: the Rust DLL was current
REM  while openote.exe was three days stale, so every Dart-side fix
REM  (fonts, table column widths, layout) appeared not to work.
REM
REM  Usage:
REM    sync-core.bat            build Rust + Flutter, then copy the DLL
REM    sync-core.bat rust       Rust + copy only (skip the Flutter build)
REM ------------------------------------------------------------------
setlocal
cd /d "%~dp0"

set "RUSTONLY="
if /i "%~1"=="rust" set "RUSTONLY=1"

echo.
echo [1/3] Building onote_core (release)...
cargo build --release --manifest-path rust\onote_core\Cargo.toml
if errorlevel 1 (
  echo.
  echo   Rust build FAILED. Is cargo on PATH? ^(reopen your terminal if
  echo   you just installed Rust^) Nothing was copied.
  echo.
  pause
  exit /b 1
)

if defined RUSTONLY (
  echo [2/3] Skipping Flutter build ^(rust-only mode^).
  echo       NOTE: Dart changes will NOT be in the app until you build it.
) else (
  echo [2/3] Building the Flutter app ^(debug^)...
  pushd app
  call flutter build windows --debug
  if errorlevel 1 (
    echo.
    echo   Flutter build FAILED. The DLL was not copied, so the app on
    echo   disk is unchanged.
    echo.
    popd
    pause
    exit /b 1
  )
  popd
)

set "DLL=rust\onote_core\target\release\onote_core.dll"

echo [3/3] Copying DLL next to openote.exe...
set "COPIED="
for %%D in (Debug Release) do (
  if exist "app\build\windows\x64\runner\%%D\openote.exe" (
    copy /Y "%DLL%" "app\build\windows\x64\runner\%%D\" >nul
    if errorlevel 1 (
      echo    -^> %%D FAILED ^(is the app still running? close it first^)
    ) else (
      echo    -^> app\build\windows\x64\runner\%%D\
      set "COPIED=1"
    )
  )
)

if not defined COPIED (
  echo    No build output found yet. Build/run the app once, then
  echo    re-run this script.
  echo.
  pause
  exit /b 1
)

echo.
echo Done. Launch the app - the status bar chip should be green.
echo.
echo Reminder: importer changes only affect NEW imports. Table column
echo widths and re-stacked layout are written into the notebook at
echo import time, so an already-imported notebook must be re-imported
echo to pick them up. Font fallback applies immediately.
echo.
pause
