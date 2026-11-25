# Bins: storage bin tracker (v0.2)

An iPhone and iPad app (SwiftUI, iOS 17+) for tracking what's in each storage bin,
where each bin lives in the house, and how often it's used. Everyone in the household
shares the same bins. Data syncs through Google Firebase and works offline, catching up
when the device is back online.

## What it does

- **Household**: each person signs in with email and password. One person creates the household,
  and the others join with its 6-character invite code (shown in the Household tab, with a Send invite button).
- **Bins tab**: every bin, sortable by *Recently used*, *Most used* (last 30 days) or *Bin ID*.
  A "Go to bin" box at the top: type the ID written on the box (`B12`, `b12`, or just `12`).
- **Bin screen**: large ID badge, location, contents with quick add, usage stats (last accessed,
  7 day, 30 day and all-time counts), an "I just opened this box" button, and access history showing who did what.
- **Items**: add, rename, set quantity and notes, move to another bin, or remove.
- **Find tab**: search for "extension cord" and see which bin it's in and where (e.g. *Garage › Shelf 2*).
- **Areas tab**: areas of the home → spots within them → bins at each spot.

## Bin IDs

Short and meant to be hand-written. New bins get the next free `B1`, `B2`, `B3`…; any ID up to
8 characters works (e.g. `G4`). IDs are unique within the household, and lookups ignore case, spaces and dashes.

## How access is counted

An access is logged when someone opens a bin's screen, taps "I just opened this box", or changes its contents.
Repeat views within 10 minutes aren't counted again. The app shows the last 90 days of history; the all-time
count is kept on the bin.

## One-time Firebase setup (about 10 minutes, free)

1. Go to [console.firebase.google.com](https://console.firebase.google.com), sign in with a Google account,
   and click **Create a project** (any name, e.g. "Bins"). Google Analytics can be turned off.
2. **Build › Authentication › Get started**, then enable **Email/Password**.
3. **Build › Firestore Database › Create database**. Pick a location near you and start in **production mode**.
4. In Firestore, open the **Rules** tab, replace everything with the contents of [`firestore.rules`](firestore.rules), and click **Publish**.
5. **Project settings (gear) › Your apps › Add app › iOS**. Bundle ID: `com.saclark3.bintracker`.
   Download **GoogleService-Info.plist** and put it in the `BinTracker/` folder of this repo
   (it identifies the app to Firebase; it isn't a password, and your data is protected by the rules above).

Without that file the app builds but shows a "Firebase isn't set up yet" screen.

The free Firebase "Spark" plan allows 50,000 reads and 20,000 writes a day, far more than a household needs.

## Building

Builds run on GitHub (see `.github/workflows/build.yml`). To build on a Mac with Xcode 16 or later:
```
brew install xcodegen
xcodegen generate
open BinTracker.xcodeproj
```

## Guesses in this version (marked `GUESS:` in code)

- ID format `B` + number.
- 10-minute window for de-duplicating repeat views.
- Starter areas offered on first launch: Garage, Basement, Attic, Hall closet, Bedroom closet.
- Email and password sign-in (Sign in with Apple could be added later).
- iPhone portrait; iPad any orientation.

## TestFlight (installing on phones and iPads)

Every push to `main` builds the app on GitHub and uploads it to TestFlight
(`.github/workflows/testflight.yml`). You can also run it by hand from the Actions tab.

One-time setup:
1. **Register the bundle ID**: [developer.apple.com/account](https://developer.apple.com/account) ›
   Certificates, Identifiers & Profiles › Identifiers › **+** › App IDs › App.
   Description `Bins`, Explicit Bundle ID `com.saclark3.bintracker`.
2. **Create the app record**: [appstoreconnect.apple.com](https://appstoreconnect.apple.com) › Apps › **+** › New App.
   Platform iOS, any unique name (e.g. "Bins Home Storage"), the bundle ID above, SKU `bins`.
3. **Create an API key**: App Store Connect › Users and Access › Integrations › App Store Connect API ›
   Team Keys › **+**. Name `GitHub`, access **Admin**. Download the `.p8` file (only possible once) and note the
   **Key ID** and the **Issuer ID** shown above the list.
4. **Add three repository secrets** on GitHub: repo › Settings › Secrets and variables › Actions › New repository secret.
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `ASC_KEY_P8`: the full text of the `.p8` file, including the BEGIN and END lines

The Apple Team ID (`SLTV9MC3Y7`) is set in `project.yml`; it isn't secret.

Adding testers: in App Store Connect › TestFlight, create an internal group and add yourself.
To add someone else (they install with their own Apple ID), invite them first under Users and Access,
then add them to the group. They'll get an email to install TestFlight and the app.
