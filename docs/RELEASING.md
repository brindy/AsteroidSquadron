# Releasing Asteroid Squadron

Public downloads live at [GitHub Releases](https://github.com/brindy/AsteroidSquadron/releases). A release has an Apple Silicon DMG, an Apple Silicon ZIP, and `SHA256SUMS`. The app contains only arm64 and requires an Apple Silicon Mac running macOS 13 or newer.

Signing and notarization run on the maintainer's Mac. The Developer ID private key and Apple notarization credentials stay in the local Keychain. No signing secrets are uploaded to GitHub.

## One-time setup

1. On an Apple Silicon Mac, install Xcode Command Line Tools and [GitHub CLI](https://cli.github.com/).
2. Authenticate GitHub CLI with `gh auth login -h github.com`. Git push also needs access to `origin`.
3. Install a **Developer ID Application** certificate with its private key. Check availability using `security find-identity -v -p codesigning`. Apple Development certificates and ad hoc signatures cannot be used for a notarized public release.
4. Store Apple notarization credentials in Keychain:

   ```sh
   ./scripts/setup-notarization.sh asteroid-squadron
   ```

   Enter your Apple Developer Apple ID and Team ID. Apple's `notarytool` then prompts securely for an **app-specific password**, not the password you normally use to sign in. Create an app-specific password in your Apple Account. The helper supplies Apple ID and Team ID explicitly, avoiding the optional API-key prompt, and validates credentials with Apple before storing them. Do not paste the password into chat, shell history, source files, or GitHub.

   An existing `notarytool` profile also works: pass its name to `--profile`. App Store Connect API key users can create a profile directly with `xcrun notarytool store-credentials --help`; the release script only needs the resulting profile name.

Apple's [notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) explains Developer ID signing, secure timestamps, hardened runtime, and stapled tickets. A Mac App Store listing is not needed for direct distribution.

## Create and publish a release

1. Update `VERSION`, increment `BUILD_NUMBER`, and add `releases/v<VERSION>.md`.
2. Review and commit all changes. The release command rejects a dirty checkout.
3. Run:

   ```sh
   ./scripts/release.sh --profile asteroid-squadron --publish
   ```

   Add `--identity 'Developer ID Application: Your Name (TEAMID)'` if multiple Developer ID identities are installed. Omit `--publish` to produce and validate local release files without pushing or publishing.

The script builds the arm64 executable, rejects other architecture lists, signs with hardened runtime and a secure timestamp, and verifies the signature. It runs native flight and jump-arrival checks, notarizes and staples the app, builds a drag-to-Applications DMG, and notarizes and staples that DMG too. The final ZIP contains the already-stapled app. Gatekeeper assessments and checksum generation must pass before publication. Notarization receipts and diagnostic logs stay in the ignored `build/releases/v<VERSION>/` folder.

Publication pushes the source commit, creates and pushes an annotated `v<VERSION>` tag, then uploads the DMG, ZIP and checksums to a GitHub release. No tags or assets are force-replaced. Approved app bundles and receipts are preserved on reruns; publishing an already prepared version reuses its verified files rather than rebuilding it. The script stops if the version was already released; increment the version for another public build.

Apple processing can take a while. If a submission times out, use its ID in the JSON receipt with `xcrun notarytool info`, `log`, or `wait` and the same `--keychain-profile`. The service keeps processing after the local timeout. Do not publish a pending or rejected submission, or repeatedly resubmit it. If publication fails after the notarized artifacts and tag were created, the artifacts remain locally; upload those existing validated files with `gh release create` (or `gh release upload` for an existing draft) rather than re-notarizing them.

## Publish an already approved package

To upload existing notarized files without rebuilding or altering the app:

```sh
./scripts/publish-release.sh --check v1.15  # Read-only artifact validation
./scripts/publish-release.sh v1.15          # Explicitly publish to GitHub
```

The publisher verifies the recorded SHA-256 values, Apple acceptance receipts, app identity/version, code signature, stapled tickets and Gatekeeper. It tags the exact source commit recorded in the evidence, even if the working branch has moved on. It never needs the Apple password, changes the bundle, or overwrites an existing release. The builder without `--publish` never creates a GitHub release.

## Local development builds

```sh
./scripts/build.sh                                  # Apple Silicon, ad hoc signature
./scripts/build.sh --output 'build/test/Asteroid Squadron.app'
./scripts/package.sh 'build/test/Asteroid Squadron.app' build/package-test
```

`package.sh` only creates and verifies a disk image. It does **not** notarize it. Local ad hoc builds are for testing, not the signed public download.

All building, signing, notarization, verification and packaging run locally. There are no GitHub Actions workflows or cloud signing secrets. GitHub hosts the source repository and published releases only. The local release command runs native flight checks, rendered GPU arrival checks, and the veteran/skybox checks before notarization. Intel/Rosetta builds and checks are not part of the release process.

Keep build products, `.p12` certificates, `.p8` keys, passwords and notarization receipts out of Git. The `.gitignore` covers the standard paths and credential extensions. Never commit an exported private key to set up signing.
