# Bins — storage bin tracker (v0.1)

An iPhone app (SwiftUI + SwiftData, iOS 17+) for tracking what's in each storage bin,
where each bin lives in the house, and how often you use it. All data stays on the phone.

## What it does

- **Bins tab**: every bin, sortable by *Recently used*, *Most used* (last 30 days) or *Bin ID*.
  A "Go to bin" box at the top: type the ID you wrote on the box (`B12`, `b12`, or just `12`) and it opens.
- **Bin screen**: big ID badge in its label colour, location, contents list with a quick-add field
  (keyboard stays up so you can rattle off items while packing), usage stats (last accessed,
  7 / 30 day / all-time counts), an "I just opened this box" button, and a full access history.
- **Items**: add, rename, set quantity and notes, move to another bin, or remove.
- **Find tab**: type "extension cord" and see which bin it's in and where that bin is (e.g. *Garage › Shelf 2*).
  Also matches bin IDs and bin names.
- **Areas tab**: areas of the home (Garage, Attic…) → spots within them (Shelf 2, Under stairs) → bins at each spot.
  Bins without a location are listed at the bottom.

## Bin IDs

IDs are short and meant to be hand-written on the box. New bins get the next free `B1`, `B2`, `B3`…,
but you can type any ID up to 8 characters (e.g. `G4` for the garage). IDs must be unique, and lookups
ignore case, spaces and dashes.

## How access is counted

An access is logged when you open a bin's screen, tap "I just opened this box", or change its contents.
Repeat views within 10 minutes of the last access aren't counted again, so moving back and forth
between screens doesn't inflate the numbers.

## Running it

You need a Mac with Xcode 15 or later.

**Option A (XcodeGen, quickest):**
```
brew install xcodegen
cd BinTracker
xcodegen generate
open BinTracker.xcodeproj
```

**Option B (no extra tools):** In Xcode choose File › New › Project › iOS App, name it `BinTracker`,
Interface SwiftUI, Storage *None*. Delete the generated `ContentView.swift` and `BinTrackerApp.swift`,
then drag the `BinTracker/` folder from here (Models, Services, Views, BinTrackerApp.swift) into the project.
Set the minimum deployment to iOS 17.

Then pick your iPhone as the run destination, set your Apple ID under Signing & Capabilities, and press Run.
A free Apple ID works for installing on your own phone (the app needs re-installing every 7 days);
a paid developer account removes that limit and allows TestFlight.

## Guesses in this version (marked `GUESS:` in code)

- ID format `B` + number.
- 10-minute window for de-duplicating repeat views.
- Starter areas offered on first launch: Garage, Basement, Attic, Hall closet, Bedroom closet.
- iPhone only, portrait only.
