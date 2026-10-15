# Tabby

Split a bill in seconds. Snap the receipt, tap who had each item, copy everyone's share.

```
Adele = $125.00
Bob = $220.00
Carmen = $35.00
Total = $380.00
```

- **Scan** with Apple's document camera, or pick a photo. Text is read on-device with Vision: no account, no network, no API keys.
- **Review** the parsed items and fix anything OCR got wrong.
- **People**: add names or just use A, B, C. Names you use are remembered on the device, so next time they're one tap away.
- **Assign** one item at a time: tap badges or type letters (`ab` = A and B share it).
- **Shares**: tax and tip are split in proportion to what each person ordered, and the cents always add up exactly. Copy or share the result.

SwiftUI, iOS 17+, iPhone, zero dependencies.

## Develop

On a Mac with Xcode:

```sh
brew install xcodegen
xcodegen generate
open Tabby.xcodeproj
```

The Xcode project is generated from `project.yml` and isn't committed.

## Ship to TestFlight (no Mac needed)

The **TestFlight** GitHub Action builds, signs and uploads the app. First do this one-time setup:

1. **Register the bundle ID.** Go to [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list) and choose **+** → App IDs → App. Enter the description `Tabby` and the explicit bundle ID `com.sarkarshubhdeep.tabby`. No extra capabilities are needed.
2. **Create the app.** Go to [App Store Connect → Apps](https://appstoreconnect.apple.com/apps) and choose **+** → New App. Pick iOS, name it `Tabby` (add a suffix if that name is taken), and select the bundle ID above. The SKU can be anything, for example `tabby`.
3. **Create an API key.** In App Store Connect, go to **Users and Access → Integrations → App Store Connect API → Team Keys** and choose **+**. Give it the **Admin** role, which Xcode needs to create the distribution certificate for cloud signing. Download the `.p8` file (you can only download it once) and note the **Key ID** and the **Issuer ID**.
4. **Add the repository secrets.** In GitHub, go to **Settings → Secrets and variables → Actions → New repository secret**:

   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | Key ID from step 3 |
   | `ASC_ISSUER_ID` | Issuer ID from step 3 |
   | `ASC_KEY_P8` | Full contents of the `.p8` file, including the `BEGIN`/`END` lines |
   | `APPLE_TEAM_ID` | Your 10-character Team ID ([developer.apple.com → Membership](https://developer.apple.com/account#MembershipDetailsCard)) |

To ship a build, open **Actions → TestFlight → Run workflow**, or push a tag like `v1.0`. Each run uploads a new build number. Processing in App Store Connect takes about 5–15 minutes.

To install it, open App Store Connect → Tabby → **TestFlight**. Create an **Internal Testing** group, add yourself, and enable automatic distribution. Then install the **TestFlight** app on your iPhone and accept the invite. Internal testing doesn't need Beta App Review.
