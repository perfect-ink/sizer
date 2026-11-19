# Mac App Store submission kit

Everything App Store Connect asks for, ready to paste or to push with fastlane.

| What | Where |
|---|---|
| Listing text (name, subtitle, promo, description, keywords, URLs, What's New) | `metadata/en-US/*.txt` |
| Copyright and categories | `metadata/copyright.txt`, `metadata/primary_category.txt`, `metadata/secondary_category.txt` |
| Notes and contact for App Review | `review.yml` (one file) |
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
| Copyright | 2026 Perfect Ink (use the legal name on the developer account if it differs) | |
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
| App Review contact | name and email in `review.yml`; the required phone comes from the `APP_REVIEW_PHONE` secret | |
| Review notes | `notes:` in `review.yml` | 4000 |

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
7. **App Review contact phone number**: set the `APP_REVIEW_PHONE` repository secret (`gh secret set APP_REVIEW_PHONE`). Everything else in App Review Information comes from `review.yml`.
8. Push `docs/PRIVACY.md` to `main` so the privacy policy URL resolves before review starts.

## The automated flow

```
git tag v1.5.2 && git push origin v1.5.2
```

1. **App Store workflow, build job** builds the sandboxed universal `.pkg`, validates and uploads it, then runs `fastlane mac metadata version:1.5.2`, which creates version 1.5.2 in App Store Connect if needed and uploads the description, keywords, URLs, promo text, What's New, categories, copyright, review notes and all six screenshots (replacing any old ones).
2. **Submit job** (same run) waits for Apple to finish processing that exact build (usually 10 to 30 minutes, up to 90), then attaches it, answers the export-compliance and IDFA questions and submits for review with automatic release on approval. Nothing to click: approval puts it on the Mac App Store.

A manual run of the App Store workflow has a "submit" box; untick it to stop after the upload (a TestFlight-only build). **App Store Submit** (Actions → App Store Submit → Run) re-submits an already uploaded version without building, e.g. after fixing listing text for a rejection.

Locally the same two steps are `make metadata VERSION=1.5.2` and `make submit VERSION=1.5.2`, which need `brew install fastlane` and the `APP_STORE_CONNECT_API_KEY_*` variables described at the top of `fastlane/Fastfile`. The macOS runners ship with fastlane; the submit job runs on Linux and installs it with `gem`.

Edit the text files and push a new tag, or rerun the Submit workflow, to update the listing. Screenshots are regenerated with `make screenshots`, which renders the app's real Settings window (compiled with `-D APPSTORE`) and draws the rest, so they track UI changes.

## Things to know before you submit

- **The name "Sizer" is probably taken.** The App Store already lists two iOS apps called exactly "Sizer", and names are unique across the store. If App Store Connect refuses it when you create the record, use a longer unique name and put the same string in `metadata/en-US/name.txt`. Suggestions within 30 characters: "Sizer: Window Snapping", "Sizer – Snap Windows", "Sizer Window Manager". The bundle name inside the app stays "Sizer".
- **Team ID.** Sizer's App Store build belongs to team `XS9W9A8FWM`, which is the Makefile's default `TEAM_ID`. The certificates in the `.p12`, the provisioning profile and the App Store Connect API key must all come from that team. The DMG workflow's `APPLE_TEAM_ID` secret is separate and goes with its Developer ID certificate.
- **Certificates on this Mac.** The keychain here has both the Apple Distribution and the 3rd Party Mac Developer Installer identities for team `XS9W9A8FWM`, so `make appstore PROFILE=…` can build and sign the `.pkg` locally once the provisioning profile is downloaded. The CI path needs both in `MAS_CERTIFICATE_P12`.
- **Test the sandboxed build before review.** The sandbox has not been exercised on a real Mac. Install the processed build from TestFlight, grant Accessibility, and confirm that snapping, global shortcuts and Launch at Login all work. That is also exactly what the reviewer will do.
- **Minimum macOS.** The App Store build targets macOS 13 (it needs `SMAppService`). The product page still says "12 or later"; update it or the listing will contradict the site.
- **Review notes mention the first-launch alert.** Reviewers often test without granting Accessibility; the alert with the "Open System Settings" button is what keeps that from being a rejection.
- **Screenshot content is illustrative.** The desktops and app windows in the screenshots are drawn, not captured; only the Settings window is the real UI. App Review accepts this as long as the screenshots show the app's actual features, which these do.
