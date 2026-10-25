# Beta builds

Beta testers get a `.dmg` that holds the app, an Applications shortcut and `Read Me First.txt`. The app is signed with the Apple Development certificate of a free Apple Developer account, with no provisioning profile, so builds don't expire. It isn't notarised: Developer ID signing and notarisation need the paid Apple Developer Program. The signature keeps the same identity from build to build, so testers keep their chosen folder across updates.

## Building
1. Bump the build number in Xcode: TaDa project › TaDa target › General › Identity › Build. Bump Version as `docs/versioning.md` says.
2. Run:
   ```bash
   scripts/make-beta-dmg.sh
   ```
   The output is `build/TaDa-<version>-<build>.dmg`. The script deletes earlier DMGs in `build/`, prints the path and reveals the file in Finder. `build/` is gitignored.

## Sharing
Send the DMG through an iCloud Drive link (right-click › Share › Copy Link), AirDrop or any file-sharing link. Downloading it adds the quarantine flag, which testers clear once per build.

## Tester steps
Requires macOS 26 or later.
1. Double-click the `.dmg`, drag **Ta Da** onto **Applications**, then eject the disk image.
2. Unblock it, either way:
   - Terminal: `xattr -dr com.apple.quarantine "/Applications/Ta Da.app"`
   - Without Terminal: double-click Ta Da and click **Done** on the warning. Then open System Settings › Privacy & Security, click **Open Anyway** next to the Ta Da message, and confirm.
3. Open Ta Da and choose the tasks folder.

For a new build, repeat steps 1–2 and choose **Replace**. The folder is remembered.
