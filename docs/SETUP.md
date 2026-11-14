# Setup

Storage Manager is a native iOS 26 app (SwiftUI, SwiftData, PhotoKit, AVKit, CloudKit, Foundation Models).
It has **no third-party dependencies**. Google Drive and OneDrive sign-in use Apple's
`WebAuthenticationSession` with OAuth 2.0 + PKCE.

## 1. Requirements

- A Mac with **Xcode 26** or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A **paid Apple Developer account** (CloudKit sync needs one)
- An iPhone on iOS 26. Apple Intelligence features need an iPhone 15 Pro or later; everything else works on any iOS 26 device.

## 2. Generate the Xcode project

```bash
cp StorageManager/Config/Secrets.example.xcconfig StorageManager/Config/Secrets.xcconfig
xcodegen generate
open StorageManager.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and is git-ignored; re-run `xcodegen generate` after adding files.
`Secrets.xcconfig` is git-ignored too: your IDs never land in the repo.

In Xcode, select the **StorageManager** target → *Signing & Capabilities* → choose your team.
Set `APP_BUNDLE_ID` in `Secrets.xcconfig` to a bundle ID you own (e.g. `com.yourname.storagemanager`).

## 3. iCloud (CloudKit)

The catalog syncs through the user's **private** CloudKit database, so a new iPhone gets the library back.

1. With your team selected, Xcode registers the container `iCloud.<APP_BUNDLE_ID>` (from the entitlements).
   If it doesn't, add it under *Signing & Capabilities → iCloud → Containers*.
2. Run the app once on a device signed into iCloud, so SwiftData creates the schema in the development environment.
3. **Before App Store release**: in the [CloudKit Console](https://icloud.developer.apple.com/), *Deploy Schema Changes* to production.

## 4. Google Drive

1. [Google Cloud Console](https://console.cloud.google.com/) → create a project.
2. *APIs & Services → Library* → enable **Google Drive API**.
3. *OAuth consent screen*: user type **External**; add the scope `.../auth/drive.file`; while in testing, add your Google account under *Test users*.
4. *Credentials → Create credentials → OAuth client ID* → type **iOS**, bundle ID = your `APP_BUNDLE_ID`.
5. Copy the client ID (`1234-abc.apps.googleusercontent.com`) into `GOOGLE_CLIENT_ID` in `Secrets.xcconfig`.

The redirect URI (`com.googleusercontent.apps.1234-abc:/oauthredirect`) is derived automatically.
`drive.file` only lets the app see files it created, which keeps Google's app verification light.

## 5. OneDrive (Microsoft Graph)

1. [Azure portal](https://portal.azure.com/) → *Microsoft Entra ID → App registrations → New registration*.
2. *Supported account types*: **Accounts in any organizational directory and personal Microsoft accounts**.
3. *Authentication → Add a platform → iOS / macOS* → bundle ID = your `APP_BUNDLE_ID`.
   This creates the redirect URI `msauth.<APP_BUNDLE_ID>://auth`.
4. *API permissions → Microsoft Graph → Delegated*: `Files.ReadWrite.AppFolder`, `User.Read`, `offline_access`.
5. Copy the *Application (client) ID* into `MICROSOFT_CLIENT_ID` in `Secrets.xcconfig`.

## 6. Run the tests

```bash
xcodebuild test -scheme StorageManager -destination 'platform=iOS Simulator,name=iPhone 17'
```

The unit tests cover the platform-independent logic: QuickXorHash and MD5 checksums, file naming,
the storage allocator, the manifest merge, search filters, upload-resume parsing and PKCE.

## 7. Trying it end to end

1. Record a few short videos on the test iPhone.
2. Launch the app → onboarding → allow Photos access.
3. *Clouds* → connect Google Drive and/or OneDrive.
4. *Videos* → select some → *Move* → confirm the iOS delete prompt.
5. *Library* → play a video, then *Restore to Photos*.
6. New-device test: delete the app (this removes its Keychain tokens), reinstall, and open it.
   The library and account list come back from iCloud and the **Welcome back** screen asks you to reconnect.
