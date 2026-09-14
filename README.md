# WindroseShared

Version 0.0.1. Windows and Steam only.

Share one Windrose world between friends so **anyone in the group can host it**.

Windrose has no dedicated servers. The world lives on the host's PC, so if the
host is not online, nobody can play. This script fixes that: the world lives in
a cloud-synced folder (OneDrive, Dropbox, Google Drive, anything that syncs a
folder), and whoever hosts gets the latest copy before the game starts and
uploads it when they quit. Everyone else just joins the host like normal.

- Windows and Steam only. It is a plain Windows batch script that hooks into
  Steam's launch options and Steam's save folder, so it needs the Steam version
  of Windrose on Windows. It does not run on Steam Deck, Linux, Mac, or a
  non-Steam copy of the game.
- Works with any number of players. The only limit is whatever the game allows.
- Your own characters and your own other worlds are never touched.
- One player does a one-time step to choose the world. Nobody else ever has to.

## How it works

Every time you press Play in Steam, the script runs first:

1. Writes a `LOCK.txt` file in the shared folder so nobody else hosts at the same time.
2. Copies the shared world from the synced folder into the game's save folder.
3. Starts Windrose and waits for it to close.
4. Copies the world back into the synced folder and removes the lock.

If someone else already holds the lock, the script offers to start the game in
**join mode** instead: it launches Windrose without touching the shared world,
and you join the host from the multiplayer menu.

The script only ever copies the game's own backup zip for that one world. Before
it overwrites anything it keeps a safety copy under
`%LOCALAPPDATA%\R5\Saved\SaveProfiles\<your Steam ID>\WindroseShared_safety`.

## Setup (every player, about 5 minutes)

### Step 1: put the script next to the game

1. In Steam, right-click Windrose > Manage > Browse local files.
   A folder opens that contains `Windrose.exe`.
2. Copy `WindroseShared.cmd` into that folder, next to `Windrose.exe`.

### Step 2: get the shared folder on your PC

One person creates a folder called `WindroseShared` in their sync service and
shares it with the group. Everyone else accepts the invite and makes it show up
in their own synced folder on disk:

- **OneDrive**: open onedrive.com > Shared > WindroseShared > "Add shortcut to My files".
  Then in File Explorer, right-click the folder and choose "Always keep on this device".
- **Dropbox**: accept the shared folder invite. Right-click the folder in File
  Explorer and choose "Make available offline".
- **Google Drive**: in drive.google.com, right-click the shared folder > Organize >
  "Add shortcut" to My Drive. In the Drive app, set the folder to "Available offline".

Whichever service you use, the folder must be fully downloaded on your PC, not
"online-only" placeholders. The script copies files with normal Windows tools and
needs them to be real files.

Then open `WindroseShared.cmd` in Notepad and check the `SHARED` line near the
top. It defaults to OneDrive:

```
set "SHARED=%OneDrive%\WindroseShared"
```

If you use something else, replace it with the matching example from the
comments right above it, for instance:

```
set "SHARED=%USERPROFILE%\Dropbox\WindroseShared"
set "SHARED=G:\My Drive\WindroseShared"
```

The path must point at the `WindroseShared` folder inside your synced folder.

### Step 3: make Steam run the script, and turn off Steam Cloud

1. In Steam, right-click Windrose > Properties > General.
2. In the LAUNCH OPTIONS box paste exactly this, all on one line:

   ```
   cmd /c .\WindroseShared.cmd steam %command%
   ```

3. On the same General tab, turn OFF "Keep games saves in the Steam Cloud for Windrose".
   Steam Cloud would otherwise fight with the synced folder over which copy of the world is newest.
4. Close the window. Done.

## First-time only: choose the world (one person, once)

The very first person to press Play after setup is asked which world to share.
This happens **once, ever**. The answer is saved to `world-id.txt` in the shared
folder and every other player's script reads it from there. Nobody else will
ever see this question, and nobody needs to look up or type a world ID.

That first person should be whoever already has the world you want to keep
playing. When they press Play, the black window lists the worlds their PC has
hosted, each with its last-saved time. Windrose does not show the world's name
here, only its ID, so pick by the time: the newest one is the world they played
most recently. If only one world is found, the script just asks Y to confirm.

After that, the first host plays as normal, quits, and their copy of the world
becomes the shared one.

If you see this question but someone in your group already did it, your sync
service has not finished downloading the shared folder yet. Press Q, wait for
the sync to finish, and press Play again.

## Playing

- Press Play in Steam like normal. A black "Windrose Shared Helm" window appears
  first and walks through four steps, then the game starts.
  **Leave that window open while you play.** It closes by itself after you quit.
- When nobody is hosting, the window asks what you want to do:
  - `H` to host the shared world. **Press H even if you are playing it alone.**
    Playing the shared world solo is the same save as hosting it, and H is what
    uploads your progress for everyone else.
  - `J` to Join / Play: join a friend's game or play a different world of your
    own. The shared world is left alone, nothing is uploaded, and your friends
    can still host it while you play.
- If the window says **someone else has the helm**, they are hosting. Press:
  - `J` to Join / Play: join their game from the multiplayer menu, or play a
    different world of your own
  - `H` to host anyway (only if you are all sure nobody is hosting)
- To quit at either prompt, just close the window. Nothing has been touched yet.
- After the host quits, wait for your sync service to finish uploading before
  the next person hosts. OneDrive shows a green check mark, Dropbox and Google
  Drive show a similar "up to date" state.
- If the game crashed, just press Play again. Nothing is lost.

## Troubleshooting

- **"The shared folder path is not valid"** or **"sync folder was not found"**:
  the `SHARED` line in the script does not match where your sync service keeps
  its folder. Fix it as described in Step 2.
- **"No Windrose save profile found"**: start Windrose once on this PC without
  the script, quit, then try again.
- **Lock is stuck**: someone's game closed without releasing it. Ask around, and
  if nobody is hosting press `H`, or delete `LOCK.txt` from the shared folder.
- **Something went wrong with the world**: the previous copy from this PC is in
  the `WindroseShared_safety` folder mentioned above, and the game itself keeps
  timestamped backups next to the `_Latest.zip` file.
- **What happened when**: `sync-log.txt` in the shared folder records every
  lock, pull, push, and error from every player's PC.

## Notes

- The script reads the Steam launch options only to start the game the way Steam
  would. It does not change anything else about Steam or the game.
- Nothing personal is stored in the shared folder except each PC's computer name
  in the lock file and the log.
- This project is not affiliated with the developers of Windrose.

## License

MIT. See [LICENSE](LICENSE).
