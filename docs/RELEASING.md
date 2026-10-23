# Releasing Tempo for Mac

## What happens

Tempo uses Sparkle 2.10 to check the public GitHub Releases feed over HTTPS, verify an Ed25519 signature, download the new app, and install/relaunch it using Sparkle's standard interface. Automatic checks and automatic downloads are enabled in release builds; Sparkle handles its user consent and installation UI. Checks run daily, or immediately from **Tempo → Check for Updates…**. The app does not force-close active work.

The source and public downloads are at `AyaanIqbal/tempo`. The stable download address always follows the latest published release:

https://github.com/AyaanIqbal/tempo/releases/latest/download/Tempo.zip

The update feed is:

https://github.com/AyaanIqbal/tempo/releases/latest/download/appcast.xml

These URLs will return 404 until the first release is published. Drafts do not change the live feed. Early Tempo versions without Sparkle need one manual installation of the first update-enabled build. Task data stays in `~/Library/Application Support/Tempo/workspace.json` when the application is replaced.

## One-time setup

The repo's `release.json` contains only version numbers, the public releases destination, and the public Sparkle key. The private key is stored in your Mac's login Keychain under account `app.tempo.tasks`.

If setting this up on a new project, run:

```sh
./scripts/configure-updates.sh AyaanIqbal/tempo
```

Do not run this on a new Mac to create a replacement key for existing users. Transfer the original key securely instead. Back up the signing key securely; losing it can break the update chain.

To allow GitHub Actions to sign releases, explicitly authorize transferring the Keychain key to the encrypted Actions secret `SPARKLE_PRIVATE_KEY`, then run:

```sh
python3 scripts/upload-update-key.py
```

The helper uses Sparkle’s official export tool in a private (0700) temporary directory, sends the key to GitHub over stdin, and deletes the temporary export even if uploading fails. It does not print the key or write it into the repo. Never paste private keys into issues, commits, PRs, or chat. If you prefer to keep the key only on this Mac, use the local release flow below instead of CI.

The same public repository uses its built-in Actions token for release creation. If you later split downloads into another repository, configure a `RELEASES_TOKEN` secret scoped to that repository with Contents write permission, and set the destination in `release.json`.

## Every release through GitHub Actions

1. Update **both** `version` and `build` in `release.json`. Use `major.minor.patch` for version and a strictly increasing positive integer for build (e.g. `0.2.1` / `3`).
2. Review, commit, and push your changes yourself.
3. Create and push a matching tag:

   ```sh
   git tag v0.2.1
   git push origin v0.2.1
   ```

4. **Actions → Release Tempo for Mac** checks the model, builds a universal Apple Silicon/Intel app, signs the ZIP, verifies the signature against the embedded public key, and creates a **draft release** with `Tempo.zip`, `appcast.xml`, and `SHA256SUMS.txt`.
5. Review the release notes and download/test the draft on a Mac. Publish the draft as the latest stable release when ready. Its appcast becomes the feed used by installed apps. Leave prereleases out of the stable channel.

The workflow rejects tags that do not match `release.json` and published builds that do not increase. Release creation fails if the tag already has a release; do not overwrite a published update with different bytes. Make another version/build instead.

## Apple Developer signing and notarization

Ed25519 update signing is configured independently of Apple Developer membership. Without a Developer ID certificate, builds use ad-hoc signing for testing; downloaded apps can be blocked by macOS Gatekeeper. This is not a fully notarized public distribution setup yet. Ad-hoc signed apps do not get hardened runtime enabled.

To check membership, sign in at https://developer.apple.com/account/ and look for Membership details. Smooth public downloads require setting up your Developer ID Application certificate and notarization credentials.

For a notarized CI release, configure:

| Type | Name | Value |
| --- | --- | --- |
| Secret | `APPLE_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate + private key export |
| Secret | `APPLE_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| Secret | `APPLE_ID` | Apple account used for notarization |
| Secret | `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notarization |
| Variable | `APPLE_TEAM_ID` | Your Apple team ID |
| Variable | `APPLE_SIGN_IDENTITY` | Full Developer ID Application signing identity |

Once a certificate is provided, all the other Apple values are required. CI signs Sparkle helpers inside out, notarizes the ZIP, staples the app, then signs the final archive for Sparkle. Signing secrets are imported into a temporary CI keychain and cleaned up afterward. Do not add these values to source files.

## Local packaging, without publishing

```sh
swift run TempoChecks
python3 Tests/release_checks.py
./scripts/package-release.sh
```

To build for both architectures:

```sh
TEMPO_UNIVERSAL=1 ./scripts/package-release.sh
```

Packaging creates files under `build/release/` and **never commits, tags, pushes, or publishes**. It signs with the Mac's Keychain key unless the CI signing secret is present. For Developer ID signing locally, set `TEMPO_SIGN_IDENTITY` to your installed identity. For notarization, store credentials with `xcrun notarytool store-credentials` and set `TEMPO_NOTARY_PROFILE` to that profile name.

After reviewing a locally packaged release, you can create a draft manually:

```sh
gh release create v0.2.1 build/release/Tempo.zip build/release/appcast.xml build/release/SHA256SUMS.txt --repo AyaanIqbal/tempo --draft --title 'Tempo 0.2.1'
```

## Verify the first actual update

A successful build/signature check does not establish an end-to-end live update. After setup is committed and pushed, publish two successive builds: install the earlier one in Applications, publish the newer one, and use **Check for Updates…**. Confirm download, install/relaunch, the updated About version, and preservation of existing tasks. This cannot be completed before the first releases exist.

References: https://sparkle-project.org/documentation/ and https://sparkle-project.org/documentation/publishing/
