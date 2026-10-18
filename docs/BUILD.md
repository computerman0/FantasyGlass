# Build, sign and install on iPhone

## Requirements and current validation boundary

You do not need to own a Mac: a hosted macOS build service can run Xcode for you. See [build and install online](ONLINE_BUILD.md) for GitHub Actions and Codemagic/TestFlight instructions.

Use macOS compatible with **stable Xcode 26 or newer**, the iOS 26+ SDK, and an iPhone on iOS 26+. A Dynamic Island-capable iPhone is required to see that presentation; the Lock Screen Live Activity is the alternative on other compatible iPhones. The repository includes a real `.xcodeproj`; no project-generation dependency or CocoaPods is required.

This Linux workspace has Swift 6.2 and Node 24, but **no Xcode, Apple SDK, provisioning profile, signing certificate or connected iPhone**. iOS builds and IPA export were not run. Syntax parsing is not an iOS build. Device verification is a required remaining step.

## First Xcode build

1. Install/open stable Xcode 26+ and accept its license. Install an iOS 26 Simulator runtime under Xcode Settings → Components if needed.
2. Select that Xcode in Xcode Settings → Locations or with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
3. Open `FantasyGlass.xcodeproj`. Xcode resolves the local `Core` Swift package; there are no remote Swift package dependencies.
4. Copy `Config/Signing.xcconfig.example` to `Config/Signing.xcconfig`. Set `DEVELOPMENT_TEAM` and a unique `FANTASYGLASS_BUNDLE_ID`, for example `com.yourname.FantasyGlass`. This changes the app, widget and tests consistently. Do not put API credentials in this file.
5. In Signing & Capabilities, confirm both **FantasyGlass** and **FantasyGlassWidgets** use your team and automatic signing. The widget identifier must be the app identifier plus `.widgets`.
6. Choose the **FantasyGlass** scheme for local updates. Choose an iOS 26 simulator or your paired, trusted iPhone. Enable Developer Mode on the iPhone when iOS asks. Build and Run.
7. Run tests using Product → Test, or use the commands below. Then perform the device checks in `VALIDATION.md`.

Regenerate the checked-in project after adding/removing source files:

```sh
python3 Scripts/generate-project.py
```

The generator is deterministic. Keep custom signing in the ignored `Signing.xcconfig`, since regeneration replaces generated project settings.

## Tests on macOS

```sh
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
xcrun simctl list devices available
bash Scripts/test-ios.sh 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID'
```

The script runs the portable package tests and the app's in-memory SwiftData/deep-link tests, storing an `.xcresult`. Live Activity UI still needs preview/simulator inspection and a physical device. Notification registration and remote delivery need actual provisioning. CI fails explicitly when its runner lacks Xcode 26 or an appropriate simulator; it does not silently use an older SDK.

## Build an unsigned IPA for re-signing

```sh
bash Scripts/build-ipa.sh unsigned
```

Output: `build/unsigned/FantasyGlass-unsigned.ipa`. The script archives the app and embedded widget with code signing disabled, then packages `Payload/FantasyGlass.app`. This is input for a signing tool. **It cannot run unsigned on a normal iPhone.** It deliberately has no APNs entitlement.

### AltStore / Sideloadly

Use the tool's current official installation instructions to install its desktop component and trust/pair your iPhone. Import the unsigned IPA, sign with your Apple ID, and install. Preserve the widget extension if the tool supports it and can provision both bundle identifiers. Do not select options that remove extensions if you want Live Activities. If your signer strips or cannot provision the extension, use direct Xcode installation instead.

Personal Team profiles commonly last seven days, require renewal, and have limits on active apps, devices and registered App IDs. An embedded extension can consume another App ID. Exact behavior depends on the current signer, iOS and account; this workflow has not been tested here with AltStore or Sideloadly. Free signing does **not** provide the Push Notifications capability. It can be suitable for the local-update app, subject to extension signing support. EU alternative distribution eligibility does not eliminate signing requirements and is not implemented by this project.

## Signed IPA with your Apple Developer account

Register the app and widget identifiers in your developer account. Copy the appropriate template:

```sh
cp Config/ExportOptions.adhoc.plist Config/ExportOptions.local.plist
```

Replace `REPLACE_TEAM_ID` in the copied file. `release-testing` is the modern Xcode export method for Ad Hoc device distribution; register your iPhone's UDID. `debugging` in the development template is for development exports. Confirm supported values with the installed Xcode's `xcodebuild -help`. Automatic signing requires your account added to Xcode and appropriate portal permissions.

```sh
bash Scripts/build-ipa.sh signed-local Config/ExportOptions.local.plist
```

Output: `build/signed-local/export/`. Install the resulting signed IPA using a compatible device-installation tool, Apple Configurator, or your chosen signing workflow. Direct Build and Run is often simpler for personal use. A paid membership is ordinarily needed for Ad Hoc distribution; free Personal Team builds should use direct Xcode installation or a compatible re-signer.

## APNs-enabled build

1. Use an Apple Developer Program team with Push Notifications capability. Apple's currently listed annual program fee and regional terms are on its membership site; no fee is assumed to be waived.
2. Enable Push Notifications for the **app** identifier. Create an APNs authentication key in Certificates, Identifiers & Profiles → Keys. Securely save its `.p8` file, Key ID and Team ID. Do not commit it or enter it into the app.
3. Refresh the app's provisioning profile so it contains `aps-environment`. The widget extension does not need its own APNs entitlement. Live Activities also require the app's `NSSupportsLiveActivities` Info key, already supplied.
4. Build the **FantasyGlass-Push** scheme. `PushDebug` sets `aps-environment=development`; `PushRelease` sets `production`. Set the backend's `APNS_ENVIRONMENT=sandbox` for development tokens and `production` for distribution tokens. The signing profile is authoritative: inspect the signed entitlements if delivery fails.
5. Export with matching distribution profiles:

```sh
bash Scripts/build-ipa.sh signed-push Config/ExportOptions.local.plist
```

6. Deploy/configure the backend, enable remote mode in the app, grant notification permission, and **re-pin** the matchup to obtain an ActivityKit push token. Device alert tokens and ActivityKit tokens are separate and both can rotate.

Do not re-sign an APNs build with an unrelated team/bundle ID and expect pushes to continue working. APNs topics, tokens, entitlements, provisioning and backend bundle ID must agree. Apple controls delivery frequency; no second-by-second or uninterrupted update promise is made.

## Troubleshooting

* “No such module SwiftUI/SwiftData/ActivityKit” on Linux: use macOS/Xcode; the portable package is the only Swift target supported here.
* Missing iOS 26 APIs: select stable Xcode 26+ and check the active SDK. The project uses native `.glass`, `.glassProminent` and `glassEffect`.
* Signing/profile mismatch: set your team and unique IDs in the local xcconfig, register the widget ID, and regenerate profiles after adding capabilities.
* App installs but no Live Activity: confirm the extension exists in `FantasyGlass.app/PlugIns`, iOS Live Activities are enabled, the app is foregrounded when starting, and the team has a current matchup.
* APNs `BadDeviceToken` / `DeviceTokenNotForTopic`: confirm sandbox vs production, exact app bundle ID, and signing team; re-register/re-pin after reinstalling.
* Free provisioning expired: refresh/re-sign using your chosen method; the app's data may be lost if the signer changes its identity or you uninstall it.
