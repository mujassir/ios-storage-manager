# Phase 1: scope and status

Goal: **free up iPhone space by moving videos safely to the user's own cloud, and keep them watchable.**

## Architecture

| Layer | Files | Notes |
|---|---|---|
| App & wiring | `App/` | `AppEnvironment` creates the services; SwiftData container with CloudKit (falls back to local) |
| Models | `Models/` | `LinkedAccount`, `MovedVideo` (SwiftData + CloudKit), value types |
| Photos | `Services/Photos/` | Scan with real sizes, export originals, thumbnails, batch delete, restore with date/location |
| Auth | `Services/Auth/` | OAuth 2.0 + PKCE via `WebAuthenticationSession`; tokens in the Keychain, *this device only* |
| Cloud | `Services/Cloud/` | `CloudProvider` protocol; Google Drive (Drive v3) and OneDrive (Graph) over plain `URLSession` |
| Transfer | `Services/Transfer/` | Export → analyze → chunked resumable upload → verify → catalog → batch delete → manifest; `BGContinuedProcessingTask` |
| Playback | `Services/Playback/` | OneDrive: pre-signed URL. Google Drive: `AVAssetResourceLoader` adds the auth header to range requests |
| Intelligence | `Services/Intelligence/` | Vision scene labels, MapKit place names, Foundation Models titles and natural-language search |
| UI | `Features/`, `Shared/` | SwiftUI with Liquid Glass; tabs: Storage, Videos, Library, Clouds, Settings |

### Where data lives

| Data | Location | On a new iPhone |
|---|---|---|
| Account list (provider, email, provider user ID) | CloudKit private DB | Synced |
| Catalog (title, date, place, size, remote ID, checksum, 30 KB thumbnail) | CloudKit private DB | Synced |
| Catalog copy | `index.json` in each cloud account | Rebuilt on reconnect |
| OAuth tokens | Keychain, `AfterFirstUnlockThisDeviceOnly`, not synchronizable | **Not** synced; reconnect once |

## Features

| # | Feature | Status |
|---|---|---|
| 1 | Onboarding (3 pages, privacy promise, Photos permission) | ✅ |
| 2 | Storage scan: real sizes, dashboard, largest first, filters (large, >1 yr, screen recordings, frees space), iCloud-only flag | ✅ |
| 3 | Google Drive + OneDrive: connect, disconnect, live quota, combined free space | ✅ |
| 4 | Move: auto/specific destination, original quality, folder layout, chunked resumable upload, verify size + checksum, single batch delete, Recently Deleted guidance, space-freed summary | ✅ |
| 5 | Catalog & gallery: SwiftData + CloudKit, month-grouped grid, provider filter, search | ✅ |
| 6 | Watch & restore: streaming with seeking, AirPlay, PiP; restore one or many with original date/location; optional cloud delete | ✅ |
| 7 | New-device recovery: Welcome back + reconnect with same-account check; manifest fallback; "Rebuild library" | ✅ |
| 8 | Settings: Wi-Fi only, Low Power pause, delete-after-move, AI toggle, privacy page | ✅ |
| + | On-device AI: smart titles (used in cloud file names), natural-language library search | ✅ |
| + | iOS 26 `BGContinuedProcessingTask` so moves continue after leaving the app | ✅ |

## Known limitations / next steps

- **Not yet compiled.** The code was written without access to Xcode; expect a handful of small fixes on the first build.
- An upload interrupted by the app being **terminated** restarts from the beginning next time (nothing is deleted
  until verified, so it is safe). Uploads resume after network drops within a run.
- Video file size and iCloud-only status use the undocumented `PHAssetResource` keys `fileSize` and
  `locallyAvailable`, the common approach. If they ever disappear, the scan falls back to an estimate.
- "Open Photos" uses the undocumented `photos-redirect://` URL.
- Entries rebuilt from a manifest have no thumbnail until the video is next played or restored.
- Deleting from Photos needs the app in the foreground (iOS shows a confirmation); a move finishing in the
  background waits for the user to return.

## Phase 2 candidates

Dropbox, MEGA, Box, pCloud · "Keep a preview in Photos" · duplicate detection · large photos and Live Photos ·
offline pins · persistent upload resume across launches · thumbnails for manifest-imported entries.
