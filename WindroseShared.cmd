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

title Windrose Shared Helm
echo.
echo  ==============================================================
echo    WINDROSE SHARED HELM   v%VERSION%
echo    One shared world. Whoever takes the helm hosts it.
echo  ==============================================================
echo.
echo  This window runs before and after the game. It is normal.
echo  Leave it open. It closes by itself when everything is done.
echo.

:: ---------- sanity checks ----------
:: A full path always has a drive letter and colon in position 2.
:: If it does not, the sync service's folder was not found.
if not "%SHARED:~1,1%"==":" (
  echo  PROBLEM: The shared folder path is not valid: "%SHARED%"
  echo  Your sync service is probably not set up on this PC, or its folder
  echo  is somewhere else. Open this script in Notepad and fix the SHARED
  echo  line at the top. See README.md.
  goto :fail
)
for %%P in ("%SHARED%\..") do set "SHARED_PARENT=%%~fP"
if not exist "%SHARED_PARENT%\" (
  echo  PROBLEM: The sync folder was not found: %SHARED_PARENT%
  echo  Open this script in Notepad and fix the SHARED line at the top.
  echo  See README.md.
  goto :fail
)
if not exist "%SHARED%\" (
  echo  Shared folder does not exist yet. Creating it.
  mkdir "%SHARED%" || goto :fail
)

:: Find this PC's save profile (the folder named with the Steam ID, not *_Backups)
set "PROFILE="
for /d %%D in ("%PROFILES%\*") do (
  set "N=%%~nxD"
  if "!N:_Backups=!"=="!N!" if not defined PROFILE set "PROFILE=%%D"
)
if not defined PROFILE (
  echo  PROBLEM: No Windrose save profile found under %PROFILES%
  echo  Start Windrose once on this PC first, then run this again.
  goto :fail
)
set "WORLDS=%PROFILE%\RocksDB_v2_Backups\Worlds"

:: Refuse to run while the game is already open
"%SYS%\tasklist.exe" /FI "IMAGENAME eq %GAME_EXE%" /FO CSV /NH 2>nul | "%SYS%\find.exe" /I "%GAME_MATCH%" >nul
if not errorlevel 1 (
  echo  PROBLEM: Windrose is already running. Close it and try again.
  goto :fail
)

:: ---------- which world? ----------
:: Read the world ID the group chose. Only if nobody has chosen one yet,
:: run the one-time setup on this PC.
set "WORLD_ID="
if exist "%WORLD_FILE%" set /p WORLD_ID=<"%WORLD_FILE%"
if not defined WORLD_ID call :first_time_setup
if not defined WORLD_ID goto :fail

set "LOCAL=%WORLDS%\%WORLD_ID%"
set "REMOTE=%SHARED%\Worlds\%WORLD_ID%"
if not exist "%LOCAL%" mkdir "%LOCAL%"
if not exist "%REMOTE%" mkdir "%REMOTE%"

echo  Shared folder : %SHARED%
echo  World         : %WORLD_ID%
echo.

:: ---------- what do you want to do? ----------
:: MODE is "host" (sync the shared world) or "play" (join someone's game or
:: play your own world). Play never touches the shared world and never
:: takes the helm.
set "MODE=host"
if exist "%LOCKFILE%" (
  set /p HOLDER=<"%LOCKFILE%"
  echo  --------------------------------------------------------------
  echo  Someone else has the helm: !HOLDER!
  echo  --------------------------------------------------------------
  echo  They are hosting right now, or their game closed without
  echo  handing the helm back.
  echo.
  echo    J = Join / Play. Join their game, or play a DIFFERENT world of your own.
  echo        The shared world is left alone and nothing is uploaded.
  echo    H = Host the shared world anyway. Only if you are all SURE nobody is hosting.
  echo.
  echo    Or just close this window to quit.
  echo.
  "%SYS%\choice.exe" /C JH /M "  Your choice"
  if errorlevel 2 (
    echo.
    echo  Taking the helm anyway.
  ) else (
    set "MODE=play"
  )
) else (
  echo  Nobody has the helm right now.
  echo.
  echo    H = Host the shared world. Also press H to play the shared world
  echo        by yourself, so your progress is saved for everyone.
  echo    J = Join / Play. Join a friend's game, or play a DIFFERENT world of
  echo        your own. The shared world is left alone and nothing is uploaded.
  echo.
  echo    Or just close this window to quit.
  echo.
  "%SYS%\choice.exe" /C HJ /M "  Your choice"
  if errorlevel 2 set "MODE=play"
)
echo.
if not "%MODE%"=="host" goto :nosync
> "%LOCKFILE%" echo %ME% since %DATE% %TIME%
call :log "LOCK taken by %ME%"
echo  [1/4] You have the helm. Nobody else can host until you quit.
echo.

