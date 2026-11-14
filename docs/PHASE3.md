# Phase 3: scope and status

Phase 3 adds the Files app, widgets, share links, iPad/Mac support and a paid tier with auto-move rules.
Phase 2 (more providers, previews in Photos, duplicates) has not been built yet; Phase 3 doesn't depend on it.

## How the pieces share data

```
            ┌──────────── App Group: group.<bundle> ────────────┐
 App  ──▶  library-snapshot.json · Thumbnails/ · settings (defaults)  ──▶  Files extension, Widgets
            └───────────────────────────────────────────────────┘
 App  ──▶  Keychain access group <team>.<bundle>.shared (tokens, device-only)  ──▶  Files extension
```

The CloudKit-backed SwiftData store stays private to the app. Extensions read a JSON **snapshot** the app writes
whenever the library, accounts or a scan change, and when the app goes to the background. That avoids opening a
CloudKit store from several processes.

Shared code compiled into every target lives in `StorageManager/Core/` (models, OAuth, providers, support, snapshot,
Files folder tree). It must not reference app-only types.

## Features

| # | Feature | Where | Status |
|---|---|---|---|
| 1 | **Files app**: "Storage Manager" location with Year › Month folders, readable names, thumbnails, download on open | `FileProvider/`, `Core/Shared/LibraryTree.swift` | ✅ read-only |
| 2 | **Widgets**: small/medium Home Screen, circular/rectangular Lock Screen; deep links to Storage, Videos, Library, cleanup | `Widgets/` | ✅ |
| 3 | **Share links**: create/stop an "anyone with the link can view" link (Drive permission / OneDrive `createLink`) | `CloudVideoDetailView`, providers | ✅ |
| 4 | **iPad & Mac**: sidebar navigation, all iPad orientations, ⌘A / ⌘M shortcuts, pointer hover, context menus, "Designed for iPad" on Apple silicon Macs | `RootView`, `project.yml` | ✅ |
| 5 | **Pro (StoreKit 2)**: monthly/yearly subscription + lifetime; native `SubscriptionStoreView` paywall; restore | `Services/Store/`, `Features/Store/` | ✅ |
| 6 | **Free-tier limit**: up to 10 videos per move; Pro is unlimited | `MoveSheet` | ✅ |
| 7 | **Auto-move rules** (Pro): size / age / screen recordings / skip favorites, per-rule destination, presets | `Services/Automation/`, `Features/Automation/` | ✅ |
| 8 | **Overnight auto-move**: `BGProcessingTask` (charging + online) uploads matches, then a notification | `AutoMoveService` | ✅ |
| 9 | **"Ready to free" cleanup**: one-tap batch delete of originals that are verified in the cloud but still on the phone | Dashboard, `TransferEngine` | ✅ |
| + | No re-uploads: videos already verified in the cloud are skipped and just deleted | `TransferEngine` | ✅ |

## Design decisions

- **Auto-move never deletes in the background.** iOS requires the user to confirm Photos deletions, so overnight runs
  only upload. The dashboard (and the notification) then offer a single "Free X GB" confirmation.
- **Files is read-only.** Moving, renaming or deleting from Files would bypass the catalog and the safety checks.
- **What's free vs Pro.** Everything from Phase 1, Files, widgets and share links stays free. Pro removes the batch
  limit and adds automation, which costs the user nothing on our side because there's no server.

## Known limitations / next steps

- **Not yet compiled**, like Phase 1. The new extension targets and iOS 26 APIs are the most likely spots for fixes.
- The Files location updates when the app writes a new snapshot, so changes from another device appear after the
  app has run on this one.
- "Move Now" on the Auto-move card runs the largest destination group; other groups go on the next run.
- iOS decides when `BGProcessingTask` runs (usually overnight on charge); it's not guaranteed nightly.
- Google Workspace admins can block "anyone with the link" sharing; the app shows the provider's error.
- Files and widgets haven't been verified in "Designed for iPad" mode on Mac.
- Manual StoreKit setup is required (see SETUP.md §7); there's no checked-in `.storekit` file yet.
