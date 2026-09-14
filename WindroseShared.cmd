@echo off
setlocal EnableDelayedExpansion
:: ============================================================
::  WindroseShared.cmd  -  version 0.0.1
::  Keeps one Windrose world in a cloud-synced folder so any
::  player in the group can host it.
::
::  Each run:  lock -> pull world from shared folder -> run game
::             -> wait for game to close -> push world -> unlock
::
::  Setup instructions are in README.md.
:: ============================================================

:: ---------- SETTINGS ----------
:: SHARED = the synced folder every player in the group has on their PC.
:: Any sync service works. Pick the line that matches yours (keep the quotes):
::   OneDrive:      set "SHARED=%OneDrive%\WindroseShared"
::   Dropbox:       set "SHARED=%USERPROFILE%\Dropbox\WindroseShared"
::   Google Drive:  set "SHARED=G:\My Drive\WindroseShared"
::   Anything else: set "SHARED=D:\Sync\WindroseShared"
set "SHARED=%OneDrive%\WindroseShared"
::
:: The world ID is NOT set here. The first person to run this picks the
:: world once, and it is saved in the shared folder as world-id.txt.
:: Nobody else ever has to do that step.
:: ------------------------------------------------

set "VERSION=0.0.1"
set "STEAM_APPID=3041230"
set "GAME_EXE=Windrose-Win64-Shipping.exe"
set "GAME_MATCH=Windrose-Win64-Shipping"
set "PROFILES=%LOCALAPPDATA%\R5\Saved\SaveProfiles"
set "LOG=%SHARED%\sync-log.txt"
set "LOCKFILE=%SHARED%\LOCK.txt"
set "WORLD_FILE=%SHARED%\world-id.txt"
set "ME=%COMPUTERNAME%"
set "SYS=%SystemRoot%\System32"

:: Steam mode: first argument is "steam", the rest is the game command line
set "STEAM_MODE=0"
set "LAUNCH="
if /I "%~1"=="steam" (
  set "STEAM_MODE=1"
  set "LAUNCH=%*"
  set "LAUNCH=!LAUNCH:~6!"
)

echo.
echo === Windrose shared world sync  v%VERSION% ===
echo Shared folder : %SHARED%
if "%STEAM_MODE%"=="1" echo Mode          : started by Steam
echo.

:: ---------- sanity checks ----------
:: A full path always has a drive letter and colon in position 2.
:: If it does not, the sync service's folder was not found.
if not "%SHARED:~1,1%"==":" (
  echo ERROR: The shared folder path is not valid: "%SHARED%"
  echo Your sync service is probably not set up on this PC, or its folder
  echo is somewhere else. Open this script in Notepad and fix the SHARED
  echo line at the top. See README.md.
  goto :fail
)
for %%P in ("%SHARED%\..") do set "SHARED_PARENT=%%~fP"
if not exist "%SHARED_PARENT%\" (
  echo ERROR: The sync folder was not found: %SHARED_PARENT%
  echo Open this script in Notepad and fix the SHARED line at the top.
  echo See README.md.
  goto :fail
)
if not exist "%SHARED%\" (
  echo Shared folder does not exist yet. Creating it.
  mkdir "%SHARED%" || goto :fail
)

:: Find this PC's save profile (the folder named with the Steam ID, not *_Backups)
set "PROFILE="
for /d %%D in ("%PROFILES%\*") do (
  set "N=%%~nxD"
  if "!N:_Backups=!"=="!N!" if not defined PROFILE set "PROFILE=%%D"
)
if not defined PROFILE (
  echo ERROR: No Windrose save profile found under %PROFILES%
  echo Start Windrose once on this PC first, then run this again.
  goto :fail
)
set "WORLDS=%PROFILE%\RocksDB_v2_Backups\Worlds"
echo Local profile : %PROFILE%

:: Refuse to run while the game is already open
"%SYS%\tasklist.exe" /FI "IMAGENAME eq %GAME_EXE%" /FO CSV /NH 2>nul | "%SYS%\find.exe" /I "%GAME_MATCH%" >nul
if not errorlevel 1 (
  echo ERROR: Windrose is already running. Close it and try again.
  goto :fail
)

:: ---------- which world? ----------
:: Read the world ID the group chose. Only if nobody has chosen one yet,
:: run the one-time setup on this PC.
set "WORLD_ID="
if exist "%WORLD_FILE%" set /p WORLD_ID=<"%WORLD_FILE%"
if not defined WORLD_ID call :first_time_setup
if not defined WORLD_ID goto :fail
echo World         : %WORLD_ID%

