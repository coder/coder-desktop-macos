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
   [homebrew-coder](https://github.com/coder/homebrew-coder) cask. The run
   waits for approval twice: once before anything is signed, and once before
   the cask pull request is opened (see [Approvals](#approvals)). Wait for it
   to finish, then review and merge the cask pull request.

## How releases are signed

The app and its installer are signed with Coder's Developer ID keys. Both keys
live in Google Cloud KMS and cannot be exported, so nothing in this repository
or its secrets can sign on its own.

Xcode cannot sign with a key in Cloud KMS, and the library that reaches the
keys only exists for Linux, while building and packaging need macOS. The jobs
of the `release` workflow, in `.github/workflows/release-sign.yml`, therefore
alternate between the two:

| Job              | Runs on | Does                                                              |
| ---------------- | ------- | ----------------------------------------------------------------- |
| `build`          | macOS   | Builds the app with code signing disabled (`scripts/build.sh`)    |
| `rcodesign`      | Linux   | Builds the signing tool, in a job with no credentials             |
| `sign-app`       | Linux   | Signs the app with the Developer ID Application key, notarizes it |
| `package`        | macOS   | Builds the installer                                              |
| `sign-installer` | Linux   | Signs the installer with the Developer ID Installer key, notarizes it |
| `sign-sparkle`   | macOS   | Signs the installer for Sparkle                                   |
| `publish`        | macOS   | Publishes the installer and updates the appcast                   |

The jobs pass files to each other as workflow artifacts. Each job records the
SHA-256 of what it uploads, and the job that downloads it checks the file
against that before using it.

The scripts are in `scripts/signing`. `sign-app.sh` reproduces what Xcode's
Developer ID export used to do. It also signs the two macOS programs inside
`mutagen-agents.tar.gz`, which signing the app bundle does not reach.

Sparkle, the app's updater, has its own signing key, which cannot be kept in
Cloud KMS. The `sign-sparkle` job signs the finished installer with it, using
Sparkle's own tool, which only runs on macOS. The job does nothing else, so
that the key is never next to the tools `publish` downloads.

### Secrets

`sign-app`, `sign-installer` and `sign-sparkle` run in the `signing`
environment, which only `main` and `v*` tags may use. Its secrets:

| Secret                         | What it is                                                        |
| ------------------------------ | ----------------------------------------------------------------- |
| `SIGNING_WORKLOAD_ID_PROVIDER` | Google Cloud workload identity provider for this workflow         |
| `SIGNING_SERVICE_ACCOUNT`      | Service account that may sign with the keys                       |
| `AC_KMS_KEY_RING`              | Resource name of the Cloud KMS key ring that holds the keys       |
| `AC_KMS_KEY`                   | Name of the Developer ID Application key in that key ring         |
| `AC_CERTIFICATE_PEM`           | The Developer ID Application certificate, as PEM text             |
| `AC_INSTALLER_KMS_KEY`         | Name of the Developer ID Installer key in that key ring           |
| `AC_INSTALLER_CERTIFICATE_PEM` | The Developer ID Installer certificate, as PEM text               |
| `AC_APP_PROVISIONPROFILE_B64`  | Provisioning profile for the app, base64-encoded                  |
| `AC_EXT_PROVISIONPROFILE_B64`  | Provisioning profile for the system extension, base64-encoded     |
| `AC_APIKEY_P8_BASE64`          | App Store Connect API key for notarization (`.p8`), base64-encoded |
| `AC_APIKEY_ID`                 | That key's ID                                                     |
| `AC_APIKEY_ISSUER_ID`          | That key's issuer ID                                              |
| `SPARKLE_PRIVATE_KEY`          | Sparkle's signing key                                             |

Google Cloud only gives a job the signing identity when the job comes from
the copy of `release-sign.yml` on `main` and runs in the `signing`
environment, on `main` or a release tag.

`publish` runs in the `publish` environment, which also only `main` and `v*`
tags may use. It holds no signing secret, so that the tools `publish` downloads
never run next to one. Its secrets:

| Secret                     | What it is                                                |
| -------------------------- | --------------------------------------------------------- |
| `GCP_WORKLOAD_ID_PROVIDER` | Google Cloud workload identity provider for publishing    |
| `GCP_SERVICE_ACCOUNT`      | Service account that may write the appcast to the releases bucket |

### Approvals

Every push to `main` is signed and published as the `preview` build, so the
`signing` and `publish` environments must have no required reviewers. A release is approved
once, in the `approve` job, before anything is signed.

| Environment        | Required reviewers                      | Used by                                      | Approval asked   |
| ------------------ | --------------------------------------- | -------------------------------------------- | ---------------- |
| `signing`          | None                                    | `sign-app`, `sign-installer`, `sign-sparkle` | Never            |
| `publish`          | None                                    | `publish`                                    | Never            |
| `release-approval` | `coder/coder-desktop-release-managers`  | `approve`                                    | Once per release |
| `release-publish`  | `coder/release-managers`                | `update-cask`                                | Once per release |

`release-approval` holds no secrets, and only `v*` tags may use it. Neither
reviewed environment lets the person who published the release approve it, so
a release needs a second person. The environments are managed in
[coder/github-org-terraform](https://github.com/coder/github-org-terraform).

`release.yml` only starts the run. It calls the copy of `release-sign.yml` on
`main`, also when a release tag starts the run, and Google Cloud lets no other
copy sign. So a tag chooses the commit to release, but not the jobs that sign
it, and it cannot leave out the `approve` job. The first job stops the run if
that commit is not on `main`. The jobs come from the newest `main`, while the
scripts they run come from the tagged commit.

The approval is a job in `release-sign.yml`, so a change to that file on
`main` could sign without it. What protects against that is the review of
changes to `main`.

The approval does not protect the secrets of the `signing` environment. GitHub
gives them to any job in that environment on a `v*` tag, whatever workflow
file the tag carries. Two of them are keys: `SPARKLE_PRIVATE_KEY` and
`AC_APIKEY_P8_BASE64`. The same holds for the `publish` environment, whose
identity may write the appcast. What protects those is that only
`coder/coder-desktop-release-managers` may push a `v*` tag.

### Trying a change

Run the `release` workflow manually on `main` with **dryrun** enabled. The
build is uploaded as a workflow artifact instead of a release asset. The
signing jobs cannot run from any other branch. A dry run needs no approval.

Every run uses the copy of `release-sign.yml` on `main`, so a change to that
file cannot be tried before it is merged.

To try the scripts without the real keys, `sign-app.sh` and
`sign-installer.sh` also accept a throwaway certificate; see the comments at
the top of each.

## Updating provisioning profiles

Release builds carry two provisioning profiles, one for the app
(`com.coder.Coder-Desktop`) and one for the system extension
(`com.coder.Coder-Desktop.VPN`). A profile is bound to the certificate chosen
when it was created, so both must be bound to the certificate in the
`AC_CERTIFICATE_PEM` secret. Nothing in the release workflow checks this.

When a profile expires or needs regenerating:

1. Sign in to the [Apple Developer portal](https://developer.apple.com/account/resources/profiles/list)
   and open **Certificates, Identifiers & Profiles** > **Profiles**.
2. Create or edit a **Developer ID** profile, select that certificate, and
   download it.
3. Set the secrets in the `signing` environment:

   ```bash
   base64 < Coder_Desktop_App.provisionprofile | tr -d '\n' |
     gh secret set AC_APP_PROVISIONPROFILE_B64 --env signing
   base64 < Coder_Desktop_Extension.provisionprofile | tr -d '\n' |
     gh secret set AC_EXT_PROVISIONPROFILE_B64 --env signing
   ```

## Changing entitlements

The entitlements the app is signed with are in `scripts/signing/entitlements`.
When you change a target's entitlements in `Coder-Desktop/project.yml`, change
the matching file there too. `scripts/build.sh` compares the two and stops the
release build if they differ. If the entitlement is a restricted one, the
provisioning profile has to grant it as well.

## Replacing a certificate

The Developer ID Application certificate expires on 2027-12-15, the Developer
ID Installer certificate on 2030-03-05. To replace one:

1. Create a new key in Cloud KMS and have the Apple Account Holder issue a
   certificate for it. The runbook is in the `coder-release-signing` project in
   [coder/gcp](https://github.com/coder/gcp).
2. Set the certificate secret (`AC_CERTIFICATE_PEM` or
   `AC_INSTALLER_CERTIFICATE_PEM`) and the key name secret (`AC_KMS_KEY` or
   `AC_INSTALLER_KMS_KEY`) in the `signing` environment.
3. For the Application certificate, create new provisioning profiles bound to
   it (see above).

Do not revoke the old certificate. Revoking a Developer ID certificate
invalidates everything already shipped under it.
