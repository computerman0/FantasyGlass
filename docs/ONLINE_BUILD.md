# Build and install FantasyGlass without owning a Mac

You can do the build and signing online. Apple's iOS SDK still runs on a **hosted Mac**; your own computer can be Windows, Linux or a Chromebook. For installation entirely through your iPhone, use **Codemagic + Apple TestFlight** with a paid Apple Developer account.

This project has not yet passed an Xcode build. **Run the unsigned cloud build first, before paying for a signing plan.** A green Linux test result does not replace that check. The workflows below are supplied and structurally checked, but have not been run against your cloud or Apple accounts.

## Choose your route

| Route | Build | Installation | Cost and limitations |
|---|---|---|---|
| **Fully online, recommended if you can pay for Apple membership** | Codemagic hosted macOS | Apple TestFlight on the iPhone | Apple lists US$99/year, regional pricing varies. Codemagic currently lists 500 free M2 build minutes/month for its individual plan; check current terms. Each TestFlight build expires after 90 days. |
| **Free Apple account + Windows** | GitHub Actions or Codemagic hosted macOS | Sideloadly on a Windows PC | Build minutes/storage may cost money beyond account allowances. Free signing commonly lasts seven days. Widget support depends on the signer; no APNs entitlement is assumed. |

A browser download of an unsigned `.ipa` cannot install it on a normal iPhone. There is no verified free, browser-only signing/install route supplied here. TestFlight avoids a Windows signing utility and USB installation.

## 1. Put the source in your GitHub account

