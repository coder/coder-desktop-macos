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

## Updating provisioning profiles

Release builds are signed with two provisioning profiles, one for the app
(`com.coder.Coder-Desktop`) and one for the network extension
(`com.coder.Coder-Desktop.VPN`). CI reads them from these repository secrets:

| Secret                                         | Profile           |
| ---------------------------------------------- | ----------------- |
| `CODER_DESKTOP_APP_PROVISIONPROFILE_B64`       | App               |
| `CODER_DESKTOP_EXTENSION_PROVISIONPROFILE_B64` | Network extension |

When a profile expires or needs regenerating:

1. Sign in to the [Apple Developer portal](https://developer.apple.com/account/resources/profiles/list)
   and open **Certificates, Identifiers & Profiles** > **Profiles**.
2. Regenerate or edit the profile if needed, then download it.
3. Base64-encode the downloaded file and copy the output:

   ```bash
   cat Coder_Desktop_<piece>.provisionprofile | base64
   ```

4. Paste the output into the matching secret under **Settings** >
   **Secrets and variables** > **Actions**.

To check new profiles before cutting a release, run the `release` workflow
manually with **dryrun** enabled. The build is uploaded as a workflow artifact
instead of a release asset.
