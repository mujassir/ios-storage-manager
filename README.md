# Storage Manager for iPhone

Free up iPhone space by moving large videos to free cloud storage you already have (Google Drive, OneDrive),
and keep them in a Photos-style library where you can stream or restore them anytime.

- **Native iOS 26**: SwiftUI with Liquid Glass, SwiftData + CloudKit, PhotoKit, AVKit, BackgroundTasks. No third-party SDKs.
- **Private by design**: videos go straight from the phone to the user's own cloud; there is no server.
  Sign-in tokens never leave the device.
- **Safe**: a video is deleted from the phone only after the cloud copy's size and checksum are verified.
- **On-device AI**: Apple Intelligence writes titles and understands searches like "beach videos from last summer".
- **New phone? No problem**: the library syncs through the user's private iCloud; reconnect each cloud once.
- **Everywhere**: browse moved videos in the Files app, check space in widgets, share links, iPhone, iPad and Mac.
- **Pro**: unlimited batch moves and auto-move rules that run overnight while charging (StoreKit 2).

## Getting started

See [docs/SETUP.md](docs/SETUP.md) to generate the Xcode project and configure Google, Microsoft and iCloud.
Scope, architecture and status are in [docs/PHASE1.md](docs/PHASE1.md) and [docs/PHASE3.md](docs/PHASE3.md).

```
StorageManager/
  App/            entry point, root tabs, deep links, dependency wiring
  Core/           shared with extensions: value models, OAuth, cloud providers, support, snapshot
  Models/         SwiftData models
  Services/       Photos, Cloud accounts, Transfer, Intelligence, Store, Automation, Sharing
  Features/       Onboarding, Dashboard, Videos, Transfer, Library, Clouds, Settings, Store, Automation
FileProvider/     Files app extension
Widgets/          WidgetKit extension
StorageManagerTests/   unit tests (Swift Testing)
project.yml       XcodeGen project definition
```