1. Download the **updated** `FantasyGlass.zip` supplied with this guide. It includes `codemagic.yaml` and `.github/workflows/build-ipa.yml`.
2. Create a private repository at [GitHub](https://github.com/new), for example `FantasyGlass`. Initialize it with a README.
3. Extract the ZIP and upload the **contents of the FantasyGlass folder**, not the outer folder. The repository root must contain `FantasyGlass.xcodeproj`, `Core`, `App`, `Widget`, `codemagic.yaml` and `.github`. Use Add file → Upload files; upload in batches if the browser hits its file-count limit.
4. Check that `.github/workflows/build-ipa.yml` exists. Some upload dialogs hide dot-prefixed folders. If it was omitted, use Add file → Create new file, enter that full path and paste the supplied workflow.

For an entirely browser-based source upload, GitHub Codespaces is another option (subject to its account quota). Open Code → Codespaces → Create codespace, upload the ZIP to the workspace root using the Explorer upload action, then run:

```sh
unzip FantasyGlass.zip -d /tmp/fantasyglass-import
cp -a /tmp/fantasyglass-import/FantasyGlass/. .
git add App AppTests Backend Config Core Shared Widget Scripts docs research \
  FantasyGlass.xcodeproj .github .gitignore README.md THIRD_PARTY_NOTICES.md codemagic.yaml
git commit -m "Add FantasyGlass native iOS project"
git push
```

Use these commands in the **new repository's root**. Stop the Codespace when finished to avoid unnecessary usage. Do not put ESPN cookies, API keys, signing certificates or Apple private keys in the repository.

## 2. Run the first Xcode build online

You can use either service for this check; you do not need both.

**GitHub Actions:**

1. Open the repository's **Actions** tab. Enable workflows if GitHub asks.
2. Select **Build iPhone IPA online** → **Run workflow** → choose the default branch → **Run workflow**.
3. The workflow selects an installed stable Xcode 26+ on GitHub's macOS runner, tests the portable Swift core, then archives the app and widget without signing.
4. If it succeeds, open that run and scroll to **Artifacts**. Download **FantasyGlass-unsigned-IPA** and extract the artifact ZIP to obtain `FantasyGlass-unsigned.ipa`.
5. If it fails, open the first failed step. Download the build log artifact when available, or copy the first compiler error. Do not treat a failed build as an IPA delivery. Compiler errors need fixing before either installation route will work.

GitHub currently provides standard hosted runners free for public repositories; private repositories receive a plan-dependent allowance. Check Settings → Billing and licensing / Actions usage before repeated builds. This project sets artifact retention to seven days. The existing **Verify** workflow may also run after a push and consumes its own quota; it runs checks but does not export the IPA. You can disable it while doing initial manual setup if you want to limit usage.

**Codemagic:**

1. Create an account at [Codemagic](https://codemagic.io/) and connect only the GitHub repository you want it to build.
2. Add the application and choose the `codemagic.yaml` configuration. This is a **native iOS** app; do not create a Flutter project or install CocoaPods.
3. Start workflow **fantasyglass-unsigned** / **FantasyGlass - unsigned build check**.
4. A successful build exposes `FantasyGlass-unsigned.ipa` in its artifacts. A failed build exposes its build log.

The unsigned workflow needs no Apple signing credentials. After it succeeds, choose the TestFlight or Windows installation route below.

## 3. Fully online installation: Apple account and app identifiers

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/enroll/). Wait until membership is active and accept any pending account agreements. A free Apple account cannot use this TestFlight signing workflow.
2. In [Apple Developer → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), register two explicit App IDs, replacing `yourname` with your own unique namespace:
   * `com.yourname.FantasyGlass` — the app.
   * `com.yourname.FantasyGlass.widgets` — its WidgetKit/Live Activity extension.
3. For the first install, use the local `FantasyGlass` scheme. If you want the optional APNs backend immediately, enable **Push Notifications for the app ID** before creating its profile. The widget does not need its own Push Notifications capability.
4. Open [App Store Connect](https://appstoreconnect.apple.com/) → My Apps → + → New App. Choose iOS, your app bundle ID, a name and a unique SKU such as `fantasyglass-personal`. If the name is unavailable, use a distinct name. Create the app record; you do not need to publish an App Store listing for your own internal TestFlight build.

Only the main app gets an App Store Connect app record. The widget gets its own identifier and provisioning profile, not a separate store listing.

## 4. Set up signing in the browser

1. In App Store Connect, open **Users and Access → Integrations → App Store Connect API**. Request API access if prompted. Generate a dedicated **team API key** for Codemagic; its documentation recommends App Manager permissions. Save the `.p8` download, **Key ID** and **Issuer ID**. Apple permits downloading the private key only once.
2. In Codemagic, open **Team settings → Team integrations → Developer Portal → Manage keys**. Add the key with the exact reference name **`fantasyglass-apple`**, entering its IDs and uploading its `.p8` file through the secure UI.
3. In **Team settings → codemagic.yaml settings → Code signing identities → iOS certificates**, choose **Generate certificate**. Choose **Apple Distribution** and the Apple integration. Codemagic can generate the key/certificate on its side; no Mac Keychain or local certificate-signing request is needed.
4. Follow Codemagic's current UI to retain the certificate in Code signing identities. Its documentation currently says to download the generated `.p12` and password, then add it through **Upload certificate**. Keep that private file/password secure. If it already appears as an available signing identity, do not generate a duplicate.
5. In Apple's Developer portal, create **App Store Connect distribution provisioning profiles** for both explicit App IDs. Select the same Apple Distribution certificate created above. Download each profile or fetch them through Codemagic's **iOS provisioning profiles → Fetch from Developer Portal**.
6. Confirm Codemagic has both profiles and that each has a matching certificate. Its documented bundle-ID matching includes the app's extensions. A profile for only the main app is insufficient.

Codemagic receives authority to sign and upload builds under that Apple API key. Store it in its integration settings, never in YAML, GitHub source or chat. This App Store Connect `.p8` key is **different from** an APNs `.p8` key for the optional FantasyGlass backend. ESPN cookies and sports API keys are not needed for cloud compilation.

## 5. Configure and run the TestFlight workflow

Edit `codemagic.yaml` in GitHub. Under `fantasyglass-testflight`:

1. Change **both** occurrences of `com.yourname.FantasyGlass` to your actual registered app ID: `ios_signing.bundle_identifier` and `vars.BUNDLE_ID`.
2. Leave `PROJECT_BUILD_NUMBER: "1"` for your first upload. Increase it to `"2"`, `"3"`, etc. after each successful Apple upload. Reusing an uploaded build number is rejected by Apple.
3. Leave `XCODE_SCHEME: FantasyGlass` for the local-update version. For provisioned remote push support, change it to `FantasyGlass-Push` after following section 7.
4. Ensure the integration name is `fantasyglass-apple`, exactly matching the saved Codemagic integration.
5. Commit the edit. In Codemagic, start **fantasyglass-testflight** / **FantasyGlass - personal TestFlight** on that branch.

This workflow creates the build's local signing configuration, generates the project, tests the portable core, applies both signing profiles, archives and uploads a signed build to your Apple account. **Do not run the project generator again after the profile-application step**, because that would replace Codemagic's signing settings.

The export is marked **TestFlight Internal Testing Only**. Automatic external beta submission and public App Store submission are disabled. The `submit_to_testflight: false` setting disables automatic beta-review submission; it does not prevent the initial upload. You assign the processed build to your own internal test group in the next step.

## 6. Install on your iPhone

1. Wait for Apple to process the uploaded build. Check App Store Connect → your app → **TestFlight** for any processing errors or missing compliance information, and answer those accurately.
2. Under **Internal Testing**, create a group such as `Personal`, add yourself as an eligible App Store Connect user, and add the processed build to that group. Internal testing does not require the external TestFlight beta-review process.
3. Install Apple's **TestFlight** app from the iPhone App Store. Sign in with the Apple account you invited and accept the invitation.
4. Tap **Install** next to FantasyGlass. No USB connection, Sideloadly or personally owned Mac is needed for this route.
5. Open FantasyGlass and enter your league IDs. Add private ESPN cookies only in its Keychain setup if required.

Your iPhone must run iOS 26+. Dynamic Island requires a compatible iPhone; other compatible models can use the Lock Screen Live Activity. TestFlight builds expire **90 days after upload**: upload a newer build before expiry. TestFlight is a beta distribution method, not a permanent sideloading exemption or an App Store release.

## 7. Optional remote Dynamic Island updates and alerts

A TestFlight install does not itself provide background score updates. For those:

1. Enable Push Notifications on the app's Apple App ID. Regenerate/refetch the app's profile after changing capabilities.
2. Set `XCODE_SCHEME: FantasyGlass-Push` in `codemagic.yaml`, increase the build number and rebuild. Confirm the signed app contains the APNs entitlement.
3. Deploy the included backend using [Backend/README.md](../Backend/README.md). It needs an always-running host, HTTPS, secret storage, and a separate APNs signing key. TestFlight uses **production APNs**; set the server environment accordingly.
4. Configure the backend in the installed app, grant notifications and re-pin the matchup to obtain a Live Activity token.

APNs provisioning, actual push delivery, current/private ESPN access and game-day accuracy remain untested until you perform the checks in [VALIDATION.md](VALIDATION.md). Apple controls delivery and the activity lifetime. Without the backend, local Live Activities can become stale when the app is suspended.

## Alternative: free Apple account and Windows

After the unsigned cloud build passes:

1. Install [Sideloadly](https://sideloadly.io/) on Windows, following its current Apple-driver/component instructions.
2. Connect and trust your iPhone. Select the extracted `.ipa`, sign with your own Apple account and install. Enable Developer Mode when required by iOS.
3. Preserve the widget extension if the signer can provision it. If the tool removes extensions or cannot sign the `.widgets` target, Dynamic Island support is unavailable through that configuration; use the paid TestFlight route instead.
4. Renew free signing before its usual seven-day expiry. Do not assume this route supports APNs even if a build can be installed.

This route builds online but installs through Windows. Its signing/extension behavior has not been tested with this app. A random online signing service is not needed for either documented route.

## Common failures

| Failure | What to check |
|---|---|
| No Run workflow button | Correct workflow committed to default branch, Actions enabled, and repository write access |
| Xcode or SDK too old | Hosted image must provide stable Xcode/iOS SDK 26+; change image/version if a provider retires one |
| Swift compiler error | Fix the first error in the Xcode build log; share that error without secrets if you need help |
| No matching widget profile | Register and provision the exact `.widgets` ID using the same distribution certificate |
| Signing identity lacks private key | Use the certificate created by Codemagic or import its full `.p12`; a `.cer` alone is insufficient |
| Apple API permission/agreement failure | Correct team key, role, active membership, accepted agreements and access to signing resources |
| Bundle ID mismatch | Both YAML values, portal app/widget IDs, profiles and App Store Connect record must match |
| Duplicate build number | Increase `PROJECT_BUILD_NUMBER` and run again |
| Upload succeeded but TestFlight shows no app | Allow processing; resolve Apple's messages, add the build to your internal group, and use the invited Apple account |
| Scores stop after leaving the app | Expected for local-only updates; configure and verify the optional APNs backend |

## Official documentation checked on 2026-10-18

* [GitHub hosted macOS 15 image/Xcode inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
* [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
* [Downloading Actions artifacts](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/downloading-workflow-artifacts)
* [Codemagic native iOS setup](https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/)
* [Codemagic signing and online certificate creation](https://docs.codemagic.io/yaml-code-signing/signing-ios/)
* [Codemagic Apple publishing](https://docs.codemagic.io/yaml-publishing/app-store-connect/)
* [Codemagic pricing](https://codemagic.io/pricing/)
* [Apple membership](https://developer.apple.com/programs/enroll/)
* [Apple internal TestFlight testing and 90-day lifetime](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)

These links and capabilities were checked against current public documentation. No paid account was registered, cloud workflow executed, certificate generated, app uploaded or signing service purchased on your behalf.
