# First prompt for the iOS / iPadOS port

You are building the Apple version of Tali's Notes, a handwriting notes app that already ships on
Android (Kotlin and Jetpack Compose, in `C:\dev\Talis-Notes`, the reference: read it, pull its
`master` to stay current, never change or commit to it). The Apple app lives in its own repository,
`C:\dev\Talis-Notes-iOS` (GitHub: `arielmz1234/Talis-Notes-iOS`, public, branch `main`); if the
folder is missing, clone it there. Copy this brief into it as `BRIEF.md` on the first run. The owner will not test, review or answer
questions during this run. It is a long, unattended run that restarts from the files on disk each
time the usage limit resets, so work in a way the next session can pick up cold.

## What to build

- **iPad first**, Apple Pencil first: the Android tablet app is the spec. Landscape and portrait.
- **iPhone too**: opens notebooks just for looking by default (a Write button switches to editing and is
  remembered per item on that phone), but can still do everything, like the Android phone layout
  (`PHONE_DP`, `MainToolbarPhone`, the library drawer).
- **Backups**: iCloud on **both iPad and iPhone** (the Apple default people expect: automatic, and
  the same notebooks reach every device signed in to the same Apple account, so the iPhone can read
  what was written on the iPad) **and** Google Drive (the same
  Drive layout as Android: a "Tali's Notes" folder, one file per notebook plus the settings file,
  `appProperties` tags; see `backup/DriveBackup.kt` and `backup/BackupArchive.kt`), so one person can
  move between an Android tablet and an iPad. Backup `.zip` files restore on both platforms, merging,
  never wiping.
- Free, no accounts, no analytics. Everything stays on the device except the user's own iCloud and Drive.

## Read first

`CLAUDE.md` and `README.md` in the Android repository describe every feature, the owner's taste, the design
(lilac and light-blue sky, soft 3D clouds, the cloud-puff "goes away" animation, gliding selection),
and dozens of hard-won fixes, especially around ink latency, page clipping, snapping and hold-to-shape.
Their *Working with the owner* and *Look and feel* sections apply here as they are (fit on one screen, taste over feature count, his animation and shape preferences, Emil Kowalski's motion rules, light and dark, the languages); the Android build, emulator and Play steps don't. Treat them as the product spec and as lessons; the Kotlin is the reference implementation. Port its
unit tests along with the logic they cover (geometry, shapes, snapping, lasso, recognizer, page
layout, backup format): they are the cheapest proof the port behaves the same.

## Environment: check this before anything else

iOS apps build only with Xcode on macOS. Find out where you are running:
- **On a Mac with Xcode:** build and test locally with `xcodebuild` and the iPad and iPhone simulators;
  use UI tests to take screenshots and look at them.
- **Not on a Mac (the owner's Windows PC, where this runs):** build in CI. Add a GitHub Actions workflow on a macOS
  runner that builds, runs the unit tests, runs UI tests that save screenshots (iPad landscape and
  portrait, iPhone, light and dark, Hebrew), and uploads them as artifacts. Push, wait for the run with
  `gh run watch`, download the artifacts with `gh run download`, and look at the screenshots yourself.
  macOS minutes are limited on private repositories, so batch your changes and keep each run lean.
- Before the owner pays for an Apple Developer account he will try it on an iPad by sideloading
  (Sideloadly or AltStore from Windows, signed with his free Apple ID, valid 7 days). So CI also
  uploads an unsigned `.ipa` of every green build as an artifact, and the app must run fully
  without capabilities a free account can't sign (iCloud, push): iCloud is switched off in that
  build and says so, while Google Drive and backup files still work. Put the sideloading steps
  in `OWNER_TODO.md`.
- Generate the Xcode project from a text file (XcodeGen `project.yml`, or a Swift package plus a thin
  app target) so you never hand-edit `.pbxproj`.

If neither works, say so in `OWNER_TODO.md` and keep writing code and pure-Swift tests that you can
check another way, rather than stopping.

## Technical direction (your judgement within these)

- Swift 6, SwiftUI for the app, UIKit where the canvas needs it. Minimum iPadOS/iOS 17.
- Ink: Apple Pencil latency matters most. PencilKit is the natural first choice for the live stroke;
  keep the notebook's own stroke model (inputs with pressure, tilt and time, as on Android) so pens,
  line styles, shapes, the lasso, page clipping and backups work the way they do on Android. Measure
  before replacing anything with a custom renderer.
- Storage: SQLite (GRDB or plain SQLite3), with a schema that maps cleanly to the Android one
  (`data/NotesDb.kt`), so backups convert both ways.
- iCloud: per-notebook files in the app's iCloud container (or CloudKit's private database if you
  judge it better), backing up by itself after changes, and restoring on a new iPad from the first-open card.
- Google Drive: Google Sign-In for iOS, scope `drive.file`, the same file format and tags as Android.
- All six languages (English, Spanish, French, Brazilian Portuguese, Arabic, Hebrew) with String
  Catalogs, the same wording as the Android strings, and right-to-left layouts mirrored except inside a
  notebook (as on Android).

## Order of work

Get a working app early, then widen it. Roughly:
1. Project, CI and screenshot pipeline; theme (colours, fonts, clouds, cloud surface).
2. Library: notebooks, folders, search, sort, Recently deleted; new-notebook card.
3. Notebook: A4 pages, papers, zoom and scroll, pens and highlighter, erasers, undo/redo, lasso
   (move, resize, copy, delete), page overview.
4. Backup `.zip` read and write compatible with Android; iCloud; Google Drive.
5. PDF import (sharp at any zoom) and PDF export; pictures; typed text.
6. Shapes, hold-to-shape, snapping, fill; then the rest of the features in `CLAUDE.md`, by how much
   they help a student.
7. iPhone layout throughout.
8. App Store readiness: icon from `tools/icon-source.png`, privacy manifest, screenshots, store text.

## How to work

- All code goes in `C:\dev\Talis-Notes-iOS`. Don't change the Android app.
- Keep `PLAN.md` (milestones, with checkboxes) and `PROGRESS.md` (what was done, what was
  verified and how, what's next, known problems). Start every session by reading them and the latest CI run;
  update them before you stop.
- Commit and push after every working chunk with a plain-English message. Keep CI green; if a change
  breaks it, fix it before moving on.
- Verify by looking: after a visual change, check the screenshots in light and dark, iPad and
  iPhone. Report only what you have actually seen working; label anything not verified as such.
- Things only the owner can do go in `OWNER_TODO.md` with exact steps (the Apple Developer
  account, bundle id and signing, App Store Connect API key as GitHub secrets, the Google Cloud iOS
  OAuth client, iCloud container, installing from TestFlight). Prepare everything around them and
  carry on with other work; don't wait.
- Never commit secrets, keys or certificates.

## Running unattended

- A scheduled task starts a fresh session every few hours. If `RUNNING` in the repository root holds
  a time less than 4 hours old, another session is still working: stop without changing anything.
  Otherwise write the current time there, push nothing for it (it's in `.gitignore`), and delete it
  when you finish.
- GitHub CLI is installed at `C:\Program Files\GitHub CLI\gh.exe` and signed in as `arielmz1234`; call it by that path if `gh` isn't on the PATH.
- If GitHub CLI (`gh`) is missing or not signed in, or the GitHub repository doesn't exist yet, put
  it first in `OWNER_TODO.md` and work locally (code, pure-Swift tests, commits) until it's there.
- Work until you run low on usage, leaving `PROGRESS.md` and the last commit in a state the next
  session can continue from.
