# Releasing Coder Desktop

These tasks require access to Coder's Apple Developer team and admin access to
this repository.

## Releasing a new version

Versions come from Git tags of the form `vX.Y.Z` (see `scripts/version.sh`).
Pushing a tag doesn't start a workflow, but the GitHub release needs a tag to
point at.

1. Tag the commit on `main` that you want to release, and push the tag:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

2. Wait for the `release` workflow run for that commit on `main` to finish.
   It publishes the `preview` build and updates the appcast, so publishing the
   release while it is still running can race on the appcast update.
3. [Create a GitHub release](https://github.com/coder/coder-desktop-macos/releases/new)
   from the tag and write the release notes. The release notes are used as the
   update description in the Sparkle appcast, so write them before publishing.
4. Publishing the release starts the `release` workflow, which builds, signs,
   and notarizes the app, uploads the assets to the release, updates the
   appcast, and opens a pull request to update the
   [homebrew-coder](https://github.com/coder/homebrew-coder) cask. Wait for it
   to finish, then review and merge the cask pull request.

## Signing

The Developer ID private key lives in Google Cloud KMS (`coder-release-signing`
project, `apple-codesign/developer-id-application`, managed in coder/gcp) and
cannot be exported. Apple issued both the Developer ID Application and the
Developer ID Installer certificates for it. Apple's `codesign` can't use it,
so `release.yml` signs on Linux with
[rcodesign](https://github.com/indygreg/apple-platform-rs) through the Cloud
KMS PKCS#11 library:

1. `build` (macOS) builds the app without signing it (`scripts/build.sh`).
2. `sign-app` (Linux) signs it with the Developer ID Application certificate
   (`scripts/sign.sh app`).
3. `package` (macOS) checks the signature with `codesign` and builds the
   installer (`scripts/package.sh`).
4. `sign-pkg` (Linux) signs the installer with the Developer ID Installer
   certificate (`scripts/sign.sh pkg`), then notarizes and staples it
   (`scripts/notarize.sh`).
5. `publish` (macOS) checks the installer with `spctl`, signs the Sparkle
   update and publishes.

Only jobs in the `signing` environment can use the keys, and only on `main`
or a published `vX.Y.Z` release. That environment holds:

| Secret                 | Value                                              |
| ---------------------- | -------------------------------------------------- |
| `AC_APIKEY_ISSUER_ID`  | App Store Connect API key issuer ID (notarization) |
| `AC_APIKEY_ID`         | App Store Connect API key ID                       |
| `AC_APIKEY_P8_BASE64`  | The API key's `.p8` file, base64-encoded          |
| `SPARKLE_PRIVATE_KEY`  | Sparkle EdDSA update signing key                   |

The certificates are public and committed in `signing/`, with the
entitlements each executable is signed with in `signing/entitlements/`. If you
change an entitlement in `Coder-Desktop/project.yml`, change it there too:
release builds are signed with those files, not with Xcode's.

To try `scripts/sign.sh` without the real keys, sign with a throwaway
certificate (it won't pass Gatekeeper, but shows what gets signed and how):

```bash
rcodesign generate-self-signed-certificate --person-name test --p12-file test.p12 --p12-password test
printf test > test.pw
P12_FILE=test.p12 P12_PASSWORD_FILE=test.pw ./scripts/sign.sh app "path/to/Coder Desktop.app"
```

## Updating provisioning profiles

Release builds are signed with two provisioning profiles, one for the app
(`com.coder.Coder-Desktop`) and one for the network extension
(`com.coder.Coder-Desktop.VPN`). CI reads them from these repository secrets:

| Secret                                         | Profile file                               |
| ---------------------------------------------- | ------------------------------------------ |
| `CODER_DESKTOP_APP_PROVISIONPROFILE_B64`       | `Coder_Desktop_App.provisionprofile`       |
| `CODER_DESKTOP_EXTENSION_PROVISIONPROFILE_B64` | `Coder_Desktop_Extension.provisionprofile` |

When a profile expires or needs regenerating:

1. Sign in to the [Apple Developer portal](https://developer.apple.com/account/resources/profiles/list)
   and open **Certificates, Identifiers & Profiles** > **Profiles**.
2. Regenerate or edit the profile if needed, then download it.
3. Base64-encode the downloaded file and copy the output:

   ```bash
   cat Coder_Desktop_App.provisionprofile | base64
   cat Coder_Desktop_Extension.provisionprofile | base64
   ```

4. Paste the output into the matching secret under **Settings** >
   **Secrets and variables** > **Actions**.

To check new profiles before cutting a release, run the `release` workflow
manually on `main` with **dryrun** enabled. The build is signed, notarized and
uploaded as a workflow artifact instead of a release asset. The signing jobs
only run on `main`, so a dry run from another branch stops after `build`.
