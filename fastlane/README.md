fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac generate

```sh
[bundle exec] fastlane mac generate
```

Xcode-Projekt aus project.yml erzeugen

### mac build

```sh
[bundle exec] fastlane mac build
```

Debug-Build als Compile-Check

### mac bump

```sh
[bundle exec] fastlane mac bump
```

Build-Nummer in project.yml um 1 erhöhen

### mac archive

```sh
[bundle exec] fastlane mac archive
```

Release-App nach build/release bauen

### mac install

```sh
[bundle exec] fastlane mac install
```

build/release-App nach /Applications kopieren und neu starten

### mac release

```sh
[bundle exec] fastlane mac release
```

Build-Nummer erhöhen, Release bauen und installieren

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
