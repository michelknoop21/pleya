fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### ios_beta

```sh
[bundle exec] fastlane ios_beta
```

iOS → TestFlight

### tvos_beta

```sh
[bundle exec] fastlane tvos_beta
```

tvOS → TestFlight

### macos_beta

```sh
[bundle exec] fastlane macos_beta
```

macOS → TestFlight (pkg)

### external

```sh
[bundle exec] fastlane external
```

Laatste build(s) naar external testgroep (Beta App Review bij eerste build van een versie)

### add_testers

```sh
[bundle exec] fastlane add_testers
```

E-mailadressen toevoegen aan de external testgroep: fastlane add_testers emails:a@x.nl,b@y.nl

### beta

```sh
[bundle exec] fastlane beta
```

Alle platforms → TestFlight; gaat door als één platform faalt

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
