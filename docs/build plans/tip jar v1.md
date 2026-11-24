# Ta Da — Tip jar v1

## Context
Ta Da stays free with nothing locked. People can tip $2, $5 or $10 through in-app purchase. Ta Da offers a tip in four places:
- the onboarding line
- an ask on day 7 and day 30
- the What's New screen after a feature update, when that release says so
- Settings ▸ About, at any time

The design is the Tip jar design (onboarding, tipAsk, whatsNew, Settings ▸ About tip jar).

In-app purchase needs an App Store build, and the Mac App Store doesn't allow Sparkle (guideline 2.4.5). So the app is built from two targets that share the same sources:
- **TaDa:** the App Store build, for iPhone and the Mac App Store. It has the tip jar and no Sparkle.
- **TaDa GitHub:** the Mac build `make-release.sh` publishes. It has Sparkle and no tip jar.

The paid Apple Developer Program (auto-update v1, Part 3) comes first.

## Decisions
- **Targets:**
  - `TaDa GitHub` is a second macOS app target. Its synchronised folders are the same as `TaDa`'s, so new files join both targets.
  - Build settings the two share go in `TaDa/Shared.xcconfig`; each target sets only what differs.
  - Sparkle is linked to `TaDa GitHub` only.
- **Flag:** `TaDa GitHub` sets `GITHUB_BUILD` in `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. No flag means an App Store build, so `TaDa` needs nothing.
  - Behind `#if GITHUB_BUILD`: `Updater.swift` and Check for Updates….
  - Behind `#if !GITHUB_BUILD`: `TaDa/Tips/` and every tip view.
- **Per target:**
  - `TaDa GitHub` keeps `TaDa/Info.plist` (the `SU*` keys) and `TaDa/TaDa.entitlements` (the `-spks` and `-spki` exceptions).
  - `TaDa` gets `TaDa/AppStore/Info.plist` and `TaDa/AppStore/TaDa.entitlements`: sandbox, user-selected files, calendars and reminders, and no Sparkle keys.
- **Schemes:** `TaDa` builds and tests the App Store build (Mac and iPhone), runs `TaDa.xctestplan`, and uses the StoreKit file. `TaDa GitHub` is the one `make-release.sh` archives.
- **Bundle ID:** both targets use `com.lobrenov.TaDa`.
  - They share one sandbox container, so settings and the folder bookmark carry over when someone moves from GitHub to the App Store.
  - The two can't be installed side by side.
  - Sparkle checks the code signature, so it won't replace an App Store copy.
- **Universal Purchase:** the iPhone and Mac App Store apps are one App Store Connect record with the same bundle ID, so a tip is the same product on both.
- **Products:** three consumable in-app purchases, `com.lobrenov.TaDa.tip.2`, `.tip.5` and `.tip.10`, at the $2.00, $5.00 and $10.00 price points, or $1.99, $4.99 and $9.99 if those are the nearest. Consumables can be bought again and aren't restored, so there's no Restore Purchase. Tips unlock nothing (guideline 3.1.1).
- **Prices:** shown from `Product.displayPrice`, never typed, so they're localised.
- **StoreKit 2:** only in `TaDa/Tips/TipJar.swift`. `TipJar` is `@Observable`, held by `AppModel.tips`. It loads the products, buys one, listens to `Transaction.updates`, finishes each transaction, and records the last tip's date and price in the settings. `TaDa/Tips/Tips.storekit` is set in the `TaDa` scheme, so Debug builds and tests buy without the App Store.
- **The asks:** `TipSchedule` is a value type that takes the first-launch date, the last tip and the asks already shown, plus an injected `today: LocalDate`. It answers whether today is an ask, and which one.
  - Day 7: on the first launch at least 7 days after the first launch.
  - Day 30: at least 30 days after it, unless a tip came first.
  - Each ask shows once; Not Now just closes it.
  - No ask on the first open after an update, which gets What's New, or while onboarding, Quick Entry or another sheet is up.
  - The first-launch date is set on the first launch of this version, so existing installs count from the update.
