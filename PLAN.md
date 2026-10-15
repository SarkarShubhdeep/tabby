# Tabby — Plan

Tabby is a small iPhone app for splitting a restaurant bill. You take a photo of the receipt, Tabby lists the items, and then shows them **one at a time**. For each item you tap who had it (A, B, C…). At the end you get each person's total and copy it as text.

The goal is a working build on **TestFlight within a few hours**. So the scope is deliberately tiny: no accounts, no backend, no AI API, no paid dependencies.

---

## 1. User flow

```
[Home] ──► [Scan / Pick Photo] ──► [Review Items] ──► [People] ──► [Assign (1 item per screen)] ──► [Summary + Copy]
```

1. **Home**: a large "Scan Bill" button, plus a "Choose Photo" button for receipts already in the photo library. A third button, "Enter Manually", is the fallback when OCR fails.
2. **Scan**: uses Apple's built-in document camera (`VNDocumentCameraViewController`), which auto-crops and de-skews the receipt. "Choose Photo" uses `PhotosPicker`.
3. **Review Items**: a native `List` of the parsed lines (`name`, `price`). The user can swipe to delete, tap to edit, or tap `+` to add a line. Subtotal, tax and tip are detected when possible and shown in their own section, where they can be edited.
4. **People**: starts with `A`, `B` and `C`. The user can add or remove people and rename them (for example "Adele", "Bob", "Carmen"). Names are optional because the letters work as defaults.
5. **Assign**: the core screen.
   - It shows the item name and price large, plus "Item 3 of 12" and a progress bar.
   - Below that is one toggle chip per person (A, B, C…). Tapping a chip selects that person. Selecting several people splits the item evenly among them.
   - There is also an **"Everyone"** shortcut chip.
   - **Next** (or the Return key) moves to the next item, and **Back** returns to the previous one. Next is disabled until at least one person is selected.
   - **Keyboard mode**: a text field where typing `ab` or `a,b,c` selects those people. This covers the "just type A, B, C" idea. Taps and typing stay in sync.
6. **Summary**:
   - One row per person with their total, for example `Adele — $125.00`. Tapping a row shows that person's items.
   - Tax and tip are split **in proportion to each person's subtotal**, which is the fair standard.
   - A **Copy** button puts plain text on the clipboard:
     ```
     Adele = $125.00
     Bob = $220.00
     Carmen = $35.00
     Total = $380.00
     ```
   - A `ShareLink` sends the same text to Messages or WhatsApp.
   - "Start Over" resets the app.

## 2. Tech choices

| Concern | Choice | Why |
|---|---|---|
| UI | **SwiftUI**, iOS 17+ | Native components, fastest to build |
| Icons | **SF Symbols** (`doc.text.viewfinder`, `person.2`, `checkmark.circle.fill`, `doc.on.doc`) | Native and free |
| Camera | `VNDocumentCameraViewController` (VisionKit) | Apple's own receipt/document scanner |
| OCR | `VNRecognizeTextRequest` (Vision, `.accurate`) | On-device, free, no network, no API key |
| State | One `@Observable` `BillSession` model | The app is too small for anything more |
| Persistence | None (v1) | Bills are short-lived |
| Dependencies | **Zero** | Nothing to vet and faster CI |
| Project gen | **XcodeGen** (`project.yml`) | Avoids hand-editing `.pbxproj` and keeps diffs readable |

## 3. Receipt parsing (the only "hard" part)

Vision returns text lines with bounding boxes. Tabby's approach:

1. Sort the observations top to bottom, then group observations whose vertical centers are within roughly half a line height into **rows**. Receipts often put the name and the price in separate observations on the same visual row.
2. In each row, find a trailing price with the regex `(-?\$?\d{1,4}[.,]\d{2})\s*$`.
3. Everything left of the price becomes the item name. Strip leading quantities like `2x` or `2 `. If a quantity is found, keep it and show it as `2× Burger`.
4. Classify rows by keyword:
   - `subtotal` → subtotal (not an item)
   - `tax`, `vat`, `gst` → tax
   - `tip`, `gratuity`, `service` → tip
   - `total`, `balance`, `amount due`, `change`, `cash`, `visa`… → ignored
5. Everything else that has a price becomes an item.
6. **Sanity check**: if the sum of the items doesn't match the detected subtotal, show a small yellow banner on the Review screen ("Items add up to $X, receipt says $Y"). OCR is never perfect, so the Review screen is the safety net.