set "LOCAL=%WORLDS%\%WORLD_ID%"
if not exist "%LOCAL%" mkdir "%LOCAL%"
if not exist "%SHARED%\Worlds\%WORLD_ID%" mkdir "%SHARED%\Worlds\%WORLD_ID%"

:: ---------- lock ----------
set "JOIN_ONLY=0"
if exist "%LOCKFILE%" (
  set /p HOLDER=<"%LOCKFILE%"
  echo.
  echo The shared world is currently locked by: !HOLDER!
  echo They are hosting right now, or their game closed without releasing it.
  echo.
  echo   J = JOIN their game. Starts Windrose without touching the shared world.
  echo   H = HOST anyway. Only if you are SURE nobody is hosting right now.
  echo   Q = Quit.
  echo.
  "%SYS%\choice.exe" /C JHQ /T 120 /D Q /M "Your choice"
  if errorlevel 3 goto :fail
  if errorlevel 2 (
    echo Overriding lock and hosting.
  ) else (
    set "JOIN_ONLY=1"
  )
)
if "%JOIN_ONLY%"=="1" goto :join
> "%LOCKFILE%" echo %ME% since %DATE% %TIME%
call :log "LOCK taken by %ME%"

:: ---------- pull ----------
if exist "%SHARED%\Worlds\%WORLD_ID%\*_Latest.zip" (
  rem keep a safety copy of what this PC had before overwriting it
  rem (kept OUTSIDE the game's Worlds folder so the game does not scan it)
  set "SAFE=%PROFILE%\WindroseShared_safety\%WORLD_ID%"
  if not exist "!SAFE!" mkdir "!SAFE!"
  if exist "%LOCAL%\*_Latest.zip" copy /Y "%LOCAL%\*_Latest.zip" "!SAFE!\" >nul
  echo Pulling world from shared folder...
  "%SYS%\robocopy.exe" "%SHARED%\Worlds\%WORLD_ID%" "%LOCAL%" /MIR /R:5 /W:3 /NJH /NJS /NDL /NP
  if errorlevel 8 (
    echo ERROR: copy from shared folder failed. Has your sync service finished syncing?
    call :log "PULL FAILED on %ME%"
    goto :unlock_fail
  )
  call :log "PULL ok on %ME%"
) else (
  echo Shared folder has no world yet. This PC's copy will seed it after you play.
  call :log "PULL skipped on %ME% (shared folder empty)"
)

:: remember what the shared world's save looked like before playing
set "BEFORE="
for %%F in ("%LOCAL%\*_Latest.zip") do set "BEFORE=%%~tF %%~zF"

:: ---------- play ----------
echo.
echo Starting Windrose. When you close the game the world is uploaded
echo to the shared folder automatically. DO NOT close this window.
echo.
goto :launch

:join
echo.
echo JOIN mode: starting Windrose. Use the multiplayer menu to join
echo the host's game. Nothing will be uploaded when you quit.
echo.
call :log "JOIN-only session on %ME%"

:launch
if "%STEAM_MODE%"=="1" (
  call :log "LAUNCH via Steam on %ME%"
  start "" !LAUNCH!
) else (
  call :log "LAUNCH via steam:// on %ME%"
  start "" "steam://rungameid/%STEAM_APPID%"
)

:: wait up to 5 minutes for the game to appear
set /a TRIES=0
:wait_start
"%SYS%\ping.exe" -n 6 127.0.0.1 >nul
"%SYS%\tasklist.exe" /FI "IMAGENAME eq %GAME_EXE%" /FO CSV /NH 2>nul | "%SYS%\find.exe" /I "%GAME_MATCH%" >nul
if not errorlevel 1 goto :running
set /a TRIES+=1
if %TRIES% lss 60 goto :wait_start
echo ERROR: Windrose did not start within 5 minutes.
call :log "GAME did not start on %ME%"
goto :unlock_fail

:running
echo Windrose is running. Waiting for it to close...
:wait_exit
"%SYS%\ping.exe" -n 11 127.0.0.1 >nul
"%SYS%\tasklist.exe" /FI "IMAGENAME eq %GAME_EXE%" /FO CSV /NH 2>nul | "%SYS%\find.exe" /I "%GAME_MATCH%" >nul
if not errorlevel 1 goto :wait_exit

:: give the game a moment to finish writing its exit backup
"%SYS%\ping.exe" -n 11 127.0.0.1 >nul

if "%JOIN_ONLY%"=="1" (
  echo.
  echo Join session finished. Shared world untouched.
  call :log "JOIN-only session ended on %ME%"
  if "%STEAM_MODE%"=="1" ("%SYS%\ping.exe" -n 6 127.0.0.1 >nul) else (pause)
  exit /b 0
)

:: ---------- push ----------
set "AFTER="
for %%F in ("%LOCAL%\*_Latest.zip") do set "AFTER=%%~tF %%~zF"
if "%AFTER%"=="%BEFORE%" if exist "%SHARED%\Worlds\%WORLD_ID%\*_Latest.zip" (
  echo.
  echo Shared world was not changed this session. Nothing to upload.
  call :log "PUSH skipped on %ME% (world unchanged)"
  goto :done
)
echo.
echo Uploading world to shared folder...
"%SYS%\robocopy.exe" "%LOCAL%" "%SHARED%\Worlds\%WORLD_ID%" /MIR /R:5 /W:3 /NJH /NJS /NDL /NP
if errorlevel 8 (
  echo ERROR: copy to shared folder failed. Your save is still safe on this PC.
  echo Run this again later, or copy the folder by hand:
  echo   from %LOCAL%
  echo   to   %SHARED%\Worlds\%WORLD_ID%
  call :log "PUSH FAILED on %ME%"
  goto :unlock_fail
)
call :log "PUSH ok on %ME%"

:done
del /Q "%LOCKFILE%" 2>nul
call :log "LOCK released by %ME%"
echo.
echo Done. Wait for your sync service to show the upload finished before
echo the next person hosts.
if "%STEAM_MODE%"=="1" ("%SYS%\ping.exe" -n 9 127.0.0.1 >nul) else (pause)
exit /b 0

:unlock_fail
del /Q "%LOCKFILE%" 2>nul
call :log "LOCK released by %ME% after error"
:fail
echo.
if "%STEAM_MODE%"=="1" ("%SYS%\ping.exe" -n 16 127.0.0.1 >nul) else (pause)
exit /b 1

:: ============================================================
::  ONE-TIME SETUP: choose the world to share.
::  Runs only when the shared folder has no world-id.txt yet, so only
::  the very first person in the group ever sees this. It lists the
::  worlds this PC has hosted and saves the chosen ID to the shared
::  folder. Everyone else's script reads it from there.
:: ============================================================
:first_time_setup
echo.
echo === ONE-TIME SETUP: choose the world to share ===
echo.
echo No world has been chosen for this shared folder yet.
echo.
echo   If your group ALREADY set this up, your sync service has not
echo   finished downloading the shared folder. Press Q, wait for it to
echo   finish, and try again.
echo.
echo   If you are the FIRST person setting this up, pick the world below.
echo   Nobody else in the group will ever have to do this.
echo.
set /a COUNT=0
if exist "%WORLDS%\" for /d %%D in ("%WORLDS%\*") do (
  set /a COUNT+=1
  set "W!COUNT!=%%~nxD"
  set "STAMP=never"
  for %%F in ("%%D\*_Latest.zip") do set "STAMP=%%~tF"
  echo   [!COUNT!]  %%~nxD    last saved: !STAMP!
)
if %COUNT%==0 (
  echo   This PC has never hosted a Windrose world, so there is nothing to share.
  echo   Either the person who owns the world should run this first, or start
  echo   a new world in Windrose, play a minute, quit, and run this again.
  echo.
  call :log "SETUP on %ME%: no local worlds found"
  exit /b 0
)
echo.
echo   Windrose does not show the world's name here, only its ID. The one
echo   with the newest "last saved" time is the world you played most recently.
echo.
set "PICK="
if %COUNT%==1 (
  "%SYS%\choice.exe" /C YQ /M "Only one world found. Share world [1]? Y = yes, Q = quit"
  if errorlevel 2 exit /b 0
  set "PICK=1"
) else (
  set /p PICK=Type the number of the world to share, or Q to quit:
  if /I "!PICK!"=="Q" exit /b 0
)
if not defined PICK exit /b 0
if not defined W%PICK% (
  echo   "%PICK%" is not one of the numbers in the list. Nothing was changed.
  exit /b 0
)
set "WORLD_ID=!W%PICK%!"
> "%WORLD_FILE%" echo !WORLD_ID!
echo.
echo   Saved. The shared world is now %WORLD_ID%.
echo   This was written to %WORLD_FILE% so everyone else picks it up automatically.
echo.
call :log "SETUP on %ME%: world set to !WORLD_ID!"
exit /b 0

:log
>> "%LOG%" echo %DATE% %TIME% %~1
exit /b 0