:: ---------- pull ----------
echo  [2/4] Getting the latest world from the shared folder...
if exist "%REMOTE%\*_Latest.zip" (
  rem keep a safety copy of what this PC had before overwriting it
  rem (kept OUTSIDE the game's Worlds folder so the game does not scan it)
  set "SAFE=%PROFILE%\WindroseShared_safety\%WORLD_ID%"
  if not exist "!SAFE!" mkdir "!SAFE!"
  if exist "%LOCAL%\*_Latest.zip" copy /Y "%LOCAL%\*_Latest.zip" "!SAFE!\" >nul
  call :last_host
  if defined LASTHOST echo        Last uploaded by !LASTHOST! on !LASTTIME!.
  call :count "%REMOTE%"
  echo        Copying !N! save files ^(!MB! MB^) into your game.
  echo        This can take a few seconds. Please wait...
  "%SYS%\robocopy.exe" "%REMOTE%" "%LOCAL%" /MIR /R:5 /W:3 /NJH /NJS /NDL /NFL /NP >nul
  if errorlevel 8 (
    echo.
    echo  PROBLEM: Could not copy the world from the shared folder.
    echo  Has your sync service finished downloading it? Wait for it, then press Play again.
    call :log "PULL FAILED on %ME%"
    goto :unlock_fail
  )
  echo        Done. Your game now has the newest version of the world.
  call :log "PULL ok on %ME%"
) else (
  echo        The shared folder has no world in it yet.
  echo        The world on this PC will become the shared one when you quit.
  call :log "PULL skipped on %ME% (shared folder empty)"
)
echo.

:: remember what the shared world's save looked like before playing
set "BEFORE="
for %%F in ("%LOCAL%\*_Latest.zip") do set "BEFORE=%%~tF %%~zF"

:: ---------- play ----------
echo  [3/4] Starting Windrose. Have fun.
echo        Leave this window open. When you quit the game it uploads
echo        the world for the next host, then closes on its own.
echo.
goto :launch

:nosync
echo  Join / Play. Starting Windrose now.
echo  Join a friend's game from the multiplayer menu, or pick your own world.
echo  The shared world is left alone and nothing is uploaded when you quit.
echo.
call :log "%MODE% session on %ME% (shared world untouched)"

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
echo  PROBLEM: Windrose did not start within 5 minutes.
call :log "GAME did not start on %ME%"
goto :unlock_fail

:running
echo        Windrose is running. This window is waiting for you to quit the game.
:wait_exit
"%SYS%\ping.exe" -n 11 127.0.0.1 >nul
"%SYS%\tasklist.exe" /FI "IMAGENAME eq %GAME_EXE%" /FO CSV /NH 2>nul | "%SYS%\find.exe" /I "%GAME_MATCH%" >nul
if not errorlevel 1 goto :wait_exit

:: give the game a moment to finish writing its exit backup
echo.
echo        Windrose closed. Giving it a moment to finish saving...
"%SYS%\ping.exe" -n 11 127.0.0.1 >nul

if not "%MODE%"=="host" (
  echo.
  echo  All done. The shared world was left alone.
  echo  This window will close in a few seconds.
  call :log "%MODE% session ended on %ME%"
  if "%STEAM_MODE%"=="1" ("%SYS%\ping.exe" -n 6 127.0.0.1 >nul) else (pause)
  exit /b 0
)

:: ---------- push ----------
echo.
set "AFTER="
for %%F in ("%LOCAL%\*_Latest.zip") do set "AFTER=%%~tF %%~zF"
if "%AFTER%"=="%BEFORE%" if exist "%REMOTE%\*_Latest.zip" (
  echo  [4/4] The world did not change this session, so there is nothing to upload.
  call :log "PUSH skipped on %ME% (world unchanged)"
  goto :done
)
echo  [4/4] Uploading your session to the shared folder...
call :count "%LOCAL%"
echo        Copying !N! save files ^(!MB! MB^). This can take a few seconds.
echo        Please wait. Do not close this window.
"%SYS%\robocopy.exe" "%LOCAL%" "%REMOTE%" /MIR /R:5 /W:3 /NJH /NJS /NDL /NFL /NP >nul
if errorlevel 8 (
  echo.
  echo  PROBLEM: Could not copy the world to the shared folder.
  echo  Your save is still safe on this PC. Press Play again later to retry,
  echo  or copy the folder by hand:
  echo    from %LOCAL%
  echo    to   %REMOTE%
  call :log "PUSH FAILED on %ME%"
  goto :unlock_fail
)
echo        Done. The next host will get this version of the world.
call :log "PUSH ok on %ME%"

:done
del /Q "%LOCKFILE%" 2>nul
call :log "LOCK released by %ME%"
echo.
echo  All done. You have handed the helm back.
echo  Before the next person hosts, give your sync service a moment to
echo  finish uploading ^(OneDrive shows a green check mark when it is done^).
echo.
echo  This window will close in a few seconds.
if "%STEAM_MODE%"=="1" ("%SYS%\ping.exe" -n 9 127.0.0.1 >nul) else (pause)
exit /b 0

:unlock_fail
del /Q "%LOCKFILE%" 2>nul
call :log "LOCK released by %ME% after error"
:fail
echo.
if "%STEAM_MODE%"=="1" (
  echo  This window will close in a few seconds.
  "%SYS%\ping.exe" -n 16 127.0.0.1 >nul
) else (
  pause
)
exit /b 1

:: ============================================================
::  Helpers
:: ============================================================

:: :count "folder"  ->  N = number of save zips, MB = their total size
:count
set /a N=0
set /a KB=0
for %%F in ("%~1\*.zip") do (
  set /a N+=1
  set /a KB+=%%~zF/1024
)
set /a MB=KB/1024
exit /b 0

:: :last_host  ->  LASTHOST / LASTTIME from the newest "PUSH ok" line in the log
:: Log lines look like:  Sun 09/13/26 22:48:08.52 PUSH ok on DESKTOP-NAME
:last_host
set "LASTHOST="
set "LASTTIME="
if not exist "%LOG%" exit /b 0
for /f "tokens=2,3,7" %%A in ('%SYS%\findstr.exe /C:"PUSH ok on" "%LOG%"') do (
  set "LASTHOST=%%C"
  set "LASTTIME=%%A %%B"
)
if defined LASTTIME set "LASTTIME=!LASTTIME:~0,14!"
exit /b 0

:log
>> "%LOG%" echo %DATE% %TIME% %~1
exit /b 0

:: ============================================================
::  ONE-TIME SETUP: choose the world to share.
::  Runs only when the shared folder has no world-id.txt yet, so only
::  the very first person in the group ever sees this. It lists the
::  worlds this PC has hosted and saves the chosen ID to the shared
::  folder. Everyone else's script reads it from there.
:: ============================================================
:first_time_setup
echo.
echo  ==============================================================
echo    ONE-TIME SETUP: choose the world to share
echo  ==============================================================
echo.
echo  No world has been chosen for this shared folder yet.
echo.
echo    If your group ALREADY set this up, your sync service has not
echo    finished downloading the shared folder. Press Q, wait for it to
echo    finish, and try again.
echo.
echo    If you are the FIRST person setting this up, pick the world below.
echo    Nobody else in the group will ever have to do this.
echo.
set /a COUNT=0
if exist "%WORLDS%\" for /d %%D in ("%WORLDS%\*") do (
  set /a COUNT+=1
  set "W!COUNT!=%%~nxD"
  set "STAMP=never"
  for %%F in ("%%D\*_Latest.zip") do set "STAMP=%%~tF"
  echo    [!COUNT!]  %%~nxD    last saved: !STAMP!
)
if %COUNT%==0 (
  echo    This PC has never hosted a Windrose world, so there is nothing to share.
  echo    Either the person who owns the world should run this first, or start
  echo    a new world in Windrose, play a minute, quit, and run this again.
  echo.
  call :log "SETUP on %ME%: no local worlds found"
  exit /b 0
)
echo.
echo    Windrose does not show the world's name here, only its ID. The one
echo    with the newest "last saved" time is the world you played most recently.
echo.
set "PICK="
if %COUNT%==1 (
  "%SYS%\choice.exe" /C YQ /M "  Only one world found. Share world [1]? Y = yes, Q = quit"
  if errorlevel 2 exit /b 0
  set "PICK=1"
) else (
  set /p PICK=  Type the number of the world to share, or Q to quit:
  if /I "!PICK!"=="Q" exit /b 0
)
if not defined PICK exit /b 0
if not defined W%PICK% (
  echo    "%PICK%" is not one of the numbers in the list. Nothing was changed.
  exit /b 0
)
set "WORLD_ID=!W%PICK%!"
> "%WORLD_FILE%" echo !WORLD_ID!
echo.
echo    Saved. The shared world is now %WORLD_ID%.
echo    This was written to the shared folder, so everyone else picks it up automatically.
echo.
call :log "SETUP on %ME%: world set to !WORLD_ID!"
exit /b 0
