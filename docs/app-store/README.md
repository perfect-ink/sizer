# Mac App Store submission kit

Everything App Store Connect asks for, ready to paste or to push with fastlane.

| What | Where |
|---|---|
| Listing text (name, subtitle, promo, description, keywords, URLs, What's New) | `metadata/en-US/*.txt` |
| Copyright and categories | `metadata/copyright.txt`, `metadata/primary_category.txt`, `metadata/secondary_category.txt` |
| Notes and contact for App Review | `metadata/review_information/` |
| Screenshots, 2880×1800 (six) | `screenshots/en-US/` (regenerate with `make screenshots`) |
| Privacy policy | `../PRIVACY.md`, served at the URL in `metadata/en-US/privacy_url.txt` once pushed |
| Automation | `../../fastlane/Fastfile`, `../../.github/workflows/appstore.yml`, `../../.github/workflows/appstore-submit.yml` |

The folder layout is fastlane `deliver`'s, so the same files feed both the manual and the automated route.

## The listing, field by field

| App Store Connect field | Value | Limit |
|---|---|---|
| Name | Sizer (see the name note below) | 30 |
| Subtitle | Snap windows with a keystroke | 30 |
| Primary language | English (U.S.) | |
| Bundle ID | org.perfectink.sizer | fixed once the record exists |
| SKU | `sizer-mac` (any unique string; never shown) | |
| Primary category | Productivity | |
| Secondary category | Utilities | |
| Promotional text | `metadata/en-US/promotional_text.txt` | 170 |
| Description | `metadata/en-US/description.txt` | 4000 |
| Keywords | `metadata/en-US/keywords.txt` | 100 |
| Support URL | https://perfectink.org/apps/sizer.html | |
| Marketing URL | https://perfectink.org/apps/sizer.html | |
| Privacy Policy URL | https://github.com/perfect-ink/sizer/blob/main/docs/PRIVACY.md | |
| What's New | `metadata/en-US/release_notes.txt` | 4000 |
| Copyright | 2026 Perfct Ink (use the legal name on the developer account if it differs) | |
| Version | matches the tag, e.g. 1.5.2 | |
| Build | uploaded by the App Store workflow; build number = workflow run number | |
| Screenshots | the six PNGs in `screenshots/en-US/`, in file-name order | 1 to 10 |
| App Preview video | none | optional |
| Age rating | every question "None" / "No", result 4+ | |
| App Privacy | Data Not Collected (no data types; nothing leaves the Mac) | |
| Sign-in required | No | |
| Export compliance | not asked: `ITSAppUsesNonExemptEncryption` is false in Info.plist | |
| Content rights | contains no third-party content | |
| Advertising identifier | No | |
| Pricing | your call; Free or a one-time price. Availability: all territories | |
| Release | Automatically after approval (what the submit lane sets) | |
| App Review contact | first/last name and email in `metadata/review_information/`; **phone number is required and not in the repo** | |
| Review notes | `metadata/review_information/notes.txt` | 4000 |

## One-time setup the API cannot do

Do these once in the browser, in this order.

1. **Certificates and profile** (developer.apple.com → Certificates, IDs & Profiles)
   - App ID `org.perfectink.sizer` with the App Sandbox capability.
   - An *Apple Distribution* certificate and a *Mac Installer Distribution* certificate, exported together as one `.p12`.
   - A *Mac App Store* provisioning profile for `org.perfectink.sizer`.
   - A team-level App Store Connect API key (Users and Access → Integrations) with the *App Manager* role; it uploads builds and also pushes the listing.
2. **Repository secrets** (the seven listed at the top of `.github/workflows/appstore.yml`).
3. **App record** (App Store Connect → Apps → +): platform macOS, name, primary language English (U.S.), bundle ID `org.perfectink.sizer`, SKU `sizer-mac`. Fastlane cannot create this record.
4. **App Privacy** on the app's page: "Data Not Collected", then Publish. There is no public API for this.
5. **Age rating**: answer the questionnaire (all None / No). It persists across versions.
6. **Pricing and Availability**: choose the price and territories.
7. **App Review contact phone number** (App Information → App Review Information). Everything else in that section is filled by the sync.
8. Push `docs/PRIVACY.md` to `main` so the privacy policy URL resolves before review starts.

## The automated flow

```
git tag v1.5.2 && git push origin v1.5.2
```

1. **App Store workflow** builds the sandboxed universal `.pkg`, validates and uploads it, then runs `fastlane mac metadata version:1.5.2`, which creates version 1.5.2 in App Store Connect if needed and uploads the description, keywords, URLs, promo text, What's New, categories, copyright, review notes and all six screenshots (replacing any old ones).
2. Wait for the build to finish processing (TestFlight tab, usually 10 to 30 minutes).
3. **App Store Submit workflow** (Actions → App Store Submit → Run, version `1.5.2`): re-syncs the listing, attaches the newest processed build for that version (or the build number you give), answers the export-compliance and IDFA questions, and submits for review with automatic release on approval.

Locally the same two steps are `make metadata VERSION=1.5.2` and `make submit VERSION=1.5.2`, which need `brew install fastlane` and the `APP_STORE_CONNECT_API_KEY_*` variables described at the top of `fastlane/Fastfile`. The GitHub macOS runners ship with fastlane, so the workflows install nothing.

Edit the text files and push a new tag, or rerun the Submit workflow, to update the listing. Screenshots are regenerated with `make screenshots`, which renders the app's real Settings window (compiled with `-D APPSTORE`) and draws the rest, so they track UI changes.

## Things to know before you submit

- **The name "Sizer" is probably taken.** The App Store already lists two iOS apps called exactly "Sizer", and names are unique across the store. If App Store Connect refuses it when you create the record, use a longer unique name and put the same string in `metadata/en-US/name.txt`. Suggestions within 30 characters: "Sizer: Window Snapping", "Sizer – Snap Windows", "Sizer Window Manager". The bundle name inside the app stays "Sizer".
- **Team ID.** The Apple Distribution identity in this Mac's keychain belongs to team `XS9W9A8FWM`, while the Makefile comment uses `K2F4FTM2XQ` as its example. The `APPLE_TEAM_ID` secret, the certificates in the `.p12`, the provisioning profile and the API key must all come from the same team.
- **Installer certificate.** The keychain here has an Apple Distribution identity but no Mac Installer Distribution identity, so `make appstore` cannot run locally yet. The CI path needs both in `MAS_CERTIFICATE_P12`.
- **Test the sandboxed build before review.** The sandbox has not been exercised on a real Mac. Install the processed build from TestFlight, grant Accessibility, and confirm that snapping, global shortcuts and Launch at Login all work. That is also exactly what the reviewer will do.
- **Minimum macOS.** The App Store build targets macOS 13 (it needs `SMAppService`). The product page still says "12 or later"; update it or the listing will contradict the site.
- **Review notes mention the first-launch alert.** Reviewers often test without granting Accessibility; the alert with the "Open System Settings" button is what keeps that from being a rejection.
- **Screenshot content is illustrative.** The desktops and app windows in the screenshots are drawn, not captured; only the Settings window is the real UI. App Review accepts this as long as the screenshots show the app's actual features, which these do.
