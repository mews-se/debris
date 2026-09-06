# Debris

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-F05138?logo=swift&logoColor=white)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Debris finds what is left of apps you no longer have, uninstalls apps together with everything
they own, and clears caches and developer junk. It shows the list first, explains why each file
is on it, and moves things to the Trash rather than deleting them, so a wrong guess is one drag
away from undone.

It is in early development. The first release will carry three modules; Leftovers and Uninstall
work today, Clean is being built.

## What it does

**Leftovers** compares every entry in the folders where apps keep their state (Application
Support, Caches, Preferences, Containers, Group Containers, HTTP storages, WebKit data, launch
agents and daemons, helper tools, kernel and audio extensions, the home folder's dotfiles and a
few more) against the apps, helpers, extensions and Homebrew packages that are actually
installed. Whatever has no owner left is listed, grouped by the app it came from, with a size, a
last-modified date and a confidence:

- *Likely leftover*: no installed app, helper or package matches the file at all.
- *Possibly leftover*: no exact match, but the same vendor still has other apps installed.
  Microsoft's updater daemon after Office is gone looks like this.
- *Unclear*: a plain name with no identifier, or a container whose owner cannot be read.

The confidence filter in the toolbar starts at Likely. Files owned by the system are marked with
a lock and left alone for now.

**Uninstall** lists the installed apps. Pick one and Debris shows the app bundle together with
everything it can tie to it: containers, group containers, preferences, caches, HTTP storages,
WebKit data, saved state, launch agents, helper tools and dotfiles, each with the reason it is on
the list. Ownership uses the same signals as the Leftovers scan turned around: bundle identifiers
including embedded helpers, the team and app groups from the code signature, launchd jobs that
point into the bundle, and names. Anything shared with another installed app stays, so removing
Word does not touch what Excel still uses. A running app is quit first, and package receipts are
shown but left alone until administrator removal exists.

**Clean** is being built. It will remove caches, logs, developer artifacts and installer files,
each behind a rule that says what the files are and why they are safe to remove.

## What it does not do

It does not tune, speed up or monitor anything, and it never deletes on its own. Everything goes
through the list and the Trash.

## Full Disk Access

macOS hides parts of the Library from every app until you grant it Full Disk Access in System
Settings. Without it Debris cannot see inside sandboxed containers, Mail, Safari or cookies, and
cannot move container leftovers to the Trash. The app tells you when that is the case and takes
you to the right setting.

## Building

```
brew install xcodegen
xcodegen generate
open Debris.xcodeproj
```

The Xcode project is generated from `project.yml` and not committed. The scanning and
classification live in the Swift package under `Packages/DebrisKit`, which also builds a small
command line tool:

```
cd Packages/DebrisKit
swift run debris            # scan and print what the app would list
swift run debris --all      # include the unclear cases
swift test
```

macOS 15 or later. Debris is not sandboxed and will not be on the App Store: the whole point is
to reach files a sandboxed app cannot.

## Licence

MIT, see [LICENSE](LICENSE).
