# Releases

The Mac app is released on GitHub (`lobrenov/ta-da-swift`), one release per build, tagged `v<version>-<build>`. Each release has three files: the update zip, the DMG for first installs, and `appcast.xml`, the Sparkle feed, which lists that build. Installed copies read the latest release's feed (`releases/latest/download/appcast.xml`) on open and daily, and update themselves (Updates in `docs/architecture.md`).

The app is signed with the Apple Development certificate of a free Apple Developer account, with no provisioning profile, so builds don't expire. It isn't notarised, so a first install is unblocked once; updates through Sparkle need no unblocking. The signature keeps the same identity from build to build, so the chosen folder is remembered across updates.

## Signing key
Updates are signed with an EdDSA key. Its public half is `SUPublicEDKey` in `TaDa/Info.plist`; its private half is in the login Keychain of each Mac that releases (item `https://sparkle-project.org`, account `ed25519`), with a copy in Apple Passwords (Ta Da Sparkle EdDSA key). Without it, installed copies can't update. Sparkle's tools are in the package's artifacts: `<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin`.

To add the key to another Mac, copy it from Passwords, then run, with `<bin>` that Mac's tools folder:
```bash
pbpaste > key.txt && <bin>/generate_keys -f key.txt; rm -f key.txt; pbcopy < /dev/null
```
`generate_keys -p` prints the Keychain's public key. `make-release.sh` stops if it isn't `SUPublicEDKey`.

## Releasing
1. Bump Build in Xcode (TaDa target › General › Identity), and Version as `docs/versioning.md` says. Commit and push.
2. Check:
   ```bash
   scripts/make-release.sh --dry-run
   ```
   It archives, then writes `TaDa-<version>-<build>.zip`, `.dmg` and `.html` (the notes: commit subjects since the last release tag) and `appcast.xml` to `build/release/`, and prints the feed. `build/` is gitignored.
3. Release:
   ```bash
   scripts/make-release.sh
   ```
   It needs a clean tree at `origin/main` and stops if the build already has a release. It creates the release as latest, with the zip, DMG and feed. A failed upload leaves a draft release; delete it before running again.

## First install
Requires macOS 26 or later.
1. Download the `.dmg` from the latest release. Double-click it, drag **Ta Da** onto **Applications**, then eject the disk image. A copy opened from Downloads or the disk image can't update itself.
2. Unblock it, either way:
   - Terminal: `xattr -dr com.apple.quarantine "/Applications/Ta Da.app"`
   - Without Terminal: double-click Ta Da and click **Done** on the warning. Then open System Settings › Privacy & Security, click **Open Anyway** next to the Ta Da message, and confirm.
3. Open Ta Da and choose the tasks folder.

Later builds arrive through Ta Da's update window, on open or with Ta Da ▸ Check for Updates…. The folder is remembered.
