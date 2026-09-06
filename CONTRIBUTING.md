# Contributing

Thanks for looking. Debris is a one-person hobby project, so here is what fits, how the project
is put together, and what will save us both some time.

## Scope

Debris finds and removes files that belong to apps: leftovers of apps that are gone, everything
an installed app owns, and caches and developer junk with a known origin. Every removal goes
through a list the user can read and ends up in the Trash.

Anything that tunes, optimises, monitors or "speeds up" a Mac is out of scope, and so is deleting
without showing the list first. Not because those are bad ideas, they are just a different app.

## Building

```
brew install xcodegen
xcodegen generate
open Debris.xcodeproj
```

The Xcode project is generated from `project.yml` and not committed, so run `xcodegen generate`
again after adding a file or editing that file. A new source file that is not in the generated
project does not fail loudly, it simply is not compiled.

The logic lives in `Packages/DebrisKit` and has no dependency on the app. `swift test` runs the
classifier tests and `swift run debris` prints what a scan finds, which is the fastest way to
check a change against a real Mac, and `swift run debris --uninstall "App Name"` prints what the
Uninstall module would list for an app. The app can also write PNGs of its own screens with
`Debris -snapshotDir /some/folder`.

macOS 15 or later. The app is not sandboxed and is signed for Developer ID, not the App Store.

## Before you open a pull request

Open an issue first for anything bigger than a fix. It saves you writing code that I then have to
turn down for reasons that were only in my head.

Branch from `dev` and open the pull request against it. `main` follows behind and is what the
outside sees: the front page, this file, and the source a release is cut from.

Look at the [open milestones](https://github.com/mews-se/debris/milestones) and the `planned`
label before you start. What is listed there is either being worked on already or decided, and
it is the cheapest way to avoid writing something twice. Planned does not automatically mean me,
so say so if you want one of them.

## Classification changes

Most of the interesting work is deciding who owns a file. When you change a rule, say in the pull
request what it now catches that it did not before and what it now leaves alone, with the apps
involved. A rule that is right on your Mac can be wrong on one with a different set of apps, so
a test in `Tests/DebrisKitTests` with a made-up inventory is worth more than a screenshot.

Never make up a leftover from a name alone if a real owner is plausible. A file wrongly listed
costs the user data; a file wrongly skipped costs disk space. The first is the one to avoid.

## Strings

All user-facing text is English only and lives as plain literals in the views; the app carries no
string catalog.

## Commits

Keep commits focused. Subject in the imperative with a conventional prefix (`feat:`, `fix:`,
`docs:`, `chore:`), and a body explaining why when the why is not obvious from the diff.

## Licence

MIT. By contributing you agree that your work is published under it.