This parsing logic lives in a pure `ReceiptParser` with no UI, so it is unit-testable with a few sample receipts in text form.

## 4. Data model

```swift
struct Person: Identifiable { id, name: String }            // "A" / "Adele"
struct LineItem: Identifiable { id, name, price: Decimal, assignees: Set<Person.ID> }
@Observable final class BillSession {
    var items: [LineItem]; var people: [Person]
    var tax: Decimal; var tip: Decimal
    func shares() -> [(Person, Decimal)]   // proportional tax/tip, rounding fixed so totals add up exactly
}
```

All money uses `Decimal`, never `Double`. Rounding leftovers (pennies) go to the person with the largest share, so the totals always add up exactly to the bill.

## 5. File layout

```
tabby/
├── project.yml                 # XcodeGen spec
├── Tabby/
│   ├── TabbyApp.swift
│   ├── Model/BillSession.swift
│   ├── Parsing/ReceiptParser.swift
│   ├── Parsing/TextRecognizer.swift     # Vision wrapper
│   ├── Views/HomeView.swift
│   ├── Views/DocumentScanner.swift      # UIViewControllerRepresentable
│   ├── Views/ReviewItemsView.swift
│   ├── Views/PeopleView.swift
│   ├── Views/AssignView.swift
│   ├── Views/SummaryView.swift
│   ├── Assets.xcassets (AppIcon, AccentColor)
│   └── Info.plist
├── TabbyTests/ReceiptParserTests.swift, BillSessionTests.swift
├── fastlane/Fastfile
└── .github/workflows/testflight.yml
```

## 6. Getting to TestFlight

The repo is built so that **no Mac is required**: GitHub Actions' macOS runners build, sign and upload the app.

**One-time setup (about 15 minutes in the browser, done by you):**

1. **Apple Developer**: create the App ID `com.<you>.tabby`.
2. **App Store Connect**: create the app record "Tabby" with that bundle ID. Apple's API can't create app records, so this step is manual.
3. **App Store Connect**: create an API key (Users and Access → Integrations → App Store Connect API, role *App Manager*). Download the `.p8` file and note the Key ID and Issuer ID.
4. **GitHub**: add the repo secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (base64) and `APPLE_TEAM_ID`.

**CI pipeline (`testflight.yml`)**: runs on a manual trigger or a `v*` tag.

1. `brew install xcodegen` → `xcodegen generate`
2. Run unit tests on a simulator.
3. Fastlane `build_app` with **automatic signing via the API key** (`-allowProvisioningUpdates`). No certificate juggling or `match` repo is needed.
4. Set the build number to the GitHub run number.
5. Run `upload_to_testflight`, then add yourself as an internal tester, which needs no Beta Review.

**App Store and TestFlight requirements handled in the code:**

- `NSCameraUsageDescription`: "Tabby uses the camera to scan your bill."
- `ITSAppUsesNonExemptEncryption = NO`, which skips the export compliance prompt.
- A 1024×1024 app icon is required. A simple generated icon (cat/receipt glyph on a solid color) can be swapped later.
- iPhone only, portrait only.

**Alternative if you have a Mac with Xcode:** run `xcodegen generate`, open `Tabby.xcodeproj`, then Product → Archive → Distribute → TestFlight. This takes about 10 minutes.

## 7. Timeline (about 3 hours)

| Step | Time |
|---|---|
| Project scaffold, model, people/assign/summary screens with manual entry | 60 min |
| Scanner and Vision OCR, parser and tests | 45 min |
| Review screen, polish (haptics, empty states, keyboard mode) | 30 min |
| CI workflow and Fastlane, first TestFlight upload | 30–45 min |

The app is usable even before OCR is done, because manual entry runs through the same assign flow.

## 8. Out of scope for v1

History of past bills, iCloud sync, multiple currencies or locales beyond `$`/`.`, uneven splits (such as 70/30), Venmo or payment links, iPad and widgets. All of these are easy to add later.

## 9. Open questions for you

1. **Bundle ID**: is `com.sarkarshubhdeep.tabby` OK?
2. **Build path**: GitHub Actions (no Mac needed, requires the 4 secrets above) or your own Mac with Xcode?
3. **Minimum iOS**: 17 is assumed. Is that fine?