- **What's New:** in both targets.
  - Shown on the first launch after the version's `x` or `y` goes up, compared with the last version seen (`lastSeenVersion` in the settings). Never after a patch, and never on a fresh install.
  - Its content is the version's `docs/release notes/<x.y.z>.md`, copied into the app as `WhatsNew.md` by a build phase on both targets.
  - A release offers tips when its notes start with `tips: true` frontmatter. `make-release.sh` strips the frontmatter before writing the Sparkle and GitHub notes.
  - The screen draws the notes' `- ` items and `## ` headings. Its tips section is behind `#if !GITHUB_BUILD`. It doesn't show on the day an ask also falls (What's New wins).
- **Settings ▸ About:** a Tip Jar section at the top, on iPhone and Mac, in App Store builds. It shows the three tiers. After a tip it says "Thank you! You tipped $5 on 7 Dec." and still takes tips.
- **Onboarding:** the App Store build says "Everything works, free. Now and then Ta Da asks if you'd like to leave a tip." The GitHub build says "Everything works, free."
- **Settings keys:** `tipsFirstLaunch`, `tipsAsksShown` and `tipsLastTip` (date and display price), plus `lastSeenVersion`. These are device settings in `SettingsStore`, not the folder's `settings.json`. A tip on one device doesn't stop the asks on another; that's accepted for v1.
- **Not in v1:** tips in the GitHub build (including an outside tip link), syncing tip state between devices, a supporter badge, and analytics.

## Part 1 — Two targets
1. Add `TaDa/Shared.xcconfig`, and move the shared build settings into it. Check: `TaDa` builds for Mac and iOS, and the tests pass as before.
2. Add the `TaDa GitHub` target and scheme, with the same synchronised folders, `GITHUB_BUILD`, Sparkle, `TaDa/Info.plist` and `TaDa/TaDa.entitlements`.
   - Give `TaDa` the App Store Info.plist and entitlements.
   - Remove Sparkle from `TaDa`.
   - Put `Updater.swift` and Check for Updates… behind `#if GITHUB_BUILD`.

   Check:
   - Both targets build.
   - `nm` or `otool -L` on the `TaDa` Mac app shows no Sparkle.
   - The `TaDa GitHub` app has Check for Updates….
3. Point `make-release.sh` at the `TaDa GitHub` scheme, and update `docs/architecture.md` (Targets) and `docs/releases.md`. Check: `make-release.sh --dry-run` builds the GitHub app; a Sparkle update from the last GitHub release to it installs and keeps the folder.

## Part 2 — App Store Connect
1. Join the Paid Apps Agreement, and fill in banking and tax. Apply to the App Store Small Business Program (15% commission). Check: the agreement is Active.
2. Create the app record for iOS and macOS (Universal Purchase), and the three consumables, with display names, descriptions and a review screenshot of the tipAsk. Check: the products are Ready to Submit, and the price points are recorded in this plan.

## Part 3 — TipJar and TipSchedule
1. `TipSchedule`, with Swift Testing tests in `TaDaTests/TipScheduleTests.swift`. Check: the tests pass for each case:
   - day 6: no ask
   - day 7: the day-7 ask
   - day 8, day-7 ask shown: no ask
   - day 30: the day-30 ask
   - tipped at day 7: no day-30 ask
   - first open after an update: no ask
   - a 45-day gap: one ask only (day 30)
2. `TipJar` and `Tips.storekit`, with tests using `SKTestSession` in `TaDaTests/TipJarTests.swift`. Check: the three products load in order; a purchase records the tip and finishes the transaction; a cancelled purchase records nothing.
3. `AppModel.tips` and the settings keys, all behind `#if !GITHUB_BUILD`. Check: both targets build, and `swift test` passes (no StoreKit in TaDaCore).

## Part 4 — Settings ▸ About and onboarding
1. The Tip Jar section in `AboutSettingsView` (Mac) and the iPhone About page, as designed, in both states. Check: in a Debug `TaDa` build, a tip through `Tips.storekit` switches it to Thank you, and the `TaDa GitHub` build has no Tip Jar.
2. The onboarding line in `FolderPickerView`, per target. Check: it matches the design on iPhone and Mac.

## Part 5 — The asks
1. The tipAsk: a sheet on iPhone and a sheet on the Mac window, with day-7 and day-30 copy and the footnotes. Check: with the first-launch date set back 7 days and then 30 (a Debug-only launch argument, `-tipsFirstLaunch <YYYY-MM-DD>`), each shows once, and a tip at day 7 skips day 30.

## Part 6 — What's New
1. The build phase that copies the version's release notes, and the frontmatter strip in `make-release.sh`. Check: `make-release.sh --dry-run` writes notes without frontmatter, and both apps' bundles have `WhatsNew.md`.
2. The whatsNew screen: a sheet on iPhone, and a sheet on the Mac window, with tips in App Store builds when the notes say so. Check:
   - Tests in `TaDaTests/WhatsNewTests.swift` cover the version comparison (0.43.2 → 0.44.0 shows, 0.44.0 → 0.44.1 doesn't, a fresh install doesn't) and the frontmatter.
   - In the app, a changed `lastSeenVersion` shows it once.

## Part 7 — Docs and release
1. A Tips section in `docs/architecture.md`, the `tips:` frontmatter and both schemes in `docs/releases.md`, the Build commands in `CLAUDE.md`, and the canvas boards moved to the reference pages. Check: the docs match the code.
2. Ship as the next `y` version: the GitHub build through Sparkle, and the App Store build for iPhone and Mac through TestFlight, then App Review. Check:
   - A TestFlight tester tips in the sandbox.
   - What's New shows once in each build.
   - The GitHub build shows no tips.
