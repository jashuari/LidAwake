# Development and releases

[Back to the README](../README.md)

## Build from source


Developers need macOS, the Xcode command-line tools (or Xcode), and a **Swift 6** toolchain with a macOS SDK supporting macOS 13 deployment. End users downloading a release do not need these tools.

```sh
./build.sh
```

This compiles separate `arm64-apple-macos13.0` and `x86_64-apple-macos13.0` binaries, combines them with `lipo`, and ad-hoc signs and verifies `build/LidAwake.app`. It does not launch or install the app, request administrator access, or change power settings.

Build the app and both downloadable archives with one command:

```sh
./scripts/release.sh
```

Outputs for version 1.0.0:

```text
dist/LidAwake-1.0.0-universal.zip
dist/LidAwake-1.0.0-universal.dmg
dist/SHA256SUMS.txt
```

The DMG includes an Applications shortcut for drag-to-install. SHA-256 checksums cover the ZIP and DMG; verify a downloaded file against the release's checksum file with `shasum -a 256 <filename>`. Packaging uses only built-in macOS tools. Archives are not byte-for-byte reproducible because signing and disk images can contain build metadata.

## Releases and CI

GitHub Actions builds and packages both architectures on branch pushes and pull requests. Downloadable CI artifacts are retained by GitHub according to repository retention settings.

For a release, update `CFBundleShortVersionString` in `Info.plist` (three-part version) and increment `CFBundleVersion`, commit, and push a matching `v<version>` tag. Tag builds validate the version and attach both archives and `SHA256SUMS.txt` to a GitHub Release. For example, `./scripts/release.sh v1.0.0` locally checks the initial tag against the app version. Only the release job has repository write permission. No signing credentials are needed or included.

