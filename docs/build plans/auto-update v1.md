# Ta Da — Auto-update v1

## Context
The Mac app updates itself with Sparkle 2: it checks for a new build on open, downloads it from GitHub, installs it and relaunches. It's built in three parts.
- Part 1: a local spike showing that a sandboxed, unnotarised Ta Da can update itself.
- Part 2: Sparkle in the app, with releases published on GitHub, still unnotarised.
- Part 3: the paid Apple Developer Program, Developer ID signing and notarisation, and what changes in Sparkle.

The iPhone app isn't part of this plan: Sparkle is macOS only.

## Decisions
- Sparkle 2 is pinned with `exact:` and linked to the Mac app only. `import Sparkle` is only in `TaDa/Updates/Updater.swift`, behind `#if os(macOS)`. Adding it updates `TaDa/Acknowledgements.txt`.
- Each update is signed with an EdDSA key (Sparkle's `generate_keys`), and Sparkle accepts it if either the EdDSA signature or the Apple code signature matches. The private key is kept in the Keychain of each Mac that releases (`generate_keys -x` exports it, `-f` imports it) and is never committed. The app's designated requirement matches the Apple Development certificate's name (`Apple Development: <Apple ID> (<member ID>)`), which is the same on every Mac signed in to the same Apple ID, so builds from any of them pass the code-signature check too.
- Once a build ships with an EdDSA key and a code signature, every later build needs both. Sparkle lets you replace the key but not drop it.
- Sandbox setup:
  - Sparkle's installer helper is turned on (`SUEnableInstallerLauncherService`).
  - A new `TaDa/TaDa.entitlements` adds the `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `-spki` mach-lookup exceptions.
  - Outgoing network connections are turned on, so Sparkle's separate download helper isn't needed.
- The Sparkle keys (`SUFeedURL`, `SUPublicEDKey`, `SUEnableInstallerLauncherService`, `SUEnableAutomaticChecks`) go in a new `TaDa/Info.plist`, which Xcode merges with the generated one. `INFOPLIST_FILE` points to it, and it's left out of the target's resources.
- Checks: on every open (`checkForUpdatesInBackground()` in `Updater`'s init, since Sparkle's own schedule checks at most daily and skips the first launch), plus Sparkle's daily check (`SUEnableAutomaticChecks = YES`, so there's no permission prompt). The Ta Da menu gets Check for Updates…. Sparkle's own update window and release notes are used as they are.
- Updates are a zip made with `ditto -c -k --keepParent`, not deltas (`generate_appcast --maximum-deltas 0`; it makes deltas by default). The DMG stays for first installs.
- Release notes are a short HTML file per build, made from the commits since the last tag.
- Versions: Part 1 has no version and isn't merged. Part 2 ships as the next `y` version, and Part 3 as the `z` version after it. The build number goes up as `docs/versioning.md` says. Sparkle compares `CFBundleVersion`, the build number.
- Not in v1: release channels (beta/stable), delta updates, Homebrew, CI builds, iPhone.

## Part 1 — Local spike
On a throwaway branch, `spike/sparkle`, not merged.

1. Add Sparkle, the entitlements, the Info.plist keys, `Updater.swift` (`SPUStandardUpdaterController`) and Check for Updates…. Point `SUFeedURL` at `http://localhost:8000/appcast.xml`, and allow it with `NSAppTransportSecurity` › `NSAllowsLocalNetworking`.
2. Generate the EdDSA key. Archive build N into `build/spike/N/` and build N+1 into `build/spike/N+1/`, zip both with `ditto`, then run `generate_appcast build/spike/feed`. Serve the folder with `python3 -m http.server 8000`.
3. Install build N in `/Applications`. Add the quarantine flag to it (`xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" "/Applications/Ta Da.app"`) and unblock it once, as a tester does.
4. Run Check for Updates… and install.
   Check:
   - Ta Da relaunches as build N+1 with no Gatekeeper warning.
   - The chosen folder is remembered.
   - `xattr -l "/Applications/Ta Da.app"` shows no `com.apple.quarantine` (record whether `com.apple.provenance` appears).
   - Console, filtered to Sparkle and Autoupdate, shows no validation errors.
5. Build N+2 on a second Mac (a different Apple Development certificate, the same EdDSA key) and update to it. Check: it installs, which shows that the EdDSA check is enough.
6. Restart the app and wait for the on-open check. Check: Sparkle offers the update without Check for Updates….
7. Write the results into this plan (Part 1 outcome), along with any changes to Parts 2–3. Check: the user signs off going ahead with Part 2.

### Part 1 outcome
Done 2026-11-02 on `spike/sparkle` (Sparkle 2.10.1, macOS 27.0.1, Xcode 27.2), installed in `~/Applications`, all on one Mac with the free Apple Development certificate. The branch holds the code Part 2 starts from: the project's Sparkle package (Mac only), `TaDa/Info.plist`, `TaDa/TaDa.entitlements`, `TaDa/Updates/Updater.swift` and Check for Updates….
- Install: a quarantined DMG of 39.1, dragged to `~/Applications` and unblocked once with Open Anyway.
- 39.1 → 39.2 with Check for Updates…: installed and relaunched with no Gatekeeper warning; the folder was remembered. The new app has no `com.apple.quarantine`, has `com.apple.provenance`, and `spctl` rejects it, which doesn't stop it opening.
- 39.2 → 39.3 signed ad-hoc: Sparkle accepted and installed it on the EdDSA signature alone. It doesn't launch, because an ad-hoc app with the hardened runtime can't load Sparkle.framework (different Team IDs), so EdDSA-only acceptance is shown for Part 3's change to Developer ID, not for ad-hoc builds.
- 39.4 → 39.5 on open: the update window appeared without Check for Updates….
- A quarantined app opened where it was downloaded runs translocated, and Sparkle refuses to update it, asking the user to move it to Applications. Dragging from the DMG avoids it.
- Sparkle's tools (`generate_keys`, `generate_appcast`, `sign_update`) are in the package's artifacts: `<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin`.

## Part 2 — Unnotarised updates via GitHub
Files attached to releases in a private repo can't be downloaded without signing in, so the feed and the update files have to be public.

### Option a: make `ta-da-swift` public
| Pros | Cons |
|---|---|
| One repo: tags, releases and the feed sit next to the code | The source, history and `SampleVault` are public; it needs a licence decision first (the editor fork is Apache-2.0, and Acknowledgements must be complete) |
| `gh release create` runs with no `--repo` | Anything sensitive in the history (paths, emails, team ID) is public; it needs an audit first |
| Free GitHub Pages, if wanted later | Issues, PRs and forks are open unless switched off |

### Option b: a public `lobrenov/ta-da-app-releases` repo
| Pros | Cons |
|---|---|
| The source stays private | A second repo to create; `gh release create --repo lobrenov/ta-da-app-releases` |
| The repo holds only builds, notes and the feed; switching later to option a just means moving the feed | Tags are in two places: `v<x.y.z>` in `ta-da-swift`, and the release tag in the releases repo |
| Its README can be the tester page (install and unblock steps) | |

Both options use the same feed URL pattern, so the steps below work for either: `https://github.com/lobrenov/<repo>/releases/latest/download/appcast.xml`. Every release attaches the zip, the DMG, its notes and the whole `appcast.xml`. `generate_appcast` builds the feed from `build/releases/`, a local folder that keeps every released zip, which `make-release.sh` syncs from the GitHub releases before it runs. The choice between a and b is final once a build ships, because `SUFeedURL` is built into every copy.

1. Choose a or b. For b, create the repo with a README holding the tester steps. Check: the user decides.
2. Sparkle in the app from `spike/sparkle`, with the real `SUFeedURL` and without the `NSAppTransportSecurity` exception, and its section in `TaDa/Acknowledgements.txt`. Check: the app builds for Mac and iOS; iOS doesn't link Sparkle.
3. `scripts/make-release.sh`, which replaces `make-beta-dmg.sh`:
   - archive, then make the DMG as now, plus the update zip
   - write the notes
   - run `generate_appcast` with the EdDSA key from the Keychain
   - run `gh release create v<x.y.z>-<n>` with the four files
   - stop if the build number already has a release

   Check: a dry run (`--dry-run`) prints the files and the feed, and creates no release.
4. `docs/beta-builds.md` becomes `docs/releases.md`: releasing, the EdDSA key on each Mac, first install from the DMG (dragged to Applications before opening, so Sparkle can update it), and updates arriving by themselves. Add the Updates section to `docs/architecture.md`. Check: the docs match the script.
5. Ship the first Sparkle build the old way (a DMG with the unblock steps), then a second build through Sparkle. Check: a tester's Mac updates from the first to the second with no unblocking, and the folder is remembered.

### Part 2 outcome
Done 2026-11-03 with option a: the app repo is public as `lobrenov/ta-da-swift` (renamed from `ta-da-app`), beside the public `lobrenov/ta-da-obsidian`.
- `scripts/make-release.sh` replaces `make-beta-dmg.sh`. The feed lists only the release's own build, with its notes embedded, so each release attaches three files (zip, DMG, `appcast.xml`) and needs no sync of earlier zips. It creates the release as latest, and stops if the Keychain's key isn't `SUPublicEDKey`.
- The updater doesn't start in Debug builds, so tests and Xcode runs don't check the feed. Check for Updates… follows `canCheckForUpdates`.
- `docs/releases.md` replaces `docs/beta-builds.md`; Updates is in `docs/architecture.md`.
- 0.37.0 (40) was installed from its DMG on a second Mac and unblocked once; on the next open it offered 0.37.1 (41), which installed with no Gatekeeper warning and kept the folder.

## Part 3 — Apple Developer Program and notarisation

### Enrolling
- Enrol as an **individual** with the Apple Account Ta Da is built with. It needs two-factor authentication, your legal name, and an address that isn't a PO box. There's no D-U-N-S number for individuals; an organisation needs one, plus a website and email on its own domain. Enrol through the Apple Developer app or the website, and agree to the licence agreement.
- Cost: 99 USD a year, charged in local currency. Apple gives no approval time; a name that doesn't match your ID delays it.
- The paid team may have a different Team ID from the free Personal Team (`U398Z5XX5X`). Check it after enrolling, because `DEVELOPMENT_TEAM` changes with it.
- The same membership covers TestFlight and the App Store for the iPhone app (the backlog item), and removes the 7-day expiry.

### Signing and notarising
- In Xcode › Settings › Accounts, create a **Developer ID Application** certificate. Export it as a `.p12` to each Mac that releases.
- Store the notarisation credentials once per Mac: `xcrun notarytool store-credentials TaDa --apple-id … --team-id … --password <app-specific password>`. An App Store Connect API key is the alternative if releases move to CI later.
- `make-release.sh` changes to:
  1. archive
  2. `xcodebuild -exportArchive` with `method: developer-id`, which re-signs Sparkle's helpers with the hardened runtime and a secure timestamp
  3. zip the app, then `notarytool submit --wait`
  4. `stapler staple` the app
  5. zip again for Sparkle
  6. make the DMG, notarise it and staple it
  7. run `generate_appcast` and `gh release create` as before
- Notarisation fails on `get-task-allow` (debug builds) and on unsigned nested code. The script checks the export with `spctl --assess --type execute -vv` and `stapler validate`.

### Sparkle changes
- None required (Part 1 showed Sparkle installing an update on its EdDSA signature alone). The first Developer ID build is still EdDSA-signed with the same key, so unnotarised builds update to it even though the code signature changes from Apple Development to Developer ID. After that, either check can be used to replace the key later.
- The sandbox container and the chosen folder: a new Team ID changes the app's signing identity, and macOS may ask about the app's data or forget the folder once. Check it on the first update.
- Optional: once every installed copy is on Developer ID, `SUVerifyUpdateBeforeExtraction` can be set to check the Apple code signature before unpacking.
- Docs: drop the unblock steps from `docs/releases.md`, `README.md` and the DMG's `Read Me First.txt` (in `make-release.sh`), and remove the Developer ID line from `docs/backlog.md`.

### Steps
1. Enrol, then create the certificate and the notarisation profile. Check: `security find-identity -v -p codesigning` lists Developer ID Application; `notarytool history --keychain-profile TaDa` runs.
2. Update `DEVELOPMENT_TEAM` and `make-release.sh` as above. Check: `spctl` reports `source=Notarized Developer ID` for the app and the DMG.
3. Release one build through Sparkle to an unnotarised install. Check: it updates without prompts, and the folder is remembered (or the one-time prompt is noted in `docs/releases.md`); a fresh download of the DMG opens with no Gatekeeper warning.
4. Update the docs. Check: no unblock steps are left.
