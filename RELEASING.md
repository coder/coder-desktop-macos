# Releasing Coder Desktop

These tasks require access to Coder's Apple Developer team and admin access to
this repository.

## Releasing a new version

Versions come from Git tags of the form `vX.Y.Z` (see `scripts/version.sh`).
Nobody can push a tag to this repository. The `release` workflow creates the
tag, and the GitHub release, after another release manager has approved the
run.

1. Merge what you want to release to `main`, and wait for the `release`
   workflow run of the last push to `main` to finish. That run publishes the
   `preview` build and updates the appcast, and so does a release, so two of
   them at once can lose one of the two updates. For the same reason, don't
   merge to `main` while a release is running.
2. Write the release notes. They become the description of the GitHub release
   and the update description in the Sparkle appcast.
3. Start the release:

   ```bash
   ./scripts/release.sh vX.Y.Z
   ```

   The script releases the head of `main` unless you pass `--commit`, and
   opens your editor for the release notes unless you pass `--notes-file`. It
   checks the version and the commit, shows what it is about to release, and
   asks before it starts the `release` workflow. With `--dry-run` it stops
   after the checks.
4. Ask another member of `coder/coder-desktop-release-managers` to approve the
   run (see [Approvals](#approvals)). You cannot approve a release you started.
5. Once approved, the run creates the tag, builds, signs and notarizes the
   app, creates the GitHub release with its assets, updates the appcast, and
   opens a pull request to update the
   [homebrew-coder](https://github.com/coder/homebrew-coder) cask. It waits
   for a second approval before it opens that pull request. Wait for it to
   finish, then review and merge the cask pull request.

The workflow refuses a release unless all of these hold. `scripts/release.sh`
checks them first, so that a mistake shows before anyone is asked to approve.

- The run is on `main`, and the commit is on `main`.
- The version looks like `vX.Y.Z` and is higher than the latest release.
- The commit comes after the latest release and has no release tag yet.
- There are release notes.

### When a release run fails

The tag is created before the app is built. If a later job fails, fix the
cause and re-run the failed jobs, or start the same version for the same
commit again: the run finds the tag, and the release if there is one, and goes
on from there. Starting it again takes a new approval, and uses the newest
`release-sign.yml` on `main`, which re-running the failed jobs does not.

If the commit itself needs a fix, release the fixed commit as the next
version. A tag is never moved to another commit.

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
environment, which only `main` may use. Its secrets:

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
environment.

`publish` runs in the `publish` environment, which also only `main` may use.
It holds no signing secret, so that the tools `publish` downloads never run
next to one. Its secrets:

| Secret                     | What it is                                                |
| -------------------------- | --------------------------------------------------------- |
| `GCP_WORKLOAD_ID_PROVIDER` | Google Cloud workload identity provider for publishing    |
| `GCP_SERVICE_ACCOUNT`      | Service account that may write the appcast to the releases bucket |

`approve` runs in the `release-approval` environment and creates the release
tag as the `coder-release-publisher` GitHub App, the App that also tags
coder/coder's releases. The App's key is in Cloud KMS, like the signing keys,
so the environment holds no key, only what the job needs to ask for a
signature:

| Secret                                | What it is                                           |
| ------------------------------------- | ---------------------------------------------------- |
| `CODER_RELEASE_PUBLISHER_APP_ID`      | The App's client ID                                  |
| `CODER_RELEASE_PUBLISHER_APP_KMS_KEY` | Resource name of the App's key in Cloud KMS          |
| `APP_KEYS_WORKLOAD_ID_PROVIDER`       | Google Cloud workload identity provider for App keys |

In this repository, Google Cloud only signs with that key for a job that comes
from the copy of `release-sign.yml` on `main` and runs in the
`release-approval` environment.

### Approvals

Every push to `main` is signed and published as the `preview` build, so the
`signing` and `publish` environments must have no required reviewers. A release is approved
once, in the `approve` job, before it is tagged, built or signed.

| Environment        | Required reviewers                      | Used by                                      | Approval asked   |
| ------------------ | --------------------------------------- | -------------------------------------------- | ---------------- |
| `signing`          | None                                    | `sign-app`, `sign-installer`, `sign-sparkle` | Never            |
| `publish`          | None                                    | `publish`                                    | Never            |
| `release-approval` | `coder/coder-desktop-release-managers`  | `approve`                                    | Once per release |
| `release-publish`  | `coder/release-managers`                | `update-cask`                                | Once per release |

All four environments only accept `main`, which is where a release runs.
Neither reviewed environment lets the person who started the release approve
it, so a release needs a second person. The environments are managed in
[coder/github-org-terraform](https://github.com/coder/github-org-terraform).

`release.yml` only starts the run. It calls the copy of `release-sign.yml` on
`main`, and Google Cloud lets no other copy sign. So a release chooses the
commit to build, but not the jobs that sign it, and it cannot leave out the
`approve` job. The first job stops the run unless it is on `main` and the
commit is on `main`. The jobs come from the newest `main`, while the scripts
they run come from the released commit.

The approval is a job in `release-sign.yml`, so a change to that file on
`main` could sign without it. What protects against that is the review of
changes to `main`.

The approval does not protect the secrets of the `signing` environment, which
every push to `main` uses without one. Two of them are keys:
`SPARKLE_PRIVATE_KEY` and `AC_APIKEY_P8_BASE64`. The same holds for the
`publish` environment, whose identity may write the appcast. What protects
those is that both environments only accept `main`, and the review of changes
to `main`.

Only the `coder-release-publisher` App may create, move or delete a tag. A
ruleset stops everyone else, admins included, and in this repository the App
can only be used from the `approve` job. So a release tag always points at a
commit on `main` that a second release manager approved.

### Trying a change

Run the `release` workflow manually on `main` with **dryrun** enabled and no
version. The build is uploaded as a workflow artifact instead of a release
asset. The workflow does not run from any other branch. A dry run needs no
approval.

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
